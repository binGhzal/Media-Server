# Proxmox Template Creator

A comprehensive bash script for creating VM templates in Proxmox VE with advanced features including support for 50+ Linux distributions and BSDs, 150+ packages in 16 categories, Ansible and Terraform integration, queue/batch processing, and full automation.

## 🚀 Features

### Core Functionality

- **50+ Linux Distributions & BSD Support**: Ubuntu, Debian, CentOS, Rocky, AlmaLinux, RHEL, Fedora, openSUSE, Arch, Alpine, FreeBSD, OpenBSD, NetBSD, Oracle, Parrot, Talos, Flatcar, Bottlerocket, Gentoo, NixOS, and more
- **Comprehensive Package Management**: 150+ pre-defined packages in 16 categories
- **Cloud-init Integration**: Automated user creation, SSH key setup, and initial configuration
- **Advanced Networking**: Bridge config, VLAN tagging, static/DHCP/manual
- **Hardware Customization**: CPU, memory, disk, storage pool, UEFI/BIOS, QEMU agent
- **Batch/Queue Processing**: Create multiple templates in sequence or from config
- **Configuration Management**: Export/import template configs, dry-run preview
- **Robust Logging & Error Handling**: Full logs, recovery, and cleanup

### Advanced Integrations

- **Ansible Integration**:
  - Dedicated LXC control node
  - Dynamic inventory generation
  - Pre-built playbooks for system hardening, Docker, and Kubernetes
  - Post-creation automation
- **Terraform Integration**:
  - Complete configuration generation
  - Multi-VM support
  - Network automation
  - Usage documentation

### User Experience

- **Interactive GUI**: Whiptail-based interface for all options
- **CLI Mode**: Full command-line support for automation
- **Comprehensive Help System**: Built-in documentation and distro info

## 📋 Requirements

- **Proxmox VE**: Version 7.0 or later
- **OS**: Debian-based Proxmox host
- **Privileges**: Root or sudo access
- **Network**: Internet for image downloads
- **Storage**: Sufficient space for images
- **Dependencies**: whiptail, wget, curl, jq, qm, virt-customize, guestfs-tools

## 🗂️ Supported Distributions (Grouped by Family)

| Family/Key              | Versions/Variants                                                         | Package Manager    | Notes/Examples                     |
| ----------------------- | ------------------------------------------------------------------------- | ------------------ | ---------------------------------- |
| **Ubuntu**              | 20.04, 22.04, 24.04, 24.10, Minimal                                       | apt                | LTS, Minimal                       |
| **Debian**              | 11, 12, Testing                                                           | apt                | Stable, Rolling                    |
| **CentOS/RHEL/Clones**  | CentOS 7, 8, Stream 9; RHEL 8, 9; Rocky 8, 9; AlmaLinux 8, 9; Oracle 8, 9 | dnf/yum/apt        | RHEL, Rocky, Alma, Oracle          |
| **Fedora**              | 38, 39, 40                                                                | dnf                | Stable, Latest                     |
| **openSUSE**            | Leap 15.4, 15.5, Tumbleweed                                               | zypper             | Stable, Rolling                    |
| **Arch Linux**          | Latest, ARM                                                               | pacman             | Rolling, ARM                       |
| **Alpine Linux**        | 3.17, 3.18, 3.19, Edge                                                    | apk                | Minimal, Rolling                   |
| **BSD**                 | FreeBSD 13, 14; OpenBSD 7.3, 7.4; NetBSD 9, 10                            | pkg/pkg_add        | BSD, Security-focused              |
| **Security/DevOps**     | Kali Linux, Parrot OS, Talos Linux                                        | apt/-              | Security, Kubernetes OS            |
| **Cloud-Native**        | Flatcar, Bottlerocket                                                     | emerge/rpm-ostree  | Container/K8s OS                   |
| **Minimal/Lightweight** | TinyCore, SliTaz, Puppy Linux, Alpine                                     | tce/tazpkg/pet/apk | Ultra-minimal, Lightweight         |
| **Network/Firewall**    | OPNsense, pfSense, VyOS, RouterOS                                         | -/apt              | Firewall, Router, Network OS       |
| **Specialized/Rescue**  | Clear Linux, Rescuezilla, GParted Live                                    | swupd/apt          | Performance, Rescue, Partition     |
| **Void/Gentoo/NixOS**   | Void Linux, Gentoo, NixOS                                                 | xbps/emerge/nix    | Minimal, Source-based, Declarative |
| **Custom ISO/Image**    | User-supplied ISO/image                                                   | auto               | Any custom distro or version       |

## 📦 Distro Categories (with Examples)

- **Ubuntu Family**: Ubuntu 20.04, 22.04, 24.04, Minimal
- **Debian Family**: Debian 11, 12, Testing
- **Red Hat Enterprise Family**: CentOS, RHEL, Rocky, AlmaLinux, Oracle
- **Fedora**: Fedora 38, 39, 40
- **SUSE Family**: openSUSE Leap, Tumbleweed
- **Arch Linux Family**: Arch Linux, Arch ARM
- **Security-Focused**: Kali Linux, Parrot OS, OpenBSD
- **Container-Optimized**: Talos Linux, Flatcar, Bottlerocket
- **BSD Systems**: FreeBSD, OpenBSD, NetBSD
- **Minimal/Lightweight**: Alpine, TinyCore, SliTaz, Puppy Linux
- **Network/Firewall**: OPNsense, pfSense, VyOS, RouterOS
- **Specialized/Rescue**: Clear Linux, Rescuezilla, GParted Live
- **Custom ISO/Image**: Any user-supplied ISO or image (see below)

## 🆕 Custom ISO/Image Support

You can now select "Custom ISO/Image" in the distribution selection menu (UI or CLI) to use any ISO, QCOW2, RAW, or other supported image. The script will prompt for the URL or local path and image type. This allows you to:

- Deploy custom or less common distros
- Use your own pre-built images
- Test new or experimental OS releases

**How to use:**

- In the UI: Select "Custom ISO/Image" and follow the prompts
- In CLI: Use `--distribution custom-iso` and provide `--custom-image-url` and `--custom-image-type` as needed

## 🚀 Advanced Features (Recap)

- Batch/queue processing for multiple templates
- Ansible and Terraform integration
- Full configuration export/import
- Robust error handling and logging
- Category-based package selection (150+ packages)
- Custom ISO/image support for any distro

## 📦 Package Categories (150+ packages in 16 categories)

- **essential**: curl, wget, git, vim, nano, htop, tree, jq, yq, openssh-server, net-tools, rsync, unzip, zip, ca-certificates, gnupg, software-properties-common, apt-transport-https, etc.
- **development**: build-essential, tmux, screen, zsh, fzf, ripgrep, fd-find, bat, exa, neovim, emacs, code, gh, micro, joe, git-lfs
- **programming**: python3, python3-pip, python3-venv, nodejs, npm, yarn, golang-go, rustc, cargo, openjdk-11-jdk, openjdk-17-jdk, php, ruby, perl, lua5.3, r-base, etc.
- **monitoring**: btop, iotop, nethogs, iftop, ncdu, duf, glances, nmon, atop, sysstat, lsof, strace, tcpdump, wireshark, bandwhich, prometheus-node-exporter, collectd
- **security**: fail2ban, ufw, nmap, nftables, iptables-persistent, wireguard, openvpn, lynis, rkhunter, chkrootkit, clamav, aide, ossec-hids, john, hashcat, nikto, sqlmap, metasploit-framework
- **webserver**: nginx, apache2, caddy, haproxy, traefik, squid, varnish
- **database**: mysql-server, postgresql, mariadb-server, redis-server, sqlite3, mongodb-org, influxdb, prometheus, cassandra, elasticsearch
- **containers**: docker.io, docker-compose, podman, buildah, skopeo, kubectl, helm, k9s, kind, minikube, containerd, runc
- **infrastructure**: terraform, ansible, packer, vagrant, consul, vault, nomad, jenkins, gitlab-runner, awscli, azure-cli, gcloud, pulumi
- **backup**: rsnapshot, borgbackup, rclone, restic, duplicity, timeshift, bacula-client, amanda-client, rdiff-backup
- **sysadmin**: systemd-timesyncd, chrony, cron, anacron, logrotate, rsyslog, auditd, acct, quotatool, etckeeper, debsums, apt-file, deborphan, localepurge
- **filesystem**: nfs-common, cifs-utils, sshfs, lvm2, cryptsetup, btrfs-progs, zfsutils-linux, xfsprogs, e2fsprogs, ntfs-3g, exfat-utils, dosfstools
- **recovery**: testdisk, photorec, ddrescue, foremost, sleuthkit, autopsy, volatility, binwalk
- **mail**: postfix, dovecot-core, exim4, sendmail, msmtp, mutt, alpine, mailutils
- **multimedia**: ffmpeg, imagemagick, graphicsmagick, gimp, inkscape, blender, vlc, mpv
- **specialized**: libguestfs-tools, kpartx, qemu-guest-agent, open-vm-tools, cloud-init, cloud-utils, virt-manager, spice-vdagent, xe-guest-utilities

## 🔗 Ansible & 🏗️ Terraform Integration

### Features

- **Ansible Integration**:
  - Dedicated LXC control node
  - Dynamic inventory generation
  - Pre-built playbooks for system hardening, Docker, and Kubernetes
  - Post-creation automation
- **Terraform Integration**:
  - Complete configuration generation
  - Multi-VM support
  - Network automation
  - Usage documentation

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

- Added support for 50+ distributions
- Implemented 150+ package categories
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

**Note**: This script is designed for Proxmox VE environments. Test in non-production before use in production.

```bash
# Example code block with language specified
```
