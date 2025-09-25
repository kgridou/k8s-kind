#!/bin/bash
set -e

CERT_DIR="certs"
DOMAIN="vault.local"
KEY_SIZE=2048
DAYS_VALID=365

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if openssl is available
command -v openssl >/dev/null 2>&1 || error "openssl is required but not installed"

log "Generating TLS certificates for Vault"

# Create certs directory
mkdir -p $CERT_DIR

# Generate private key
log "Generating private key..."
openssl genrsa -out $CERT_DIR/$DOMAIN-key.pem $KEY_SIZE

# Create certificate configuration
log "Creating certificate configuration..."
cat > $CERT_DIR/cert.conf <<EOF
[req]
default_bits = $KEY_SIZE
prompt = no
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = Development
OU = IT Department
CN = $DOMAIN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
DNS.3 = vault
DNS.4 = vault.default
DNS.5 = vault.default.svc
DNS.6 = vault.default.svc.cluster.local
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate certificate
log "Generating certificate..."
openssl req -new -x509 -key $CERT_DIR/$DOMAIN-key.pem \
    -out $CERT_DIR/$DOMAIN.pem \
    -days $DAYS_VALID \
    -config $CERT_DIR/cert.conf \
    -extensions v3_req

# Set proper permissions
chmod 600 $CERT_DIR/$DOMAIN-key.pem
chmod 644 $CERT_DIR/$DOMAIN.pem

# Clean up config file
rm $CERT_DIR/cert.conf

# Verify certificate
log "Verifying certificate..."
openssl x509 -in $CERT_DIR/$DOMAIN.pem -text -noout | grep -A 1 "Subject:"
openssl x509 -in $CERT_DIR/$DOMAIN.pem -text -noout | grep -A 10 "Subject Alternative Name:"

log "Certificate details:"
echo -e "  Private Key: ${GREEN}$CERT_DIR/$DOMAIN-key.pem${NC}"
echo -e "  Certificate: ${GREEN}$CERT_DIR/$DOMAIN.pem${NC}"
echo -e "  Valid for:   ${GREEN}$DAYS_VALID days${NC}"

# Add to /etc/hosts if not already present
if ! grep -q "$DOMAIN" /etc/hosts 2>/dev/null; then
    warn "Adding $DOMAIN to /etc/hosts (requires sudo)"
    echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
    log "Added $DOMAIN to /etc/hosts"
else
    log "$DOMAIN already exists in /etc/hosts"
fi

# Test certificate
log "Testing certificate validity..."
openssl verify -CAfile $CERT_DIR/$DOMAIN.pem $CERT_DIR/$DOMAIN.pem || warn "Self-signed certificate verification warning (expected)"

echo ""
log "✅ TLS certificates generated successfully!"
echo -e "You can now run: ${GREEN}./deploy-kind.sh${NC}"