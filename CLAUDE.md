# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Spring Boot application demonstrating production-ready Kubernetes deployment with HashiCorp Vault integration. The architecture consists of:

- **Spring Boot 3.2.0** application with Java 17
- **HashiCorp Vault** for secure secret management using Kubernetes authentication
- **Kind cluster** for local development and testing
- **Production-ready Kubernetes manifests** with security, monitoring, and scaling features

### Key Components

- **Main Application**: `src/main/java/com/example/myapp/MyAppApplication.java` - Standard Spring Boot entry point
- **Vault Configuration**: `src/main/java/com/example/myapp/config/AppConfiguration.java` - Manages Vault secret injection
- **REST Controller**: `src/main/java/com/example/myapp/controller/AppController.java` - Provides endpoints for testing Vault integration
- **Entity Layer**: `src/main/java/com/example/myapp/entity/User.java` - JPA entities for database operations

### Configuration Architecture

- **Application Config**: `src/main/resources/application.yml` - Uses Vault secret placeholders with fallback defaults
- **Kubernetes Manifests**: `k8s/myapp.yaml` - Complete production-ready deployment with security contexts, probes, and autoscaling
- **Vault Integration**: Uses Kubernetes service account authentication, not static tokens

## Common Development Commands

### Build and Package
```bash
# Build with Maven (preferred method)
./mvnw clean package -DskipTests

# Alternative if mvnw is not available
mvn clean package -DskipTests

# Run tests
./mvnw test
```

### Local Development with Kind

```bash
# Complete deployment (one command setup)
chmod +x deploy-kind.sh
./deploy-kind.sh

# Cleanup everything
./deploy-kind.sh --cleanup
```

### Application Testing
```bash
# Port forward to access the application
kubectl port-forward svc/myapp 8080:8080

# Test endpoints
curl http://localhost:8080/                    # Home page
curl http://localhost:8080/config              # Configuration (safe values)
curl http://localhost:8080/health              # Health check
curl http://localhost:8080/vault-test          # Vault integration test
```

### Kubernetes Operations
```bash
# Application logs
kubectl logs -l app=myapp -f

# Vault logs
kubectl logs -l app.kubernetes.io/name=vault -f

# Check pod status
kubectl get pods

# Update application after code changes
./mvnw clean package -DskipTests
docker build -t myapp:latest .
kind load docker-image myapp:latest --name dev
kubectl rollout restart deployment/myapp
```

### Vault Operations
```bash
# Access Vault UI (after deployment)
# Vault is port-forwarded automatically by deploy-kind.sh
open https://vault.local:8200

# Get root token
cat vault-keys.txt

# Set environment for CLI operations
export VAULT_ADDR=https://vault.local:8200
export VAULT_TOKEN=$(grep 'Root Token:' vault-keys.txt | cut -d' ' -f3)

# Add new secrets
vault kv put secret/myapp/cache redis-url="redis://redis.default.svc.cluster.local:6379"
vault kv put secret/myapp/email smtp-server="smtp.gmail.com" smtp-username="app@company.com"
```

## Deployment Architecture

### Local Development (Kind)
- **Cluster Name**: `dev`
- **Vault**: Runs with TLS using self-signed certificates
- **Authentication**: Kubernetes service account based
- **Secrets**: Automatically populated during deployment
- **Networking**: Uses kind's built-in networking with port forwarding

### Certificate Management
- TLS certificates must be generated before deployment
- Stored in `certs/` directory
- Vault requires `vault.local.pem` and `vault.local-key.pem`
- `/etc/hosts` entry required: `127.0.0.1 vault.local`

### Secret Structure in Vault
```
secret/myapp/db/username = "devuser"
secret/myapp/db/password = "devpass"
secret/myapp/db/host = "postgres.default.svc.cluster.local"
secret/myapp/db/port = "5432"
secret/myapp/db/database = "myapp"

secret/myapp/api/external-api-key = "dev-api-key-12345"
secret/myapp/api/jwt-secret = "dev-jwt-secret-abcdef"
```

## Security Features

- **Non-root containers**: All containers run as user 1001
- **Network policies**: Restricts pod-to-pod communication
- **TLS everywhere**: Vault communication encrypted
- **Kubernetes RBAC**: Service account with minimal permissions
- **Secret rotation**: Vault handles automatic renewal
- **Security contexts**: Proper filesystem permissions

## Production Readiness Features

- **Health checks**: Liveness, readiness, and startup probes
- **Resource management**: CPU and memory limits/requests
- **Horizontal scaling**: HPA based on CPU/memory usage
- **Rolling updates**: Zero-downtime deployments with proper strategy
- **Pod disruption budgets**: Maintains availability during cluster operations
- **Monitoring**: Actuator endpoints exposed for Prometheus

## Troubleshooting

### Port Forward Issues
```bash
# Kill existing port-forwards and restart
pkill -f "kubectl port-forward"
kubectl port-forward svc/vault 8200:8200 &
kubectl port-forward svc/myapp 8080:8080 &
```

### Certificate Issues
```bash
# Regenerate certificates if needed
mkdir -p certs && cd certs
openssl genrsa -out vault.local-key.pem 2048
openssl req -new -x509 -key vault.local-key.pem -out vault.local.pem -days 365 -subj "/CN=vault.local"
```

### Vault Connection Issues
```bash
# Check Vault status
kubectl exec -it deployment/vault -- vault status

# Verify certificates
openssl x509 -in certs/vault.local.pem -text -noout
```