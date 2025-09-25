# Spring Boot + Vault + Kubernetes (Kind) - Complete Workflow

A **production-ready**, **one-command** deployment workflow that sets up:
- **Spring Boot** application with Vault integration
- **HashiCorp Vault** with TLS and Kubernetes authentication
- **Complete automation** from source code to running application
- **Same configuration** for local kind and production K8s

## 🚀 Quick Start

### Prerequisites

Install required tools:
```bash
# macOS
brew install kind kubectl helm docker

# or Ubuntu/Debian
sudo snap install kubectl helm
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

### Generate TLS Certificates

Create self-signed certificates for Vault:
```bash
mkdir -p certs
cd certs

# Generate private key
openssl genrsa -out vault.local-key.pem 2048

# Generate certificate
openssl req -new -x509 -key vault.local-key.pem -out vault.local.pem -days 365 -subj "/CN=vault.local"

# Add to /etc/hosts
echo "127.0.0.1 vault.local" | sudo tee -a /etc/hosts

cd ..
```

### Deploy Everything

Run the single command:
```bash
chmod +x deploy-kind.sh
./deploy-kind.sh
```

That's it! The script will:
1. ✅ Create kind cluster
2. ✅ Install and configure Vault with TLS
3. ✅ Initialize and unseal Vault
4. ✅ Enable Kubernetes authentication
5. ✅ Load application secrets
6. ✅ Build and deploy Spring Boot app
7. ✅ Verify everything is working

## 📁 Project Structure

```
project/
├── deploy-kind.sh           # Main deployment script
├── Dockerfile              # Multi-stage Docker build
├── pom.xml                 # Maven dependencies
├── README.md               # This file
├── src/
│   └── main/java/com/example/myapp/
│       ├── MyAppApplication.java        # Main Spring Boot class
│       ├── controller/AppController.java # REST endpoints
│       ├── config/AppConfiguration.java # Vault secrets config
│       └── entity/User.java            # JPA entity example
├── src/main/resources/
│   └── application.yml     # Spring Boot configuration
├── k8s/
│   └── myapp.yaml         # Kubernetes manifests
├── certs/
│   ├── vault.local.pem    # Vault TLS certificate
│   └── vault.local-key.pem # Vault TLS private key
└── vault-keys.txt         # Auto-generated Vault keys
```

## 🔧 Configuration Details

### Vault Secrets Structure
The script automatically creates these secrets in Vault:

```bash
# Database credentials
secret/myapp/db/username = "devuser"
secret/myapp/db/password = "devpass"
secret/myapp/db/host = "postgres.default.svc.cluster.local"
secret/myapp/db/port = "5432"
secret/myapp/db/database = "myapp"

# API keys
secret/myapp/api/external-api-key = "dev-api-key-12345"
secret/myapp/api/jwt-secret = "dev-jwt-secret-abcdef"
```

### Spring Boot Configuration
The application uses **Kubernetes authentication** to connect to Vault:

```yaml
spring:
  cloud:
    vault:
      uri: https://vault.local:8200
      authentication: kubernetes
      kubernetes:
        role: myapp
        service-account-token-file: /var/run/secrets/kubernetes.io/serviceaccount/token
```

## 🌐 Access Your Application

After deployment, access your services:

### Application Endpoints
```bash
# Port-forward to access the app
kubectl port-forward svc/myapp 8080:8080

# Test endpoints
curl http://localhost:8080/                    # Home page
curl http://localhost:8080/config              # Configuration (safe values)
curl http://localhost:8080/health              # Health check
curl http://localhost:8080/vault-test          # Vault integration test
```

### Vault UI
```bash
# Vault is already port-forwarded by the script
open https://vault.local:8200

# Login with root token (check vault-keys.txt)
cat vault-keys.txt
```

### Monitoring
```bash
# Application logs
kubectl logs -l app=myapp -f

# Vault logs  
kubectl logs -l app.kubernetes.io/name=vault -f

# All pods status
kubectl get pods
```

## 🛠️ Advanced Usage

### Cleanup
```bash
./deploy-kind.sh --cleanup
```

### Add More Secrets
```bash
# Set environment variables
export VAULT_ADDR=https://vault.local:8200
export VAULT_TOKEN=$(grep 'Root Token:' vault-keys.txt | cut -d' ' -f3)

# Add new secrets
vault kv put secret/myapp/cache redis-url="redis://redis.default.svc.cluster.local:6379"
vault kv put secret/myapp/email smtp-server="smtp.gmail.com" smtp-username="app@company.com"
```

### Update Application
```bash
# Make code changes, then redeploy
./mvnw clean package -DskipTests
docker build -t myapp:latest .
kind load docker-image myapp:latest --name dev
kubectl rollout restart deployment/myapp
```

## 🔐 Security Features

- **TLS Everywhere**: Vault runs with proper TLS certificates
- **Kubernetes Auth**: No hardcoded credentials
- **Least Privilege**: Custom Vault policy for application
- **Network Policies**: Restricts pod-to-pod communication  
- **Security Context**: Runs as non-root user
- **Secret Rotation**: Vault handles automatic secret renewal

## 🏭 Production Readiness

This setup includes production-ready features:

- **Health Checks**: Liveness, readiness, and startup probes
- **Resource Limits**: Memory and CPU constraints
- **Horizontal Scaling**: HPA based on CPU/memory
- **Pod Disruption Budget**: Ensures availability during updates
- **Rolling Updates**: Zero-downtime deployments
- **Observability**: Actuator endpoints for monitoring

## 🎯 Development Workflow

1. **Local Development**: Use the kind cluster for development
2. **Code Changes**: Modify application code
3. **Quick Deploy**: Use the update commands above
4. **Test**: Use the provided endpoints to verify functionality
5. **Production**: The same manifests work in production K8s

## 🔍 Troubleshooting

### Vault Connection Issues
```bash
# Check Vault status
kubectl exec -it deployment/vault -- vault status

# Check certificates
openssl x509 -in certs/vault.local.pem -text -noout
```

### Application Issues
```bash
# Check application logs
kubectl logs -l app=myapp --tail=50

# Check Vault integration
kubectl exec -it deployment/myapp -- env | grep VAULT
```

### Port Forward Issues
```bash
# Kill existing port-forwards
pkill -f "kubectl port-forward"

# Restart port-forward
kubectl port-forward svc/vault 8200:8200 &
kubectl port-forward svc/myapp 8080:8080 &
```

## 📝 Customization

### Environment Variables
Edit `k8s/myapp.yaml` to add environment variables:
```yaml
env:
- name: CUSTOM_CONFIG
  value: "your-value"
```

### Additional Secrets
Modify the `enable_kv_secrets()` function in `deploy-kind.sh` to add more secrets.

### Database Integration
The setup includes JPA configuration. To add a real database:

1. Deploy PostgreSQL to the cluster
2. Update the database secrets in Vault
3. The application will automatically connect

---

## ⚡ Key Benefits

- **One Command Deploy**: Complete local K8s environment in minutes
- **Production Parity**: Same config for dev and prod
- **Security First**: TLS, RBAC, and secret management built-in
- **Developer Friendly**: Easy debugging and development workflow
- **Enterprise Ready**: Includes monitoring, scaling, and reliability features

Ready to get started? Run `./deploy-kind.sh` and you'll have a complete Spring Boot + Vault environment running locally! 🎉