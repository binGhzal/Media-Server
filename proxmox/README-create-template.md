# Proxmox Template Creator

A comprehensive bash script for creating VM templates in Proxmox VE with advanced features including support for 25+ Linux distributions, package management, Ansible integration, and Terraform configuration generation.

## 🚀 Features

### Core Functionality

- **25+ Linux Distributions & BSD Support**: Ubuntu, Debian, CentOS, Rocky Linux, AlmaLinux, RHEL, Fedora, openSUSE, Arch Linux, Alpine Linux, FreeBSD, OpenBSD, NetBSD, Oracle Linux, Parrot Security OS, Talos Linux, and more
- **Comprehensive Package Management**: 80+ pre-defined packages organized in 10 categories
- **Cloud-init Integration**: Automated user creation, SSH key setup, and initial configuration
- **Advanced Networking**: Bridge configuration, VLAN tagging, and multiple network modes
- **Hardware Customization**: CPU, memory, disk size, and storage pool configuration

### Advanced Integrations

- **Ansible Integration**:
  - Dedicated LXC container for Ansible management
  - Automatic inventory generation
  - Pre-built playbooks for system hardening, Docker, and Kubernetes
  - Seamless template management
- **Terraform Integration**:
  - Complete Terraform configuration generation
  - Variables, providers, and main configuration files
  - Infrastructure-as-code approach
  - Multi-VM deployment support

### User Experience

- **Interactive GUI**: User-friendly whiptail-based interface
- **CLI Mode**: Full command-line support for automation
- **Batch Processing**: Create multiple templates in queue
- **Configuration Management**: Export/import template configurations
- **Comprehensive Help System**: Built-in documentation and distribution information

## 📋 Requirements

- **Proxmox VE**: Version 7.0 or later
- **Operating System**: Debian-based Proxmox host
- **Privileges**: Root or sudo access
- **Network**: Internet connection for image downloads
- **Storage**: Sufficient space for template images (varies by distribution)
- **Dependencies**:
  - `whiptail` (for interactive mode)
  - `wget` (for image downloads)
  - `qm` (Proxmox VE commands)

## 🔧 Installation

1. **Download the script**:

   ```bash
   wget https://raw.githubusercontent.com/binghzal/homelab/main/proxmox/create-template.sh
   chmod +x create-template.sh
   ```

2. **Install dependencies** (if not already present):

   ```bash
   apt update
   apt install whiptail wget curl -y
   ```

3. **Run the script**:
   ```bash
    ./create-template.sh
   ```

## 📖 Usage

### Interactive Mode (Default)

Run the script without arguments for the full interactive experience:

```bash
./create-template.sh
```

#### Main Menu Options:

1. **Select Distribution** - Choose from 25+ supported distributions
2. **Configure Template** - Set hardware, networking, and cloud-init options
3. **Select Packages** - Choose from 80+ pre-defined packages in 10 categories
4. **Configure Integrations** - Enable Ansible and/or Terraform integration
5. **Template Queue** - Manage multiple template configurations
6. **Configuration Management** - Export/import configurations
7. **Create Template** - Start the template creation process

### Command Line Interface (CLI)

For automation and scripting, use CLI mode:

```bash
# Basic template creation
sudo ./create-template.sh -d ubuntu -v 22.04 -n ubuntu-22.04-template -i 9000

# Advanced configuration
sudo ./create-template.sh \
  --distribution ubuntu \
  --version 22.04 \
  --name "Ubuntu 22.04 Server" \
  --vmid 9001 \
  --cores 4 \
  --memory 4096 \
  --disk-size 40G \
  --storage local-lvm \
  --bridge vmbr0 \
  --vlan 100 \
  --user admin \
  --ssh-key /root/.ssh/id_rsa.pub \
  --packages "docker.io,kubectl,ansible" \
  --ansible \
  --terraform \
  --batch
```

#### CLI Options:

- `-h, --help` - Show help information
- `-d, --distribution` - Distribution name (ubuntu, debian, centos, etc.)
- `-v, --version` - Distribution version
- `-n, --name` - Template name
- `-i, --vmid` - VM ID (100-999999999)
- `-c, --cores` - Number of CPU cores
- `-m, --memory` - Memory in MB
- `-s, --storage` - Storage pool name
- `--disk-size` - Disk size (e.g., 20G, 50G)
- `--bridge` - Network bridge (default: vmbr0)
- `--vlan` - VLAN tag
- `--ssh-key` - Path to SSH public key file
- `--user` - Cloud-init username
- `--packages` - Comma-separated package list
- `--ansible` - Enable Ansible integration
- `--terraform` - Enable Terraform integration
- `--batch` - Non-interactive batch mode
- `--import-config` - Import configuration file
- `--export-config` - Export current configuration
- `--list-distributions` - List all supported distributions
- `--validate-config` - Validate current configuration

### Batch Mode Examples

```bash
# Create multiple templates from configuration files
sudo ./create-template.sh --import-config ubuntu-templates.conf --batch

# List supported distributions
./create-template.sh --list-distributions

# Validate configuration before creation
sudo ./create-template.sh -d debian -v 12 -i 9002 --validate-config
```

## 🗂️ Supported Distributions

### Linux Distributions

| Distribution       | Versions                     | Package Manager | Notes                 |
| ------------------ | ---------------------------- | --------------- | --------------------- |
| Ubuntu             | 20.04, 22.04, 24.04          | APT             | LTS releases          |
| Debian             | 11 (Bullseye), 12 (Bookworm) | APT             | Stable releases       |
| CentOS             | 7, 8, 9                      | YUM/DNF         | Stream versions       |
| Rocky Linux        | 8, 9                         | DNF             | RHEL rebuild          |
| AlmaLinux          | 8, 9                         | DNF             | RHEL rebuild          |
| RHEL               | 8, 9                         | DNF             | Subscription required |
| Fedora             | 38, 39, 40                   | DNF             | Latest releases       |
| openSUSE           | Leap 15.4, 15.5, Tumbleweed  | Zypper          | Stable & rolling      |
| Arch Linux         | Latest                       | Pacman          | Rolling release       |
| Alpine Linux       | 3.17, 3.18, 3.19             | APK             | Minimal & secure      |
| Oracle Linux       | 8, 9                         | DNF             | Enterprise-focused    |
| Parrot Security OS | Latest                       | APT             | Security-focused      |
| Talos Linux        | Latest                       | -               | Kubernetes-focused    |

### BSD Variants

| Distribution | Versions | Package Manager | Notes            |
| ------------ | -------- | --------------- | ---------------- |
| FreeBSD      | 13, 14   | pkg             | General purpose  |
| OpenBSD      | 7.3, 7.4 | pkg_add         | Security-focused |
| NetBSD       | 9, 10    | pkg_add         | Portable         |

## 📦 Package Categories

The script provides 80+ pre-defined packages organized into 10 categories:

### 1. Essential System Tools

- Basic utilities: `curl`, `wget`, `git`, `vim`, `nano`
- System monitoring: `htop`, `tmux`, `screen`
- File management: `rsync`, `unzip`, `zip`, `tree`
- JSON/YAML tools: `jq`, `yq`

### 2. Development Tools

- Runtime environments: `nodejs`, `python3`, `golang`, `openjdk-11-jdk`
- Build tools: `maven`, `gradle`, `make`, `gcc`
- DevOps tools: `docker-compose`, `kubectl`, `helm`
- Infrastructure tools: `terraform`, `ansible`, `packer`, `vagrant`

### 3. Network & Security

- Network services: `openssh-server`, `nginx-extras`
- Security tools: `ufw`, `fail2ban`, `nmap`, `wireshark-common`
- VPN tools: `wireguard`, `openvpn`
- SSL/TLS: `openssl`, `certbot`

### 4. Monitoring & Performance

- System monitoring: `prometheus`, `node-exporter`, `grafana-agent`
- Performance analysis: `htop`, `iotop`, `nethogs`, `iftop`
- System statistics: `sysstat`, `dstat`, `glances`, `atop`

### 5. Container & Virtualization

- Container runtimes: `docker.io`, `containerd`, `podman`
- Container tools: `buildah`, `skopeo`
- VM tools: `qemu-guest-agent`, `cloud-init`, `cloud-utils`

### 6. Web & Database Servers

- Web servers: `nginx`, `apache2`
- Databases: `mysql-server`, `postgresql`, `redis-server`, `mongodb`
- Application servers: `php-fpm`, `nodejs`
- Search & analytics: `elasticsearch`, `logstash`, `kibana`

### 7. File & Storage Management

- Network filesystems: `nfs-common`, `cifs-utils`, `samba`
- File transfer: `ftp`, `vsftpd`, `rclone`
- Backup tools: `duplicity`, `borgbackup`, `restic`
- Cloud storage: `s3fs-fuse`

### 8. Text Editors & IDEs

- Console editors: `vim`, `neovim`, `emacs`, `nano`, `micro`, `joe`
- GUI editors: `code`, `sublime-text-installer`, `atom`, `gedit`

### 9. Backup & Synchronization

- Backup tools: `rsync`, `rdiff-backup`, `duplicity`, `borgbackup`, `restic`
- Sync tools: `rclone`, `syncthing`, `nextcloud-client`

### 10. Desktop Environment (GUI)

- Desktop environments: `ubuntu-desktop-minimal`, `xfce4`, `lxde`
- Window managers: `kde-plasma-desktop`, `gnome-core`, `mate-desktop`
- Lightweight options: `cinnamon-desktop-environment`

## 🔗 Ansible Integration

### Features

- **Dedicated LXC Container**: Creates a separate Ansible control node
- **Inventory Management**: Automatic Proxmox inventory generation
- **Pre-built Playbooks**: System hardening, Docker setup, Kubernetes preparation
- **Template Management**: Easy deployment and configuration of created templates

### Setup Process

1. Enable Ansible integration in the script
2. Script creates LXC container with Ansible installed
3. Generates Proxmox dynamic inventory
4. Creates default playbooks for common tasks
5. Provides commands for template management

### Generated Files

- `/opt/ansible/inventory/proxmox.yml` - Dynamic inventory
- `/opt/ansible/playbooks/` - Default playbooks directory
- `/opt/ansible/roles/` - Custom roles directory

### Example Usage

```bash
# Run system hardening on all templates
ansible-playbook -i /opt/ansible/inventory/proxmox.yml /opt/ansible/playbooks/system-hardening.yml

# Install Docker on specific template
ansible-playbook -i /opt/ansible/inventory/proxmox.yml /opt/ansible/playbooks/install-docker.yml --limit template-group
```

## 🏗️ Terraform Integration

### Features

- **Complete Configuration Generation**: Variables, providers, main config, outputs
- **Multi-VM Support**: Deploy multiple VMs from single template
- **Network Configuration**: Automatic network and IP management
- **Documentation**: Generated README with usage instructions

### Generated Structure

```
terraform-proxmox/
├── variables.tf          # Input variables
├── providers.tf          # Terraform providers
├── main.tf               # Main configuration
├── outputs.tf            # Output values
└── README.md             # Usage documentation
```

### Example Usage

```bash
cd terraform-proxmox
terraform init
terraform plan
terraform apply
```

### Generated Variables

- `vm_count` - Number of VMs to create
- `vm_name_prefix` - VM name prefix
- `template_id` - Source template ID
- `cpu_cores` - CPU configuration
- `memory_mb` - Memory configuration
- `disk_size` - Disk size
- `network_bridge` - Network configuration

## 💾 Configuration Management

### Export Configuration

Save current template configuration for reuse:

```bash
# Interactive export
./create-template.sh # Then select "Export Configuration"

# CLI export
./create-template.sh --export-config my-template.conf
```

### Import Configuration

Load previously saved configuration:

```bash
# Interactive import
./create-template.sh # Then select "Import Configuration"

# CLI import
./create-template.sh --import-config my-template.conf
```

### Configuration File Format

```ini
# Proxmox Template Configuration
[DISTRIBUTION]
DIST_NAME="ubuntu"
DIST_VERSION="22.04"
IMG_URL="https://cloud-images.ubuntu.com/..."

[TEMPLATE]
TEMPL_NAME_DEFAULT="ubuntu-22.04-template"
VMID_DEFAULT="9000"

[HARDWARE]
CORES="2"
MEM="2048"
DISK_SIZE="20G"

[PACKAGES]
SELECTED_PACKAGES=("docker.io" "kubectl" "ansible")

[ANSIBLE]
ANSIBLE_ENABLED="true"

[TERRAFORM]
TERRAFORM_ENABLED="true"
```

## 🔄 Template Queue (Batch Processing)

Create multiple templates in sequence:

### Interactive Queue Management

1. Configure first template
2. Add to queue
3. Configure additional templates
4. Review queue
5. Create all templates

### CLI Batch Processing

```bash
# Import queue configuration and process
./create-template.sh --import-config template-queue.conf --batch
```

### Queue Configuration Example

```ini
[TEMPLATE_1]
DIST_NAME="ubuntu"
DIST_VERSION="22.04"
TEMPL_NAME_DEFAULT="ubuntu-22.04"
VMID_DEFAULT="9000"

[TEMPLATE_2]
DIST_NAME="debian"
DIST_VERSION="12"
TEMPL_NAME_DEFAULT="debian-12"
VMID_DEFAULT="9001"
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. Permission Denied

```bash
Error: This script must be run as root or with sudo.
```

**Solution**: Run with `sudo ./create-template.sh`

#### 2. VM ID Already Exists

```bash
Error: VM ID 9000 is already in use.
```

**Solution**: Choose a different VM ID or remove existing VM

#### 3. Storage Not Found

```bash
Error: Storage 'local-lvm' not found or not available.
```

**Solution**: Check available storages with `pvesm status`

#### 4. Network Bridge Not Found

```bash
Warning: Network bridge 'vmbr0' not found.
```

**Solution**: Check available bridges with `ip link show` or create bridge

#### 5. Image Download Failed

```bash
Error: Failed to download image from URL
```

**Solution**: Check internet connectivity and image URL validity

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Add debug flag to script
set -x  # Enable debug mode
set +x  # Disable debug mode
```

### Log Files

Check Proxmox logs for additional information:

- `/var/log/pve/tasks/` - Task logs
- `/var/log/syslog` - System logs
- `/tmp/proxmox-template-*/` - Temporary files (during creation)

## 📁 File Structure

```
~/.proxmox-templates/          # Configuration directory
├── ubuntu-22.04-20241201.conf # Exported configurations
├── template-queue-*.conf      # Batch configurations
└── ...

/var/lib/vz/snippets/          # Cloud-init snippets
├── user-data-9000             # VM-specific user data
└── ...

/opt/ansible/                  # Ansible integration (if enabled)
├── inventory/
│   └── proxmox.yml           # Dynamic inventory
├── playbooks/
│   ├── system-hardening.yml  # Security playbook
│   ├── install-docker.yml    # Docker installation
│   └── kubernetes-prep.yml   # Kubernetes preparation
└── roles/                    # Custom roles

./terraform-proxmox/          # Terraform integration (if enabled)
├── variables.tf              # Input variables
├── providers.tf              # Provider configuration
├── main.tf                   # Main configuration
├── outputs.tf                # Output definitions
└── README.md                 # Usage documentation
```

## 🔐 Security Considerations

### SSH Key Management

- Always use SSH key authentication
- Store private keys securely
- Use different keys for different environments

### Network Security

- Use VLANs to segment template networks
- Configure firewalls appropriately
- Limit template access during creation

### Template Security

- Keep templates updated with latest security patches
- Use minimal package installations
- Enable automatic security updates where appropriate

### Ansible Security

- Secure Ansible control node access
- Use Ansible Vault for sensitive data
- Limit playbook execution permissions

## 🚀 Advanced Usage

### Custom Package Lists

Create custom package configurations:

```bash
# Create custom package list
echo "docker.io kubectl helm terraform ansible" > my-packages.list

# Use in CLI mode
./create-template.sh --packages "$(cat my-packages.list)" --batch
```

### Integration with CI/CD

Use the script in automation pipelines:

```yaml
# GitHub Actions example
name: Create Proxmox Templates
on:
  schedule:
    - cron: "0 2 * * 0" # Weekly on Sunday at 2 AM

jobs:
  create-templates:
    runs-on: self-hosted
    steps:
      - name: Create Ubuntu Template
        run: |
          sudo ./create-template.sh \
            -d ubuntu -v 22.04 \
            -n "ubuntu-$(date +%Y%m%d)" \
            -i 9000 --batch
```

### Custom Distributions

Add support for additional distributions by modifying the `DISTRO_LIST` array:

```bash
DISTRO_LIST+=(
    "CustomLinux|1.0|http://custom.example.com/image.qcow2|qcow2|apt"
)
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Development Guidelines

- Follow existing code style
- Add appropriate comments
- Test with multiple distributions
- Update documentation

## 📄 License

This script is released under the MIT License. See LICENSE file for details.

## 🆘 Support

- **Issues**: Report bugs via GitHub Issues
- **Discussions**: Join community discussions
- **Documentation**: Check the project wiki
- **Email**: Contact maintainers directly

## 🔄 Changelog

### Version 2.0.0 (Current)

- Added support for 25+ distributions
- Implemented 80+ package categories
- Added Ansible integration
- Added Terraform integration
- Implemented batch processing
- Added configuration management
- Enhanced CLI interface
- Improved error handling

### Version 1.0.0

- Basic template creation
- Limited distribution support
- Simple configuration options

---

**Note**: This script is designed for Proxmox VE environments. Ensure you have proper backups and test in a non-production environment before using in production.
