#!/bin/bash
# Proxmox Template Creator - Container Registry Module
# Deploy and manage private Docker registry with authentication and SSL/TLS

set -e

# Script version
VERSION="0.1.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR

# Logging function
log() {
    local level="$1"; shift
    local color=""
    local reset="\033[0m"
    case $level in
        INFO)
            color="\033[0;32m" # Green
            ;;
        WARN)
            color="\033[0;33m" # Yellow
            ;;
        ERROR)
            color="\033[0;31m" # Red
            ;;
        *)
            color=""
            ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*${reset}"
}

# Error handling function
# shellcheck disable=SC2317  # False positive - this function is used in trap
handle_error() {
    local exit_code="$1"
    local line_no="$2"
    log "ERROR" "An error occurred on line $line_no with exit code $exit_code"
    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit "$exit_code"
}

# Set up error trap
trap 'handle_error $? $LINENO' ERR

# Parse command line arguments
TEST_MODE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            shift
            ;;
        --help|-h)
            cat << EOF
Proxmox Template Creator - Container Registry Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual deployments)
  --help, -h          Show this help message

EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Configuration
REGISTRY_DIR="/opt/registry"
REGISTRY_PORT="5000"
REGISTRY_UI_PORT="8080"
REGISTRY_VERSION="2.8.3"

# Function to check if Docker is installed
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "INFO" "Docker is installed"
        return 0
    else
        log "INFO" "Docker is not installed"
        return 1
    fi
}

# Function to install Docker (if needed)
install_docker() {
    log "INFO" "Installing Docker..."

    # Update package index
    apt-get update

    # Install dependencies
    apt-get install -y ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Enable and start Docker
    systemctl enable --now docker

    log "INFO" "Docker installed successfully"
}

# Function to check for required tools
check_dependencies() {
    local missing_tools=()

    # Check for openssl
    if ! command -v openssl >/dev/null 2>&1; then
        missing_tools+=("openssl")
    fi

    # Check for apache2-utils (for htpasswd)
    if ! command -v htpasswd >/dev/null 2>&1; then
        missing_tools+=("apache2-utils")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing_tools[*]}"
        apt-get update
        apt-get install -y "${missing_tools[@]}"
    fi
}

# Function to create registry directories
create_registry_dirs() {
    log "INFO" "Creating registry directories..."

    mkdir -p "$REGISTRY_DIR"/{data,auth,certs,config}

    log "INFO" "Registry directories created"
}

# Function to generate SSL certificates
generate_ssl_certificates() {
    log "INFO" "Generating SSL certificates..."

    local hostname
    hostname=$(hostname -f)
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')

    # Create OpenSSL config
    cat > "$REGISTRY_DIR/certs/openssl.conf" << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
OU = Organizational Unit
CN = $hostname

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $hostname
DNS.2 = localhost
IP.1 = $ip_address
IP.2 = 127.0.0.1
EOF

    # Generate private key
    openssl genrsa -out "$REGISTRY_DIR/certs/registry.key" 4096

    # Generate certificate signing request
    openssl req -new -key "$REGISTRY_DIR/certs/registry.key" -out "$REGISTRY_DIR/certs/registry.csr" -config "$REGISTRY_DIR/certs/openssl.conf"

    # Generate self-signed certificate
    openssl x509 -req -days 365 -in "$REGISTRY_DIR/certs/registry.csr" -signkey "$REGISTRY_DIR/certs/registry.key" -out "$REGISTRY_DIR/certs/registry.crt" -extensions v3_req -extfile "$REGISTRY_DIR/certs/openssl.conf"

    # Set proper permissions
    chmod 600 "$REGISTRY_DIR/certs/registry.key"
    chmod 644 "$REGISTRY_DIR/certs/registry.crt"

    log "INFO" "SSL certificates generated"
    log "INFO" "Certificate details:"
    log "INFO" "  Hostname: $hostname"
    log "INFO" "  IP Address: $ip_address"
    log "INFO" "  Certificate: $REGISTRY_DIR/certs/registry.crt"
    log "INFO" "  Private Key: $REGISTRY_DIR/certs/registry.key"
}

# Function to create authentication
create_authentication() {
    log "INFO" "Setting up authentication..."

    local username
    local password

    if [ -n "$TEST_MODE" ]; then
        username="admin"
        password="admin"
        log "INFO" "Test mode: Using default credentials (admin/admin)"
    else
        # Prompt for username and password
        username=$(whiptail --inputbox "Enter registry username:" 10 60 "admin" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            log "ERROR" "Username input cancelled"
            return 1
        fi

        password=$(whiptail --passwordbox "Enter registry password:" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            log "ERROR" "Password input cancelled"
            return 1
        fi
    fi

    # Create htpasswd file
    htpasswd -Bbn "$username" "$password" > "$REGISTRY_DIR/auth/htpasswd"

    log "INFO" "Authentication configured for user: $username"
}

# Function to create registry configuration
create_registry_config() {
    log "INFO" "Creating registry configuration..."

    cat > "$REGISTRY_DIR/config/config.yml" << 'EOF'
version: 0.1

# Server settings
server:
  addr: :5000
  debug:
    addr: :5001  # Debug server on different port
  headers:
    X-Content-Type-Options: [nosniff]
    X-Frame-Options: [DENY]
    X-XSS-Protection: [1; mode=block]
    Content-Security-Policy: ["default-src 'none'", "style-src 'self' 'unsafe-inline'", "img-src 'self' data:", "font-src 'self'"]

# Authentication settings
auth:
  htpasswd:
    realm: Registry Realm
    path: /auth/htpasswd

# Storage configuration
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
    maxthreads: 100
  maintenance:
    uploadpurging:
      enabled: true
      age: 168h  # 1 week
      interval: 24h
      dryrun: false
  delete:
    enabled: true
  redirect:
    disable: false

# HTTP settings
http:
  debug:
    addr: :5001
  headers:
    X-Content-Type-Options: [nosniff]
    X-Frame-Options: [DENY]
    X-XSS-Protection: [1; mode=block]
    Content-Security-Policy: ["default-src 'none'", "style-src 'self' 'unsafe-inline'", "img-src 'self' data:", "font-src 'self'"]
  tls:
    certificate: /certs/registry.crt
    key: /certs/registry.key
    minimumTLS: tls1.2
    clientCAs:
      - /certs/registry-ca.crt
  http2:
    disabled: false
  debug:
    addr: localhost:5001

# Logging configuration
log:
  level: info
  formatter: text
  fields:
    service: registry
    environment: production
  hooks:
    - type: mail
      levels: [error, panic]
      mailoptions:
        smtp:
          addr: mail.example.com:25
          username: your_username
          password: your_password
          insecure: false
        from: registry@example.com
        to: [admin@example.com]

# Validation settings
validation:
  manifests:
    urls:
      allow:
        - ^https?://([^/]+/)*[^:]+$
      deny:
        - ^https?://example\.com/.*$

# Middleware configuration
middleware:
  registry:
    - name: AUTH
    - name: GZIP
  repository:
    - name: AUTH
    - name: GZIP
  storage:
    - name: REDIRECT
    - name: MAINTENANCE

# Health check configuration
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
  file:
    - file: /var/lib/registry/healthcheck
      interval: 10s
  tcp:
    - addr: redis:6379
      timeout: 3s
      interval: 30s

# Monitoring configuration
profiling:
  stackdriver:
    enabled: false
    service: registry
    serviceversion: v1.0.0
    projectid: your-project-id
    keyfile: /path/to/keyfile.json

# Redis configuration for cache and notifications
redis:
  addr: redis:6379
  password: your_redis_password
  db: 0
  dialtimeout: 10s
  readtimeout: 10s
  writetimeout: 10s
  pool:
    maxidle: 16
    maxactive: 64
    idletimeout: 300s

# Notifications configuration
notifications:
  endpoints:
    - name: alistener
      disabled: false
      url: https://webhook.example.com/registry
      headers:
        Authorization: [Bearer <example token>]
      timeout: 500ms
      threshold: 5
      backoff: 1s
      ignoredmediatypes:
        - application/octet-stream
      ignore:
        medietypes:
          - application/octet-stream
        actions:
          - pull

# Garbage collection settings
gc:
  disabled: false
  maxbackoff: 24h
  noidlebackoff: false
  transactiontimeout: 10s
  reviewafter: 24h
  blobs:
    disabled: false
    interval: 24h
    storagetimeout: 5s
    policies:
      - repositories: ['.*']
        keepyoungerthan: 168h  # 1 week
        keep: 10
      - repositories: ['important/.*']
        keepyoungerthan: 720h  # 30 days
        keep: 50

# Compatibility settings
compatibility:
  schema1:
    enabled: false
  manifest:
    urls:
      allow:
        - ^https?://([^/]+/)*[^:]+$
      deny:
        - ^https?://example\.com/.*$

# Reporting settings
reporting:
  bugsnag:
    apikey: your-bugsnag-api-key
    releasestage: production
    endpoint: https://notify.bugsnag.com/
  newrelic:
    licensekey: your-newrelic-license-key
    name: registry
    verbose: false
    enabled: false

# HTTP API settings
httpapi:
  version: 2.0
  realm: Registry Realm
  service: Docker Registry
  issuer: registry-token-issuer
  rootcertbundle: /certs/registry.crt
  autoredirect: false
  ttl: 15m
  maxscheduled: 100
  maxincoming: 500
  maxrequests: 1000
  maxwait: 10s
  maxheaderbytes: 32768
  debug:
    addr: localhost:5001
    prometheus:
      enabled: true
      path: /metrics

# Storage middleware configuration
storage.middleware:
  - name: cloudfront
    options:
      baseurl: https://my.cloudfronted.domain.com/
      privatekey: /path/to/private/key.pem
      keypairid: cloudfrontkeypairid
      duration: 3000
  - name: redirect
    disable: false
  - name: cloudfront
    options:
      baseurl: https://my.cloudfronted.domain.com/
      privatekey: /path/to/private/key.pem
      keypairid: cloudfrontkeypairid
      duration: 3000

# Proxy configuration
proxy:
  remoteurl: https://registry-1.docker.io
  username: [username]
  password: [password]
  ttl: 168h
  header:
    X-Forwarded-Proto: [https]
    X-Forwarded-For: [192.168.1.1]
  remoteurls:
    - https://registry-1.docker.io
    - https://registry-2.docker.io
  username: [username]
  password: [password]
  ttl: 168h

# Redis cache configuration
cache:
  blobdescriptor: redis
  blobdescriptorsize: 10000
  blobdescriptorttl: 24h
  blobdescriptorpurge: 1h
  blobdescriptormaxsize: 1000000
  blobdescriptormaxage: 168h
  blobdescriptormaxitems: 1000000
  blobdescriptormaxsize: 1000000
  blobdescriptormaxage: 168h
  blobdescriptormaxitems: 1000000

# Rate limiting configuration
ratelimit:
  enabled: true
  backend: redis
  burst: 200
  average: 100
  period: 1s
  sources:
    - addr: 192.168.1.0/24
      burst: 500
      average: 200
    - addr: 10.0.0.0/8
      burst: 1000
      average: 500

# Authentication configuration
authn:
  token:
    realm: https://auth.example.com/token
    service: registry.example.com
    issuer: registry-token-issuer
    rootcertbundle: /certs/registry.crt
    autoredirect: false
    autoredirectscheme: https
    autoredirecthost: registry.example.com
    autoredirectstatus: 307
    autoredirectrealm: https://registry.example.com/token
    autoredirectservice: registry.example.com
    autoredirectissuer: registry-token-issuer

# Authorization configuration
authz:
  actions:
    pull:
      - match: {account: "/.+/"}
    push:
      - match: {account: "admin"}
      - match: {account: "deploy"}
    delete:
      - match: {account: "admin"}
    *:
      - match: {account: "admin"}

# Audit logging configuration
audit:
  enabled: true
  loglevel: info
  formatter: json
  hooks:
    - type: file
      options:
        filename: /var/log/registry/audit.log
        maxsize: 100
        maxbackups: 10
        maxage: 30
        compress: true

# Metrics configuration
metrics:
  enabled: true
  addr: :5001
  path: /metrics
  secret: your-secret-key
  debug:
    addr: :5002
    prometheus:
      enabled: true
      path: /metrics

# Tracing configuration
tracing:
  enabled: true
  service: registry
  tags:
    environment: production
  agent:
    host: localhost
    port: 6831
    type: const
    param: 1
  sampler:
    type: probabilistic
    param: 0.1
  reporter:
    queueSize: 1000
    bufferFlushInterval: 1s
    logSpans: true
  throttler:
    hostPort: localhost:5778
    refreshInterval: 10s
    synchronousInitialization: false

# Storage driver configuration
storage:
  filesystem:
    rootdirectory: /var/lib/registry
    maxthreads: 100
  cache:
    blobdescriptor: inmemory
  maintenance:
    uploadpurging:
      enabled: true
      age: 168h
      interval: 24h
      dryrun: false
  delete:
    enabled: true
  redirect:
    disable: false
  middleware:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# HTTP API v2 configuration
http:
  v2:
    enabled: true
    strict: true
    debug:
      addr: localhost:5001
    prometheus:
      enabled: true
      path: /metrics
    debug:
      addr: localhost:5001
    prometheus:
      enabled: true
      path: /metrics

# Repository middleware configuration
repository:
  middleware:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Storage driver middleware configuration
storagedriver:
  middleware:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Distribution configuration
distribution:
  storage:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Registry configuration
registry:
  storage:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Configuration for the registry service
service:
  registry:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Configuration for the registry API
api:
  version: 2.0
  registry:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Configuration for the registry storage driver
storagedriver:
  - name: cloudfront
    options:
      baseurl: https://my.cloudfronted.domain.com/
      privatekey: /path/to/private/key.pem
      keypairid: cloudfrontkeypairid
      duration: 3000

# Configuration for the registry middleware
middleware:
  registry:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Configuration for the registry storage
storage:
  - name: cloudfront
    options:
      baseurl: https://my.cloudfronted.domain.com/
      privatekey: /path/to/private/key.pem
      keypairid: cloudfrontkeypairid
      duration: 3000

# Configuration for the registry cache
cache:
  blobdescriptor: redis
  blobdescriptorsize: 10000
  blobdescriptorttl: 24h
  blobdescriptorpurge: 1h
  blobdescriptormaxsize: 1000000
  blobdescriptormaxage: 168h
  blobdescriptormaxitems: 1000000

# Configuration for the registry notifications
notifications:
  endpoints:
    - name: alistener
      disabled: false
      url: https://webhook.example.com/registry
      headers:
        Authorization: [Bearer <example token>]
      timeout: 500ms
      threshold: 5
      backoff: 1s
      ignoredmediatypes:
        - application/octet-stream
      ignore:
        medietypes:
          - application/octet-stream
        actions:
          - pull

# Configuration for the registry garbage collection
gc:
  disabled: false
  maxbackoff: 24h
  noidlebackoff: false
  transactiontimeout: 10s
  reviewafter: 24h
  blobs:
    disabled: false
    interval: 24h
    storagetimeout: 5s
    policies:
      - repositories: ['.*']
        keepyoungerthan: 168h  # 1 week
        keep: 10
      - repositories: ['important/.*']
        keepyoungerthan: 720h  # 30 days
        keep: 50

# Configuration for the registry validation
validation:
  manifests:
    urls:
      allow:
        - ^https?://([^/]+/)*[^:]+$
      deny:
        - ^https?://example\.com/.*$

# Configuration for the registry compatibility
compatibility:
  schema1:
    enabled: false
  manifest:
    urls:
      allow:
        - ^https?://([^/]+/)*[^:]+$
      deny:
        - ^https?://example\.com/.*$

# Configuration for the registry reporting
reporting:
  bugsnag:
    apikey: your-bugsnag-api-key
    releasestage: production
    endpoint: https://notify.bugsnag.com/
  newrelic:
    licensekey: your-newrelic-license-key
    name: registry
    verbose: false
    enabled: false

# Configuration for the registry HTTP API
httpapi:
  version: 2.0
  realm: Registry Realm
  service: Docker Registry
  issuer: registry-token-issuer
  rootcertbundle: /certs/registry.crt
  autoredirect: false
  ttl: 15m
  maxscheduled: 100
  maxincoming: 500
  maxrequests: 1000
  maxwait: 10s
  maxheaderbytes: 32768
  debug:
    addr: localhost:5001
    prometheus:
      enabled: true
      path: /metrics

# Configuration for the registry storage driver
storagedriver:
  - name: cloudfront
    options:
      baseurl: https://my.cloudfronted.domain.com/
      privatekey: /path/to/private/key.pem
      keypairid: cloudfrontkeypairid
      duration: 3000

# Configuration for the registry middleware
middleware:
  registry:
    - name: cloudfront
      options:
        baseurl: https://my.cloudfronted.domain.com/
        privatekey: /path/to/private/key.pem
        keypairid: cloudfrontkeypairid
        duration: 3000

# Configuration for the registry storage
storage:
  - name: cloudfront
    options:
      baseurl: https://my.cloudfronted.domain.com/
      privatekey: /path/to/private/key.pem
      keypairid: cloudfrontkeypairid
      duration: 3000

# Configuration for the registry cache
cache:
  blobdescriptor: redis
  blobdescriptorsize: 10000
  blobdescriptorttl: 24h
  blobdescriptorpurge: 1h
  blobdescriptormaxsize: 1000000
  blobdescriptormaxage: 168h
  blobdescriptormaxitems: 1000000

# Configuration for the registry notifications
notifications:
  endpoints:
    - name: alistener
      disabled: false
      url: https://webhook.example.com/registry
      headers:
        Authorization: [Bearer <example token>]
      timeout: 500ms
      threshold: 5
      backoff: 1s
      ignoredmediatypes:
        - application/octet-stream
      ignore:
        medietypes:
          - application/octet-stream
        actions:
          - pull

# Configuration for the registry garbage collection
gc:
  disabled: false
  maxbackoff: 24h
  noidlebackoff: false
  transactiontimeout: 10s
  reviewafter: 24h
  blobs:
    disabled: false
    interval: 24h
    storagetimeout: 5s
    policies:
      - repositories: ['.*']
        keepyoungerthan: 168h  # 1 week
        keep: 10
      - repositories: ['important/.*']
        keepyoungerthan: 720h  # 30 days
        keep: 50

# Configuration for the registry validation
validation:
  manifests:
    urls:
      allow:
        - ^https?://([^/]+/)*[^:]+$
      deny:
        - ^https?://example\.com/.*$

# Configuration for the registry compatibility
compatibility:
  schema1:
    enabled: false
  manifest:
    urls:
      allow:
        - ^https?://([^/]+/)*[^:]+$
      deny:
        - ^https?://example\.com/.*$

# Configuration for the registry reporting
reporting:
  bugsnag:
    apikey: your-bugsnag-api-key
    releasestage: production
    endpoint: https://notify.bugsnag.com/
  newrelic:
    licensekey: your-newrelic-license-key
    name: registry
    verbose: false
    enabled: false

# Configuration for the registry HTTP API
httpapi:
  version: 2.0
  realm: Registry Realm
  service: Docker Registry
  issuer: registry-token-issuer
  rootcertbundle: /certs/registry.crt
  autoredirect: false
  ttl: 15m
  maxscheduled: 100
  maxincoming: 500
  maxrequests: 1000
  maxwait: 10s
  maxheaderbytes: 32768
  debug:
    addr: localhost:5001
    prometheus:
      enabled: true
      path: /metrics
EOF

    log "INFO" "Registry configuration created"
}

# Function to create Docker Compose file
create_docker_compose() {
    log "INFO" "Creating Docker Compose configuration..."

    cat > "$REGISTRY_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  registry:
    image: registry:${REGISTRY_VERSION}
    container_name: docker-registry
    ports:
      - "${REGISTRY_PORT}:5000"
    volumes:
      - ./data:/var/lib/registry
      - ./auth:/auth
      - ./certs:/certs
      - ./config/config.yml:/etc/docker/registry/config.yml
    environment:
      - REGISTRY_AUTH=htpasswd
      - REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm
      - REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd
      - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt
      - REGISTRY_HTTP_TLS_KEY=/certs/registry.key
    restart: unless-stopped
    networks:
      - registry

  registry-ui:
    image: joxit/docker-registry-ui:latest
    container_name: registry-ui
    ports:
      - "${REGISTRY_UI_PORT}:80"
    environment:
      - SINGLE_REGISTRY=true
      - REGISTRY_TITLE=Private Docker Registry
      - DELETE_IMAGES=true
      - SHOW_CONTENT_DIGEST=true
      - NGINX_PROXY_PASS_URL=https://registry:5000
      - SHOW_CATALOG_NB_TAGS=true
      - CATALOG_MIN_BRANCHES=1
      - CATALOG_MAX_BRANCHES=1
      - TAGLIST_PAGE_SIZE=100
      - REGISTRY_SECURED=true
      - CATALOG_ELEMENTS_LIMIT=1000
    depends_on:
      - registry
    restart: unless-stopped
    networks:
      - registry

networks:
  registry:
    driver: bridge
EOF

    log "INFO" "Docker Compose configuration created"
}

# Function to deploy registry
deploy_registry() {
    log "INFO" "Deploying container registry..."

    cd "$REGISTRY_DIR"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would deploy registry with docker-compose up -d"
    else
        docker compose up -d

        # Wait for services to be ready
        log "INFO" "Waiting for services to be ready..."
        sleep 20

        # Check service status
        log "INFO" "Checking service status..."
        docker compose ps

        local hostname
        hostname=$(hostname -I | awk '{print $1}')

        log "INFO" "Container registry deployed successfully!"
        log "INFO" "Access URLs:"
        log "INFO" "  Registry API: https://$hostname:$REGISTRY_PORT/v2/"
        log "INFO" "  Registry UI: http://$hostname:$REGISTRY_UI_PORT"
        log "INFO" ""
        log "INFO" "Docker client configuration:"
        log "INFO" "  1. Copy certificate to Docker certs directory:"
        log "INFO" "     mkdir -p /etc/docker/certs.d/$hostname:$REGISTRY_PORT"
        log "INFO" "     cp $REGISTRY_DIR/certs/registry.crt /etc/docker/certs.d/$hostname:$REGISTRY_PORT/ca.crt"
        log "INFO" "  2. Test registry access:"
        log "INFO" "     docker login $hostname:$REGISTRY_PORT"
        log "INFO" "  3. Push an image:"
        log "INFO" "     docker tag hello-world $hostname:$REGISTRY_PORT/hello-world:latest"
        log "INFO" "     docker push $hostname:$REGISTRY_PORT/hello-world:latest"
    fi
}

# Function to check registry status
check_registry_status() {
    log "INFO" "Checking registry status..."

    if [ ! -f "$REGISTRY_DIR/docker-compose.yml" ]; then
        log "INFO" "Registry not deployed"
        return 1
    fi

    cd "$REGISTRY_DIR"

    local services_running=0
    local expected_services=2

    if docker compose ps --services --filter "status=running" | grep -q registry; then
        ((services_running++))
        log "INFO" "Registry: Running"
    else
        log "WARN" "Registry: Not running"
    fi

    if docker compose ps --services --filter "status=running" | grep -q registry-ui; then
        ((services_running++))
        log "INFO" "Registry UI: Running"
    else
        log "WARN" "Registry UI: Not running"
    fi

    if [ $services_running -eq $expected_services ]; then
        log "INFO" "All registry services are running"

        # Test registry API
        local hostname
        hostname=$(hostname -I | awk '{print $1}')

        if curl -k -s "https://$hostname:$REGISTRY_PORT/v2/" >/dev/null 2>&1; then
            log "INFO" "Registry API is accessible"
        else
            log "WARN" "Registry API is not accessible"
        fi

        return 0
    else
        log "WARN" "Some registry services are not running ($services_running/$expected_services)"
        return 1
    fi
}

# Function to stop registry
stop_registry() {
    log "INFO" "Stopping registry..."

    if [ ! -f "$REGISTRY_DIR/docker-compose.yml" ]; then
        log "INFO" "Registry not deployed"
        return 1
    fi

    cd "$REGISTRY_DIR"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would stop registry with docker-compose down"
    else
        docker compose down
        log "INFO" "Registry stopped"
    fi
}

# Function to remove registry
remove_registry() {
    log "INFO" "Removing registry..."

    if [ ! -f "$REGISTRY_DIR/docker-compose.yml" ]; then
        log "INFO" "Registry not deployed"
        return 1
    fi

    cd "$REGISTRY_DIR"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would remove registry and data"
    else
        # Stop and remove containers
        docker compose down -v

        # Ask for confirmation before removing data
        if whiptail --title "Remove Data" --yesno "Do you want to remove all registry data?\nThis action cannot be undone." 10 60; then
            rm -rf "$REGISTRY_DIR"
            log "INFO" "Registry and data removed"
        else
            log "INFO" "Registry removed, data preserved"
        fi
    fi
}

# Function to configure Docker client
configure_docker_client() {
    log "INFO" "Configuring Docker client for registry access..."

    local hostname
    hostname=$(hostname -I | awk '{print $1}')

    # Create Docker certs directory
    mkdir -p "/etc/docker/certs.d/$hostname:$REGISTRY_PORT"

    # Copy certificate
    if [ -f "$REGISTRY_DIR/certs/registry.crt" ]; then
        cp "$REGISTRY_DIR/certs/registry.crt" "/etc/docker/certs.d/$hostname:$REGISTRY_PORT/ca.crt"
        log "INFO" "Certificate copied to Docker certs directory"
    else
        log "ERROR" "Registry certificate not found"
        return 1
    fi

    # Test registry access
    log "INFO" "Testing registry access..."
    if curl -k -s "https://$hostname:$REGISTRY_PORT/v2/" >/dev/null 2>&1; then
        log "INFO" "Registry is accessible"
        log "INFO" "You can now login with: docker login $hostname:$REGISTRY_PORT"
    else
        log "ERROR" "Registry is not accessible"
        return 1
    fi
}

# Function to show registry information
show_registry_info() {
    log "INFO" "Registry Information"
    log "INFO" "==================="

    if [ ! -f "$REGISTRY_DIR/docker-compose.yml" ]; then
        log "INFO" "Registry not deployed"
        return 1
    fi

    local hostname
    hostname=$(hostname -I | awk '{print $1}')

    log "INFO" "Registry Status: $(check_registry_status && echo "Running" || echo "Not Running")"
    log "INFO" "Registry URL: https://$hostname:$REGISTRY_PORT"
    log "INFO" "Registry UI: http://$hostname:$REGISTRY_UI_PORT"
    log "INFO" "Data Directory: $REGISTRY_DIR/data"
    log "INFO" "Certificate: $REGISTRY_DIR/certs/registry.crt"
    log "INFO" "Configuration: $REGISTRY_DIR/config/config.yml"

    if [ -f "$REGISTRY_DIR/auth/htpasswd" ]; then
        log "INFO" "Authentication: Enabled"
    else
        log "INFO" "Authentication: Disabled"
    fi
}

# Main menu function
main_menu() {
    local option
    option=$(whiptail --title "Container Registry" --menu "Choose an option:" 18 70 8 \
        "1" "Deploy container registry" \
        "2" "Check registry status" \
        "3" "Configure Docker client" \
        "4" "Show registry information" \
        "5" "Stop registry" \
        "6" "Remove registry" \
        "7" "Help & Documentation" \
        "8" "Exit" 3>&1 1>&2 2>&3)

    case $option in
        1)
            # Deploy registry
            if ! check_docker; then
                if whiptail --title "Docker Required" --yesno "Docker is required for the container registry.\nInstall Docker now?" 10 60; then
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would install Docker"
                    else
                        install_docker
                    fi
                else
                    log "INFO" "Docker installation cancelled"
                    return 1
                fi
            fi

            check_dependencies
            create_registry_dirs
            generate_ssl_certificates
            create_authentication
            create_registry_config
            create_docker_compose
            deploy_registry

            whiptail --title "Registry Deployed" --msgbox "Container registry has been deployed successfully!\n\nNext steps:\n1. Configure Docker client (option 3)\n2. Access registry UI in your browser\n3. Start pushing/pulling images" 12 70
            main_menu
            ;;
        2)
            # Check status
            check_registry_status
            whiptail --title "Registry Status" --msgbox "Check the terminal output for detailed status information." 10 60
            main_menu
            ;;
        3)
            # Configure Docker client
            configure_docker_client
            whiptail --title "Docker Client Configured" --msgbox "Docker client has been configured for registry access.\n\nYou can now use:\ndocker login $(hostname -I | awk '{print $1}'):$REGISTRY_PORT" 10 70
            main_menu
            ;;
        4)
            # Show registry information
            show_registry_info
            whiptail --title "Registry Information" --msgbox "Check the terminal output for detailed registry information." 10 60
            main_menu
            ;;
        5)
            # Stop registry
            stop_registry
            main_menu
            ;;
        6)
            # Remove registry
            if whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove the container registry?" 10 60; then
                remove_registry
            fi
            main_menu
            ;;
        7)
            whiptail --title "Container Registry Help" --msgbox "Container Registry Module v${VERSION}\n\nThis module helps you deploy a private Docker registry with:\n\n- Private Docker Registry v2\n- SSL/TLS encryption\n- HTTP authentication\n- Web UI for management\n- Docker client configuration\n\nDefault ports:\n- Registry: 5000 (HTTPS)\n- UI: 8080 (HTTP)\n\nFor more information, see the documentation." 18 70
            main_menu
            ;;
        8|*)
            log "INFO" "Exiting container registry module."
            exit 0
            ;;
    esac
}

# Run the main menu if not in test mode
if [ -n "$TEST_MODE" ]; then
    log "INFO" "Container Registry module (test mode)"
else
    main_menu
fi

exit 0
