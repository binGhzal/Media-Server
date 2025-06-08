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
    docker_option=$(whiptail --title "Docker Deployment" --menu "Choose a deployment option:" 15 60 3 \
        "1" "Deploy a single container" \
        "2" "Deploy with Docker Compose" \
        "3" "Container management" 3>&1 1>&2 2>&3)
    
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
            # Container management
            local manage_option
            manage_option=$(whiptail --title "Container Management" --menu "Choose an option:" 15 60 5 \
                "1" "List running containers" \
                "2" "Stop a container" \
                "3" "Start a container" \
                "4" "Remove a container" \
                "5" "View container logs" 3>&1 1>&2 2>&3)
            
            case $manage_option in
                1)
                    # List running containers
                    docker ps
                    ;;
                2)
                    # Stop a container
                    local containers
                    containers=$(docker ps --format "{{.ID}}|{{.Names}}|{{.Image}}" | tr '\n' ' ')
                    
                    if [ -z "$containers" ]; then
                        whiptail --title "No Containers" --msgbox "No running containers found." 10 60 3>&1 1>&2 2>&3
                        return 1
                    fi
                    
                    local container_menu=()
                    for container in $containers; do
                        IFS='|' read -r id name image <<< "$container"
                        container_menu+=("$id" "$name ($image)")
                    done
                    
                    local selected
                    selected=$(whiptail --title "Stop Container" --menu "Select a container to stop:" 15 60 5 "${container_menu[@]}" 3>&1 1>&2 2>&3)
                    
                    if [ -n "$selected" ]; then
                        if [ -n "$TEST_MODE" ]; then
                            log "INFO" "Test mode: Would stop container $selected"
                        else
                            docker stop "$selected"
                            log "INFO" "Container $selected stopped."
                        fi
                    fi
                    ;;
                # Other management options would go here
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
    k8s_option=$(whiptail --title "Kubernetes Deployment" --menu "Choose a deployment option:" 15 60 3 \
        "1" "Initialize a new cluster" \
        "2" "Join an existing cluster" \
        "3" "Deploy an application" 3>&1 1>&2 2>&3)
    
    case $k8s_option in
        1)
            # Initialize a new cluster
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
            # Join an existing cluster
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
        3)
            # Deploy an application
            local deploy_option
            deploy_option=$(whiptail --title "Application Deployment" --menu "Choose a deployment option:" 15 60 3 \
                "1" "Deploy from YAML file" \
                "2" "Deploy using kubectl create" \
                "3" "Deploy using Helm" 3>&1 1>&2 2>&3)
            
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
                # Other deployment options would go here
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
    option=$(whiptail --title "Container Workloads" --menu "Choose a container platform:" 15 60 3 \
        "1" "Docker - Container Engine" \
        "2" "Kubernetes - Container Orchestration" \
        "3" "Help & Documentation" 3>&1 1>&2 2>&3)
    
    case $option in
        1)
            docker_deployment
            ;;
        2)
            kubernetes_deployment
            ;;
        3)
            whiptail --title "Container Workloads Help" --msgbox "Container Workloads Module v${VERSION}\n\nThis module helps you deploy and manage Docker containers and Kubernetes clusters.\n\n- Docker: Deploy single containers or multi-container applications with Docker Compose\n- Kubernetes: Set up new clusters, join existing clusters, and deploy applications\n\nFor more information, see the documentation at:\nhttps://github.com/binghzal/homelab/tree/main/docs" 16 70 3>&1 1>&2 2>&3
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
