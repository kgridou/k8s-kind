#!/bin/bash
set -e

# Configuration
CLUSTER_NAME=dev
APP_NAME=myapp
VAULT_TLS_SECRET=vault-tls
VAULT_LOCAL_HOST=vault.local
VAULT_NAMESPACE=default
VAULT_ADDR=https://$VAULT_LOCAL_HOST:8200

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

cleanup() {
    log "=== CLEANUP: Removing kind cluster and resources ==="
    pkill -f "kubectl port-forward" || true
    kind delete cluster --name $CLUSTER_NAME || true
    docker rmi $APP_NAME:latest 2>/dev/null || true
    log "Cleanup completed"
}

validate_prerequisites() {
    log "=== Validating prerequisites ==="

    # Check required tools
    command -v kind >/dev/null 2>&1 || error "kind is not installed"
    command -v kubectl >/dev/null 2>&1 || error "kubectl is not installed"
    command -v helm >/dev/null 2>&1 || error "helm is not installed"
    command -v docker >/dev/null 2>&1 || error "docker is not installed"
    command -v mvn >/dev/null 2>&1 || command -v ./mvnw >/dev/null 2>&1 || error "maven is not installed"

    # Check certificate files
    if [[ ! -f "certs/vault.local.pem" ]]; then
        error "Certificate file certs/vault.local.pem not found"
    fi

    if [[ ! -f "certs/vault.local-key.pem" ]]; then
        error "Certificate key file certs/vault.local-key.pem not found"
    fi

    # Validate certificate
    openssl x509 -in certs/vault.local.pem -text -noout >/dev/null 2>&1 || error "Invalid certificate file"
    openssl rsa -in certs/vault.local-key.pem -check -noout >/dev/null 2>&1 || error "Invalid certificate key file"

    log "All prerequisites validated successfully"
}

create_kind_cluster() {
    log "=== 1. Creating kind cluster ==="
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        warn "Cluster $CLUSTER_NAME already exists, using existing cluster"
    else
        kind create cluster --name $CLUSTER_NAME --image kindest/node:v1.28.0
        log "Kind cluster created successfully"
    fi

    kubectl cluster-info --context kind-$CLUSTER_NAME
}

setup_vault_tls() {
    log "=== 2. Setting up TLS secret for Vault ==="
    kubectl delete secret $VAULT_TLS_SECRET --ignore-not-found
    kubectl create secret tls $VAULT_TLS_SECRET \
        --cert=certs/vault.local.pem \
        --key=certs/vault.local-key.pem

    log "Vault TLS secret created successfully"
}

install_vault() {
    log "=== 3. Installing Vault via Helm ==="
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update

    # Uninstall existing Vault
    helm uninstall vault 2>/dev/null || true

    # Wait for cleanup
    kubectl wait --for=delete pod -l app.kubernetes.io/name=vault --timeout=60s || true

    # Install Vault with TLS
    helm install vault hashicorp/vault \
        --set "server.dev.enabled=false" \
        --set "server.ha.enabled=false" \
        --set 'server.standalone.config=listener "tcp" { address = ":8200" tls_cert_file = "/vault/userconfig/tls/tls.crt" tls_key_file = "/vault/userconfig/tls/tls.key" } storage "file" { path = "/vault/data" }' \
        --set "server.extraVolumes[0].name=vault-tls" \
        --set "server.extraVolumes[0].secret.secretName=$VAULT_TLS_SECRET" \
        --set "server.extraVolumeMounts[0].name=vault-tls" \
        --set "server.extraVolumeMounts[0].mountPath=/vault/userconfig/tls" \
        --set "server.extraVolumeMounts[0].readOnly=true"

    log "Vault installation initiated"
}

wait_for_vault() {
    log "=== 4. Waiting for Vault pod to be ready ==="
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault --timeout=300s
    log "Vault pod is ready"
}

setup_port_forward() {
    log "=== 5. Setting up Vault port-forward ==="
    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*vault.*8200" || true
    sleep 2

    # Start new port-forward in background
    kubectl port-forward svc/vault 8200:8200 &
    PORT_FORWARD_PID=$!

    # Wait for port-forward to be ready
    for i in {1..30}; do
        if nc -z localhost 8200 2>/dev/null; then
            log "Port-forward established successfully"
            return 0
        fi
        sleep 1
    done

    error "Failed to establish port-forward to Vault"
}

initialize_vault() {
    log "=== 6. Initializing and unsealing Vault ==="

    # Wait a bit more for Vault to be fully ready
    sleep 5

    # Initialize Vault
    log "Initializing Vault..."
    INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1 -format=json -address=$VAULT_ADDR -tls-skip-verify)

    UNSEAL_KEY=$(echo $INIT_OUTPUT | jq -r .unseal_keys_b64[0])
    ROOT_TOKEN=$(echo $INIT_OUTPUT | jq -r .root_token)

    # Save keys for reference
    echo "Unseal Key: $UNSEAL_KEY" > vault-keys.txt
    echo "Root Token: $ROOT_TOKEN" >> vault-keys.txt
    log "Vault keys saved to vault-keys.txt"

    # Unseal Vault
    log "Unsealing Vault..."
    vault operator unseal $UNSEAL_KEY -address=$VAULT_ADDR -tls-skip-verify

    # Login with root token
    export VAULT_TOKEN=$ROOT_TOKEN
    vault auth -address=$VAULT_ADDR -tls-skip-verify $ROOT_TOKEN

    log "Vault initialized and unsealed successfully"
}

configure_vault_auth() {
    log "=== 7. Configuring Vault Kubernetes authentication ==="

    export VAULT_TOKEN=$(grep "Root Token:" vault-keys.txt | cut -d' ' -f3)

    # Enable Kubernetes auth
    log "Enabling Kubernetes auth method..."
    vault auth enable kubernetes -address=$VAULT_ADDR -tls-skip-verify

    # Get Kubernetes cluster info
    K8S_HOST="https://kubernetes.default.svc:443"
    K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)

    # Configure Kubernetes auth
    log "Configuring Kubernetes auth..."
    vault write auth/kubernetes/config \
        token_reviewer_jwt="$(kubectl get secret $(kubectl get serviceaccount default -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)" \
        kubernetes_host="$K8S_HOST" \
        kubernetes_ca_cert="$K8S_CA_CERT" \
        -address=$VAULT_ADDR -tls-skip-verify

    # Create policy for myapp
    log "Creating application policy..."
    vault policy write myapp-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

    # Create role for myapp
    log "Creating Kubernetes role..."
    vault write auth/kubernetes/role/myapp \
        bound_service_account_names=myapp-sa \
        bound_service_account_namespaces=default \
        policies=myapp-policy \
        ttl=1h \
        -address=$VAULT_ADDR -tls-skip-verify

    log "Vault Kubernetes authentication configured successfully"
}

enable_kv_secrets() {
    log "=== 8. Enabling KV secrets engine and loading initial secrets ==="

    export VAULT_TOKEN=$(grep "Root Token:" vault-keys.txt | cut -d' ' -f3)

    # Enable KV v2 secrets engine
    log "Enabling KV secrets engine..."
    vault secrets enable -path=secret kv-v2 -address=$VAULT_ADDR -tls-skip-verify

    # Load initial secrets
    log "Loading initial application secrets..."
    vault kv put secret/myapp/db \
        username="devuser" \
        password="devpass" \
        host="postgres.default.svc.cluster.local" \
        port="5432" \
        database="myapp" \
        -address=$VAULT_ADDR -tls-skip-verify

    vault kv put secret/myapp/api \
        external-api-key="dev-api-key-12345" \
        jwt-secret="dev-jwt-secret-abcdef" \
        -address=$VAULT_ADDR -tls-skip-verify

    # Verify secrets were loaded
    log "Verifying secrets..."
    vault kv get secret/myapp/db -address=$VAULT_ADDR -tls-skip-verify >/dev/null
    vault kv get secret/myapp/api -address=$VAULT_ADDR -tls-skip-verify >/dev/null

    log "Initial secrets loaded successfully"
}

build_and_load_app() {
    log "=== 9. Building and loading Spring Boot application ==="

    # Build application
    log "Building Spring Boot application..."
    if [[ -f "./mvnw" ]]; then
        ./mvnw clean package -DskipTests
    else
        mvn clean package -DskipTests
    fi

    # Build Docker image
    log "Building Docker image..."
    docker build -t $APP_NAME:latest .

    # Load image into kind
    log "Loading Docker image into kind cluster..."
    kind load docker-image $APP_NAME:latest --name $CLUSTER_NAME

    log "Application built and loaded successfully"
}

deploy_app() {
    log "=== 10. Deploying Spring Boot application ==="

    # Apply Kubernetes manifests
    kubectl apply -f k8s/

    # Wait for deployment
    log "Waiting for application deployment..."
    kubectl wait --for=condition=Available deployment/myapp --timeout=300s

    # Wait for pods to be ready
    kubectl wait --for=condition=Ready pod -l app=myapp --timeout=300s

    log "Application deployed successfully"
}

show_status() {
    log "=== 11. Deployment Status ==="

    echo -e "\n${BLUE}=== VAULT STATUS ===${NC}"
    kubectl get pods -l app.kubernetes.io/name=vault
    echo -e "Vault UI: ${GREEN}$VAULT_ADDR${NC}"
    echo -e "Root Token: ${GREEN}$(grep 'Root Token:' vault-keys.txt | cut -d' ' -f3)${NC}"

    echo -e "\n${BLUE}=== APPLICATION STATUS ===${NC}"
    kubectl get pods -l app=myapp
    kubectl get svc myapp

    echo -e "\n${BLUE}=== ACCESS INFORMATION ===${NC}"
    APP_PORT=$(kubectl get svc myapp -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "8080")
    echo -e "Application: ${GREEN}kubectl port-forward svc/myapp 8080:8080${NC}"
    echo -e "Then access: ${GREEN}http://localhost:8080${NC}"

    echo -e "\n${BLUE}=== USEFUL COMMANDS ===${NC}"
    echo -e "View app logs: ${GREEN}kubectl logs -l app=myapp -f${NC}"
    echo -e "View vault logs: ${GREEN}kubectl logs -l app.kubernetes.io/name=vault -f${NC}"
    echo -e "Access vault: ${GREEN}export VAULT_ADDR=$VAULT_ADDR && export VAULT_TOKEN=\$(grep 'Root Token:' vault-keys.txt | cut -d' ' -f3)${NC}"

    echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
}

# Main execution
main() {
    # Handle command line arguments
    if [[ $1 == "--cleanup" ]]; then
        cleanup
        exit 0
    fi

    log "Starting enhanced kind deployment workflow..."

    validate_prerequisites
    create_kind_cluster
    setup_vault_tls
    install_vault
    wait_for_vault
    setup_port_forward
    initialize_vault
    configure_vault_auth
    enable_kv_secrets
    build_and_load_app
    deploy_app
    show_status

    log "All done! Your Spring Boot + Vault environment is ready."
}

# Trap cleanup on exit
trap 'error "Script interrupted"' INT TERM

main "$@"