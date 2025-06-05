# Terraform Integration for Proxmox Template Creator

This section covers the Terraform integration with the Proxmox Template Creator, enabling Infrastructure as Code (IaC) deployments with modular, scalable configurations.

## Overview

The Proxmox Template Creator includes comprehensive Terraform integration that provides:

- Modular Terraform configuration generation
- Multi-environment support (dev/staging/prod)
- Automatic variable collection and validation
- Module-based architecture for scalability
- Integrated CI/CD workflow support

## Features

### Enhanced Configuration Generation

- **Modular Structure**: Organized into reusable modules (VM, network, storage)
- **Environment Management**: Separate configurations for dev, staging, and production
- **Variable Validation**: Built-in validation for configuration parameters
- **Provider Management**: Automatic provider configuration and versioning

### Supported Modules

- **VM Module**: Virtual machine provisioning and management
- **Network Module**: Network configuration and firewall rules
- **Storage Module**: Storage backend management
- **Monitoring Module**: Monitoring and logging setup
- **Backup Module**: Automated backup configuration
- **Security Module**: Security hardening and compliance

## Directory Structure

When Terraform integration is enabled, the following structure is created:

```directory
terraform/
├── main.tf                    # Main configuration with module calls
├── variables.tf               # Variable definitions with validation
├── outputs.tf                 # Output values
├── terraform.tfvars.example   # Example variable values
├── Makefile                   # Common operations automation
├── modules/
│   ├── vm/                    # VM provisioning module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── network/               # Network configuration module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── storage/               # Storage management module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    ├── dev/
    │   └── terraform.tfvars
    ├── staging/
    │   └── terraform.tfvars
    └── prod/
        └── terraform.tfvars
```

## Usage Examples

### Via Template Creator UI

1. Run the template creator: `./create-template.sh`
2. Create your template as usual
3. In the automation menu, enable Terraform
4. Select desired modules (VM, network, storage, etc.)
5. Configure variables interactively
6. Choose target environment

### Via CLI

```bash
# Create template with Terraform automation
./create-template.sh \
  --distro ubuntu-22.04 \
  --terraform \
  --terraform-modules vm,network \
  --terraform-env dev
```

### Direct Terraform Usage

After configuration generation:

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
make init

# Plan deployment for dev environment
make dev

# Apply to dev environment
make dev-apply

# Plan for production
make prod

# Apply to production
make prod-apply
```

## Configuration

### Provider Configuration

The generated configuration includes comprehensive provider setup:

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "~> 2.9.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.1"
    }
    tls = {
      source = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
```

### Variable Management

Variables are automatically collected and validated:

```hcl
variable "vm_count" {
  description = "Number of VMs to create"
  type = number
  default = 1
  validation {
    condition = var.vm_count > 0 && var.vm_count <= 100
    error_message = "VM count must be between 1 and 100."
  }
}
```

### Environment-Specific Configuration

Each environment has its own variable file:

```hcl
# environments/dev/terraform.tfvars
environment = "dev"
vm_count = 1
vm_name_prefix = "dev-vm"
vm_id_start = 1000

# environments/prod/terraform.tfvars
environment = "prod"
vm_count = 3
vm_name_prefix = "prod-vm"
vm_id_start = 3000
```

## Module Details

### VM Module

Handles virtual machine provisioning with:

- Template cloning
- Resource allocation (CPU, memory, disk)
- Network configuration
- Cloud-init setup
- SSH key management
- Tagging and lifecycle management

### Network Module

Manages network infrastructure:

- Bridge configuration
- VLAN setup
- Firewall rules
- Load balancer configuration

### Storage Module

Handles storage resources:

- Disk provisioning
- Storage backend configuration
- Backup storage setup

## Advanced Features

### Workspace Initialization

Terraform workspace is automatically initialized with:

- Provider installation
- Configuration validation
- Code formatting
- Module dependency resolution

### Makefile Automation

Generated Makefile provides convenient commands:

```makefile
# Common operations
make init          # Initialize Terraform
make plan          # Plan changes
make apply         # Apply changes
make destroy       # Destroy resources
make validate      # Validate configuration
make format        # Format code
make lint          # Run linting

# Environment-specific
make dev           # Plan for dev
make dev-apply     # Apply to dev
make staging       # Plan for staging
make staging-apply # Apply to staging
make prod          # Plan for prod
make prod-apply    # Apply to prod
```

### CI/CD Integration

The configuration includes CI/CD workflow support:

```yaml
# Example GitHub Actions workflow
name: Terraform
on: [push, pull_request]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: terraform init
      - name: Terraform Validate
        run: terraform validate
      - name: Terraform Plan
        run: terraform plan
```

## Best Practices

### State Management

- Use remote state backends for production
- Enable state locking
- Regular state backups

### Security

- Store sensitive variables in secure locations
- Use service accounts for automation
- Enable audit logging

### Module Development

- Keep modules focused and reusable
- Include comprehensive documentation
- Version your modules

## Troubleshooting

### Common Issues

1. **Provider authentication**

   ```bash
   # Verify API credentials
   terraform plan -var-file=environments/dev/terraform.tfvars
   ```

2. **State lock issues**

   ```bash
   # Force unlock if needed (use carefully)
   terraform force-unlock LOCK_ID
   ```

3. **Module dependencies**

   ```bash
   # Refresh module sources
   terraform get -update
   ```

### Debug Mode

Enable detailed logging:

```bash
export TF_LOG=DEBUG
terraform plan
```

## Migration and Upgrades

### From Basic to Modular

If you have existing basic Terraform configurations:

1. Backup existing state
2. Generate new modular configuration
3. Import existing resources
4. Validate and test

### Provider Upgrades

```bash
# Upgrade providers
terraform init -upgrade

# Validate after upgrade
terraform validate
```

## Integration Examples

### With Docker Templates

```hcl
module "docker_vm" {
  source = "./modules/vm"

  vm_configs = local.vm_configs
  template_name = "docker-template"
  # Docker-specific configuration
}
```

### With Kubernetes Templates

```hcl
module "k8s_cluster" {
  source = "./modules/vm"

  vm_count = 3
  template_name = "k8s-template"
  # Kubernetes cluster configuration
}
```

## See Also

- [Proxmox Template Creator Main Documentation](README.md)
- [Ansible Integration](ansible.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Terraform Provider Documentation](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
