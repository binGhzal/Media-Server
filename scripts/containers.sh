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
            # Container management
            local manage_option
            manage_option=$(whiptail --title "Container Management" --menu "Choose an option:" 15 60 6 \
                "1" "List running containers" \
                "2" "Stop a container" \
                "3" "Start a container" \
                "4" "Remove a container" \
                "5" "View container logs" \
                "6" "Monitor container health" 3>&1 1>&2 2>&3)
            
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
                3)
                    # Start a container
                    local stopped_containers
                    stopped_containers=$(docker ps -a --filter "status=exited" --format "{{.ID}}|{{.Names}}|{{.Image}}" | tr '\n' ' ')
                    
                    if [ -z "$stopped_containers" ]; then
                        whiptail --title "No Stopped Containers" --msgbox "No stopped containers found." 10 60 3>&1 1>&2 2>&3
                        return 1
                    fi
                    
                    local container_menu=()
                    for container in $stopped_containers; do
                        IFS='|' read -r id name image <<< "$container"
                        container_menu+=("$id" "$name ($image)")
                    done
                    
                    local selected
                    selected=$(whiptail --title "Start Container" --menu "Select a container to start:" 15 60 5 "${container_menu[@]}" 3>&1 1>&2 2>&3)
                    
                    if [ -n "$selected" ]; then
                        if [ -n "$TEST_MODE" ]; then
                            log "INFO" "Test mode: Would start container $selected"
                        else
                            docker start "$selected"
                            log "INFO" "Container $selected started."
                        fi
                    fi
                    ;;
                4)
                    # Remove a container
                    local all_containers
                    all_containers=$(docker ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}" | tr '\n' ' ')
                    
                    if [ -z "$all_containers" ]; then
                        whiptail --title "No Containers" --msgbox "No containers found." 10 60 3>&1 1>&2 2>&3
                        return 1
                    fi
                    
                    local container_menu=()
                    for container in $all_containers; do
                        IFS='|' read -r id name image status <<< "$container"
                        container_menu+=("$id" "$name ($image) - $status")
                    done
                    
                    local selected
                    selected=$(whiptail --title "Remove Container" --menu "Select a container to remove:" 15 60 5 "${container_menu[@]}" 3>&1 1>&2 2>&3)
                    
                    if [ -n "$selected" ]; then
                        if whiptail --title "Confirm Remove" --yesno "Are you sure you want to remove container $selected?\n\nThis action cannot be undone." 10 60; then
                            if [ -n "$TEST_MODE" ]; then
                                log "INFO" "Test mode: Would remove container $selected"
                            else
                                # Stop container first if running
                                docker stop "$selected" 2>/dev/null || true
                                docker rm "$selected"
                                log "INFO" "Container $selected removed."
                            fi
                        fi
                    fi
                    ;;
                5)
                    # View container logs
                    local running_containers
                    running_containers=$(docker ps --format "{{.ID}}|{{.Names}}|{{.Image}}" | tr '\n' ' ')
                    
                    if [ -z "$running_containers" ]; then
                        whiptail --title "No Running Containers" --msgbox "No running containers found." 10 60 3>&1 1>&2 2>&3
                        return 1
                    fi
                    
                    local container_menu=()
                    for container in $running_containers; do
                        IFS='|' read -r id name image <<< "$container"
                        container_menu+=("$id" "$name ($image)")
                    done
                    
                    local selected
                    selected=$(whiptail --title "View Logs" --menu "Select a container to view logs:" 15 60 5 "${container_menu[@]}" 3>&1 1>&2 2>&3)
                    
                    if [ -n "$selected" ]; then
                        if [ -n "$TEST_MODE" ]; then
                            log "INFO" "Test mode: Would show logs for container $selected"
                        else
                            log "INFO" "Showing logs for container $selected (press Ctrl+C to exit)..."
                            docker logs -f "$selected"
                        fi
                    fi
                    ;;
                6)
                    # Container monitoring/health check
                    show_container_monitoring
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
                        
                        # Deploy MySQL and WordPress
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
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Function for registry integration
registry_integration() {
    log "INFO" "Setting up container registry integration..."
    
    local registry_option
    registry_option=$(whiptail --title "Registry Integration" --menu "Choose an option:" 15 60 4 \
        "1" "Configure Docker to use private registry" \
        "2" "Push image to private registry" \
        "3" "Pull image from private registry" \
        "4" "Deploy from private registry" 3>&1 1>&2 2>&3)
    
    case $registry_option in
        1)
            configure_private_registry
            ;;
        2)
            push_to_registry
            ;;
        3)
            pull_from_registry
            ;;
        4)
            deploy_from_registry
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to configure Docker for private registry
configure_private_registry() {
    log "INFO" "Configuring Docker for private registry..."
    
    local registry_url
    registry_url=$(whiptail --title "Registry URL" --inputbox "Enter registry URL (e.g., registry.local:5000):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_url" ]; then
        return 1
    fi
    
    local use_tls
    if whiptail --title "Registry Security" --yesno "Does the registry use TLS/SSL?" 10 60; then
        use_tls="yes"
    else
        use_tls="no"
    fi
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would configure Docker for registry $registry_url (TLS: $use_tls)"
    else
        # Create Docker daemon configuration
        local docker_config_dir="/etc/docker"
        local docker_config_file="$docker_config_dir/daemon.json"
        
        mkdir -p "$docker_config_dir"
        
        if [ "$use_tls" = "no" ]; then
            # Configure insecure registry
            local insecure_registries=""
            if [ -f "$docker_config_file" ]; then
                insecure_registries=$(jq -r '.["insecure-registries"] // [] | join(",")' "$docker_config_file" 2>/dev/null || echo "")
            fi
            
            if [ -n "$insecure_registries" ]; then
                insecure_registries="${insecure_registries},${registry_url}"
            else
                insecure_registries="$registry_url"
            fi
            
            cat > "$docker_config_file" << EOF
{
    "insecure-registries": ["$registry_url"]
}
EOF
            
            log "INFO" "Added $registry_url to insecure registries"
        else
            # For TLS registries, copy certificate if available
            local cert_path
            cert_path=$(whiptail --title "Certificate Path" --inputbox "Enter path to registry certificate (optional):" 10 60 3>&1 1>&2 2>&3)
            
            if [ -n "$cert_path" ] && [ -f "$cert_path" ]; then
                local registry_host
                registry_host=$(echo "$registry_url" | cut -d':' -f1)
                local registry_port
                registry_port=$(echo "$registry_url" | cut -d':' -f2)
                
                mkdir -p "/etc/docker/certs.d/$registry_url"
                cp "$cert_path" "/etc/docker/certs.d/$registry_url/ca.crt"
                log "INFO" "Copied certificate for $registry_url"
            fi
        fi
        
        # Restart Docker daemon
        systemctl restart docker
        log "INFO" "Docker daemon restarted"
        
        # Test registry access
        if docker login "$registry_url" 2>/dev/null; then
            log "INFO" "Successfully logged into registry $registry_url"
        else
            log "WARN" "Could not login to registry automatically. You may need to login manually."
        fi
    fi
}

# Function to push image to registry
push_to_registry() {
    log "INFO" "Pushing image to private registry..."
    
    local local_image
    local_image=$(whiptail --title "Local Image" --inputbox "Enter local image name:tag:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$local_image" ]; then
        return 1
    fi
    
    local registry_url
    registry_url=$(whiptail --title "Registry URL" --inputbox "Enter registry URL:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_url" ]; then
        return 1
    fi
    
    local registry_image
    registry_image=$(whiptail --title "Registry Image" --inputbox "Enter registry image name:tag:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_image" ]; then
        return 1
    fi
    
    local full_registry_image="${registry_url}/${registry_image}"
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would tag $local_image as $full_registry_image"
        log "INFO" "Test mode: Would push $full_registry_image"
    else
        log "INFO" "Tagging image..."
        docker tag "$local_image" "$full_registry_image"
        
        log "INFO" "Pushing to registry..."
        docker push "$full_registry_image"
        
        log "INFO" "Successfully pushed $full_registry_image"
        whiptail --title "Push Complete" --msgbox "Image pushed successfully!\n\nLocal image: $local_image\nRegistry image: $full_registry_image" 12 70
    fi
}

# Function to pull image from registry
pull_from_registry() {
    log "INFO" "Pulling image from private registry..."
    
    local registry_url
    registry_url=$(whiptail --title "Registry URL" --inputbox "Enter registry URL:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_url" ]; then
        return 1
    fi
    
    local registry_image
    registry_image=$(whiptail --title "Registry Image" --inputbox "Enter image name:tag to pull:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_image" ]; then
        return 1
    fi
    
    local full_registry_image="${registry_url}/${registry_image}"
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would pull $full_registry_image"
    else
        log "INFO" "Pulling from registry..."
        docker pull "$full_registry_image"
        
        log "INFO" "Successfully pulled $full_registry_image"
        whiptail --title "Pull Complete" --msgbox "Image pulled successfully!\n\nRegistry image: $full_registry_image\n\nYou can now use this image for deployments." 12 70
    fi
}

# Function to deploy from registry
deploy_from_registry() {
    log "INFO" "Deploying container from private registry..."
    
    local registry_url
    registry_url=$(whiptail --title "Registry URL" --inputbox "Enter registry URL:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_url" ]; then
        return 1
    fi
    
    local registry_image
    registry_image=$(whiptail --title "Registry Image" --inputbox "Enter image name:tag to deploy:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$registry_image" ]; then
        return 1
    fi
    
    local container_name
    container_name=$(whiptail --title "Container Name" --inputbox "Enter container name:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$container_name" ]; then
        return 1
    fi
    
    local port_mapping
    port_mapping=$(whiptail --title "Port Mapping" --inputbox "Enter port mapping (optional, e.g., 8080:80):" 10 60 3>&1 1>&2 2>&3)
    
    local full_registry_image="${registry_url}/${registry_image}"
    
    local command="docker run -d --name $container_name"
    if [ -n "$port_mapping" ]; then
        command="$command -p $port_mapping"
    fi
    command="$command $full_registry_image"
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would execute: $command"
    else
        log "INFO" "Deploying container from registry..."
        eval "$command"
        
        log "INFO" "Successfully deployed $container_name from $full_registry_image"
        whiptail --title "Deployment Complete" --msgbox "Container deployed successfully!\n\nContainer: $container_name\nImage: $full_registry_image\nPort mapping: ${port_mapping:-none}" 12 70
    fi
}

# Enhanced multi-node Kubernetes support functions

# Function to check cluster status and node health
check_cluster_health() {
    log "INFO" "Checking Kubernetes cluster health..."
    
    if ! command -v kubectl >/dev/null 2>&1; then
        log "ERROR" "kubectl is not installed or not in PATH"
        return 1
    fi
    
    # Check if cluster is reachable
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    local node_count ready_nodes
    node_count=$(kubectl get nodes --no-headers | wc -l)
    ready_nodes=$(kubectl get nodes --no-headers | grep -c "Ready")
    
    log "INFO" "Cluster Status:"
    log "INFO" "  Total nodes: $node_count"
    log "INFO" "  Ready nodes: $ready_nodes"
    
    # Display detailed node information
    kubectl get nodes -o wide
    
    # Check system pods
    log "INFO" "System pods status:"
    kubectl get pods -n kube-system
    
    return 0
}

# Function to automatically setup multi-node cluster across VMs
setup_multi_node_cluster() {
    log "INFO" "Setting up multi-node Kubernetes cluster..."
    
    # Get cluster configuration
    local master_ip worker_ips pod_cidr cni_plugin
    master_ip=$(whiptail --title "Master Node" --inputbox "Enter master node IP address:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$master_ip" ]; then
        log "ERROR" "Master IP is required"
        return 1
    fi
    
    worker_ips=$(whiptail --title "Worker Nodes" --inputbox "Enter worker node IPs (comma-separated):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$worker_ips" ]; then
        log "WARN" "No worker nodes specified, setting up single-node cluster"
    fi
    
    pod_cidr=$(whiptail --title "Pod Network CIDR" --inputbox "Enter Pod Network CIDR:" 10 60 "10.244.0.0/16" 3>&1 1>&2 2>&3)
    if [ -z "$pod_cidr" ]; then
        pod_cidr="10.244.0.0/16"
    fi
    
    local cni_option
    cni_option=$(whiptail --title "CNI Plugin" --menu "Select CNI plugin:" 15 60 4 \
        "1" "Flannel (recommended)" \
        "2" "Calico" \
        "3" "Weave Net" \
        "4" "Canal (Flannel + Calico)" 3>&1 1>&2 2>&3)
    
    case $cni_option in
        1) cni_plugin="flannel" ;;
        2) cni_plugin="calico" ;;
        3) cni_plugin="weave" ;;
        4) cni_plugin="canal" ;;
        *) cni_plugin="flannel" ;;
    esac
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would setup multi-node cluster"
        log "INFO" "  Master: $master_ip"
        log "INFO" "  Workers: $worker_ips"
        log "INFO" "  Pod CIDR: $pod_cidr"
        log "INFO" "  CNI: $cni_plugin"
        return 0
    fi
    
    # Initialize cluster on master node
    log "INFO" "Initializing cluster on master node $master_ip..."
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    local master_setup_script="/tmp/k8s_master_setup.sh"
    
    # Create master setup script
    cat > "$master_setup_script" << EOF
#!/bin/bash
set -e

# Install Kubernetes tools if not present
if ! command -v kubeadm >/dev/null 2>&1; then
    # Add Kubernetes repository
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
fi

# Disable swap
swapoff -a
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab

# Initialize cluster
kubeadm init --pod-network-cidr=$pod_cidr --control-plane-endpoint $master_ip:6443 --upload-certs

# Setup kubectl for root
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

# Generate join commands
kubeadm token create --print-join-command > /tmp/worker-join-command
kubeadm init phase upload-certs --upload-certs | tail -n 1 > /tmp/control-plane-key

# Save cluster info
echo "$master_ip" > /tmp/master-ip
echo "$pod_cidr" > /tmp/pod-cidr
echo "$cni_plugin" > /tmp/cni-plugin
EOF
    
    # Copy and execute master setup script
    scp $ssh_opts "$master_setup_script" "root@$master_ip:/tmp/"
    ssh $ssh_opts "root@$master_ip" "chmod +x /tmp/k8s_master_setup.sh && /tmp/k8s_master_setup.sh"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to initialize cluster on master node"
        return 1
    fi
    
    log "INFO" "Master node initialized successfully"
    
    # Get join command from master
    local worker_join_cmd
    worker_join_cmd=$(ssh $ssh_opts "root@$master_ip" "cat /tmp/worker-join-command")
    
    # Install CNI plugin on master
    log "INFO" "Installing CNI plugin: $cni_plugin"
    install_cni_plugin "$master_ip" "$cni_plugin" "$pod_cidr"
    
    # Join worker nodes if specified
    if [ -n "$worker_ips" ]; then
        log "INFO" "Adding worker nodes to cluster..."
        
        IFS=',' read -ra WORKERS <<< "$worker_ips"
        for worker_ip in "${WORKERS[@]}"; do
            worker_ip=$(echo "$worker_ip" | xargs)  # Trim whitespace
            log "INFO" "Setting up worker node: $worker_ip"
            
            local worker_setup_script="/tmp/k8s_worker_setup.sh"
            
            # Create worker setup script
            cat > "$worker_setup_script" << EOF
#!/bin/bash
set -e

# Install Kubernetes tools if not present
if ! command -v kubeadm >/dev/null 2>&1; then
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
fi

# Disable swap
swapoff -a
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab

# Join cluster
$worker_join_cmd
EOF
            
            # Copy and execute worker setup script
            scp $ssh_opts "$worker_setup_script" "root@$worker_ip:/tmp/"
            ssh $ssh_opts "root@$worker_ip" "chmod +x /tmp/k8s_worker_setup.sh && /tmp/k8s_worker_setup.sh"
            
            if [ $? -eq 0 ]; then
                log "INFO" "Worker node $worker_ip joined successfully"
            else
                log "ERROR" "Failed to join worker node $worker_ip"
            fi
        done
    fi
    
    # Wait for nodes to be ready
    log "INFO" "Waiting for all nodes to be ready..."
    ssh $ssh_opts "root@$master_ip" "kubectl wait --for=condition=Ready nodes --all --timeout=300s"
    
    # Display final cluster status
    log "INFO" "Multi-node cluster setup complete!"
    ssh $ssh_opts "root@$master_ip" "kubectl get nodes -o wide"
    
    # Copy kubeconfig locally if this is the master node
    local_ip
    local_ip=$(hostname -I | awk '{print $1}')
    if [ "$local_ip" = "$master_ip" ]; then
        mkdir -p "$HOME/.kube"
        cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
        chown -R "$(id -u):$(id -g)" "$HOME/.kube"
        log "INFO" "kubectl configured for local use"
    fi
    
    # Clean up temporary files
    rm -f "$master_setup_script" "$worker_setup_script"
    ssh $ssh_opts "root@$master_ip" "rm -f /tmp/k8s_master_setup.sh /tmp/worker-join-command /tmp/control-plane-key"
    
    return 0
}

# Function to install CNI plugins with better error handling
install_cni_plugin() {
    local master_ip="$1"
    local cni_plugin="$2"
    local pod_cidr="$3"
    
    log "INFO" "Installing CNI plugin: $cni_plugin on master $master_ip"
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    
    case $cni_plugin in
        "flannel")
            ssh $ssh_opts "root@$master_ip" "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
            ;;
        "calico")
            ssh $ssh_opts "root@$master_ip" "kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml"
            # Create custom resources for Calico with correct CIDR
            ssh $ssh_opts "root@$master_ip" "cat > /tmp/calico-custom.yaml << 'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: $pod_cidr
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF"
            ssh $ssh_opts "root@$master_ip" "kubectl apply -f /tmp/calico-custom.yaml"
            ;;
        "weave")
            ssh $ssh_opts "root@$master_ip" "kubectl apply -f \"https://cloud.weave.works/k8s/net?k8s-version=\$(kubectl version | base64 | tr -d '\n')\""
            ;;
        "canal")
            # Canal combines Flannel for networking and Calico for network policy
            ssh $ssh_opts "root@$master_ip" "kubectl apply -f https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/1.7/rbac.yaml"
            ssh $ssh_opts "root@$master_ip" "kubectl apply -f https://raw.githubusercontent.com/projectcalico/canal/master/k8s-install/1.7/canal.yaml"
            ;;
        *)
            log "ERROR" "Unknown CNI plugin: $cni_plugin"
            return 1
            ;;
    esac
    
    # Wait for CNI pods to be ready
    log "INFO" "Waiting for CNI pods to be ready..."
    case $cni_plugin in
        "flannel")
            ssh $ssh_opts "root@$master_ip" "kubectl wait --for=condition=ready pods --all -n kube-flannel --timeout=300s || true"
            ;;
        "calico")
            ssh $ssh_opts "root@$master_ip" "kubectl wait --for=condition=ready pods --all -n calico-system --timeout=300s || true"
            ;;
        "weave"|"canal")
            ssh $ssh_opts "root@$master_ip" "kubectl wait --for=condition=ready pods --all -n kube-system --timeout=300s || true"
            ;;
    esac
    
    log "INFO" "CNI plugin $cni_plugin installed successfully"
    return 0
}

# Function for intelligent cluster joining with auto-discovery
auto_join_cluster() {
    log "INFO" "Starting automatic cluster discovery and joining..."
    
    # Try to discover existing clusters on the network
    local discovered_masters
    discovered_masters=$(discover_k8s_masters)
    
    if [ -z "$discovered_masters" ]; then
        # No clusters found, offer to create one
        if whiptail --title "No Clusters Found" --yesno "No Kubernetes clusters discovered on the network.\n\nWould you like to create a new cluster?" 10 60; then
            setup_multi_node_cluster
        fi
        return
    fi
    
    # Present discovered clusters to user
    local cluster_options=()
    local counter=1
    
    while IFS= read -r master; do
        cluster_options+=("$counter" "Cluster at $master")
        ((counter++))
    done <<< "$discovered_masters"
    
    cluster_options+=("new" "Create new cluster")
    
    local choice
    choice=$(whiptail --title "Available Clusters" --menu "Select a cluster to join or create new:" 15 60 $((${#cluster_options[@]}/2)) "${cluster_options[@]}" 3>&1 1>&2 2>&3)
    
    if [ "$choice" = "new" ]; then
        setup_multi_node_cluster
    elif [ -n "$choice" ] && [ "$choice" -ge 1 ] && [ "$choice" -le $((counter-1)) ]; then
        local selected_master
        selected_master=$(echo "$discovered_masters" | sed -n "${choice}p")
        join_existing_cluster "$selected_master"
    fi
}

# Function to discover Kubernetes masters on the network
discover_k8s_masters() {
    log "INFO" "Scanning network for Kubernetes clusters..."
    
    local network_range
    network_range=$(ip route | grep -E '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -n1 | awk '{print $1}')
    
    if [ -z "$network_range" ]; then
        log "WARN" "Could not determine network range for scanning"
        return 1
    fi
    
    local masters=""
    local ssh_opts="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes"
    
    # Scan common IPs in the network range
    for i in $(seq 1 254); do
        local ip="${network_range%.*}.$i"
        
        # Try to connect and check for Kubernetes API server
        if timeout 3 ssh $ssh_opts "root@$ip" "systemctl is-active kubelet >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1" 2>/dev/null; then
            masters="$masters$ip\n"
            log "INFO" "Found Kubernetes master at $ip"
        fi
    done 2>/dev/null
    
    echo -e "$masters" | grep -v "^$"
}

# Function to join existing cluster with enhanced automation
join_existing_cluster() {
    local master_ip="$1"
    
    log "INFO" "Joining existing cluster at $master_ip..."
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    
    # Get join command from master
    local join_command
    join_command=$(ssh $ssh_opts "root@$master_ip" "kubeadm token create --print-join-command" 2>/dev/null)
    
    if [ -z "$join_command" ]; then
        log "ERROR" "Failed to get join command from master node"
        return 1
    fi
    
    # Install Kubernetes tools if not present
    if ! command -v kubeadm >/dev/null 2>&1; then
        log "INFO" "Installing Kubernetes tools..."
        install_kubernetes_tools
    fi
    
    # Disable swap
    swapoff -a
    sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would execute join command: $join_command"
        return 0
    fi
    
    # Execute join command
    log "INFO" "Joining cluster..."
    eval "$join_command"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Successfully joined cluster at $master_ip"
        
        # Verify the join
        ssh $ssh_opts "root@$master_ip" "kubectl get nodes"
        
        return 0
    else
        log "ERROR" "Failed to join cluster"
        return 1
    fi
}

# Enhanced function for advanced cluster management
advanced_cluster_management() {
    log "INFO" "Advanced Kubernetes cluster management..."
    
    local mgmt_option
    mgmt_option=$(whiptail --title "Advanced Cluster Management" --menu "Choose an operation:" 18 70 8 \
        "1" "Setup multi-node cluster" \
        "2" "Auto-discover and join cluster" \
        "3" "Check cluster health" \
        "4" "Add worker node to existing cluster" \
        "5" "Remove node from cluster" \
        "6" "Upgrade cluster" \
        "7" "Backup cluster configuration" \
        "8" "Restore cluster configuration" 3>&1 1>&2 2>&3)
    
    case $mgmt_option in
        1)
            setup_multi_node_cluster
            ;;
        2)
            auto_join_cluster
            ;;
        3)
            check_cluster_health
            ;;
        4)
            add_worker_node
            ;;
        5)
            remove_cluster_node
            ;;
        6)
            upgrade_cluster
            ;;
        7)
            backup_cluster_config
            ;;
        8)
            restore_cluster_config
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to add worker node to existing cluster
add_worker_node() {
    log "INFO" "Adding worker node to existing cluster..."
    
    local master_ip worker_ip
    master_ip=$(whiptail --title "Master Node" --inputbox "Enter master node IP:" 10 60 3>&1 1>&2 2>&3)
    worker_ip=$(whiptail --title "Worker Node" --inputbox "Enter new worker node IP:" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$master_ip" ] || [ -z "$worker_ip" ]; then
        log "ERROR" "Both master and worker IPs are required"
        return 1
    fi
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    
    # Get join command from master
    local join_command
    join_command=$(ssh $ssh_opts "root@$master_ip" "kubeadm token create --print-join-command")
    
    if [ -z "$join_command" ]; then
        log "ERROR" "Failed to get join command from master"
        return 1
    fi
    
    # Setup worker node
    local worker_setup_script="/tmp/add_worker.sh"
    cat > "$worker_setup_script" << EOF
#!/bin/bash
set -e

# Install Kubernetes tools if not present
if ! command -v kubeadm >/dev/null 2>&1; then
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
fi

# Disable swap
swapoff -a
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab

# Join cluster
$join_command
EOF
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would add worker node $worker_ip to cluster"
        return 0
    fi
    
    # Execute on worker node
    scp $ssh_opts "$worker_setup_script" "root@$worker_ip:/tmp/"
    ssh $ssh_opts "root@$worker_ip" "chmod +x /tmp/add_worker.sh && /tmp/add_worker.sh"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Worker node $worker_ip added successfully"
        ssh $ssh_opts "root@$master_ip" "kubectl get nodes"
    else
        log "ERROR" "Failed to add worker node"
    fi
    
    rm -f "$worker_setup_script"
}

# Function to remove node from cluster
remove_cluster_node() {
    log "INFO" "Removing node from cluster..."
    
    local master_ip node_name
    master_ip=$(whiptail --title "Master Node" --inputbox "Enter master node IP:" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$master_ip" ]; then
        log "ERROR" "Master IP is required"
        return 1
    fi
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    
    # Get list of nodes
    local nodes
    nodes=$(ssh $ssh_opts "root@$master_ip" "kubectl get nodes --no-headers | awk '{print \$1}'")
    
    if [ -z "$nodes" ]; then
        log "ERROR" "No nodes found or cannot connect to cluster"
        return 1
    fi
    
    # Present nodes for selection
    local node_options=()
    local counter=1
    
    while IFS= read -r node; do
        node_options+=("$counter" "$node")
        ((counter++))
    done <<< "$nodes"
    
    local choice
    choice=$(whiptail --title "Remove Node" --menu "Select node to remove:" 15 60 $((${#node_options[@]}/2)) "${node_options[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$choice" ] && [ "$choice" -ge 1 ] && [ "$choice" -le $((counter-1)) ]; then
        node_name=$(echo "$nodes" | sed -n "${choice}p")
        
        if whiptail --title "Confirm Removal" --yesno "Remove node '$node_name' from cluster?" 10 60; then
            if [ -n "$TEST_MODE" ]; then
                log "INFO" "Test mode: Would remove node $node_name"
                return 0
            fi
            
            # Drain and delete node
            ssh $ssh_opts "root@$master_ip" "kubectl drain $node_name --ignore-daemonsets --delete-emptydir-data --force"
            ssh $ssh_opts "root@$master_ip" "kubectl delete node $node_name"
            
            log "INFO" "Node $node_name removed from cluster"
        fi
    fi
}

# Function to upgrade cluster
upgrade_cluster() {
    log "INFO" "Upgrading Kubernetes cluster..."
    
    local master_ip
    master_ip=$(whiptail --title "Master Node" --inputbox "Enter master node IP:" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$master_ip" ]; then
        log "ERROR" "Master IP is required"
        return 1
    fi
    
    local target_version
    target_version=$(whiptail --title "Target Version" --inputbox "Enter target Kubernetes version (e.g., 1.29.0):" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$target_version" ]; then
        log "ERROR" "Target version is required"
        return 1
    fi
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would upgrade cluster to version $target_version"
        return 0
    fi
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    
    # Upgrade master node
    log "INFO" "Upgrading master node..."
    ssh $ssh_opts "root@$master_ip" "
        apt-mark unhold kubeadm
        apt-get update
        apt-get install -y kubeadm=$target_version-00
        apt-mark hold kubeadm
        kubeadm upgrade plan
        kubeadm upgrade apply v$target_version -y
        apt-mark unhold kubelet kubectl
        apt-get install -y kubelet=$target_version-00 kubectl=$target_version-00
        apt-mark hold kubelet kubectl
        systemctl restart kubelet
    "
    
    log "INFO" "Master node upgrade completed"
    log "INFO" "Remember to upgrade worker nodes manually or use the cluster management tools"
}

# Function to backup cluster configuration
backup_cluster_config() {
    log "INFO" "Backing up cluster configuration..."
    
    local master_ip backup_path
    master_ip=$(whiptail --title "Master Node" --inputbox "Enter master node IP:" 10 60 3>&1 1>&2 2>&3)
    backup_path=$(whiptail --title "Backup Path" --inputbox "Enter local backup path:" 10 60 "/tmp/k8s-backup-$(date +%Y%m%d-%H%M%S)" 3>&1 1>&2 2>&3)
    
    if [ -z "$master_ip" ] || [ -z "$backup_path" ]; then
        log "ERROR" "Master IP and backup path are required"
        return 1
    fi
    
    mkdir -p "$backup_path"
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would backup cluster config to $backup_path"
        return 0
    fi
    
    # Backup etcd and kubernetes configs
    scp -r $ssh_opts "root@$master_ip:/etc/kubernetes" "$backup_path/"
    scp -r $ssh_opts "root@$master_ip:/var/lib/etcd" "$backup_path/" 2>/dev/null || log "WARN" "Could not backup etcd data"
    
    # Export all resources
    ssh $ssh_opts "root@$master_ip" "kubectl get all --all-namespaces -o yaml" > "$backup_path/all-resources.yaml"
    
    log "INFO" "Cluster configuration backed up to $backup_path"
}

# Function to restore cluster configuration
restore_cluster_config() {
    log "INFO" "Restoring cluster configuration..."
    
    local backup_path
    backup_path=$(whiptail --title "Backup Path" --inputbox "Enter backup path:" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$backup_path" ] || [ ! -d "$backup_path" ]; then
        log "ERROR" "Valid backup path is required"
        return 1
    fi
    
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would restore cluster config from $backup_path"
        return 0
    fi
    
    if whiptail --title "Confirm Restore" --yesno "This will restore cluster configuration from backup.\nThis operation may affect current cluster state.\n\nContinue?" 12 60; then
        # Apply backed up resources
        if [ -f "$backup_path/all-resources.yaml" ]; then
            kubectl apply -f "$backup_path/all-resources.yaml"
            log "INFO" "Cluster resources restored successfully"
        else
            log "ERROR" "No resource backup found in $backup_path"
        fi
    fi
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
