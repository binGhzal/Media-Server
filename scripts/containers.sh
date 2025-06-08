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
