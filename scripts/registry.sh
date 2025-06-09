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
    
    cat > "$REGISTRY_DIR/config/config.yml" << EOF
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
    Access-Control-Allow-Origin: ['*']
    Access-Control-Allow-Methods: ['HEAD', 'GET', 'OPTIONS', 'DELETE']
    Access-Control-Allow-Headers: ['Authorization', 'Accept', 'Cache-Control']
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
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
