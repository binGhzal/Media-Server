# Proxmox Template Creator - Complete Feature Documentation

## Overview

The Proxmox Template Creator is a comprehensive infrastructure automation tool that creates VM templates and deploys container workloads on Proxmox VE. This tool supports 50+ Linux distributions, Docker containers, Kubernetes clusters, and complete infrastructure stacks.

## Quick Start Guide

```bash
# Download and extract
wget https://github.com/yourusername/homelab/archive/main.zip
unzip main.zip
cd homelab-main/proxmox

# Run as root (required for Proxmox operations)
chmod +x create-template.sh
./create-template.sh

# Or use CLI mode
./create-template.sh --help
```

## Core Features

### 1. Template Creation

- **50+ Linux Distributions**: Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux, openSUSE, Fedora, Arch Linux, Manjaro, Void Linux, NixOS, Gentoo, Amazon Linux 2, and more
- **Custom ISO Support**: Use your own ISO files or disk images
- **Cloud-Init Integration**: Automatic cloud-init configuration
- **Package Management**: Pre-install packages by category
- **User Configuration**: Setup default users with SSH keys
- **Network Configuration**: VLAN, bridge, and IP settings

### 2. Container Workloads

#### Docker Support

- **Container Deployment**: Deploy individual Docker containers
- **Docker Compose**: Support for docker-compose.yml files
- **Multi-VM Deployment**: Scale across multiple VMs
- **Registry Integration**: Private container registry support

#### Kubernetes Support

- **Multi-Node Clusters**: Master and worker node deployment
- **CNI Plugins**: Flannel, Calico, Weave networking
- **Ingress Controllers**: NGINX, Traefik support
- **Add-ons**: cert-manager, monitoring stack
- **Auto-joining**: Automatic cluster formation

### 3. Infrastructure Components

#### Monitoring Stack

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Node Exporter**: System metrics
- **cAdvisor**: Container metrics
- **Alertmanager**: Alert routing and notification

#### Container Registry

- **Private Registry**: Self-hosted Docker registry
- **Authentication**: User management and access control
- **SSL/TLS**: Optional certificate management
- **Storage**: Configurable storage backends

### 4. Automation Integration

#### Ansible Support

- **Playbook Discovery**: Automatic detection of available playbooks
- **Template Configuration**: Apply playbooks to templates
- **VM Orchestration**: Deploy and configure VMs
- **Inventory Generation**: Automatic inventory creation

#### Terraform Integration

- **Module Discovery**: Automatic detection of Terraform modules
- **Infrastructure as Code**: Declarative infrastructure
- **Container Workloads**: Specialized modules for containers
- **State Management**: Terraform state handling

### 5. Configuration Management

#### Settings System

- **VM Defaults**: CPU, memory, disk, storage settings
- **Network Configuration**: Bridge, VLAN, IP, DNS, firewall
- **Storage Settings**: Pools, formats, backup configuration
- **Security Settings**: SSH keys, firewall, encryption
- **Automation Settings**: Ansible, Terraform, CI/CD integration

#### Import/Export

- **Configuration Files**: Save and restore settings
- **Batch Processing**: Multiple template creation
- **Template Queues**: Automated template pipelines

## Getting Started

### Prerequisites

Before you begin, ensure you have:

- **Proxmox VE Host**: Version 7.x or 8.x
- **Root Access**: The script must be run as root
- **Network Connectivity**: Internet access for downloading images
- **Storage Space**: At least 50GB free for templates
- **Memory**: Minimum 4GB RAM available

### Quick Installation

1. **Download the Repository:**

   ```bash
   # Option 1: Using git (recommended)
   git clone https://github.com/binghzal/homelab.git
   cd homelab/proxmox

   # Option 2: Using wget
   wget https://github.com/binghzal/homelab/archive/main.zip
   unzip main.zip
   cd homelab-main/proxmox
   ```

2. **Prepare the Environment:**

   ```bash
   # Make script executable
   chmod +x create-template.sh

   # Verify Proxmox environment
   pvesm status  # Check storage
   pct list      # Verify container support
   ```

3. **Run Your First Template:**

   ```bash
   # Interactive mode (beginner-friendly)
   ./create-template.sh

   # Quick start with Ubuntu
   ./create-template.sh --distribution ubuntu-22.04 --template-name my-first-template
   ```

## Step-by-Step Guides

### Guide 1: Creating Your First VM Template

**Goal**: Create a basic Ubuntu 22.04 template with development tools

**Time Required**: 10-15 minutes

#### Step 1: Choose Your Distribution

```bash
# List all available distributions
./create-template.sh --list-distributions

# Or start interactive mode and select from menu
./create-template.sh
# Choose: "1) Create Single Template"
# Choose: "Ubuntu 22.04 LTS"
```

#### Step 2: Configure Basic Settings

```bash
# CLI approach
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name ubuntu-dev \
  --cpu-cores 2 \
  --memory 4096 \
  --disk-size 20G
```

Or in interactive mode:

1. Select "Configure VM Settings"
2. Set CPU cores: `2`
3. Set Memory: `4096 MB`
4. Set Disk size: `20G`

#### Step 3: Select Package Categories

```bash
# CLI: Select development and security packages
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "development,security,network"
```

Interactive mode:

1. Choose "Select Packages"
2. Select: `[x] Development Tools`
3. Select: `[x] Network & Security`
4. Select: `[x] Essential System Tools`

#### Step 4: Execute Template Creation

```bash
# Preview with dry-run first
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name ubuntu-dev \
  --packages "development,security" \
  --dry-run

# Create the actual template
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name ubuntu-dev \
  --packages "development,security"
```

#### Step 5: Verify Template Creation

```bash
# Check if template was created
qm list | grep ubuntu-dev

# View template details
qm config <TEMPLATE_ID>

# Clone template to test
qm clone <TEMPLATE_ID> 100 --name test-vm
qm start 100
```

### Guide 2: Setting Up Docker Container Workloads

**Goal**: Create a template with Docker and deploy a web application stack

**Time Required**: 20-25 minutes

#### Step 1: Create Docker-Enabled Template

```bash
# Create Ubuntu template with Docker support
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name docker-host \
  --packages "docker,development" \
  --docker-template web-server
```

#### Step 2: Choose Docker Template

Interactive mode:

1. Start script: `./create-template.sh`
2. Choose "Docker Template Integration"
3. Select available templates:
   - `web-server` (Nginx + PHP + MySQL)
   - `development` (VS Code Server + Tools)
   - `monitoring` (Prometheus + Grafana)

#### Step 3: Configure Container Settings

```bash
# Advanced Docker configuration
./create-template.sh \
  --docker-template web-server \
  --docker-registry "registry.example.com" \
  --docker-compose-file "/path/to/docker-compose.yml"
```

#### Step 4: Deploy and Test

```bash
# Clone template and start VM
qm clone <TEMPLATE_ID> 101 --name web-server-vm
qm start 101

# SSH into VM and verify Docker
ssh user@<VM_IP>
docker ps
docker-compose ps

# Access web application
curl http://<VM_IP>
```

### Guide 3: Kubernetes Cluster Deployment

**Goal**: Deploy a complete Kubernetes cluster with monitoring

**Time Required**: 30-40 minutes

#### Step 1: Create Control Plane Template

```bash
# Create Kubernetes control plane
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name k8s-control-plane \
  --k8s-template control-plane \
  --cpu-cores 2 \
  --memory 4096
```

#### Step 2: Create Worker Node Template

```bash
# Create Kubernetes worker nodes
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name k8s-worker \
  --k8s-template worker-node \
  --cpu-cores 2 \
  --memory 2048
```

#### Step 3: Deploy Cluster Nodes

```bash
# Clone and start control plane
qm clone <CONTROL_TEMPLATE_ID> 110 --name k8s-master
qm start 110

# Clone and start worker nodes
qm clone <WORKER_TEMPLATE_ID> 111 --name k8s-worker-1
qm clone <WORKER_TEMPLATE_ID> 112 --name k8s-worker-2
qm start 111
qm start 112
```

#### Step 4: Initialize Cluster

```bash
# SSH to control plane
ssh user@<MASTER_IP>

# Initialize cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Setup kubectl for user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (Flannel)
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

#### Step 5: Join Worker Nodes

```bash
# Get join command from master
kubeadm token create --print-join-command

# SSH to each worker and run join command
ssh user@<WORKER_IP>
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

#### Step 6: Deploy Monitoring Stack

```bash
# Use K8s template for monitoring
./create-template.sh \
  --k8s-template monitoring-stack \
  --template-name k8s-monitoring

# Or deploy directly to existing cluster
kubectl create namespace monitoring
kubectl apply -f kubernetes/templates/monitoring-stack.yml
```

### Guide 4: Ansible Automation Integration

**Goal**: Automate template configuration with Ansible

**Time Required**: 15-20 minutes

#### Step 1: Enable Ansible Integration

```bash
# Create template with Ansible support
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name ansible-managed \
  --ansible \
  --ansible-playbook security-hardening,docker-install
```

#### Step 2: Configure Ansible Playbooks

Interactive mode:

1. Choose "Configure Ansible Automation"
2. Select playbooks to apply:
   - `[x] security-hardening`
   - `[x] docker-install`
   - `[x] monitoring-setup`

#### Step 3: Customize Ansible Variables

```bash
# Edit Ansible variables for your environment
cat > /tmp/ansible-vars.yml << EOF
# Security settings
ssh_port: 2222
allowed_users: ["admin", "developer"]
install_fail2ban: true

# Docker settings
docker_version: "24.0"
docker_compose_version: "2.21.0"

# Monitoring settings
prometheus_retention: "30d"
grafana_admin_password: "secure_password"
EOF
```

#### Step 4: Apply Ansible Configuration

```bash
# Run with custom variables
./create-template.sh \
  --ansible \
  --ansible-vars /tmp/ansible-vars.yml \
  --template-name hardened-template
```

### Guide 5: Terraform Infrastructure as Code

**Goal**: Manage infrastructure with Terraform

**Time Required**: 25-30 minutes

#### Step 1: Enable Terraform Integration

```bash
# Create template with Terraform support
./create-template.sh \
  --distribution ubuntu-22.04 \
  --terraform \
  --terraform-module docker-containers,monitoring-stack
```

#### Step 2: Review Generated Terraform Code

```bash
# Check generated Terraform files
ls -la terraform/
cat terraform/main.tf
cat terraform/variables.tf
cat terraform/modules/docker-containers/main.tf
```

#### Step 3: Customize Infrastructure

```bash
# Edit terraform variables
cat > terraform/terraform.tfvars << EOF
# VM Configuration
vm_count = 3
vm_memory = 4096
vm_cores = 2

# Network Configuration
vm_network_bridge = "vmbr0"
vm_network_vlan = 100

# Storage Configuration
vm_storage_pool = "local-lvm"
vm_disk_size = "20G"

# Container Configuration
docker_templates = ["web-server", "database", "monitoring"]
enable_monitoring = true
enable_backup = true
EOF
```

#### Step 4: Deploy Infrastructure

```bash
# Initialize Terraform
cd terraform
terraform init

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

#### Step 5: Manage Infrastructure

```bash
# View current state
terraform show

# Update infrastructure
terraform plan
terraform apply

# Destroy when needed
terraform destroy
```

### Guide 6: Batch Processing and Automation

**Goal**: Create multiple templates automatically

**Time Required**: Variable (depends on number of templates)

#### Step 1: Create Configuration Files

```bash
# Create configs directory
mkdir -p configs

# Ubuntu development template
cat > configs/ubuntu-dev.conf << EOF
DISTRIBUTION="ubuntu-22.04"
TEMPLATE_NAME="ubuntu-dev"
CPU_CORES="2"
MEMORY_MB="4096"
DISK_SIZE="20G"
PACKAGES="development,docker,security"
DOCKER_TEMPLATES="development"
EOF

# CentOS web server template
cat > configs/centos-web.conf << EOF
DISTRIBUTION="centos-stream-9"
TEMPLATE_NAME="centos-web"
CPU_CORES="2"
MEMORY_MB="2048"
DISK_SIZE="15G"
PACKAGES="web-server,security"
DOCKER_TEMPLATES="web-server"
EOF

# Debian database template
cat > configs/debian-db.conf << EOF
DISTRIBUTION="debian-12"
TEMPLATE_NAME="debian-db"
CPU_CORES="4"
MEMORY_MB="8192"
DISK_SIZE="50G"
PACKAGES="database,security"
DOCKER_TEMPLATES="database"
EOF
```

#### Step 2: Run Batch Processing

```bash
# Process all configurations
for config in configs/*.conf; do
    echo "Processing $config..."
    ./create-template.sh --batch --config "$config"
done

# Or use built-in queue processing
./create-template.sh --batch --config-dir configs/
```

#### Step 3: Monitor Progress

```bash
# Check creation status
tail -f /var/log/template-creator.log

# Verify created templates
qm list | grep -E "ubuntu-dev|centos-web|debian-db"
```

### Guide 7: Advanced Customization

**Goal**: Create highly customized templates with specific requirements

#### Custom Package Installation

```bash
# Create custom package list
cat > /tmp/custom-packages.txt << EOF
# Development tools
build-essential
git
vim
tmux
htop

# Python environment
python3
python3-pip
python3-venv
python3-dev

# Node.js environment
nodejs
npm
yarn

# Database tools
postgresql-client
mysql-client
redis-tools

# Container tools
docker.io
docker-compose
kubectl
helm
EOF

# Use custom package list
./create-template.sh \
  --distribution ubuntu-22.04 \
  --custom-packages /tmp/custom-packages.txt
```

#### Custom Post-Installation Scripts

```bash
# Create post-install script
cat > /tmp/post-install.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Configure development environment
echo "Configuring development environment..."

# Install code editor
curl -fsSL https://code-server.dev/install.sh | sh
systemctl enable --now code-server@$USER

# Configure git
git config --global user.name "Template User"
git config --global user.email "user@example.com"

# Setup zsh with oh-my-zsh
apt-get update && apt-get install -y zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
chsh -s $(which zsh)

# Configure firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 8080  # code-server

echo "Post-installation configuration complete!"
EOF

chmod +x /tmp/post-install.sh

# Use custom post-install script
./create-template.sh \
  --distribution ubuntu-22.04 \
  --post-install-script /tmp/post-install.sh
```

#### Custom Cloud-Init Configuration

```bash
# Create custom cloud-init config
cat > /tmp/cloud-init-custom.yml << EOF
#cloud-config
users:
  - name: developer
    groups: sudo,docker
    shell: /bin/zsh
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAA... # Your SSH key here

packages:
  - curl
  - wget
  - git
  - vim
  - htop
  - docker.io

runcmd:
  - systemctl enable docker
  - usermod -aG docker developer
  - curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
  - chmod +x /usr/local/bin/docker-compose

timezone: UTC

locale: en_US.UTF-8
EOF

# Use custom cloud-init
./create-template.sh \
  --distribution ubuntu-22.04 \
  --cloud-init-config /tmp/cloud-init-custom.yml
```

## Troubleshooting Common Issues

### Template Creation Fails

**Issue**: Template creation process stops with errors

**Solutions**:

```bash
# Check logs for details
tail -f /var/log/template-creator.log

# Verify Proxmox storage
pvesm status
df -h

# Check network connectivity
ping 8.8.8.8
curl -I http://releases.ubuntu.com

# Retry with debug mode
./create-template.sh --debug --distribution ubuntu-22.04
```

### Docker Container Issues

**Issue**: Docker containers fail to start or access services

**Solutions**:

```bash
# SSH into VM and check Docker
ssh user@<VM_IP>

# Check Docker service
systemctl status docker

# Check container logs
docker logs <container_name>

# Verify network connectivity
docker network ls
docker network inspect bridge

# Check firewall rules
ufw status
iptables -L
```

### Kubernetes Cluster Problems

**Issue**: Kubernetes nodes fail to join cluster

**Solutions**:

```bash
# On control plane - check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Regenerate join token
kubeadm token create --print-join-command

# On worker nodes - reset and rejoin
sudo kubeadm reset
sudo kubeadm join <NEW_TOKEN_COMMAND>

# Check network plugin
kubectl get pods -n kube-system | grep -E 'flannel|calico|weave'
```

### Performance Issues

**Issue**: Template creation is slow or VMs are underperforming

**Solutions**:

```bash
# Check storage performance
pvesm status
iostat 1 5

# Monitor resource usage during creation
htop
iotop

# Adjust VM resources
./create-template.sh \
  --cpu-cores 4 \
  --memory 8192 \
  --disk-size 40G

# Use faster storage
./create-template.sh \
  --storage local-ssd \  # Use SSD storage if available
  --distribution ubuntu-22.04
```

### Network Configuration Issues

**Issue**: VMs cannot communicate or access internet

**Solutions**:

```bash
# Check Proxmox network configuration
cat /etc/network/interfaces

# Verify bridge configuration
ip addr show vmbr0
brctl show

# Check VLAN configuration (if using VLANs)
./create-template.sh \
  --network-bridge vmbr0 \
  --network-vlan 100 \
  --distribution ubuntu-22.04

# Test connectivity from VM
ping <GATEWAY_IP>
ping 8.8.8.8
nslookup google.com
```

## CLI Reference

### Basic Usage Commands

```bash
# Interactive mode (default)
./create-template.sh

# Help and version
./create-template.sh --help
./create-template.sh --version

# List available distributions
./create-template.sh --list-distributions
```

### Template Creation Commands

```bash
# Create specific distribution template
./create-template.sh --distribution ubuntu-22.04

# Batch mode with configuration
./create-template.sh --batch --config myconfig.conf

# Custom ISO
./create-template.sh --distribution custom-iso --iso-url http://example.com/my.iso
```

### Container Workload Commands

```bash
# Docker templates
./create-template.sh --docker-template nginx,redis,postgres

# Kubernetes templates
./create-template.sh --k8s-template webapp,database,monitoring

# Combined deployment
./create-template.sh --distribution ubuntu-22.04 --docker-template nginx --k8s-template webapp
```

### Automation Integration Commands

```bash
# With Ansible
./create-template.sh --ansible --ansible-playbook install-docker,configure-security

# With Terraform
./create-template.sh --terraform --terraform-module docker-containers,monitoring-stack

# Combined automation
./create-template.sh --ansible --terraform --batch
```

### Advanced Option Commands

```bash
# Dry run mode
./create-template.sh --dry-run --distribution ubuntu-22.04

# Debug logging
./create-template.sh --debug --log-file /tmp/template-creation.log

# Specific VM settings
./create-template.sh --cpu-cores 4 --memory 8192 --disk-size 50G
```

## Configuration Files

### Template Configuration File Format

```ini
# ubuntu-dev.conf
DISTRIBUTION="ubuntu-22.04"
CPU_CORES="4"
MEMORY_MB="8192"
DISK_SIZE="40G"
PACKAGES="development,security"
DOCKER_TEMPLATES="nginx,postgres"
ANSIBLE_PLAYBOOKS="install-docker,system-hardening"
```

### Batch Processing Configuration

```ini
# batch-templates.conf
[template1]
distribution=ubuntu-22.04
packages=web-server
docker_templates=nginx,redis

[template2]
distribution=debian-12
packages=development
k8s_templates=webapp,monitoring
```

## Terraform Modules

### Available Infrastructure Modules

#### Core Infrastructure

- `main.tf`: Basic VM provisioning
- `network.tf`: Network configuration
- `storage.tf`: Storage management
- `firewall.tf`: Security rules
- `user.tf`: User management

#### Container Workload Deployment

- `docker-containers.tf`: Docker VM deployment with containers
- `kubernetes-cluster.tf`: Multi-node Kubernetes clusters
- `container-registry.tf`: Private Docker registry
- `monitoring-stack.tf`: Prometheus/Grafana monitoring

### Module Usage Examples

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan Docker deployment
terraform plan -var-file="docker.tfvars"

# Deploy Kubernetes cluster
terraform apply -var="k8s_master_count=1" -var="k8s_worker_count=3"

# Deploy monitoring stack
terraform apply -var-file="monitoring.tfvars"
```

### Example Variable Configuration

```hcl
# docker.tfvars
docker_vm_count = 3
docker_cpu_cores = 4
docker_memory_mb = 8192
docker_containers = [
  {
    name = "nginx"
    image = "nginx:latest"
    ports = ["80:80", "443:443"]
    volumes = ["/var/www:/usr/share/nginx/html:ro"]
    environment = {}
    restart = "unless-stopped"
  }
]
```

## Ansible Playbooks

### Available Playbook Library

- `update-all-packages.yml`: System updates
- `install-docker.yml`: Docker installation
- `install-development-tools.yml`: Development packages
- `system-hardening.yml`: Security hardening
- `user-management.yml`: User and SSH configuration
- `deploy-docker-containers.yml`: Container deployment
- `deploy-k8s-manifests.yml`: Kubernetes deployments
- `configure-backups.yml`: Backup configuration
- `install-security-tools.yml`: Security tools

### Playbook Usage Examples

```bash
cd ansible

# Run individual playbook
ansible-playbook -i inventory playbooks/templates/install-docker.yml

# Run multiple playbooks
ansible-playbook -i inventory playbooks/templates/update-all-packages.yml playbooks/templates/system-hardening.yml
```

## Template Library

### Docker Templates Available

Located in `docker/templates/`:

- `nginx-container.yml`: NGINX web server
- `database-stack.yml`: MySQL/PostgreSQL databases
- `monitoring-tools.yml`: Monitoring containers
- `development-env.yml`: Development environment

### Kubernetes Templates Available

Located in `kubernetes/templates/`:

- `nginx-deployment.yaml`: NGINX deployment
- `database-cluster.yaml`: Database cluster
- `monitoring-stack.yaml`: Prometheus/Grafana
- `ingress-controller.yaml`: Ingress configuration

## Advanced Features

### 1. Security Configuration

- **SSH Key Management**: Automatic key deployment
- **Firewall Rules**: iptables and ufw configuration
- **User Access Control**: RBAC and permission management
- **Encryption**: Disk and network encryption options
- **Audit Logging**: Security event tracking

### 2. Network Configuration

- **VLAN Support**: Virtual LAN configuration
- **Bridge Management**: Network bridge setup
- **DNS Configuration**: Custom DNS servers
- **Load Balancing**: HAProxy integration
- **VPN Integration**: WireGuard and OpenVPN

### 3. Storage Management

- **Multiple Storage Pools**: Support for different storage types
- **Backup Configuration**: Automated backup strategies
- **Quota Management**: Storage quota enforcement
- **Snapshot Management**: VM snapshot automation
- **Disk Format Options**: raw, qcow2, vmdk support

### 4. Monitoring and Logging

- **Comprehensive Logging**: Detailed operation logs
- **Performance Monitoring**: Resource usage tracking
- **Alert Configuration**: Notification setup
- **Dashboard Creation**: Custom Grafana dashboards
- **Log Aggregation**: Centralized log management

## How-To Guides

### How to Create a Complete Development Environment

This guide shows how to create a comprehensive development environment with IDE, database, and container tools.

```bash
# Step 1: Create Ubuntu template with development packages
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "development,containers,database" \
  --vm-name "dev-template" \
  --cpu-cores 4 \
  --memory 8192 \
  --disk-size 100G

# Step 2: Deploy development containers
./create-template.sh \
  --docker-template development-stack.yml \
  --vm-name "dev-environment" \
  --clone-from dev-template
```

Example `development-stack.yml`:

```yaml
version: "3.8"
services:
  vscode-server:
    image: codercom/code-server:latest
    ports:
      - "8080:8080"
    volumes:
      - ./workspace:/home/coder/workspace
      - ./config:/home/coder/.config
    environment:
      - PASSWORD=secure-password
    restart: unless-stopped

  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: devdb
      POSTGRES_USER: developer
      POSTGRES_PASSWORD: dev-password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

  adminer:
    image: adminer:latest
    ports:
      - "8081:8080"
    depends_on:
      - postgres
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

### How to Set Up a Kubernetes Cluster

This guide demonstrates creating a complete Kubernetes cluster with monitoring.

```bash
# Step 1: Create K8s node templates
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "containers,kubernetes" \
  --vm-name "k8s-node-template" \
  --cpu-cores 2 \
  --memory 4096

# Step 2: Deploy master node
terraform apply -var-file="k8s-master.tfvars" terraform/kubernetes-cluster.tf

# Step 3: Deploy worker nodes
terraform apply -var="k8s_worker_count=3" terraform/kubernetes-cluster.tf

# Step 4: Apply monitoring stack
./create-template.sh --k8s-template monitoring-stack.yaml
```

Example monitoring stack (`monitoring-stack.yaml`):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:latest
          ports:
            - containerPort: 9090
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
            - name: storage
              mountPath: /prometheus
      volumes:
        - name: config
          configMap:
            name: prometheus-config
        - name: storage
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  selector:
    app: prometheus
  ports:
    - port: 9090
      targetPort: 9090
  type: ClusterIP
```

### How to Deploy a Complete Monitoring Stack

This guide shows deploying Prometheus, Grafana, and associated monitoring tools.

```bash
# Step 1: Create monitoring VM template
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "monitoring,containers" \
  --vm-name "monitoring-template" \
  --cpu-cores 4 \
  --memory 8192 \
  --disk-size 100G

# Step 2: Deploy monitoring stack with Terraform
cd terraform
terraform apply -var-file="monitoring-stack.tfvars"

# Step 3: Configure Grafana dashboards via Ansible
cd ../ansible
ansible-playbook -i inventory playbooks/configure-grafana-dashboards.yml
```

Example `monitoring-stack.tfvars`:

```hcl
# Monitoring Stack Configuration
monitoring_vm_count = 1
monitoring_cpu_cores = 4
monitoring_memory_mb = 8192
monitoring_disk_size = "100G"

# Prometheus configuration
prometheus_retention_days = 30
prometheus_storage_size = "50G"

# Grafana configuration
grafana_admin_password = "secure-admin-password"
grafana_plugins = [
  "grafana-piechart-panel",
  "grafana-worldmap-panel",
  "grafana-clock-panel"
]

# Alert manager configuration
alertmanager_webhook_url = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
alertmanager_email_from = "alerts@yourcompany.com"
alertmanager_email_to = "devops@yourcompany.com"
```

### How to Set Up a Private Container Registry

This comprehensive guide shows setting up a private Docker registry with authentication and SSL.

```bash
# Step 1: Create registry template
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "containers,security,web-server" \
  --vm-name "registry-template" \
  --cpu-cores 2 \
  --memory 4096 \
  --disk-size 50G

# Step 2: Deploy registry with Terraform
cd terraform
terraform apply -var-file="container-registry.tfvars"

# Step 3: Configure SSL and authentication
cd ../ansible
ansible-playbook -i inventory playbooks/configure-registry-ssl.yml
```

### How to Create Multi-Environment Infrastructure

This guide demonstrates setting up dev, staging, and production environments.

```bash
# Step 1: Create base templates for each environment
for env in dev staging prod; do
  ./create-template.sh \
    --distribution ubuntu-22.04 \
    --packages "base,security" \
    --vm-name "${env}-base-template" \
    --cpu-cores 2 \
    --memory 2048
done

# Step 2: Deploy environment-specific infrastructure
cd terraform
terraform workspace new dev
terraform apply -var-file="dev.tfvars"

terraform workspace new staging
terraform apply -var-file="staging.tfvars"

terraform workspace new prod
terraform apply -var-file="prod.tfvars"

# Step 3: Configure environment-specific settings
cd ../ansible
ansible-playbook -i inventory/dev playbooks/configure-dev-environment.yml
ansible-playbook -i inventory/staging playbooks/configure-staging-environment.yml
ansible-playbook -i inventory/prod playbooks/configure-prod-environment.yml
```

### How to Implement CI/CD Pipelines

This guide shows setting up automated CI/CD with the template creator.

```bash
# Step 1: Create CI/CD runner template
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "development,containers,infrastructure" \
  --vm-name "cicd-runner-template" \
  --cpu-cores 4 \
  --memory 8192 \
  --disk-size 100G

# Step 2: Deploy CI/CD infrastructure
cd terraform
terraform apply -var-file="cicd.tfvars"

# Step 3: Configure CI/CD tools
cd ../ansible
ansible-playbook -i inventory playbooks/install-jenkins.yml
ansible-playbook -i inventory playbooks/configure-docker-registry-access.yml
```

Example CI/CD pipeline (`.github/workflows/deploy.yml`):

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate Proxmox scripts
        run: |
          cd proxmox
          ./test-template-creator.sh

      - name: Validate Terraform
        run: |
          cd terraform
          terraform init
          terraform validate
          terraform plan

      - name: Validate Ansible
        run: |
          cd ansible
          ansible-playbook --syntax-check playbooks/*.yml

  deploy-dev:
    needs: validate
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to dev environment
        run: |
          cd terraform
          terraform workspace select dev
          terraform apply -auto-approve -var-file="dev.tfvars"

      - name: Configure with Ansible
        run: |
          cd ansible
          ansible-playbook -i inventory/dev playbooks/site.yml

  deploy-staging:
    needs: deploy-dev
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: |
          cd terraform
          terraform workspace select staging
          terraform apply -auto-approve -var-file="staging.tfvars"
```

### How to Backup and Restore Templates

This guide covers backup strategies and disaster recovery.

```bash
# Step 1: Create backup template
./create-template.sh \
  --distribution ubuntu-22.04 \
  --packages "backup,security" \
  --vm-name "backup-template" \
  --ansible-playbook configure-backups.yml

# Step 2: Configure automated backups
cd ansible
ansible-playbook -i inventory playbooks/configure-proxmox-backups.yml

# Step 3: Set up offsite backup
ansible-playbook -i inventory playbooks/configure-offsite-backup.yml
```

### How to Troubleshoot Common Issues

#### Template Creation Failures

```bash
# Enable debug logging
./create-template.sh --debug --log-file /tmp/debug.log

# Check Proxmox logs
tail -f /var/log/pve/tasks/current

# Validate template manually
qm list | grep template
qm config TEMPLATE_ID
```

#### Container Deployment Issues

```bash
# Check LXC container logs
pct list
journalctl -u pve-container@CONTAINER_ID

# Validate Docker templates
docker compose -f template.yml config
docker compose -f template.yml up --dry-run

# Check Kubernetes connectivity
kubectl cluster-info
kubectl get nodes
kubectl get all --all-namespaces
```

#### Network Connectivity Problems

```bash
# Check network configuration
ip route show
systemctl status networking

# Validate Proxmox network
pvesm status
qm config VMID | grep net

# Test connectivity
ping -c 4 gateway_ip
nslookup hostname
```

### How to Scale Infrastructure

This guide covers scaling strategies for growing workloads.

```bash
# Horizontal scaling - more VMs
terraform apply -var="vm_count=10" -var="load_balancer_enabled=true"

# Vertical scaling - bigger VMs
terraform apply -var="vm_cpu_cores=8" -var="vm_memory_mb=16384"

# Auto-scaling with monitoring
cd ansible
ansible-playbook -i inventory playbooks/configure-auto-scaling.yml
```

## Best Practices

### Security Best Practices

1. **Use SSH Keys**: Always configure SSH key authentication
2. **Regular Updates**: Keep templates updated with latest security patches
3. **Firewall Rules**: Configure network access restrictions
4. **User Management**: Use dedicated service accounts
5. **Secret Management**: Use tools like HashiCorp Vault for secrets

### Performance Best Practices

1. **Resource Planning**: Right-size CPU and memory allocations
2. **Storage Optimization**: Use appropriate storage types (SSD vs HDD)
3. **Network Optimization**: Configure appropriate network bridges
4. **Monitoring**: Implement comprehensive monitoring from day 1
5. **Backup Strategy**: Regular backups with tested restore procedures

### Automation Best Practices

1. **Infrastructure as Code**: Use Terraform for all infrastructure
2. **Configuration Management**: Use Ansible for post-deployment configuration
3. **CI/CD Integration**: Automate template creation and deployment
4. **Testing**: Implement automated testing for all components
5. **Documentation**: Keep documentation updated with infrastructure changes

### Cost Optimization Best Practices

1. **Resource Monitoring**: Track resource utilization
2. **Automated Scaling**: Scale resources based on demand
3. **Template Optimization**: Use minimal base templates
4. **Storage Management**: Implement proper storage lifecycle policies
5. **Environment Management**: Use separate environments appropriately

## Troubleshooting Reference

### Common Issues and Solutions

#### Issue: Template Creation Fails

**Symptoms:**

- Error during image download
- VM creation failure
- Package installation errors

**Solutions:**

```bash
# Check internet connectivity
curl -I http://google.com

# Verify Proxmox storage
pvesm status

# Check available space
df -h

# Validate distribution URL
wget --spider DISTRIBUTION_URL

# Check log files
tail -f /var/log/pve/tasks/current
```

#### Issue: Container Deployment Fails

**Symptoms:**

- Docker compose errors
- Container startup failures
- Network connectivity issues

**Solutions:**

```bash
# Check Docker daemon
systemctl status docker

# Validate compose file
docker compose config

# Check network configuration
docker network ls
docker network inspect bridge

# Review container logs
docker logs CONTAINER_NAME
```

#### Issue: Kubernetes Cluster Problems

**Symptoms:**

- Nodes not joining cluster
- Pod scheduling failures
- Network policy issues

**Solutions:**

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Check pod status
kubectl get pods --all-namespaces
kubectl describe pod POD_NAME

# Check logs
kubectl logs POD_NAME
journalctl -u kubelet
```

#### Issue: Ansible Playbook Failures

**Symptoms:**

- SSH connection failures
- Task execution errors
- Inventory problems

**Solutions:**

```bash
# Test connectivity
ansible all -i inventory -m ping

# Check SSH configuration
ssh -vvv user@host

# Validate playbook syntax
ansible-playbook --syntax-check playbook.yml

# Run with verbose output
ansible-playbook -vvv playbook.yml
```

### Performance Optimization Reference

#### VM Performance Optimization

1. **CPU Allocation**: Use `host` CPU type for best performance
2. **Memory Ballooning**: Disable if not needed
3. **Disk I/O**: Use `virtio-scsi` with `iothread`
4. **Network**: Use `virtio` network adapter

#### Storage Performance Optimization

1. **Use SSD Storage**: For database and high I/O workloads
2. **RAID Configuration**: Use appropriate RAID levels
3. **Cache Settings**: Configure proper cache modes
4. **Backup Storage**: Use separate storage for backups

#### Network Performance Optimization

1. **Bridge Configuration**: Use Linux bridges for performance
2. **VLAN Optimization**: Minimize VLAN overhead
3. **Bandwidth Management**: Implement QoS where needed
4. **Multi-path Networking**: Use bonding for redundancy

## Advanced Topics

### Custom Distributions Support

Add support for custom distributions by extending the script:

```bash
# Add to DISTRO_LIST array
DISTRO_LIST+=(
    "custom-linux|1.0|https://releases.example.com/custom-linux-1.0.iso|iso|yum|l26|root|8G|Custom enterprise Linux"
)

# Add package manager support
case "$PKG_MANAGER" in
    "custom-pkg")
        install_cmd="custom-pkg install"
        update_cmd="custom-pkg update"
        ;;
esac
```

### Integration with External Systems

#### LDAP Integration Configuration

```yaml
# Configure LDAP authentication
- name: Configure LDAP
  template:
    src: ldap.conf.j2
    dest: /etc/ldap/ldap.conf
  vars:
    ldap_server: "{{ ldap_server_url }}"
    ldap_base_dn: "{{ ldap_base_dn }}"
```

#### Monitoring Integration Configuration

```yaml
# Configure external monitoring
- name: Install monitoring agent
  package:
    name: monitoring-agent
    state: present
  vars:
    monitoring_endpoint: "{{ external_monitoring_url }}"
```

### Scaling Considerations

#### Multi-Node Proxmox Clusters Configuration

```bash
# Configure cluster storage
pvesm add cephfs ceph-storage --server ceph-mon1,ceph-mon2,ceph-mon3

# Set up migration policies
ha-manager add vm:100 --state started --group production

# Configure automatic failover
ha-manager set vm:100 --state started --max_restart 3
```

#### Load Balancing Configuration

```yaml
# HAProxy configuration for load balancing
frontend web_frontend
bind *:80
bind *:443 ssl crt /etc/ssl/certs/
default_backend web_servers

backend web_servers
balance roundrobin
server web1 192.168.1.10:80 check
server web2 192.168.1.11:80 check
server web3 192.168.1.12:80 check
```

## Support and Resources

### Documentation Links

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Docker Documentation](https://docs.docker.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform Documentation](https://registry.terraform.io/providers/Telmate/proxmox/)
- [Ansible Documentation](https://docs.ansible.com/)

### Community Resources

- [Proxmox Community Forum](https://forum.proxmox.com/)
- [r/Proxmox](https://reddit.com/r/Proxmox)
- [Proxmox Discord](https://discord.gg/proxmox)

### Professional Support Options

- Proxmox Support Subscriptions
- Custom consultation services
- Training and certification programs
