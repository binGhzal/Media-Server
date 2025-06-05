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
