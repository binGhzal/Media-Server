#!/bin/bash
# Proxmox Template Creator - Containers Module
# Support for Docker and Kubernetes deployments

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

# Error handling function - Fixed unreachable function issue
handle_error() {
    local exit_code="$1"
    local line_no="$2"
    log "ERROR" "An error occurred on line $line_no with exit code $exit_code"
    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit "$exit_code"
}

# Set up error trap - Fixed to pass correct parameters
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
Proxmox Template Creator - Containers Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual deployments)
  --check-docker      Check if Docker is installed
  --help, -h          Show this help message

EOF
            exit 0
            ;;
        --check-docker)
            if command -v docker >/dev/null 2>&1; then
                log "INFO" "Docker is installed: $(docker --version)"
                exit 0
            else
                log "INFO" "Docker is not installed."
                exit 1
            fi
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Function to check Docker installation
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
        log "INFO" "Docker $docker_version is installed"
        return 0
    else
        log "INFO" "Docker is not installed"
        return 1
    fi
}

# Function to install Docker
install_docker() {
    log "INFO" "Installing Docker..."
    
    # Create a temporary file for the installation script
    local temp_script
    temp_script=$(mktemp)
    
    # Download the Docker installation script
    curl -fsSL https://get.docker.com -o "$temp_script"
    
    # Make it executable and run it
    chmod +x "$temp_script"
    sh "$temp_script"
    
    # Clean up
    rm "$temp_script"
    
    # Enable and start Docker service
    systemctl enable --now docker
    
    # Add current user to docker group if not running as root
    if [ "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
        log "INFO" "Added user $SUDO_USER to the docker group"
    fi
    
    log "INFO" "Docker installed successfully: $(docker --version)"
    return 0
}

# Function to install Docker Compose
install_docker_compose() {
    log "INFO" "Installing Docker Compose..."
    
    # Get the latest version of Docker Compose
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    
    # Download Docker Compose
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
    
    # Make it executable
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    
    log "INFO" "Docker Compose installed successfully: $(docker compose version)"
    return 0
}

# Function to check Kubernetes installation
check_kubernetes() {
    if command -v kubectl >/dev/null 2>&1; then
        local k8s_version
        k8s_version=$(kubectl version --client --output=json | grep -oP '"gitVersion": "\K(.*)(?=")')
        log "INFO" "Kubernetes client $k8s_version is installed"
        return 0
    else
        log "INFO" "Kubernetes is not installed"
        return 1
    fi
}

# Function to install k3s (lightweight Kubernetes)
install_k3s() {
    local node_type="$1"  # "server" or "agent"
    local server_ip="$2"  # Only required for agent nodes
    local node_token="$3" # Only required for agent nodes
    
    log "INFO" "Installing k3s as $node_type..."
    
    # Download and install k3s
    if [ "$node_type" = "server" ]; then
        # Install k3s server (master)
        curl -sfL https://get.k3s.io | sh -
        
        # Get the node token for other nodes to join
        local token
        token=$(cat /var/lib/rancher/k3s/server/node-token)
        
        # Set up kubectl for the current user
        mkdir -p "$HOME/.kube"
        cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
        chown -R "$(id -u):$(id -g)" "$HOME/.kube"
        
        # Also set up kubectl for the sudo user if applicable
        if [ "$SUDO_USER" ]; then
            sudo_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            mkdir -p "$sudo_home/.kube"
            cp /etc/rancher/k3s/k3s.yaml "$sudo_home/.kube/config"
            sed -i "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" "$sudo_home/.kube/config"
            chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$sudo_home/.kube"
        fi
        
        log "INFO" "k3s server installed successfully"
        log "INFO" "Node token: $token"
        log "INFO" "Server IP: $(hostname -I | awk '{print $1}')"
        whiptail --title "k3s Server Info" --msgbox "k3s server installed successfully!\n\nServer IP: $(hostname -I | awk '{print $1}')\nNode Token: $token\n\nSave this information to join other nodes." 15 70
        
    elif [ "$node_type" = "agent" ]; then
        # Install k3s agent (worker)
        if [ -z "$server_ip" ] || [ -z "$node_token" ]; then
            log "ERROR" "Server IP and node token are required for agent installation"
            return 1
        fi
        
        curl -sfL https://get.k3s.io | K3S_URL="https://$server_ip:6443" K3S_TOKEN="$node_token" sh -
        
        log "INFO" "k3s agent installed successfully and joined cluster at $server_ip"
    else
        log "ERROR" "Invalid node type: $node_type. Must be 'server' or 'agent'"
        return 1
    fi
    
    return 0
}

# Function to uninstall k3s
uninstall_k3s() {
    log "INFO" "Uninstalling k3s..."
    
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        /usr/local/bin/k3s-uninstall.sh
    elif [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
        /usr/local/bin/k3s-agent-uninstall.sh
    else
        log "WARN" "k3s uninstall script not found"
    fi
    
    log "INFO" "k3s uninstalled"
}

# Function to check k3s status
check_k3s() {
    if systemctl is-active --quiet k3s; then
        log "INFO" "k3s server is running"
        return 0
    elif systemctl is-active --quiet k3s-agent; then
        log "INFO" "k3s agent is running"
        return 0
    else
        log "INFO" "k3s is not running"
        return 1
    fi
}

# Function to install Kubernetes tools
install_kubernetes_tools() {
    log "INFO" "Installing Kubernetes tools (kubectl, kubeadm, kubelet)..."
    
    # Add Kubernetes apt repository
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    
    # Add Kubernetes signing key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # Add Kubernetes apt repository
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
    
    # Update apt and install Kubernetes components
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    
    log "INFO" "Kubernetes tools installed successfully: $(kubectl version --client)"
    return 0
}

# Function to initialize a Kubernetes cluster
init_kubernetes_cluster() {
    local pod_network_cidr="$1"
    
    log "INFO" "Initializing Kubernetes cluster..."
    
    # Disable swap (required for Kubernetes)
    swapoff -a
    sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
    
    # Initialize the cluster
    kubeadm init --pod-network-cidr="$pod_network_cidr" --control-plane-endpoint "$(hostname -I | awk '{print $1}'):6443"
    
    # Set up kubectl for the current user
    mkdir -p "$HOME/.kube"
    cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    chown -R "$(id -u):$(id -g)" "$HOME/.kube"
    
    # Also set up kubectl for the sudo user if applicable
    if [ "$SUDO_USER" ]; then
        sudo_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        mkdir -p "$sudo_home/.kube"
        cp -i /etc/kubernetes/admin.conf "$sudo_home/.kube/config"
        chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$sudo_home/.kube"
    fi
    
    log "INFO" "Kubernetes cluster initialized successfully"
    return 0
}

# Function to deploy Calico CNI
deploy_calico_cni() {
    log "INFO" "Deploying Calico CNI..."
    
    # Apply Calico manifest
    kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
    kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml
    
    # Wait for the pods to be ready
    log "INFO" "Waiting for Calico pods to be ready..."
    kubectl wait --for=condition=ready pods --all -n calico-system --timeout=300s
    
    log "INFO" "Calico CNI deployed successfully"
    return 0
}

# Function for advanced cluster management
advanced_cluster_management() {
    log "INFO" "Starting advanced Kubernetes cluster management..."
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log "ERROR" "kubectl is not available. Please set up a Kubernetes cluster first."
        return 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Kubernetes cluster. Please check your configuration."
        return 1
    fi
    
    local management_option
    management_option=$(whiptail --title "Advanced Cluster Management" --menu "Choose a management option:" 18 70 7 \
        "1" "Setup Ingress Controller (NGINX/Traefik)" \
        "2" "Deploy cert-manager for SSL certificates" \
        "3" "Install Kubernetes Dashboard" \
        "4" "Setup monitoring with Prometheus/Grafana" \
        "5" "Manage cluster add-ons" \
        "6" "Resource management (deployments, services, pods)" \
        "7" "Network policies and security" 3>&1 1>&2 2>&3)
    
    case $management_option in
        1)
            setup_ingress_controller
            ;;
        2)
            setup_cert_manager
            ;;
        3)
            setup_kubernetes_dashboard
            ;;
        4)
            setup_cluster_monitoring
            ;;
        5)
            manage_cluster_addons
            ;;
        6)
            manage_cluster_resources
            ;;
        7)
            manage_network_security
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function to setup ingress controller
setup_ingress_controller() {
    log "INFO" "Setting up Kubernetes Ingress Controller..."
    
    # Check if any ingress controller is already installed
    local existing_ingress=""
    if kubectl get ingressclass >/dev/null 2>&1; then
        existing_ingress=$(kubectl get ingressclass -o name 2>/dev/null | head -n1)
        if [ -n "$existing_ingress" ]; then
            if ! whiptail --title "Existing Ingress Controller" --yesno "An ingress controller is already installed: $existing_ingress\n\nDo you want to continue and install another one?" 12 70; then
                return 0
            fi
        fi
    fi
    
    local ingress_type
    ingress_type=$(whiptail --title "Ingress Controller Selection" --menu "Choose an ingress controller:" 15 70 3 \
        "1" "NGINX Ingress Controller (most popular)" \
        "2" "Traefik (modern, easy to configure)" \
        "3" "View current ingress controllers" 3>&1 1>&2 2>&3)
    
    case $ingress_type in
        1)
            install_nginx_ingress
            ;;
        2)
            install_traefik_ingress
            ;;
        3)
            show_ingress_status
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function to install NGINX Ingress Controller
install_nginx_ingress() {
    log "INFO" "Installing NGINX Ingress Controller..."
    
    # Choose installation method
    local install_method
    install_method=$(whiptail --title "NGINX Installation Method" --menu "Choose installation method:" 15 60 3 \
        "1" "Helm chart (recommended)" \
        "2" "Raw YAML manifests" \
        "3" "Custom configuration" 3>&1 1>&2 2>&3)
    
    case $install_method in
        1)
            install_nginx_with_helm
            ;;
        2)
            install_nginx_with_yaml
            ;;
        3)
            install_nginx_custom
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function to install NGINX with Helm
install_nginx_with_helm() {
    log "INFO" "Installing NGINX Ingress Controller using Helm..."
    
    # Check if Helm is installed
    if ! command -v helm >/dev/null 2>&1; then
        if whiptail --title "Helm Required" --yesno "Helm is not installed. Install it now?" 10 60; then
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would install Helm"
            else
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                log "INFO" "Helm installed successfully"
            fi
        else
            return 1
        fi
    fi
    
    # Get configuration options
    local namespace="ingress-nginx"
    local service_type
    service_type=$(whiptail --title "Service Type" --menu "Choose service type for NGINX controller:" 15 60 3 \
        "LoadBalancer" "LoadBalancer (cloud environments)" \
        "NodePort" "NodePort (on-premises, specific ports)" \
        "ClusterIP" "ClusterIP (internal only)" 3>&1 1>&2 2>&3)
    
    # Get additional configuration
    local enable_metrics=""
    if whiptail --title "Metrics" --yesno "Enable Prometheus metrics collection?" 10 60; then
        enable_metrics="--set controller.metrics.enabled=true --set controller.metrics.serviceMonitor.enabled=true"
    fi
    
    local replica_count
    replica_count=$(whiptail --title "Replica Count" --inputbox "Enter number of controller replicas:" 10 60 "2" 3>&1 1>&2 2>&3)
    if [ -z "$replica_count" ] || [ "$replica_count" -lt 1 ]; then
        replica_count="2"
    fi
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install NGINX Ingress Controller with Helm"
        log "INFO" "Namespace: $namespace"
        log "INFO" "Service Type: $service_type"
        log "INFO" "Replicas: $replica_count"
        log "INFO" "Metrics: $([ -n "$enable_metrics" ] && echo "enabled" || echo "disabled")"
    else
        # Add NGINX Ingress Helm repository
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        
        # Create namespace
        kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
        
        # Install NGINX Ingress Controller
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace "$namespace" \
            --set controller.service.type="$service_type" \
            --set controller.replicaCount="$replica_count" \
            $enable_metrics
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for NGINX Ingress Controller to be ready..."
        kubectl wait --namespace "$namespace" \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=300s
        
        log "INFO" "NGINX Ingress Controller installed successfully!"
        
        # Show access information
        show_nginx_access_info "$namespace" "$service_type"
    fi
    
    return 0
}

# Function to install NGINX with raw YAML
install_nginx_with_yaml() {
    log "INFO" "Installing NGINX Ingress Controller using raw YAML manifests..."
    
    local manifest_version
    manifest_version=$(whiptail --title "NGINX Version" --menu "Choose NGINX Ingress version:" 15 60 3 \
        "latest" "Latest stable version" \
        "v1.10.0" "Version 1.10.0 (tested)" \
        "custom" "Custom version" 3>&1 1>&2 2>&3)
    
    if [ "$manifest_version" = "custom" ]; then
        manifest_version=$(whiptail --title "Custom Version" --inputbox "Enter NGINX Ingress version (e.g., v1.10.0):" 10 60 3>&1 1>&2 2>&3)
        if [ -z "$manifest_version" ]; then
            manifest_version="latest"
        fi
    fi
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install NGINX Ingress Controller from YAML manifests"
        log "INFO" "Version: $manifest_version"
    else
        # Determine the manifest URL
        local manifest_url
        if [ "$manifest_version" = "latest" ]; then
            manifest_url="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml"
        else
            manifest_url="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-$manifest_version/deploy/static/provider/cloud/deploy.yaml"
        fi
        
        # Apply the manifest
        kubectl apply -f "$manifest_url"
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for NGINX Ingress Controller to be ready..."
        kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=300s
        
        log "INFO" "NGINX Ingress Controller installed successfully!"
        show_nginx_access_info "ingress-nginx" "LoadBalancer"
    fi
    
    return 0
}

# Function to install NGINX with custom configuration
install_nginx_custom() {
    log "INFO" "Setting up custom NGINX Ingress Controller configuration..."
    
    # Create custom values file
    local config_file="/tmp/nginx-values.yaml"
    
    # Get custom configuration options
    local custom_config=""
    custom_config=$(whiptail --title "Custom Configuration" --inputbox "Enter custom Helm values (YAML format) or leave empty for interactive setup:" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$custom_config" ]; then
        # Interactive configuration
        setup_nginx_interactive_config "$config_file"
    else
        # Use provided configuration
        echo "$custom_config" > "$config_file"
    fi
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install NGINX with custom configuration"
        log "INFO" "Configuration file: $config_file"
        [ -f "$config_file" ] && log "INFO" "Configuration contents:" && cat "$config_file"
    else
        # Install with custom values
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        
        kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
        
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --values "$config_file"
        
        log "INFO" "NGINX Ingress Controller installed with custom configuration!"
        show_nginx_access_info "ingress-nginx" "LoadBalancer"
    fi
    
    return 0
}

# Function to setup interactive NGINX configuration
setup_nginx_interactive_config() {
    local config_file="$1"
    
    log "INFO" "Setting up interactive NGINX configuration..."
    
    # Service type
    local service_type
    service_type=$(whiptail --title "Service Type" --menu "Choose service type:" 15 60 3 \
        "LoadBalancer" "LoadBalancer" \
        "NodePort" "NodePort" \
        "ClusterIP" "ClusterIP" 3>&1 1>&2 2>&3)
    
    # Replica count
    local replicas
    replicas=$(whiptail --title "Replicas" --inputbox "Number of controller replicas:" 10 60 "2" 3>&1 1>&2 2>&3)
    
    # Enable metrics
    local metrics="false"
    if whiptail --title "Metrics" --yesno "Enable Prometheus metrics?" 10 60; then
        metrics="true"
    fi
    
    # SSL redirect
    local ssl_redirect="true"
    if ! whiptail --title "SSL Redirect" --yesno "Force HTTPS redirect by default?" 10 60; then
        ssl_redirect="false"
    fi
    
    # Custom annotations
    local custom_annotations=""
    if whiptail --title "Custom Annotations" --yesno "Add custom service annotations?" 10 60; then
        custom_annotations=$(whiptail --title "Service Annotations" --inputbox "Enter custom annotations (key=value,key2=value2):" 10 60 3>&1 1>&2 2>&3)
    fi
    
    # Create values file
    cat > "$config_file" << EOF
controller:
  replicaCount: $replicas
  service:
    type: $service_type
EOF
    
    if [ -n "$custom_annotations" ]; then
        echo "    annotations:" >> "$config_file"
        IFS=',' read -ra ANNOTATIONS <<< "$custom_annotations"
        for annotation in "${ANNOTATIONS[@]}"; do
            key=$(echo "$annotation" | cut -d'=' -f1)
            value=$(echo "$annotation" | cut -d'=' -f2-)
            echo "      $key: \"$value\"" >> "$config_file"
        done
    fi
    
    cat >> "$config_file" << EOF
  config:
    ssl-redirect: "$ssl_redirect"
  metrics:
    enabled: $metrics
    serviceMonitor:
      enabled: $metrics
EOF
    
    log "INFO" "Configuration file created: $config_file"
}

# Function to show NGINX access information
show_nginx_access_info() {
    local namespace="$1"
    local service_type="$2"
    
    log "INFO" "NGINX Ingress Controller access information:"
    
    # Get service information
    local service_info
    service_info=$(kubectl get service -n "$namespace" -l app.kubernetes.io/component=controller -o wide 2>/dev/null)
    
    if [ -n "$service_info" ]; then
        echo "Service Information:"
        echo "$service_info"
        
        # Show specific access instructions based on service type
        case $service_type in
            LoadBalancer)
                local external_ip
                external_ip=$(kubectl get service -n "$namespace" -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
                if [ -n "$external_ip" ]; then
                    log "INFO" "External IP: $external_ip"
                    log "INFO" "You can now create Ingress resources pointing to this controller"
                else
                    log "INFO" "LoadBalancer is provisioning. Check 'kubectl get svc -n $namespace' for external IP"
                fi
                ;;
            NodePort)
                local http_port https_port
                http_port=$(kubectl get service -n "$namespace" -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null)
                https_port=$(kubectl get service -n "$namespace" -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null)
                log "INFO" "NodePort HTTP: $http_port"
                log "INFO" "NodePort HTTPS: $https_port"
                log "INFO" "Access via: http://<node-ip>:$http_port or https://<node-ip>:$https_port"
                ;;
            ClusterIP)
                log "INFO" "Controller is accessible only within the cluster"
                log "INFO" "Use port-forwarding for external access: kubectl port-forward -n $namespace svc/<service-name> 8080:80"
                ;;
        esac
    fi
    
    # Show example ingress resource
    show_example_ingress_resource
}

# Function to install Traefik Ingress Controller
install_traefik_ingress() {
    log "INFO" "Installing Traefik Ingress Controller..."
    
    local install_method
    install_method=$(whiptail --title "Traefik Installation Method" --menu "Choose installation method:" 15 60 3 \
        "1" "Helm chart (recommended)" \
        "2" "Raw YAML manifests" \
        "3" "Custom configuration" 3>&1 1>&2 2>&3)
    
    case $install_method in
        1)
            install_traefik_with_helm
            ;;
        2)
            install_traefik_with_yaml
            ;;
        3)
            install_traefik_custom
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function to install Traefik with Helm
install_traefik_with_helm() {
    log "INFO" "Installing Traefik using Helm..."
    
    # Check if Helm is installed
    if ! command -v helm >/dev/null 2>&1; then
        if whiptail --title "Helm Required" --yesno "Helm is not installed. Install it now?" 10 60; then
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would install Helm"
            else
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                log "INFO" "Helm installed successfully"
            fi
        else
            return 1
        fi
    fi
    
    # Configuration options
    local namespace="traefik-system"
    local enable_dashboard=""
    if whiptail --title "Traefik Dashboard" --yesno "Enable Traefik dashboard?" 10 60; then
        enable_dashboard="--set dashboard.enabled=true"
    fi
    
    local service_type
    service_type=$(whiptail --title "Service Type" --menu "Choose service type:" 15 60 3 \
        "LoadBalancer" "LoadBalancer (cloud)" \
        "NodePort" "NodePort (on-premises)" \
        "ClusterIP" "ClusterIP (internal)" 3>&1 1>&2 2>&3)
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install Traefik with Helm"
        log "INFO" "Namespace: $namespace"
        log "INFO" "Service Type: $service_type"
        log "INFO" "Dashboard: $([ -n "$enable_dashboard" ] && echo "enabled" || echo "disabled")"
    else
        # Add Traefik Helm repository
        helm repo add traefik https://traefik.github.io/charts
        helm repo update
        
        # Create namespace
        kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
        
        # Install Traefik
        helm install traefik traefik/traefik \
            --namespace "$namespace" \
            --set service.type="$service_type" \
            $enable_dashboard
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for Traefik to be ready..."
        kubectl wait --namespace "$namespace" \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/name=traefik \
            --timeout=300s
        
        log "INFO" "Traefik Ingress Controller installed successfully!"
        show_traefik_access_info "$namespace" "$service_type"
    fi
    
    return 0
}

# Function to install Traefik with YAML
install_traefik_with_yaml() {
    log "INFO" "Installing Traefik using YAML manifests..."
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install Traefik from YAML manifests"
    else
        # Create namespace
        kubectl create namespace traefik-system --dry-run=client -o yaml | kubectl apply -f -
        
        # Apply Traefik CRDs and resources
        kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
        
        # Create basic Traefik deployment
        cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik
  namespace: traefik-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: traefik
rules:
  - apiGroups: [""]
    resources: ["services","endpoints","secrets"]
    verbs: ["get","list","watch"]
  - apiGroups: ["extensions","networking.k8s.io"]
    resources: ["ingresses","ingressclasses"]
    verbs: ["get","list","watch"]
  - apiGroups: ["extensions","networking.k8s.io"]
    resources: ["ingresses/status"]
    verbs: ["update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: traefik
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik
subjects:
  - kind: ServiceAccount
    name: traefik
    namespace: traefik-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik
  namespace: traefik-system
  labels:
    app: traefik
spec:
  replicas: 1
  selector:
    matchLabels:
      app: traefik
  template:
    metadata:
      labels:
        app: traefik
    spec:
      serviceAccountName: traefik
      containers:
        - name: traefik
          image: traefik:v3.0
          args:
            - --api.insecure=true
            - --providers.kubernetesingress=true
            - --entrypoints.web.address=:80
            - --entrypoints.websecure.address=:443
          ports:
            - name: web
              containerPort: 80
            - name: websecure
              containerPort: 443
            - name: admin
              containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: traefik
  namespace: traefik-system
spec:
  type: LoadBalancer
  ports:
    - port: 80
      name: web
      targetPort: 80
    - port: 443
      name: websecure
      targetPort: 443
    - port: 8080
      name: admin
      targetPort: 8080
  selector:
    app: traefik
EOF
        
        log "INFO" "Traefik installed successfully!"
        show_traefik_access_info "traefik-system" "LoadBalancer"
    fi
    
    return 0
}

# Function to install Traefik with custom configuration
install_traefik_custom() {
    log "INFO" "Setting up custom Traefik configuration..."
    
    # Create custom values file for Helm installation
    local config_file="/tmp/traefik-values.yaml"
    
    # Get configuration options
    local enable_dashboard="false"
    if whiptail --title "Dashboard" --yesno "Enable Traefik dashboard?" 10 60; then
        enable_dashboard="true"
    fi
    
    local enable_metrics="false"
    if whiptail --title "Metrics" --yesno "Enable Prometheus metrics?" 10 60; then
        enable_metrics="true"
    fi
    
    local service_type
    service_type=$(whiptail --title "Service Type" --menu "Choose service type:" 15 60 3 \
        "LoadBalancer" "LoadBalancer" \
        "NodePort" "NodePort" \
        "ClusterIP" "ClusterIP" 3>&1 1>&2 2>&3)
    
    # Create configuration file
    cat > "$config_file" << EOF
dashboard:
  enabled: $enable_dashboard

metrics:
  prometheus:
    enabled: $enable_metrics

service:
  type: $service_type

ports:
  web:
    port: 80
    expose: true
  websecure:
    port: 443
    expose: true

providers:
  kubernetesingress:
    enabled: true
  kubernetescrd:
    enabled: true
EOF
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install Traefik with custom configuration"
        log "INFO" "Configuration file: $config_file"
        cat "$config_file"
    else
        helm repo add traefik https://traefik.github.io/charts
        helm repo update
        
        kubectl create namespace traefik-system --dry-run=client -o yaml | kubectl apply -f -
        
        helm install traefik traefik/traefik \
            --namespace traefik-system \
            --values "$config_file"
        
        log "INFO" "Traefik installed with custom configuration!"
        show_traefik_access_info "traefik-system" "$service_type"
    fi
    
    return 0
}

# Function to show Traefik access information
show_traefik_access_info() {
    local namespace="$1"
    local service_type="$2"
    
    log "INFO" "Traefik Ingress Controller access information:"
    
    # Get service information
    local service_info
    service_info=$(kubectl get service -n "$namespace" traefik -o wide 2>/dev/null)
    
    if [ -n "$service_info" ]; then
        echo "Service Information:"
        echo "$service_info"
        
        # Show dashboard access if enabled
        local dashboard_port
        dashboard_port=$(kubectl get service -n "$namespace" traefik -o jsonpath='{.spec.ports[?(@.name=="traefik")].port}' 2>/dev/null)
        if [ -n "$dashboard_port" ]; then
            log "INFO" "Traefik Dashboard available on port $dashboard_port"
            case $service_type in
                LoadBalancer)
                    local external_ip
                    external_ip=$(kubectl get service -n "$namespace" traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
                    if [ -n "$external_ip" ]; then
                        log "INFO" "Dashboard URL: http://$external_ip:$dashboard_port/dashboard/"
                    fi
                    ;;
                NodePort)
                    local node_port
                    node_port=$(kubectl get service -n "$namespace" traefik -o jsonpath='{.spec.ports[?(@.name=="traefik")].nodePort}' 2>/dev/null)
                    log "INFO" "Dashboard URL: http://<node-ip>:$node_port/dashboard/"
                    ;;
            esac
        fi
    fi
    
    # Show example ingress resource for Traefik
    show_example_traefik_ingress
}

# Function to show ingress status
show_ingress_status() {
    log "INFO" "Current Ingress Controller Status:"
    
    # Check for existing ingress classes
    echo "=== Ingress Classes ==="
    if kubectl get ingressclass >/dev/null 2>&1; then
        kubectl get ingressclass
    else
        echo "No ingress classes found"
    fi
    
    echo ""
    echo "=== Ingress Controllers ==="
    
    # Check for NGINX
    if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
        echo "NGINX Ingress Controller:"
        kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller
        kubectl get service -n ingress-nginx -l app.kubernetes.io/component=controller
    fi
    
    # Check for Traefik
    if kubectl get namespace traefik-system >/dev/null 2>&1; then
        echo "Traefik Ingress Controller:"
        kubectl get pods -n traefik-system -l app.kubernetes.io/name=traefik
        kubectl get service -n traefik-system traefik
    fi
    
    echo ""
    echo "=== Existing Ingress Resources ==="
    if kubectl get ingress --all-namespaces >/dev/null 2>&1; then
        kubectl get ingress --all-namespaces
    else
        echo "No ingress resources found"
    fi
    
    # Show example commands
    echo ""
    echo "=== Example Usage ==="
    echo "Create an ingress resource:"
    echo "kubectl create ingress <name> --rule='<host>/<path>=<service>:<port>'"
    echo ""
    echo "Test ingress controller:"
    echo "curl -H 'Host: <your-domain>' http://<ingress-ip>/<path>"
}

# Function to show example ingress resource
show_example_ingress_resource() {
    cat << 'EOF'

=== Example NGINX Ingress Resource ===
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80

To apply: kubectl apply -f ingress.yaml
EOF
}

# Function to show example Traefik ingress
show_example_traefik_ingress() {
    cat << 'EOF'

=== Example Traefik Ingress Resource ===
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-traefik-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80

To apply: kubectl apply -f traefik-ingress.yaml
EOF
}

# Placeholder functions for other advanced cluster management features
setup_cert_manager() {
    log "INFO" "Setting up cert-manager for automatic SSL certificate management..."
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log "ERROR" "kubectl is not available. Please set up a Kubernetes cluster first."
        return 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Kubernetes cluster. Please check your configuration."
        return 1
    fi
    
    # Choose installation method
    local install_method
    install_method=$(whiptail --title "cert-manager Installation" --menu "Choose installation method:" 15 60 3 \
        "1" "Helm chart (recommended)" \
        "2" "YAML manifests" \
        "3" "Custom configuration" 3>&1 1>&2 2>&3)
    
    case $install_method in
        1)
            install_cert_manager_helm
            ;;
        2)
            install_cert_manager_yaml
            ;;
        3)
            install_cert_manager_custom
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function to install cert-manager with Helm
install_cert_manager_helm() {
    log "INFO" "Installing cert-manager using Helm..."
    
    # Check if Helm is installed
    if ! command -v helm >/dev/null 2>&1; then
        if whiptail --title "Helm Required" --yesno "Helm is not installed. Install it now?" 10 60; then
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would install Helm"
            else
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                log "INFO" "Helm installed successfully"
            fi
        else
            return 1
        fi
    fi
    
    local namespace="cert-manager"
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install cert-manager with Helm"
        log "INFO" "Namespace: $namespace"
    else
        # Add Jetstack Helm repository
        helm repo add jetstack https://charts.jetstack.io
        helm repo update
        
        # Create namespace
        kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
        
        # Install cert-manager
        helm install cert-manager jetstack/cert-manager \
            --namespace "$namespace" \
            --version v1.13.2 \
            --set installCRDs=true \
            --set global.leaderElection.namespace="$namespace"
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for cert-manager to be ready..."
        kubectl wait --namespace "$namespace" \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/instance=cert-manager \
            --timeout=300s
        
        log "INFO" "cert-manager installed successfully!"
        
        # Show example ClusterIssuer
        show_cert_manager_examples
    fi
    
    return 0
}

# Function to install cert-manager with YAML
install_cert_manager_yaml() {
    log "INFO" "Installing cert-manager using YAML manifests..."
    
    local version="v1.13.2"
    version=$(whiptail --title "cert-manager Version" --inputbox "Enter cert-manager version:" 10 60 "$version" 3>&1 1>&2 2>&3)
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install cert-manager from YAML manifests"
        log "INFO" "Version: $version"
    else
        # Apply cert-manager CRDs
        kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$version/cert-manager.crds.yaml"
        
        # Apply cert-manager
        kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$version/cert-manager.yaml"
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for cert-manager to be ready..."
        kubectl wait --namespace cert-manager \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/instance=cert-manager \
            --timeout=300s
        
        log "INFO" "cert-manager installed successfully!"
        show_cert_manager_examples
    fi
    
    return 0
}

# Function to install cert-manager with custom configuration
install_cert_manager_custom() {
    log "INFO" "Setting up custom cert-manager configuration..."
    
    # Get issuer type
    local issuer_type
    issuer_type=$(whiptail --title "Certificate Issuer" --menu "Choose certificate issuer:" 15 60 3 \
        "letsencrypt-staging" "Let's Encrypt Staging (testing)" \
        "letsencrypt-prod" "Let's Encrypt Production" \
        "selfsigned" "Self-signed certificates" 3>&1 1>&2 2>&3)
    
    # Get email for Let's Encrypt
    local email=""
    if [[ "$issuer_type" == letsencrypt* ]]; then
        email=$(whiptail --title "Email Address" --inputbox "Enter email for Let's Encrypt:" 10 60 3>&1 1>&2 2>&3)
        if [ -z "$email" ]; then
            log "ERROR" "Email is required for Let's Encrypt"
            return 1
        fi
    fi
    
    # Install cert-manager first
    install_cert_manager_helm
    
    if [ $? -eq 0 ] && [ -z "$TEST_MODE" ]; then
        # Create ClusterIssuer
        create_cluster_issuer "$issuer_type" "$email"
    fi
    
    return 0
}

# Function to create ClusterIssuer
create_cluster_issuer() {
    local issuer_type="$1"
    local email="$2"
    
    log "INFO" "Creating ClusterIssuer for $issuer_type..."
    
    case $issuer_type in
        letsencrypt-staging)
            cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: $email
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
            ;;
        letsencrypt-prod)
            cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
            ;;
        selfsigned)
            cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
            ;;
    esac
    
    log "INFO" "ClusterIssuer created successfully!"
}

# Function to show cert-manager examples
show_cert_manager_examples() {
    log "INFO" "cert-manager has been installed successfully!"
    
    # Show example usage
    whiptail --title "cert-manager Examples" --msgbox "cert-manager is now ready! Here are some examples:

1. Create a ClusterIssuer for Let's Encrypt:
   kubectl apply -f examples/letsencrypt-issuer.yaml

2. Request a certificate in your Ingress:
   Add these annotations to your Ingress:
   cert-manager.io/cluster-issuer: \"letsencrypt-prod\"
   
3. Check certificate status:
   kubectl get certificates
   kubectl describe certificate <cert-name>

For more examples, check the cert-manager documentation." 20 80
}

setup_kubernetes_dashboard() {
    log "INFO" "Setting up Kubernetes Dashboard..."
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log "ERROR" "kubectl is not available. Please set up a Kubernetes cluster first."
        return 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Kubernetes cluster. Please check your configuration."
        return 1
    fi
    
    # Choose installation method
    local install_method
    install_method=$(whiptail --title "Dashboard Installation" --menu "Choose installation method:" 15 60 3 \
        "1" "Official Kubernetes Dashboard" \
        "2" "Dashboard with metrics server" \
        "3" "Dashboard with custom configuration" 3>&1 1>&2 2>&3)
    
    case $install_method in
        1)
            install_k8s_dashboard_basic
            ;;
        2)
            install_k8s_dashboard_with_metrics
            ;;
        3)
            install_k8s_dashboard_custom
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function to install basic Kubernetes Dashboard
install_k8s_dashboard_basic() {
    log "INFO" "Installing Kubernetes Dashboard..."
    
    local version="v2.7.0"
    version=$(whiptail --title "Dashboard Version" --inputbox "Enter dashboard version:" 10 60 "$version" 3>&1 1>&2 2>&3)
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install Kubernetes Dashboard"
        log "INFO" "Version: $version"
    else
        # Apply dashboard manifests
        kubectl apply -f "https://raw.githubusercontent.com/kubernetes/dashboard/${version}/aio/deploy/recommended.yaml"
        
        # Wait for deployment to be ready
        log "INFO" "Waiting for dashboard to be ready..."
        kubectl wait --namespace kubernetes-dashboard \
            --for=condition=ready pod \
            --selector=k8s-app=kubernetes-dashboard \
            --timeout=300s
        
        # Create admin user and get token
        create_dashboard_admin_user
        
        log "INFO" "Kubernetes Dashboard installed successfully!"
        show_dashboard_access_info
    fi
    
    return 0
}

# Function to install dashboard with metrics server
install_k8s_dashboard_with_metrics() {
    log "INFO" "Installing Kubernetes Dashboard with metrics server..."
    
    # Install metrics server first
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would install metrics server"
    else
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
        
        # Wait for metrics server to be ready
        log "INFO" "Waiting for metrics server to be ready..."
        kubectl wait --namespace kube-system \
            --for=condition=ready pod \
            --selector=k8s-app=metrics-server \
            --timeout=300s
    fi
    
    # Install dashboard
    install_k8s_dashboard_basic
    
    return 0
}

# Function to install dashboard with custom configuration
install_k8s_dashboard_custom() {
    log "INFO" "Setting up custom Kubernetes Dashboard configuration..."
    
    # Get access type
    local access_type
    access_type=$(whiptail --title "Dashboard Access" --menu "Choose access method:" 15 60 3 \
        "NodePort" "NodePort (accessible from outside)" \
        "LoadBalancer" "LoadBalancer (cloud environments)" \
        "Ingress" "Ingress (with domain name)" 3>&1 1>&2 2>&3)
    
    # Install basic dashboard first
    install_k8s_dashboard_basic
    
    if [ $? -eq 0 ] && [ -z "$TEST_MODE" ]; then
        # Configure access method
        configure_dashboard_access "$access_type"
    fi
    
    return 0
}

# Function to create dashboard admin user
create_dashboard_admin_user() {
    log "INFO" "Creating dashboard admin user..."
    
    # Create admin user
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
    
    # Get the token
    local token
    token=$(kubectl -n kubernetes-dashboard create token admin-user)
    
    # Save token to file for reference
    echo "$token" > /tmp/dashboard-admin-token.txt
    
    log "INFO" "Admin user created successfully!"
    log "INFO" "Token saved to /tmp/dashboard-admin-token.txt"
}

# Function to configure dashboard access
configure_dashboard_access() {
    local access_type="$1"
    
    log "INFO" "Configuring dashboard access via $access_type..."
    
    case $access_type in
        NodePort)
            # Patch service to NodePort
            kubectl patch service kubernetes-dashboard \
                -n kubernetes-dashboard \
                -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8443,"nodePort":30443}]}}'
            
            log "INFO" "Dashboard accessible via NodePort 30443"
            ;;
        LoadBalancer)
            # Patch service to LoadBalancer
            kubectl patch service kubernetes-dashboard \
                -n kubernetes-dashboard \
                -p '{"spec":{"type":"LoadBalancer"}}'
            
            log "INFO" "Dashboard accessible via LoadBalancer (check external IP)"
            ;;
        Ingress)
            # Create ingress for dashboard
            local domain
            domain=$(whiptail --title "Domain Name" --inputbox "Enter domain name for dashboard:" 10 60 "dashboard.local" 3>&1 1>&2 2>&3)
            
            cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  rules:
  - host: $domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF
            
            log "INFO" "Dashboard accessible via https://$domain"
            ;;
    esac
}

# Function to show dashboard access information
show_dashboard_access_info() {
    log "INFO" "Kubernetes Dashboard access information:"
    
    # Get service information
    local service_info
    service_info=$(kubectl get service -n kubernetes-dashboard kubernetes-dashboard -o wide 2>/dev/null)
    
    if [ -n "$service_info" ]; then
        echo "Service Information:"
        echo "$service_info"
    fi
    
    # Check if token file exists
    if [ -f /tmp/dashboard-admin-token.txt ]; then
        local token
        token=$(cat /tmp/dashboard-admin-token.txt)
        
        whiptail --title "Dashboard Access" --msgbox "Kubernetes Dashboard is ready!

Access Methods:
1. Port forwarding (secure):
   kubectl proxy
   Then access: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

2. Direct access (if configured):
   Check service external IP/NodePort

Admin Token (copy this token for login):
$token

Token also saved to: /tmp/dashboard-admin-token.txt" 20 80
    fi
}

setup_cluster_monitoring() {
    log "INFO" "Cluster monitoring setup not yet implemented"
    whiptail --title "Coming Soon" --msgbox "Cluster monitoring setup will be implemented in the next update." 10 60
    return 0
}

manage_cluster_addons() {
    log "INFO" "Cluster add-ons management not yet implemented"
    whiptail --title "Coming Soon" --msgbox "Cluster add-ons management will be implemented in the next update." 10 60
    return 0
}

manage_cluster_resources() {
    log "INFO" "Cluster resource management not yet implemented"
    whiptail --title "Coming Soon" --msgbox "Cluster resource management will be implemented in the next update." 10 60
    return 0
}

manage_network_security() {
    log "INFO" "Network security management not yet implemented"
    whiptail --title "Coming Soon" --msgbox "Network security management will be implemented in the next update." 10 60
    return 0
}

# Function for multi-VM deployment
multi_vm_deployment() {
    log "INFO" "Starting multi-VM deployment setup..."
    
    # Get deployment configuration
    local deployment_type
    deployment_type=$(whiptail --title "Multi-VM Deployment" --menu "Choose deployment type:" 15 60 3 \
        "1" "Docker Swarm cluster" \
        "2" "Distributed containers across VMs" \
        "3" "Load-balanced application" 3>&1 1>&2 2>&3)
    
    case $deployment_type in
        1)
            setup_docker_swarm
            ;;
        2)
            deploy_distributed_containers
            ;;
        3)
            deploy_load_balanced_app
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to setup Docker Swarm cluster
setup_docker_swarm() {
    log "INFO" "Setting up Docker Swarm cluster..."
    
    local swarm_option
    swarm_option=$(whiptail --title "Docker Swarm Setup" --menu "Choose an option:" 15 60 3 \
        "1" "Initialize new swarm (manager node)" \
        "2" "Join existing swarm as worker" \
        "3" "Join existing swarm as manager" 3>&1 1>&2 2>&3)
    
    case $swarm_option in
        1)
            # Initialize swarm
            local advertise_addr
            advertise_addr=$(whiptail --title "Advertise Address" --inputbox "Enter the IP address to advertise (leave empty for auto-detect):" 10 60 3>&1 1>&2 2>&3)
            
            local command="docker swarm init"
            if [ -n "$advertise_addr" ]; then
                command="$command --advertise-addr $advertise_addr"
            fi
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would execute: $command"
                whiptail --title "Swarm Initialized" --msgbox "Test mode: Docker Swarm would be initialized.\n\nTo join workers, run:\ndocker swarm join --token <worker-token> <manager-ip>:2377\n\nTo join managers, run:\ndocker swarm join --token <manager-token> <manager-ip>:2377" 15 70
            else
                log "INFO" "Initializing Docker Swarm..."
                eval "$command"
                
                # Get join tokens
                local worker_token manager_token
                worker_token=$(docker swarm join-token worker -q)
                manager_token=$(docker swarm join-token manager -q)
                local manager_ip
                manager_ip=$(hostname -I | awk '{print $1}')
                
                whiptail --title "Swarm Initialized" --msgbox "Docker Swarm initialized successfully!\n\nTo join workers, run on each worker node:\ndocker swarm join --token $worker_token $manager_ip:2377\n\nTo join managers, run on each manager node:\ndocker swarm join --token $manager_token $manager_ip:2377" 15 70
                log "INFO" "Docker Swarm initialized on $manager_ip"
            fi
            ;;
        2)
            # Join as worker
            local join_command
            join_command=$(whiptail --title "Join Swarm" --inputbox "Enter the full 'docker swarm join' command provided by the manager:" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$join_command" ]; then
                return 1
            fi
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would execute: $join_command"
            else
                log "INFO" "Joining swarm as worker..."
                eval "$join_command"
                log "INFO" "Successfully joined swarm as worker"
            fi
            ;;
        3)
            # Join as manager
            local join_command
            join_command=$(whiptail --title "Join Swarm" --inputbox "Enter the full 'docker swarm join' command for managers:" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$join_command" ]; then
                return 1
            fi
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would execute: $join_command"
            else
                log "INFO" "Joining swarm as manager..."
                eval "$join_command"
                log "INFO" "Successfully joined swarm as manager"
            fi
            ;;
    esac
}

# Function to deploy distributed containers across VMs
deploy_distributed_containers() {
    log "INFO" "Setting up distributed container deployment..."
    
    # Get VM list
    local vm_list
    vm_list=$(whiptail --title "VM List" --inputbox "Enter comma-separated list of VM IPs/hostnames:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$vm_list" ]; then
        return 1
    fi
    
    # Get container configuration
    local image_name
    image_name=$(whiptail --title "Container Image" --inputbox "Enter container image (e.g., nginx:latest):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$image_name" ]; then
        return 1
    fi
    
    local container_prefix
    container_prefix=$(whiptail --title "Container Prefix" --inputbox "Enter container name prefix:" 10 60 "app" 3>&1 1>&2 2>&3)
    
    local port_mapping
    port_mapping=$(whiptail --title "Port Mapping" --inputbox "Enter port mapping (e.g., 8080:80):" 10 60 3>&1 1>&2 2>&3)
    
    # Deploy to each VM
    local counter=1
    IFS=',' read -ra VMS <<< "$vm_list"
    for vm in "${VMS[@]}"; do
        vm=$(echo "$vm" | xargs)  # Trim whitespace
        local container_name="${container_prefix}-${counter}"
        
        local ssh_command="docker run -d --name $container_name"
        if [ -n "$port_mapping" ]; then
            ssh_command="$ssh_command -p $port_mapping"
        fi
        ssh_command="$ssh_command $image_name"
        
        if [ -n "$TEST_MODE" ]; then
            log "INFO" "Test mode: Would SSH to $vm and execute: $ssh_command"
        else
            log "INFO" "Deploying $container_name to $vm..."
            if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$vm" "$ssh_command"; then
                log "INFO" "Successfully deployed $container_name to $vm"
            else
                log "ERROR" "Failed to deploy to $vm"
            fi
        fi
        
        ((counter++))
    done
    
    if [ -z "$TEST_MODE" ]; then
        whiptail --title "Deployment Complete" --msgbox "Distributed container deployment completed!\n\nDeployed to VMs: $vm_list\nContainer prefix: $container_prefix\nImage: $image_name" 12 70
    fi
}

# Function to deploy load-balanced application
deploy_load_balanced_app() {
    log "INFO" "Setting up load-balanced application deployment..."
    
    # Get configuration
    local backend_vms
    backend_vms=$(whiptail --title "Backend VMs" --inputbox "Enter comma-separated list of backend VM IPs:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$backend_vms" ]; then
        return 1
    fi
    
    local lb_vm
    lb_vm=$(whiptail --title "Load Balancer VM" --inputbox "Enter load balancer VM IP:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$lb_vm" ]; then
        return 1
    fi
    
    local app_image
    app_image=$(whiptail --title "Application Image" --inputbox "Enter application image:" 10 60 "nginx:latest" 3>&1 1>&2 2>&3)
    
    local app_port
    app_port=$(whiptail --title "Application Port" --inputbox "Enter application port:" 10 60 "80" 3>&1 1>&2 2>&3)
    
    # Deploy backends
    local counter=1
    IFS=',' read -ra BACKENDS <<< "$backend_vms"
    local backend_list=""
    
    for backend in "${BACKENDS[@]}"; do
        backend=$(echo "$backend" | xargs)
        local container_name="backend-${counter}"
        
        if [ -n "$TEST_MODE" ]; then
            log "INFO" "Test mode: Would deploy $container_name to $backend"
        else
            log "INFO" "Deploying $container_name to $backend..."
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$backend" \
                "docker run -d --name $container_name -p $app_port:$app_port $app_image"
        fi
        
        backend_list="${backend_list}server backend${counter} ${backend}:${app_port} check\n    "
        ((counter++))
    done
    
    # Create HAProxy configuration
    local haproxy_config="/tmp/haproxy.cfg"
    cat > "$haproxy_config" << EOF
global
    daemon

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http_front
    bind *:80
    default_backend http_back

backend http_back
    balance roundrobin
    $backend_list
EOF
    
    # Deploy load balancer
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would deploy HAProxy to $lb_vm"
        log "INFO" "HAProxy config created at $haproxy_config"
    else
        log "INFO" "Deploying HAProxy load balancer to $lb_vm..."
        
        # Copy config to LB VM
        scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$haproxy_config" "root@$lb_vm:/tmp/"
        
        # Deploy HAProxy container
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$lb_vm" \
            "docker run -d --name haproxy-lb -p 80:80 -v /tmp/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro haproxy:latest"
        
        whiptail --title "Load Balancer Deployed" --msgbox "Load-balanced application deployed successfully!\n\nLoad Balancer: http://$lb_vm\nBackends: $backend_vms\n\nThe application is now accessible through the load balancer." 12 70
    fi
    
    # Clean up
    rm -f "$haproxy_config"
}

# Function to show container monitoring and health status
show_container_monitoring() {
    log "INFO" "Displaying container monitoring and health status..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        whiptail --title "Error" --msgbox "Docker is not running or not accessible." 8 60
        return 1
    fi
    
    # Get list of containers
    local containers
    containers=$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}" 2>/dev/null)
    
    if [ -z "$containers" ] || [ "$(echo "$containers" | wc -l)" -eq 1 ]; then
        whiptail --title "Container Monitoring" --msgbox "No containers found on this system." 8 60
        return 0
    fi
    
    # Show monitoring options
    local monitoring_option
    monitoring_option=$(whiptail --title "Container Monitoring" --menu "Choose monitoring option:" 15 80 4 \
        "1" "View all container status" \
        "2" "Monitor specific container" \
        "3" "View container resource usage" \
        "4" "View container health checks" 3>&1 1>&2 2>&3)
    
    case $monitoring_option in
        1)
            # Show all container status
            local status_info
            status_info=$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CPU}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | head -20)
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would display container status information"
            else
                whiptail --title "Container Status" --msgbox "$status_info" 20 120 --scrolltext
            fi
            ;;
        2)
            # Monitor specific container
            local container_list
            container_list=$(docker ps -a --format "{{.Names}}" | sort)
            
            if [ -z "$container_list" ]; then
                whiptail --title "Error" --msgbox "No containers found." 8 60
                return 1
            fi
            
            local menu_items=()
            local counter=1
            while IFS= read -r container; do
                menu_items+=("$counter" "$container")
                ((counter++))
            done <<< "$container_list"
            
            local selected_num
            selected_num=$(whiptail --title "Select Container" --menu "Choose container to monitor:" 15 60 8 "${menu_items[@]}" 3>&1 1>&2 2>&3)
            
            if [ -n "$selected_num" ]; then
                local selected_container
                selected_container=$(echo "$container_list" | sed -n "${selected_num}p")
                
                if [ -n "$TEST_MODE" ]; then
                    log "INFO" "Test mode: Would monitor container $selected_container"
                else
                    # Show detailed container information
                    local container_info
                    container_info=$(docker inspect "$selected_container" --format "
Container: {{.Name}}
Status: {{.State.Status}}
Started: {{.State.StartedAt}}
Image: {{.Config.Image}}
Ports: {{range .NetworkSettings.Ports}}{{.}}{{end}}
CPU Usage: {{.HostConfig.CpuShares}}
Memory Limit: {{.HostConfig.Memory}}
RestartPolicy: {{.HostConfig.RestartPolicy.Name}}
Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}No health check{{end}}")
                    
                    whiptail --title "Container Details: $selected_container" --msgbox "$container_info" 20 80 --scrolltext
                fi
            fi
            ;;
        3)
            # View resource usage
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would display container resource usage"
            else
                local stats_info
                stats_info=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}")
                whiptail --title "Container Resource Usage" --msgbox "$stats_info" 20 120 --scrolltext
            fi
            ;;
        4)
            # View health checks
            local health_info
            health_info=$(docker ps --filter "health=healthy" --filter "health=unhealthy" --filter "health=starting" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null)
            
            if [ -z "$health_info" ] || [ "$(echo "$health_info" | wc -l)" -eq 1 ]; then
                whiptail --title "Health Checks" --msgbox "No containers with health checks found." 8 60
            else
                if [ -n "$TEST_MODE" ]; then
                    log "INFO" "Test mode: Would display container health check information"
                else
                    whiptail --title "Container Health Status" --msgbox "$health_info" 15 80 --scrolltext
                fi
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Main function for Docker deployment
docker_deployment() {
    # Check if Docker is already installed
    if ! check_docker; then
        # Ask to install Docker
        if (whiptail --title "Docker Installation" --yesno "Docker is not installed. Would you like to install it now?" 10 60 3>&1 1>&2 2>&3); then
            install_docker
            install_docker_compose
        else
            log "INFO" "Docker installation skipped."
            return 1
        fi
    fi
    
    # Docker deployment options
    local docker_option
    docker_option=$(whiptail --title "Docker Deployment" --menu "Choose a deployment option:" 18 70 4 \
        "1" "Deploy a single container" \
        "2" "Deploy with Docker Compose" \
        "3" "Multi-VM deployment" \
        "4" "Container management" 3>&1 1>&2 2>&3)
    
    case $docker_option in
        1)
            # Deploy a single container
            local container_name
            container_name=$(whiptail --title "Container Name" --inputbox "Enter container name:" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$container_name" ]; then
                return 1
            fi
            
            local image_name
            image_name=$(whiptail --title "Container Image" --inputbox "Enter image name (e.g., nginx:latest):" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$image_name" ]; then
                return 1
            fi
            
            local port_mapping
            port_mapping=$(whiptail --title "Port Mapping" --inputbox "Enter port mapping (e.g., 8080:80):" 10 60 3>&1 1>&2 2>&3)
            
            local command
            command="docker run -d --name $container_name"
            if [ -n "$port_mapping" ]; then
                command="$command -p $port_mapping"
            fi
            command="$command $image_name"
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would execute: $command"
            else
                log "INFO" "Running: $command"
                eval "$command"
                log "INFO" "Container $container_name deployed successfully."
            fi
            ;;
        2)
            # Deploy with Docker Compose
            local compose_path
            compose_path=$(whiptail --title "Docker Compose File" --inputbox "Enter path to docker-compose.yml:" 10 60 "./docker-compose.yml" 3>&1 1>&2 2>&3)
            if [ -z "$compose_path" ] || [ ! -f "$compose_path" ]; then
                log "ERROR" "Invalid docker-compose.yml path: $compose_path"
                return 1
            fi
            
            local compose_project
            compose_project=$(whiptail --title "Project Name" --inputbox "Enter project name:" 10 60 3>&1 1>&2 2>&3)
            
            local command
            if [ -n "$compose_project" ]; then
                command="docker compose -p $compose_project -f $compose_path up -d"
            else
                command="docker compose -f $compose_path up -d"
            fi
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would execute: $command"
            else
                log "INFO" "Running: $command"
                eval "$command"
                log "INFO" "Docker Compose services deployed successfully."
            fi
            ;;
        3)
            # Multi-VM deployment
            multi_vm_deployment
            ;;
        4)
            # Container management - Enhanced functionality
            local manage_option
            manage_option=$(whiptail --title "Container Management" --menu "Choose an option:" 20 70 7 \
                "1" "List containers (with options)" \
                "2" "Start containers (multiple methods)" \
                "3" "Stop containers (safely)" \
                "4" "Remove containers (with safety)" \
                "5" "Manage container logs" \
                "6" "Monitor container health" \
                "7" "Return to main menu" 3>&1 1>&2 2>&3)
            
            case $manage_option in
                1)
                    # Enhanced container listing
                    list_containers
                    ;;
                2)
                    # Enhanced container starting
                    start_containers
                    ;;
                3)
                    # Enhanced container stopping
                    stop_containers
                    ;;
                4)
                    # Enhanced container removal
                    remove_containers
                    ;;
                5)
                    # Enhanced container logs management
                    manage_container_logs
                    ;;
                6)
                    # Container monitoring/health check
                    show_container_monitoring
                    ;;
                7)
                    # Return to main menu
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Main function for k3s deployment
k3s_deployment() {
    # Check if k3s is already installed
    if ! check_k3s; then
        # Ask to install k3s
        if (whiptail --title "k3s Installation" --yesno "k3s is not installed. Would you like to install it now?" 10 60 3>&1 1>&2 2>&3); then
            local node_type
            node_type=$(whiptail --title "k3s Node Type" --menu "Select node type:" 15 60 2 \
                "server" "k3s Server (Master Node)" \
                "agent" "k3s Agent (Worker Node)" 3>&1 1>&2 2>&3)
            
            case $node_type in
                server)
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would install k3s server"
                    else
                        install_k3s "server"
                    fi
                    ;;
                agent)
                    local server_ip
                    server_ip=$(whiptail --title "Server IP" --inputbox "Enter k3s server IP address:" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$server_ip" ]; then
                        log "ERROR" "Server IP is required for agent installation"
                        return 1
                    fi
                    
                    local node_token
                    node_token=$(whiptail --title "Node Token" --inputbox "Enter k3s node token:" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$node_token" ]; then
                        log "ERROR" "Node token is required for agent installation"
                        return 1
                    fi
                    
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would install k3s agent to join $server_ip"
                    else
                        install_k3s "agent" "$server_ip" "$node_token"
                    fi
                    ;;
                *)
                    return 1
                    ;;
            esac
        else
            log "INFO" "k3s installation skipped."
            return 1
        fi
    fi
    
    # k3s management options
    local k3s_option
    k3s_option=$(whiptail --title "k3s Management" --menu "Choose an option:" 15 60 5 \
        "1" "Check cluster status" \
        "2" "Deploy an application" \
        "3" "Get node token (for adding workers)" \
        "4" "Uninstall k3s" \
        "5" "View cluster info" 3>&1 1>&2 2>&3)
    
    case $k3s_option in
        1)
            # Check cluster status
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would check k3s cluster status"
            else
                kubectl get nodes
                kubectl get pods --all-namespaces
            fi
            ;;
        2)
            # Deploy an application
            local app_option
            app_option=$(whiptail --title "Application Deployment" --menu "Choose an application to deploy:" 15 60 4 \
                "1" "Nginx web server" \
                "2" "WordPress with MySQL" \
                "3" "Custom YAML file" \
                "4" "Helm chart" 3>&1 1>&2 2>&3)
            
            case $app_option in
                1)
                    # Deploy Nginx
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would deploy Nginx"
                    else
                        kubectl create deployment nginx --image=nginx
                        kubectl expose deployment nginx --port=80 --type=LoadBalancer
                        log "INFO" "Nginx deployed successfully"
                    fi
                    ;;
                2)
                    # Deploy WordPress with MySQL
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would deploy WordPress with MySQL"
                    else
                        # Create namespace
                        kubectl create namespace wordpress
                        
                        # Deploy MySQL
                        kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: wordpress
type: Opaque
data:
  password: $(echo -n 'wordpress123' | base64)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: wordpress
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: MYSQL_DATABASE
          value: wordpress
        - name: MYSQL_USER
          value: wordpress
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: wordpress
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:6.0
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql
        - name: WORDPRESS_DB_NAME
          value: wordpress
        - name: WORDPRESS_DB_USER
          value: wordpress
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: wordpress
spec:
  selector:
    app: wordpress
  ports:
  - port: 80
  type: LoadBalancer
EOF
                        log "INFO" "WordPress with MySQL deployed successfully in namespace 'wordpress'"
                    fi
                    ;;
                3)
                    # Deploy from YAML file
                    local yaml_path
                    yaml_path=$(whiptail --title "YAML File" --inputbox "Enter path to YAML file:" 10 60 "./deployment.yaml" 3>&1 1>&2 2>&3)
                    if [ -z "$yaml_path" ] || [ ! -f "$yaml_path" ]; then
                        log "ERROR" "Invalid YAML file path: $yaml_path"
                        return 1
                    fi
                    
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would apply YAML file $yaml_path"
                    else
                        kubectl apply -f "$yaml_path"
                        log "INFO" "Application deployed successfully from $yaml_path"
                    fi
                    ;;
                4)
                    # Install Helm and deploy chart
                    if ! command -v helm >/dev/null 2>&1; then
                        if (whiptail --title "Helm Installation" --yesno "Helm is not installed. Install it now?" 10 60 3>&1 1>&2 2>&3); then
                            if [ -n "$TEST_MODE" ]; then
                                log "INFO" "Test mode: Would install Helm"
                            else
                                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                                log "INFO" "Helm installed successfully"
                            fi
                        else
                            return 1
                        fi
                    fi
                    
                    local chart_name
                    chart_name=$(whiptail --title "Helm Chart" --inputbox "Enter Helm chart name (e.g., bitnami/nginx):" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$chart_name" ]; then
                        return 1
                    fi
                    
                    local release_name
                    release_name=$(whiptail --title "Release Name" --inputbox "Enter release name:" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$release_name" ]; then
                        return 1
                    fi
                    
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would deploy Helm chart $chart_name as release $release_name"
                    else
                        helm repo add bitnami https://charts.bitnami.com/bitnami
                        helm repo update
                        helm install "$release_name" "$chart_name"
                        log "INFO" "Helm chart $chart_name deployed as release $release_name"
                    fi
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        3)
            # Get node token
            if [ -f /var/lib/rancher/k3s/server/node-token ]; then
                local token
                token=$(cat /var/lib/rancher/k3s/server/node-token)
                local server_ip
                server_ip=$(hostname -I | awk '{print $1}')
                whiptail --title "k3s Node Token" --msgbox "Server IP: $server_ip\nNode Token: $token\n\nTo join a worker node, run:\ncurl -sfL https://get.k3s.io | K3S_URL=https://$server_ip:6443 K3S_TOKEN=$token sh -" 12 80
            else
                whiptail --title "Error" --msgbox "Node token not found. This may not be a k3s server node." 10 60
            fi
            ;;
        4)
            # Uninstall k3s
            if (whiptail --title "Uninstall k3s" --yesno "Are you sure you want to uninstall k3s?" 10 60 3>&1 1>&2 2>&3); then
                if [ -n "$TEST_MODE" ]; then
                    log "INFO" "Test mode: Would uninstall k3s"
                else
                    uninstall_k3s
                fi
            fi
            ;;
        5)
            # View cluster info
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would show cluster info"
            else
                kubectl cluster-info
                kubectl get nodes -o wide
                kubectl get pods --all-namespaces
            fi
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Main function for Kubernetes deployment
kubernetes_deployment() {
    # Check if Kubernetes is already installed
    if ! check_kubernetes; then
        # Ask to install Kubernetes
        if (whiptail --title "Kubernetes Installation" --yesno "Kubernetes is not installed. Would you like to install it now?" 10 60 3>&1 1>&2 2>&3); then
            install_kubernetes_tools
        else
            log "INFO" "Kubernetes installation skipped."
            return 1
        fi
    fi
    
    # Kubernetes deployment options
    local k8s_option
    k8s_option=$(whiptail --title "Kubernetes Deployment" --menu "Choose a deployment option:" 18 70 6 \
        "1" "Initialize a new cluster (basic)" \
        "2" "Setup multi-node cluster (advanced)" \
        "3" "Auto-discover and join cluster" \
        "4" "Join an existing cluster (manual)" \
        "5" "Advanced cluster management" \
        "6" "Deploy an application" 3>&1 1>&2 2>&3)
    
    case $k8s_option in
        1)
            # Initialize a new cluster (basic)
            local pod_cidr
            pod_cidr=$(whiptail --title "Pod Network CIDR" --inputbox "Enter Pod Network CIDR:" 10 60 "10.244.0.0/16" 3>&1 1>&2 2>&3)
            if [ -z "$pod_cidr" ]; then
                pod_cidr="10.244.0.0/16"  # Default to Flannel's CIDR
            fi
            
            local cni_option
            cni_option=$(whiptail --title "CNI Selection" --menu "Select a CNI plugin:" 15 60 3 \
                "1" "Calico" \
                "2" "Flannel" \
                "3" "Weave Net" 3>&1 1>&2 2>&3)
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would initialize Kubernetes cluster with CIDR $pod_cidr"
            else
                init_kubernetes_cluster "$pod_cidr"
                
                # Deploy selected CNI
                case $cni_option in
                    1)
                        deploy_calico_cni
                        ;;
                    2)
                        kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
                        ;;
                    3)
                        kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
                        ;;
                    *)
                        log "WARN" "No CNI selected, network will not be functional."
                        ;;
                esac
                
                # Display the join command for worker nodes
                log "INFO" "To add worker nodes, run the following command on each node:"
                kubeadm token create --print-join-command
            fi
            ;;
        2)
            # Setup multi-node cluster (advanced)
            setup_multi_node_cluster
            ;;
        3)
            # Auto-discover and join cluster
            auto_join_cluster
            ;;
        4)
            # Join an existing cluster (manual)
            local join_command
            join_command=$(whiptail --title "Join Cluster" --inputbox "Enter the kubeadm join command:" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$join_command" ]; then
                return 1
            fi
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would execute join command"
            else
                eval "$join_command"
                log "INFO" "Node joined the cluster successfully."
            fi
            ;;
        5)
            # Advanced cluster management
            advanced_cluster_management
            ;;
        6)
            # Deploy an application
            local deploy_option
            deploy_option=$(whiptail --title "Application Deployment" --menu "Choose a deployment option:" 15 60 4 \
                "1" "Deploy from YAML file" \
                "2" "Deploy using kubectl create" \
                "3" "Deploy using Helm" \
                "4" "Deploy sample WordPress with MySQL" 3>&1 1>&2 2>&3)
            
            case $deploy_option in
                1)
                    # Deploy from YAML
                    local yaml_path
                    yaml_path=$(whiptail --title "YAML File" --inputbox "Enter path to YAML file:" 10 60 "./deployment.yaml" 3>&1 1>&2 2>&3)
                    if [ -z "$yaml_path" ] || [ ! -f "$yaml_path" ]; then
                        log "ERROR" "Invalid YAML file path: $yaml_path"
                        return 1
                    fi
                    
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would apply YAML file $yaml_path"
                    else
                        kubectl apply -f "$yaml_path"
                        log "INFO" "Application deployed successfully from $yaml_path"
                    fi
                    ;;
                2)
                    # Deploy using kubectl create
                    local app_name
                    app_name=$(whiptail --title "Application Name" --inputbox "Enter application name:" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$app_name" ]; then
                        return 1
                    fi
                    
                    local image_name
                    image_name=$(whiptail --title "Container Image" --inputbox "Enter image name (e.g., nginx:latest):" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$image_name" ]; then
                        return 1
                    fi
                    
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would create deployment $app_name with image $image_name"
                    else
                        kubectl create deployment "$app_name" --image="$image_name"
                        kubectl expose deployment "$app_name" --port=80 --type=LoadBalancer
                        log "INFO" "Application $app_name deployed successfully"
                    fi
                    ;;
                3)
                    # Deploy using Helm
                    if ! command -v helm >/dev/null 2>&1; then
                        if (whiptail --title "Helm Installation" --yesno "Helm is not installed. Install it now?" 10 60 3>&1 1>&2 2>&3); then
                            if [ -n "$TEST_MODE" ]; then
                                log "INFO" "Test mode: Would install Helm"
                            else
                                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                                log "INFO" "Helm installed successfully"
                            fi
                        else
                            return 1
                        fi
                    fi
                    
                    local chart_name
                    chart_name=$(whiptail --title "Helm Chart" --inputbox "Enter Helm chart name (e.g., bitnami/nginx):" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$chart_name" ]; then
                        return 1
                    fi
                    
                    local release_name
                    release_name=$(whiptail --title "Release Name" --inputbox "Enter release name:" 10 60 3>&1 1>&2 2>&3)
                    if [ -z "$release_name" ]; then
                        return 1
                    fi
                    
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would deploy Helm chart $chart_name as release $release_name"
                    else
                        helm repo add bitnami https://charts.bitnami.com/bitnami
                        helm repo update
                        helm install "$release_name" "$chart_name"
                        log "INFO" "Helm chart $chart_name deployed as release $release_name"
                    fi
                    ;;
                4)
                    # Deploy sample WordPress with MySQL
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would deploy WordPress with MySQL"
                    else
                        # Create namespace
                        kubectl create namespace wordpress
                        
                        # Deploy MySQL
                        kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: wordpress
type: Opaque
data:
  password: $(echo -n 'wordpress123' | base64)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: wordpress
spec:
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: MYSQL_DATABASE
          value: wordpress
        - name: MYSQL_USER
          value: wordpress
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: wordpress
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:6.0
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql
        - name: WORDPRESS_DB_NAME
          value: wordpress
        - name: WORDPRESS_DB_USER
          value: wordpress
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: wordpress
spec:
  selector:
    app: wordpress
  ports:
  - port: 80
  type: LoadBalancer
EOF
                        log "INFO" "WordPress with MySQL deployed successfully in namespace 'wordpress'"
                    fi
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        4)
            # Install Helm and deploy chart
            if ! command -v helm >/dev/null 2>&1; then
                if (whiptail --title "Helm Installation" --yesno "Helm is not installed. Install it now?" 10 60 3>&1 1>&2 2>&3); then
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would install Helm"
                    else
                        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                        log "INFO" "Helm installed successfully"
                    fi
                else
                    return 1
                fi
            fi
            
            local chart_name
            chart_name=$(whiptail --title "Helm Chart" --inputbox "Enter Helm chart name (e.g., bitnami/nginx):" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$chart_name" ]; then
                return 1
            fi
            
            local release_name
            release_name=$(whiptail --title "Release Name" --inputbox "Enter release name:" 10 60 3>&1 1>&2 2>&3)
            if [ -z "$release_name" ]; then
                return 1
            fi
            
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would deploy Helm chart $chart_name as release $release_name"
            else
                helm repo add bitnami https://charts.bitnami.com/bitnami
                helm repo update
                helm install "$release_name" "$chart_name"
                log "INFO" "Helm chart $chart_name deployed as release $release_name"
            fi
            ;;
        3)
            # Multi-VM deployment
            multi_vm_deployment
            ;;
        4)
            # Container management - Enhanced functionality
            local manage_option
            manage_option=$(whiptail --title "Container Management" --menu "Choose an option:" 20 70 7 \
                "1" "List containers (with options)" \
                "2" "Start containers (multiple methods)" \
                "3" "Stop containers (safely)" \
                "4" "Remove containers (with safety)" \
                "5" "Manage container logs" \
                "6" "Monitor container health" \
                "7" "Return to main menu" 3>&1 1>&2 2>&3)
            
            case $manage_option in
                1)
                    # Enhanced container listing
                    list_containers
                    ;;
                2)
                    # Enhanced container starting
                    start_containers
                    ;;
                3)
                    # Enhanced container stopping
                    stop_containers
                    ;;
                4)
                    # Enhanced container removal
                    remove_containers
                    ;;
                5)
                    # Enhanced container logs management
                    manage_container_logs
                    ;;
                6)
                    # Container monitoring/health check
                    show_container_monitoring
                    ;;
                7)
                    # Return to main menu
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Main menu for the containers module
main_menu() {
    local option
    option=$(whiptail --title "Container Workloads" --menu "Choose a container platform:" 15 60 4 \
        "1" "Docker - Container Engine" \
        "2" "Kubernetes - Container Orchestration" \
        "3" "k3s - Lightweight Kubernetes" \
        "4" "Help & Documentation" 3>&1 1>&2 2>&3)
    
    case $option in
        1)
            docker_deployment
            ;;
        2)
            kubernetes_deployment
            ;;
        3)
            k3s_deployment
            ;;
        4)
            whiptail --title "Container Workloads Help" --msgbox "Container Workloads Module v${VERSION}\n\nThis module helps you deploy and manage Docker containers and Kubernetes clusters.\n\n- Docker: Deploy single containers or multi-container applications with Docker Compose\n- Kubernetes: Set up new clusters, join existing clusters, and deploy applications\n- k3s: Lightweight Kubernetes distribution for edge computing\n\nFor more information, see the documentation at:\nhttps://github.com/binghzal/homelab/tree/main/docs" 18 70 3>&1 1>&2 2>&3
            main_menu
            ;;
        *)
            log "INFO" "User exited container workloads menu."
            exit 0
            ;;
    esac
}

# Run the main menu if not in test mode
if [ -n "$TEST_MODE" ]; then
    log "INFO" "Container Workloads module (test mode)"
else
    main_menu
fi

exit 0
