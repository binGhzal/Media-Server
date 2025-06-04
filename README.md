# Homelab Infrastructure

## Introduction

This repository contains the configuration files and scripts for setting up a comprehensive homelab environment. The infrastructure supports various applications and services including virtualization, container orchestration, monitoring, automation, and development tools.

## Features

### 🚀 Proxmox VM Template Creation

- **Automated Template Builder**: Advanced script for creating VM templates with 70+ pre-configured packages
- **Multi-Distribution Support**: Compatible with 15+ Linux distributions and BSD variants
- **Interactive UI**: User-friendly Whiptail interface for package selection and configuration
- **Batch Processing**: Queue system for creating multiple templates simultaneously
- **Configuration Management**: Export/import functionality for template configurations

### 📦 Available Packages

The template creation script includes support for:

**Development Tools:**

- `zsh` - Enhanced shell with powerful features
- `fzf` - Fuzzy finder for command-line
- `vscode-server` - Visual Studio Code Server for remote development
- `ripgrep` - Ultra-fast text search tool
- `fd-find` - Modern alternative to find command
- `sad` - Batch file editor with regex support

**System Utilities:**

- `mc` - Midnight Commander file manager
- `mlocate` - Fast file location utility
- `timeshift` - System backup and restore tool

**Infrastructure & DevOps:**

- `docker.io` - Container runtime
- `ansible` - Configuration management and automation
- And 60+ additional packages for various use cases

### 🔧 Advanced Installation Features

- **Simple Packages**: Standard repository-based installations
- **Complex Software**: Custom installation procedures for specialized tools
- **Cloud-Init Integration**: Automated initial configuration
- **SSH Key Management**: Secure access configuration
- **Disk Management**: Flexible storage configuration

## Quick Start

### Proxmox Template Creation

1. **Run the Script:**

   ```bash
   cd proxmox
   sudo ./create-template.sh
   ```

2. **Choose Operating Mode:**

   - **Interactive Mode**: Use the Whiptail UI for guided setup
   - **CLI Mode**: Use command-line arguments for automation

3. **Configure Template:**

   - Select base OS distribution
   - Choose packages to install
   - Configure VM specifications (CPU, memory, disk)
   - Set up SSH keys and cloud-init

4. **Template Creation:**
   - Script automatically downloads ISO if needed
   - Creates VM with specified configuration
   - Installs selected packages via virt-customize
   - Converts VM to template

### Command Line Usage

```bash
# Interactive mode (default)
sudo ./create-template.sh

# CLI mode with specific configuration
sudo ./create-template.sh --cli \
  --template-name "ubuntu-dev-template" \
  --os-type "ubuntu" \
  --packages "zsh,fzf,vscode-server,docker.io" \
  --cpu 2 --memory 4096 --disk-size 32

# Show help
./create-template.sh --help
```

## Script Features

### Package Management

- **Repository Packages**: Standard apt/yum/pkg installations
- **Complex Software**: Custom installation scripts for specialized tools
- **Dependency Resolution**: Automatic handling of package dependencies
- **Version Control**: Consistent package versions across templates

### VM Configuration

- **Hardware Specs**: Configurable CPU, memory, and disk settings
- **Network Setup**: Automatic network interface configuration
- **Storage Management**: Flexible disk allocation and management
- **Cloud-Init**: Automated initial system configuration

### Advanced Features

- **Queue System**: Create multiple templates in sequence
- **Configuration Export**: Save and reuse template configurations
- **Error Recovery**: Robust error handling and cleanup procedures
- **Logging**: Comprehensive logging for troubleshooting

## Supported Distributions

| Distribution | Versions            | Package Manager |
| ------------ | ------------------- | --------------- |
| Ubuntu       | 20.04, 22.04, 24.04 | apt             |
| Debian       | 11, 12              | apt             |
| CentOS       | 8, 9                | yum/dnf         |
| Rocky Linux  | 8, 9                | yum/dnf         |
| AlmaLinux    | 8, 9                | yum/dnf         |
| Fedora       | 38, 39, 40          | dnf             |
| openSUSE     | Leap, Tumbleweed    | zypper          |
| FreeBSD      | 13, 14              | pkg             |
| And more...  |                     |                 |

## Complete Package List

### Development & Programming

- `zsh` - Z shell with advanced features
- `fzf` - Fuzzy finder for enhanced command-line experience
- `vscode-server` - Visual Studio Code Server for remote development
- `ripgrep` - Ultra-fast text search tool written in Rust
- `fd-find` - Simple, fast, and user-friendly alternative to find
- `sad` - CLI search and replace tool with regex support
- `git` - Distributed version control system
- `vim` / `neovim` - Advanced text editors
- `tmux` - Terminal multiplexer

### System Administration

- `mc` - Midnight Commander dual-pane file manager
- `mlocate` - Fast file location database
- `timeshift` - System backup and restore utility
- `htop` - Interactive process viewer
- `ncdu` - Disk usage analyzer with ncurses interface
- `tree` - Directory listing in tree format
- `wget` / `curl` - File download utilities

### Infrastructure & DevOps

- `docker.io` - Container runtime and management
- `ansible` - Configuration management and automation
- `terraform` - Infrastructure as Code tool
- `kubectl` - Kubernetes command-line tool
- `helm` - Kubernetes package manager

### Networking & Security

- `openssh-server` - Secure shell server
- `ufw` - Uncomplicated firewall
- `fail2ban` - Intrusion prevention system
- `nmap` - Network discovery and security auditing
- `wireshark` - Network protocol analyzer

### Monitoring & Logging

- `prometheus-node-exporter` - Hardware and OS metrics exporter
- `rsyslog` - Enhanced syslog daemon
- `logrotate` - Log file rotation utility

## Troubleshooting

### Common Issues

#### 1. Script Permission Denied

```bash
# Fix permissions
chmod +x create-template.sh
sudo ./create-template.sh
```

#### 2. Insufficient Disk Space

```bash
# Check available space
df -h
# Clean up old templates if needed
qm list
qm destroy <template-id>
```

#### 3. Package Installation Failures

- Check internet connectivity
- Verify repository configuration
- Review logs in `/tmp/template-creation.log`

#### 4. VM Creation Timeout

```bash
# Increase timeout in script configuration
# Check Proxmox node resources
pvesh get /nodes/$(hostname)/status
```

### Debug Mode

Enable verbose logging:

```bash
sudo bash -x ./create-template.sh --debug
```

### Log Locations

- **Main Log**: `/tmp/template-creation.log`
- **Virt-customize Log**: `/tmp/virt-customize.log`
- **VM Console**: Check Proxmox web interface

## Project Structure

```text
homelab/
├── proxmox/
│   ├── create-template.sh      # Main template creation script
│   ├── configs/                # Template configuration files
│   └── iso/                    # ISO storage directory
├── terraform/                  # Infrastructure as Code
├── ansible/                    # Configuration management
├── docker/                     # Container configurations
├── kubernetes/                 # K8s manifests
├── monitoring/                 # Monitoring stack configs
├── docs/                       # Additional documentation
├── README.md                   # This file
├── CONTRIBUTING.md             # Contribution guidelines
├── LICENSE                     # Project license
└── SECURITY.md                # Security policies
```

## Technologies Used

### Virtualization & Containerization

- **Proxmox VE** - Virtual environment platform
- **Docker** - Container runtime
- **Kubernetes** - Container orchestration
- **QEMU/KVM** - Virtualization technology

### Infrastructure as Code

- **Terraform/OpenTofu** - Infrastructure provisioning
- **Ansible** - Configuration management
- **Packer** - Image building automation

### Monitoring & Observability

- **Prometheus** - Metrics collection
- **Grafana** - Visualization and dashboards
- **AlertManager** - Alert handling

### Development Tools

- **Git/GitHub** - Version control and collaboration
- **VS Code Server** - Remote development environment
- **Various CLI tools** - Enhanced productivity

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Security

For security-related issues, please review our [Security Policy](SECURITY.md).

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Resources & References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Cloud-Init Documentation](https://cloud-init.readthedocs.io/)
- [Virt-customize Manual](https://libguestfs.org/virt-customize.1.html)
- [Christian Lempa's Boilerplates](https://github.com/christianlempa/boilerplates)

---

## Support

If you encounter issues or have questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review existing [GitHub Issues](../../issues)
3. Create a new issue with detailed information

### Enjoy your homelab journey! 🚀
