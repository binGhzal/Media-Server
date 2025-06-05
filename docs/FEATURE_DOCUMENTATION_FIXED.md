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

1. **Download the Repository:**

   ```bash
   wget https://github.com/binghzal/homelab/archive/main.zip
   unzip main.zip
   cd homelab-main/proxmox
   ```

2. **Run the Script (as root):**

   ```bash
   chmod +x create-template.sh
   ./create-template.sh
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
