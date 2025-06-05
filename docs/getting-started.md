# Getting Started

## Prerequisites

Before you begin using the Proxmox Template Creator, ensure you have:

- **Proxmox VE Host**: A running Proxmox VE 7.x or 8.x installation
- **Root Access**: The script must be run as root on the Proxmox host
- **Storage**: Sufficient storage for VM templates (recommended: 50GB+ free space)
- **Network**: Internet connectivity for downloading distribution images
- **Memory**: At least 4GB RAM available for template creation

## Quick Start

### 1. Download and Setup

```bash
# Clone the repository
git clone https://github.com/binghzal/homelab.git
cd homelab/proxmox

# Make the script executable
chmod +x create-template.sh

# Run as root
./create-template.sh
```

### 2. Basic Template Creation

The easiest way to create your first template:

1. Run the script: `./create-template.sh`
2. Select "Create Single Template" from the main menu
3. Choose a distribution (e.g., Ubuntu 22.04)
4. Select packages to install
5. Configure basic settings
6. Let the script create your template

### 3. Using CLI Mode

For automation and scripting:

```bash
# Create an Ubuntu development template
./create-template.sh --distribution ubuntu-22.04 \
                     --template-name ubuntu-dev \
                     --packages "development,docker" \
                     --dry-run

# Use a configuration file
./create-template.sh --config examples/ubuntu-22.04-dev.conf
```

## Next Steps

- Explore [Container Integration](docker-integration.md) for Docker and Kubernetes templates
- Configure [Ansible Integration](ansible.md) for automated provisioning
- Set up [Terraform Integration](terraform.md) for infrastructure as code
- Review [Advanced Configuration](advanced-configuration.md) options

## Common Issues

### Permission Errors

The script must run as root. Use `sudo su -` before running.

### Network Issues

Ensure your Proxmox host can reach package repositories and download mirrors.

### Storage Issues

Check available storage with `pvesm status` and ensure sufficient space.

For more troubleshooting, see the [Troubleshooting Guide](troubleshooting.md).
