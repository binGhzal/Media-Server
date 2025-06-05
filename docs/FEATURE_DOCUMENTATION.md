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

## Quick Start

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

### Basic Usage

```bash
# Interactive mode (default)
./create-template.sh

# Help and version
./create-template.sh --help
./create-template.sh --version

# List available distributions
./create-template.sh --list-distributions
```

### Template Creation

```bash
# Create specific distribution template
./create-template.sh --distribution ubuntu-22.04

# Batch mode with configuration
./create-template.sh --batch --config myconfig.conf

# Custom ISO
./create-template.sh --distribution custom-iso --iso-url http://example.com/my.iso
```

### Container Workloads

```bash
# Docker templates
./create-template.sh --docker-template nginx,redis,postgres

# Kubernetes templates
./create-template.sh --k8s-template webapp,database,monitoring

# Combined deployment
./create-template.sh --distribution ubuntu-22.04 --docker-template nginx --k8s-template webapp
```

### Automation Integration

```bash
# With Ansible
./create-template.sh --ansible --ansible-playbook install-docker,configure-security

# With Terraform
./create-template.sh --terraform --terraform-module docker-containers,monitoring-stack

# Combined automation
./create-template.sh --ansible --terraform --batch
```

### Advanced Options

```bash
# Dry run mode
./create-template.sh --dry-run --distribution ubuntu-22.04

# Debug logging
./create-template.sh --debug --log-file /tmp/template-creation.log

# Specific VM settings
./create-template.sh --cpu-cores 4 --memory 8192 --disk-size 50G
```

## Configuration Files

### Template Configuration

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

### Batch Processing

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

### Available Modules

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

### Module Usage

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

### Example Variables

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

### Available Playbooks

- `update-all-packages.yml`: System updates
- `install-docker.yml`: Docker installation
- `install-development-tools.yml`: Development packages
- `system-hardening.yml`: Security hardening
- `user-management.yml`: User and SSH configuration
- `deploy-docker-containers.yml`: Container deployment
- `deploy-k8s-manifests.yml`: Kubernetes deployments
- `configure-backups.yml`: Backup configuration
- `install-security-tools.yml`: Security tools

### Playbook Usage

```bash
cd ansible

# Run individual playbook
ansible-playbook -i inventory playbooks/templates/install-docker.yml

# Run multiple playbooks
ansible-playbook -i inventory playbooks/templates/update-all-packages.yml playbooks/templates/system-hardening.yml
```

## Template Library

### Docker Templates

Located in `docker/templates/`:

- `nginx-container.yml`: NGINX web server
- `database-stack.yml`: MySQL/PostgreSQL databases
- `monitoring-tools.yml`: Monitoring containers
- `development-env.yml`: Development environment

### Kubernetes Templates

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

## Troubleshooting

### Common Issues

#### Template Creation Fails

```bash
# Check Proxmox permissions
pveum user list

# Verify storage access
pvesm status

# Check network configuration
ip addr show
```

#### Container Deployment Issues

```bash
# Check Docker service
systemctl status docker

# Verify container registry access
docker login registry.example.com

# Check Kubernetes cluster status
kubectl cluster-info
```

#### Ansible/Terraform Integration

```bash
# Verify Ansible connectivity
ansible all -m ping -i inventory

# Check Terraform state
terraform state list

# Validate configuration
terraform validate
```

### Debug Mode

```bash
# Enable debug logging
./create-template.sh --debug --log-file /tmp/debug.log

# Check detailed logs
tail -f /tmp/debug.log
```

## Best Practices

### 1. Template Management

- Use consistent naming conventions
- Implement version control for templates
- Regular template updates and security patches
- Backup template configurations

### 2. Security

- Regular SSH key rotation
- Network segmentation
- Firewall rule management
- Regular security audits

### 3. Resource Management

- Monitor resource usage
- Implement quotas and limits
- Regular cleanup of unused resources
- Capacity planning

### 4. Automation

- Use Infrastructure as Code principles
- Implement CI/CD pipelines
- Version control all configurations
- Automated testing and validation

## API Integration

### Proxmox API Usage

The script integrates with Proxmox VE API for:

- VM creation and management
- Template operations
- Network configuration
- Storage management
- User and permission management

### External Integrations

- **Container Registries**: Docker Hub, Harbor, AWS ECR
- **CI/CD Systems**: GitLab CI, Jenkins, GitHub Actions
- **Monitoring**: Prometheus, Grafana, Zabbix
- **Configuration Management**: Ansible, Puppet, Chef

## Roadmap and Future Features

### Planned Enhancements

- **Multi-Cluster Support**: Manage multiple Proxmox clusters
- **Advanced Networking**: SDN and micro-segmentation
- **GPU Support**: GPU passthrough for containers
- **Edge Computing**: Edge node deployment
- **Disaster Recovery**: Automated DR procedures

### Integration Roadmap

- **Cloud Integration**: AWS, Azure, GCP hybrid setups
- **Service Mesh**: Istio and Linkerd support
- **GitOps**: ArgoCD and Flux integration
- **Observability**: OpenTelemetry and Jaeger
- **AI/ML Workloads**: MLOps pipeline support

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines.

## License

See [LICENSE](../LICENSE) for license information.

## Support

For support and questions:

1. Check this documentation
2. Review troubleshooting section
3. Check existing issues on GitHub
4. Create a new issue with detailed information
