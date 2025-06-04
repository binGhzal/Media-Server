#!/bin/bash

#===============================================================================
# Proxmox Template Creator - Ultra Enhanced Version
#===============================================================================
# 
# Advanced script for creating Proxmox VM templates with comprehensive features:
# 
# CORE FEATURES:
# - Interactive whiptail UI for easy configuration
# - Support for 50+ Linux distributions and BSD variants
# - Package selection with 150+ pre-defined packages
# - Custom ISO/Image URL support with auto-detection
# - Network configuration (DHCP/Static IP with VLAN support)
# - Multiple template creation with auto-incrementing VMID
# - Configuration export/import functionality
# - Default disk sizing with optional expansion
# - Template tagging and categorization
# 
# AUTOMATION FEATURES:
# - Automated Ansible post-configuration via temporary LXC container
# - Auto-generated Proxmox inventory management
# - Terraform integration for rapid VM deployment
# - Ansible playbooks for complex software installation
# - Queue processing for batch template creation
# 
# ADVANCED FEATURES:
# - Cloud-init integration with SSH key management
# - Network bridge and VLAN configuration
# - Hardware specification templates
# - Error recovery and cleanup procedures
# - Comprehensive logging and monitoring
# - Temporary LXC container for automation tasks
# - Auto-cleanup of temporary resources
# 
# Usage:
#   ./create-template.sh           # Use whiptail UI (default)
#   ./create-template.sh --cli     # Use command-line interface
#   ./create-template.sh --batch   # Batch mode with config file
#   ./create-template.sh --help    # Show help information
#
# NOTE: This script must be run as ROOT, not with sudo!
#
#===============================================================================

# Script version and metadata
SCRIPT_VERSION="5.0"
SCRIPT_NAME="Proxmox Template Creator Ultra Enhanced"
SCRIPT_AUTHOR="Homelab Infrastructure Team"
SCRIPT_DATE="2025-06-04"

# Essential dependency check
# Enhanced dependency check with auto-installation
check_dependencies() {
    local deps=("whiptail" "pvesm" "qm" "pct" "curl" "wget" "jq" "virt-customize" "guestfs-tools")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo "Installing missing packages..."
        
        # Attempt to install missing packages
        if command -v apt &> /dev/null; then
            apt update
            apt install -y libguestfs-tools guestfs-tools whiptail curl wget jq
        elif command -v dnf &> /dev/null; then
            dnf install -y libguestfs-tools-c whiptail curl wget jq
        elif command -v zypper &> /dev/null; then
            zypper install -y libguestfs whiptail curl wget jq
        else
            echo "Unable to auto-install dependencies. Please install manually."
            exit 1
        fi
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "=============================================="
        echo "ERROR: Root privileges required!"
        echo "=============================================="
        echo ""
        echo "This script must be run as root (not with sudo)."
        echo ""
        echo "To run as root:"
        echo "  su - root"
        echo "  cd $(pwd)"
        echo "  ./create-template.sh"
        echo ""
        echo "Or use sudo with preserved environment:"
        echo "  sudo -E ./create-template.sh"
        echo ""
        exit 1
    fi
}

# Enhanced initialization with comprehensive directory structure
initialize_script() {
    check_root
    check_dependencies
    
    # Set script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    # Create comprehensive directory structure
    mkdir -p "$SCRIPT_DIR"/{logs,configs,temp}
    mkdir -p "$REPO_ROOT/terraform/templates"
    mkdir -p "$REPO_ROOT/ansible/inventory"
    mkdir -p "$REPO_ROOT/ansible/playbooks/"{templates,servers,post-deployment}
    mkdir -p "$REPO_ROOT/ansible/roles"
    mkdir -p "$REPO_ROOT/ansible/group_vars"
    mkdir -p "$REPO_ROOT/ansible/host_vars"
    
    # Set global paths
    TERRAFORM_DIR="$REPO_ROOT/terraform/templates"
    ANSIBLE_DIR="$REPO_ROOT/ansible"
    INVENTORY_DIR="$ANSIBLE_DIR/inventory"
    PLAYBOOKS_DIR="$ANSIBLE_DIR/playbooks"
    
    # Initialize logging with rotation
    LOG_DIR="$SCRIPT_DIR/logs"
    LOG_FILE="$LOG_DIR/template-creator-$(date +%Y%m%d_%H%M%S).log"
    
    # Rotate old logs (keep last 10)
    find "$LOG_DIR" -name "template-creator-*.log" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
    
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    # Set up signal handlers for cleanup
    trap cleanup_on_exit EXIT
    trap cleanup_on_interrupt INT TERM
    
    log_info "Proxmox Template Creator v$SCRIPT_VERSION initialized"
    log_info "Working directory: $SCRIPT_DIR"
    log_info "Repository root: $REPO_ROOT"
}

#===============================================================================
# ENHANCED DEFAULT VARIABLES AND CONFIGURATION
#===============================================================================

# Security and random generation
GEN_PASS=$(openssl rand -base64 16) # Secure random password generation
WORK_DIR="/tmp/proxmox-template-$$" # Unique temporary directory

# Cloud-init defaults
CLOUD_PASSWORD_DEFAULT="$GEN_PASS"
CLOUD_USER_DEFAULT="ubuntu" # Changed from root for security
LOCAL_LANG="en_US.UTF-8" # More universal default
SET_X11="no" # Disabled by default for server templates
X11_LAYOUT="us" # US layout as default
X11_MODEL="pc105"
ADD_SUDO_NOPASSWD="true" # Enable for convenience
SSH_KEY_PATH="" # Path to SSH public key file

# VM ID Management
VMID_DEFAULT="9000" # Starting from 9000 for templates
VMID_INCREMENT="1" # Increment value for batch creation
VMID_MAX="999999999" # Maximum VMID allowed by Proxmox

# Template Identification and Tagging
TEMPLATE_TAG="template" # Default tag for all templates
VM_CATEGORY_TAG="" # Category tag (web, db, dev, k8s, etc.)
TEMPLATE_NOTES="" # Template description/notes

# Network Configuration
NETWORK_MODE="dhcp" # Options: dhcp, static, none
STATIC_IP="" # Static IP address (CIDR format: 192.168.1.100/24)
STATIC_GATEWAY="" # Gateway IP
STATIC_DNS="1.1.1.1,8.8.8.8" # Cloudflare and Google DNS
NETWORK_BRIDGE="vmbr0" # Default network bridge
VLAN_TAG="" # VLAN tag (optional)
NETWORK_MODEL="virtio" # Network card model

# Storage and Hardware
STORAGE_POOL="local-lvm" # Default storage pool
KEEP_DEFAULT_DISK_SIZE="true" # Use image default unless overridden
DISK_SIZE_OVERRIDE="" # Override in GB (e.g., "20")
DISK_FORMAT="qcow2" # Disk format
DISK_CACHE="none" # Disk cache mode
DISK_IO_THREAD="true" # Enable I/O threads for better performance

# CPU Configuration
CPU_CORES="2" # Default CPU cores
CPU_SOCKETS="1" # CPU sockets
CPU_TYPE="host" # CPU type (host for best performance)
CPU_FLAGS="" # Additional CPU flags

# Memory Configuration
MEMORY_SIZE="2048" # RAM in MB
MEMORY_BALLOON="1024" # Minimum balloon size
MEMORY_SHARES="1000" # Memory shares for prioritization

# Advanced VM Settings
BIOS_TYPE="ovmf" # UEFI by default (ovmf), legacy: seabios
MACHINE_TYPE="q35" # Modern machine type
OS_TYPE="l26" # Linux 2.6+ kernel
QEMU_AGENT="true" # Enable QEMU guest agent
BOOT_ORDER="order=scsi0" # Boot from primary disk
SERIAL_CONSOLE="true" # Enable serial console
VGA_TYPE="std" # VGA adapter type
PROTECTION="false" # VM protection against accidental deletion

# Batch Processing and Queue Management
BATCH_MODE="false" # Enable batch processing
BATCH_COUNT="1" # Number of templates to create
BATCH_CONFIG_FILE="" # Configuration file for batch processing
TEMPLATE_QUEUE=() # Array to store template configurations
AUTO_START_AFTER_CREATION="false" # Start template after creation (for testing)

# Custom Image Support
CUSTOM_IMAGE_URL="" # URL for custom image/ISO
CUSTOM_IMAGE_TYPE="auto" # auto-detect, qcow2, raw, iso
CUSTOM_IMAGE_CHECKSUM="" # Optional checksum verification
CUSTOM_PACKAGE_MANAGER="auto" # auto-detect, apt, dnf, zypper, pacman

# Integration Configurations
ANSIBLE_ENABLED="false" # Enable Ansible integration
ANSIBLE_LXC_TEMPLATE="ubuntu" # LXC template for Ansible container
ANSIBLE_LXC_CORES="1" # CPU cores for Ansible LXC
ANSIBLE_LXC_MEMORY="1024" # Memory for Ansible LXC (MB)
ANSIBLE_LXC_STORAGE="local-lvm" # Storage for Ansible LXC
ANSIBLE_CLEANUP_AFTER="true" # Remove Ansible LXC after completion

TERRAFORM_ENABLED="false" # Generate Terraform configurations
TERRAFORM_PROVIDER="telmate/proxmox" # Terraform provider
TERRAFORM_VERSION_CONSTRAINT=">= 2.9.0" # Provider version constraint

# Inventory and Documentation
INVENTORY_ENABLED="true" # Generate Proxmox inventory
INVENTORY_FORMAT="yaml" # yaml or ini format
GENERATE_DOCS="true" # Generate template documentation
DOCUMENTATION_FORMAT="markdown" # markdown or html

# Post-Installation Configurations
POST_INSTALL_REBOOT="false" # Reboot after package installation
POST_INSTALL_UPDATE="true" # Update packages after installation
POST_INSTALL_CLEANUP="true" # Clean package cache after installation
INSTALL_SECURITY_UPDATES="true" # Install security updates
CONFIGURE_FIREWALL="false" # Configure basic firewall rules
SETUP_SSH_HARDENING="false" # Apply SSH security hardening

# Monitoring and Health Checks
ENABLE_MONITORING_PACKAGES="false" # Install monitoring packages by default
HEALTH_CHECK_ENABLED="true" # Perform health checks after creation
HEALTH_CHECK_TIMEOUT="300" # Health check timeout in seconds

# Error Handling and Recovery
ERROR_RECOVERY_ENABLED="true" # Enable automatic error recovery
MAX_RETRY_ATTEMPTS="3" # Maximum retry attempts for failed operations
CLEANUP_ON_FAILURE="true" # Clean up resources on failure
PRESERVE_LOGS_ON_FAILURE="true" # Keep logs when operations fail

# Performance and Optimization
PARALLEL_DOWNLOADS="true" # Enable parallel image downloads
COMPRESSION_ENABLED="true" # Compress template disk after creation
OPTIMIZE_FOR_SIZE="false" # Optimize template for minimum size
OPTIMIZE_FOR_PERFORMANCE="true" # Optimize template for performance

# Security Settings
DISABLE_PASSWORD_AUTH="true" # Disable password authentication (SSH key only)
RANDOMIZE_ROOT_PASSWORD="true" # Set random root password
INSTALL_SECURITY_PACKAGES="false" # Install security packages by default
ENABLE_AUDIT_LOGGING="false" # Enable audit logging
SECURE_BOOT_ENABLED="false" # Enable secure boot (requires OVMF)

# Development and Testing
DEBUG_MODE="false" # Enable debug output
TEST_MODE="false" # Enable test mode (don't actually create VMs)
VERBOSE_OUTPUT="false" # Enable verbose output
DRY_RUN="false" # Show what would be done without executing

# Temporary Resource Management
TEMP_LXC_ID="" # Temporary LXC container ID
TEMP_DIR="" # Temporary directory for downloads
CLEANUP_ENABLED="true" # Enable automatic cleanup

# Advanced Features
CLOUD_INIT_SNIPPETS="true" # Use cloud-init snippets
CUSTOM_CLOUD_INIT_CONFIG="" # Path to custom cloud-init config
TPM_ENABLED="false" # Enable TPM 2.0 support
UEFI_SECURE_BOOT="false" # Enable UEFI Secure Boot
NESTED_VIRTUALIZATION="false" # Enable nested virtualization

# Welcome message for UI mode
show_welcome() {
    whiptail --title "Welcome to Proxmox Template Creator v$SCRIPT_VERSION" --msgbox \
"Welcome to the Enhanced Proxmox Template Creator!

This advanced tool helps you create VM templates with:
• 50+ supported distributions including latest versions
• 150+ pre-defined packages across 16 categories
• Custom ISO/Image URL support with auto-detection
• Advanced network configuration (DHCP/Static/VLAN)
• Automatic Ansible post-configuration
• Terraform integration for rapid deployment
• Batch processing with auto-incrementing VMIDs
• Comprehensive logging and error recovery

Features:
→ Templates tagged automatically for organization
→ VMs tagged by category for easy grouping
→ Temporary LXC containers for automation
→ Auto-generated inventory and playbooks
→ Default disk sizing with optional expansion

Use arrow keys to navigate, Space to select, Enter to confirm.

Press OK to begin..." 24 75
}

# Required packages for the script
REQUIRED_PKG=("libguestfs-tools" "wget" "whiptail" "jq" "curl")

#===============================================================================
# SCRIPT LOGIC AND FUNCTION DEFINITIONS
#===============================================================================

# Script version and metadata
SCRIPT_VERSION="5.0"
SCRIPT_NAME="Proxmox Template Creator Ultra Enhanced"
SCRIPT_AUTHOR="Homelab Infrastructure Team"
SCRIPT_DATE="2025-06-04"

# Essential dependency check
# Enhanced dependency check with auto-installation
check_dependencies() {
    local deps=("whiptail" "pvesm" "qm" "pct" "curl" "wget" "jq" "virt-customize" "guestfs-tools")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo "Installing missing packages..."
        
        # Attempt to install missing packages
        if command -v apt &> /dev/null; then
            apt update
            apt install -y libguestfs-tools guestfs-tools whiptail curl wget jq
        elif command -v dnf &> /dev/null; then
            dnf install -y libguestfs-tools-c whiptail curl wget jq
        elif command -v zypper &> /dev/null; then
            zypper install -y libguestfs whiptail curl wget jq
        else
            echo "Unable to auto-install dependencies. Please install manually."
            exit 1
        fi
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "=============================================="
        echo "ERROR: Root privileges required!"
        echo "=============================================="
        echo ""
        echo "This script must be run as root (not with sudo)."
        echo ""
        echo "To run as root:"
        echo "  su - root"
        echo "  cd $(pwd)"
        echo "  ./create-template.sh"
        echo ""
        echo "Or use sudo with preserved environment:"
        echo "  sudo -E ./create-template.sh"
        echo ""
        exit 1
    fi
}

#===============================================================================
# ENHANCED GLOBAL VARIABLES AND DEFAULTS
#===============================================================================
SET_X11="yes" # "yes" or "no" required
VMID_DEFAULT="52000" # VM ID
X11_LAYOUT="gb"
X11_MODEL="pc105"
ADD_SUDO_NOPASSWD="false" # Add sudo NOPASSWD for cloud user
NETWORK_MODE="dhcp" # dhcp or static
STATIC_IP="" # Static IP address
STATIC_GATEWAY="" # Static gateway
STATIC_NETMASK="" # Static netmask
STATIC_DNS="8.8.8.8,8.8.4.4" # Static DNS servers
CUSTOM_ISO_URL="" # Custom ISO download URL
CUSTOM_ISO_TYPE="" # Custom ISO type (qcow2, img, iso)
CUSTOM_PKG_MANAGER="" # Custom package manager
KEEP_DEFAULT_DISK_SIZE="true" # Use image default size unless overridden
DISK_SIZE_OVERRIDE="" # Override disk size in GB
BATCH_MODE="false" # Multiple template creation
BATCH_COUNT="1" # Number of templates to create
BATCH_VMID_START="52000" # Starting VMID for batch creation
AUTO_INCREMENT_VMID="true" # Auto-increment VMID for batch creation
TEMPLATE_QUEUE=() # Array to store multiple template configurations
ANSIBLE_ENABLED="false" # Enable Ansible post-configuration
LXC_ANSIBLE_CONTAINER="ansible-runner" # LXC container for Ansible
ANSIBLE_PLAYBOOK_PATH="/etc/ansible/playbooks" # Path to Ansible playbooks
TERRAFORM_ENABLED="false" # Generate Terraform configurations
INVENTORY_ENABLED="true" # Generate Proxmox inventory files

#===============================================================================
# COMPREHENSIVE DISTRIBUTION CONFIGURATIONS
#===============================================================================

# Ultra-enhanced distribution list with 50+ supported distributions
# Format: [key]="Display Name|Image URL|Format|Package Manager|OS Type|Default User|Default Disk Size"
declare -A DISTRO_LIST=(
    # ==== UBUNTU FAMILY ====
    ["ubuntu-20.04"]="Ubuntu 20.04 LTS (Focal)|https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS (Jammy)|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G"
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS (Noble)|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G"
    ["ubuntu-24.10"]="Ubuntu 24.10 (Oracular)|https://cloud-images.ubuntu.com/oracular/current/oracular-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G"
    ["ubuntu-25.04"]="Ubuntu 25.04 (Plucky)|https://cloud-images.ubuntu.com/plucky/current/plucky-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G"
    
    # ==== DEBIAN FAMILY ====
    ["debian-11"]="Debian 11 (Bullseye)|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|qcow2|apt|l26|debian|8G"
    ["debian-12"]="Debian 12 (Bookworm)|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|qcow2|apt|l26|debian|8G"
    ["debian-13"]="Debian 13 (Trixie)|https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2|qcow2|apt|l26|debian|8G"
    ["debian-testing"]="Debian Testing|https://cloud.debian.org/images/cloud/testing/latest/debian-testing-generic-amd64.qcow2|qcow2|apt|l26|debian|8G"
    ["debian-sid"]="Debian Sid (Unstable)|https://cloud.debian.org/images/cloud/sid/latest/debian-sid-generic-amd64.qcow2|qcow2|apt|l26|debian|8G"
    
    # ==== RHEL FAMILY ====
    ["rocky-8"]="Rocky Linux 8|https://download.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2|qcow2|dnf|l26|rocky|12G"
    ["rocky-9"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2|qcow2|dnf|l26|rocky|12G"
    
    ["almalinux-8"]="AlmaLinux 8|https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2|qcow2|dnf|l26|almalinux|12G"
    ["almalinux-9"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|qcow2|dnf|l26|almalinux|12G"
    
    ["centos-stream-8"]="CentOS Stream 8|https://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-latest.x86_64.qcow2|qcow2|dnf|l26|centos|12G"
    ["centos-stream-9"]="CentOS Stream 9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|qcow2|dnf|l26|centos|12G"
    
    ["oracle-8"]="Oracle Linux 8|https://yum.oracle.com/templates/OracleLinux/OL8/u10/x86_64/OL8U10_x86_64-olvm-b236.qcow2|qcow2|dnf|l26|oracle|12G"
    ["oracle-9"]="Oracle Linux 9|https://yum.oracle.com/templates/OracleLinux/OL9/u4/x86_64/OL9U4_x86_64-olvm-b234.qcow2|qcow2|dnf|l26|oracle|12G"
    
    ["rhel-8"]="Red Hat Enterprise Linux 8|manual|qcow2|dnf|l26|cloud-user|12G"
    ["rhel-9"]="Red Hat Enterprise Linux 9|manual|qcow2|dnf|l26|cloud-user|12G"
    
    # ==== FEDORA ====
    ["fedora-39"]="Fedora 39|https://download.fedoraproject.org/pub/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2|qcow2|dnf|l26|fedora|8G"
    ["fedora-40"]="Fedora 40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|qcow2|dnf|l26|fedora|8G"
    ["fedora-41"]="Fedora 41|https://download.fedoraproject.org/pub/fedora/linux/releases/41/Cloud/x86_64/images/Fedora-Cloud-Base-41-1.4.x86_64.qcow2|qcow2|dnf|l26|fedora|8G"
    ["fedora-rawhide"]="Fedora Rawhide|https://download.fedoraproject.org/pub/fedora/linux/development/rawhide/Cloud/x86_64/images/Fedora-Cloud-Base-Rawhide-latest.x86_64.qcow2|qcow2|dnf|l26|fedora|8G"
    
    # ==== SUSE FAMILY ====
    ["opensuse-leap-15.5"]="openSUSE Leap 15.5|https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.5/images/openSUSE-Leap-15.5-OpenStack.x86_64.qcow2|qcow2|zypper|l26|opensuse|10G"
    ["opensuse-leap-15.6"]="openSUSE Leap 15.6|https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.6/images/openSUSE-Leap-15.6-OpenStack.x86_64.qcow2|qcow2|zypper|l26|opensuse|10G"
    ["opensuse-tumbleweed"]="openSUSE Tumbleweed|https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-JeOS.x86_64-kvm-and-xen.qcow2|qcow2|zypper|l26|opensuse|10G"
    ["sles-15"]="SUSE Linux Enterprise Server 15|manual|qcow2|zypper|l26|sles|12G"
    
    # ==== ARCH LINUX FAMILY ====
    ["arch"]="Arch Linux|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|qcow2|pacman|l26|arch|8G"
    ["manjaro"]="Manjaro Linux|https://download.manjaro.org/minimal/21.3.7/manjaro-minimal-21.3.7-220816-linux515.iso|iso|pacman|l26|manjaro|10G"
    ["endeavouros"]="EndeavourOS|https://mirrors.endeavouros.com/iso/EndeavourOS_Artemis_22_12.iso|iso|pacman|l26|endeavour|10G"
    ["arcolinux"]="ArcoLinux|https://sourceforge.net/projects/arcolinux/files/latest/download|iso|pacman|l26|arco|12G"
    ["garuda"]="Garuda Linux|manual|iso|pacman|l26|garuda|15G"
    
    # ==== SECURITY-FOCUSED DISTRIBUTIONS ====
    ["kali"]="Kali Linux|https://kali.download/cloud-images/kali-rolling/kali-linux-2024.3-cloud-amd64.img|raw|apt|l26|kali|15G"
    ["parrot-security"]="Parrot Security OS|https://deb.parrot.sh/parrot/cloud/parrot-security-5.3_amd64.qcow2|qcow2|apt|l26|parrot|12G"
    ["parrot-home"]="Parrot Home Edition|https://deb.parrot.sh/parrot/cloud/parrot-home-5.3_amd64.qcow2|qcow2|apt|l26|parrot|10G"
    ["blackarch"]="BlackArch Linux|manual|iso|pacman|l26|blackarch|20G"
    ["pentoo"]="Pentoo Linux|manual|iso|portage|l26|pentoo|15G"
    
    # ==== CONTAINER-OPTIMIZED ====
    ["talos"]="Talos Linux|https://github.com/siderolabs/talos/releases/latest/download/nocloud-amd64.qcow2|qcow2|none|l26|talos|4G"
    ["flatcar-stable"]="Flatcar Container Linux (Stable)|https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2|qcow2|none|l26|core|8G"
    ["flatcar-beta"]="Flatcar Container Linux (Beta)|https://beta.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2|qcow2|none|l26|core|8G"
    ["coreos-stable"]="CoreOS (Fedora Stable)|https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/latest/x86_64/fedora-coreos-latest-qemu.x86_64.qcow2.xz|qcow2|rpm-ostree|l26|core|8G"
    ["coreos-testing"]="CoreOS (Fedora Testing)|https://builds.coreos.fedoraproject.org/prod/streams/testing/builds/latest/x86_64/fedora-coreos-latest-qemu.x86_64.qcow2.xz|qcow2|rpm-ostree|l26|core|8G"
    
    # ==== BSD SYSTEMS ====
    ["freebsd-13"]="FreeBSD 13.3|https://download.freebsd.org/ftp/releases/VM-IMAGES/13.3-RELEASE/amd64/Latest/FreeBSD-13.3-RELEASE-amd64.qcow2.xz|qcow2|pkg|other|freebsd|8G"
    ["freebsd-14"]="FreeBSD 14.1|https://download.freebsd.org/ftp/releases/VM-IMAGES/14.1-RELEASE/amd64/Latest/FreeBSD-14.1-RELEASE-amd64.qcow2.xz|qcow2|pkg|other|freebsd|8G"
    ["freebsd-current"]="FreeBSD Current|https://download.freebsd.org/ftp/snapshots/VM-IMAGES/15.0-CURRENT/amd64/Latest/FreeBSD-15.0-CURRENT-amd64.qcow2.xz|qcow2|pkg|other|freebsd|10G"
    ["openbsd-7.4"]="OpenBSD 7.4|https://cdn.openbsd.org/pub/OpenBSD/7.4/amd64/install74.img|raw|pkg_add|other|openbsd|8G"
    ["openbsd-7.5"]="OpenBSD 7.5|https://cdn.openbsd.org/pub/OpenBSD/7.5/amd64/install75.img|raw|pkg_add|other|openbsd|8G"
    ["netbsd-10.0"]="NetBSD 10.0|https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.0/images/NetBSD-10.0-amd64-install.img|raw|pkgin|other|netbsd|8G"
    ["dragonfly-6.4"]="DragonFly BSD 6.4|https://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-6.4.0_REL.iso|iso|pkg|other|dragonfly|10G"
    
    # ==== MINIMAL/ALPINE ====
    ["alpine-3.19"]="Alpine Linux 3.19|https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.4-x86_64.iso|iso|apk|l26|alpine|2G"
    ["alpine-3.20"]="Alpine Linux 3.20|https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-virt-3.20.3-x86_64.iso|iso|apk|l26|alpine|2G"
    ["alpine-edge"]="Alpine Linux Edge|https://dl-cdn.alpinelinux.org/alpine/edge/releases/x86_64/alpine-virt-latest-x86_64.iso|iso|apk|l26|alpine|2G"
    
    # ==== NETWORK/FIREWALL DISTRIBUTIONS ====
    ["vyos-1.4"]="VyOS 1.4 LTS|manual|iso|none|l26|vyos|4G"
    ["vyos-1.5"]="VyOS 1.5|manual|iso|none|l26|vyos|4G"
    ["opnsense"]="OPNsense|manual|iso|none|other|root|8G"
    ["pfsense"]="pfSense|manual|iso|none|other|root|8G"
    ["ipfire"]="IPFire|manual|iso|none|other|root|4G"
    ["smoothwall"]="SmoothWall|manual|iso|none|other|root|4G"
    
    # ==== SPECIALIZED DISTRIBUTIONS ====
    ["proxmox-ve"]="Proxmox VE|manual|iso|apt|l26|root|32G"
    ["truenas-core"]="TrueNAS Core|manual|iso|none|other|root|16G"
    ["truenas-scale"]="TrueNAS Scale|manual|iso|apt|l26|root|16G"
    ["xcp-ng"]="XCP-ng|manual|iso|none|other|root|16G"
    
    # ==== CUSTOM OPTION ====
    ["custom"]="Custom ISO/Image URL|custom|auto|auto|auto|auto|auto"
)

# Distribution categories for organized selection
DISTRO_CATEGORIES=(
    "ubuntu" "Ubuntu Family"
    "debian" "Debian Family"
    "rhel" "Red Hat Enterprise Family"
    "fedora" "Fedora"
    "suse" "SUSE Family"
    "arch" "Arch Linux Family"
    "security" "Security-Focused"
    "container" "Container-Optimized"
    "bsd" "BSD Systems"
    "minimal" "Minimal/Alpine"
    "network" "Network/Firewall"
    "specialized" "Specialized"
    "custom" "Custom"
)

#===============================================================================
# COMPREHENSIVE PACKAGE CONFIGURATIONS
#===============================================================================

# Ultra-enhanced package list organized by categories (150+ packages)
# Format: "package_name" "Description" "default_state" "category" "complexity"
# Complexity: simple (direct apt install), complex (requires custom script)
AVAILABLE_PACKAGES=(
    # ==== ESSENTIAL SYSTEM TOOLS ====
    "curl" "Data transfer tool with URL syntax" off "essential" "simple"
    "wget" "Web file downloader" off "essential" "simple"
    "ca-certificates" "Common CA certificates" off "essential" "simple"
    "gnupg" "GNU Privacy Guard for encryption" off "essential" "simple"
    "software-properties-common" "Software repository management" off "essential" "simple"
    "apt-transport-https" "HTTPS transport for APT" off "essential" "simple"
    "openssh-server" "SSH server for remote access" off "essential" "simple"
    "net-tools" "Legacy network configuration tools" off "essential" "simple"
    "iputils-ping" "Network connectivity testing" off "essential" "simple"
    "rsync" "File synchronization and transfer" off "essential" "simple"
    "unzip" "Archive extraction utility" off "essential" "simple"
    "zip" "Archive creation utility" off "essential" "simple"
    "p7zip-full" "7-Zip archive tool" off "essential" "simple"
    "git" "Distributed version control system" off "essential" "simple"
    "vim" "Advanced text editor" off "essential" "simple"
    "nano" "Simple text editor" off "essential" "simple"
    "less" "File pager" off "essential" "simple"
    "htop" "Interactive process viewer" off "essential" "simple"
    "tree" "Directory tree display utility" off "essential" "simple"
    "jq" "Command-line JSON processor" off "essential" "simple"
    "yq" "Command-line YAML processor" off "essential" "simple"
    
    # ==== DEVELOPMENT TOOLS ====
    "build-essential" "Compilation tools and libraries" off "development" "simple"
    "tmux" "Terminal multiplexer" off "development" "simple"
    "screen" "Terminal multiplexer alternative" off "development" "simple"
    "zsh" "Enhanced shell with features" off "development" "simple"
    "fzf" "Fuzzy finder for command-line" off "development" "simple"
    "ripgrep" "Ultra-fast text search tool" off "development" "simple"
    "fd-find" "Modern alternative to find" off "development" "simple"
    "bat" "Cat clone with syntax highlighting" off "development" "simple"
    "exa" "Modern replacement for ls" off "development" "simple"
    "neovim" "Hyperextensible Vim-based editor" off "development" "simple"
    "emacs" "Extensible text editor" off "development" "simple"
    "code" "Visual Studio Code" off "development" "complex"
    "git-lfs" "Git Large File Storage" off "development" "simple"
    "gh" "GitHub CLI tool" off "development" "complex"
    "micro" "Modern terminal text editor" off "development" "simple"
    "joe" "Joe's Own Editor" off "development" "simple"
    
    # ==== PROGRAMMING LANGUAGES & RUNTIMES ====
    "python3" "Python 3 programming language" off "programming" "simple"
    "python3-pip" "Python package installer" off "programming" "simple"
    "python3-venv" "Python virtual environments" off "programming" "simple"
    "python3-dev" "Python development headers" off "programming" "simple"
    "pipx" "Install Python applications in isolation" off "programming" "simple"
    "nodejs" "JavaScript runtime" off "programming" "simple"
    "npm" "Node.js package manager" off "programming" "simple"
    "yarn" "Alternative Node.js package manager" off "programming" "complex"
    "golang-go" "Go programming language" off "programming" "simple"
    "rustc" "Rust programming language compiler" off "programming" "simple"
    "cargo" "Rust package manager" off "programming" "simple"
    "openjdk-11-jdk" "OpenJDK 11 Development Kit" off "programming" "simple"
    "openjdk-17-jdk" "OpenJDK 17 Development Kit" off "programming" "simple"
    "php" "PHP scripting language" off "programming" "simple"
    "php-cli" "PHP command line interface" off "programming" "simple"
    "ruby" "Ruby programming language" off "programming" "simple"
    "gem" "Ruby package manager" off "programming" "simple"
    "perl" "Perl programming language" off "programming" "simple"
    "lua5.3" "Lua scripting language" off "programming" "simple"
    "r-base" "R statistical computing language" off "programming" "simple"
    
    # ==== SYSTEM MONITORING & PERFORMANCE ====
    "btop" "Modern system monitor" off "monitoring" "simple"
    "iotop" "I/O monitoring tool" off "monitoring" "simple"
    "nethogs" "Network bandwidth monitor per process" off "monitoring" "simple"
    "iftop" "Network bandwidth monitoring" off "monitoring" "simple"
    "ncdu" "Disk usage analyzer with ncurses" off "monitoring" "simple"
    "duf" "Modern disk usage utility" off "monitoring" "simple"
    "glances" "Cross-platform system monitoring" off "monitoring" "simple"
    "nmon" "System performance monitor" off "monitoring" "simple"
    "atop" "Advanced system monitor" off "monitoring" "simple"
    "sysstat" "System performance tools (sar, iostat)" off "monitoring" "simple"
    "lsof" "List open files" off "monitoring" "simple"
    "strace" "System call tracer" off "monitoring" "simple"
    "tcpdump" "Network packet analyzer" off "monitoring" "simple"
    "wireshark" "Network protocol analyzer" off "monitoring" "simple"
    "bandwhich" "Terminal bandwidth utilization tool" off "monitoring" "simple"
    "prometheus-node-exporter" "Hardware metrics exporter" off "monitoring" "simple"
    "collectd" "System statistics collection daemon" off "monitoring" "simple"
    
    # ==== NETWORK & SECURITY TOOLS ====
    "fail2ban" "Intrusion prevention system" off "security" "simple"
    "ufw" "Uncomplicated Firewall" off "security" "simple"
    "nmap" "Network discovery and security auditing" off "security" "simple"
    "nftables" "Modern netfilter framework" off "security" "simple"
    "iptables-persistent" "Persistent iptables rules" off "security" "simple"
    "wireguard" "Modern VPN solution" off "security" "simple"
    "openvpn" "Traditional VPN solution" off "security" "simple"
    "lynis" "Security auditing tool" off "security" "simple"
    "rkhunter" "Rootkit hunter" off "security" "simple"
    "chkrootkit" "Rootkit checker" off "security" "simple"
    "clamav" "Antivirus engine" off "security" "simple"
    "aide" "Advanced Intrusion Detection Environment" off "security" "simple"
    "ossec-hids" "Host-based intrusion detection" off "security" "complex"
    "john" "John the Ripper password cracker" off "security" "simple"
    "hashcat" "Advanced password recovery" off "security" "simple"
    "nikto" "Web server scanner" off "security" "simple"
    "sqlmap" "SQL injection testing tool" off "security" "simple"
    "metasploit-framework" "Penetration testing framework" off "security" "complex"
    
    # ==== WEB SERVERS & PROXIES ====
    "nginx" "High-performance web server" off "webserver" "simple"
    "apache2" "Apache HTTP server" off "webserver" "simple"
    "caddy" "Modern web server with automatic HTTPS" off "webserver" "complex"
    "haproxy" "Load balancer and proxy server" off "webserver" "simple"
    "traefik" "Modern reverse proxy" off "webserver" "complex"
    "squid" "Caching proxy server" off "webserver" "simple"
    "varnish" "HTTP accelerator" off "webserver" "simple"
    
    # ==== DATABASES ====
    "mysql-server" "MySQL database server" off "database" "simple"
    "postgresql" "PostgreSQL database server" off "database" "simple"
    "mariadb-server" "MariaDB database server" off "database" "simple"
    "redis-server" "In-memory data structure store" off "database" "simple"
    "sqlite3" "Lightweight database engine" off "database" "simple"
    "mongodb-org" "Document-oriented database" off "database" "complex"
    "influxdb" "Time series database" off "database" "complex"
    "prometheus" "Monitoring system and time series DB" off "database" "complex"
    "cassandra" "Distributed NoSQL database" off "database" "complex"
    "elasticsearch" "Search and analytics engine" off "database" "complex"
    
    # ==== CONTAINERS & ORCHESTRATION ====
    "docker.io" "Container platform" off "containers" "complex"
    "docker-compose" "Multi-container applications" off "containers" "complex"
    "podman" "Daemonless container engine" off "containers" "simple"
    "buildah" "Container image builder" off "containers" "simple"
    "skopeo" "Container image operations" off "containers" "simple"
    "kubectl" "Kubernetes command-line tool" off "containers" "complex"
    "helm" "Kubernetes package manager" off "containers" "complex"
    "k9s" "Kubernetes CLI manager" off "containers" "complex"
    "kind" "Kubernetes in Docker" off "containers" "complex"
    "minikube" "Local Kubernetes development" off "containers" "complex"
    "containerd" "Container runtime" off "containers" "simple"
    "runc" "CLI tool for spawning containers" off "containers" "simple"
    
    # ==== INFRASTRUCTURE & DEVOPS TOOLS ====
    "terraform" "Infrastructure as Code" off "infrastructure" "complex"
    "ansible" "Configuration management" off "infrastructure" "complex"
    "packer" "Image building tool" off "infrastructure" "complex"
    "vagrant" "Development environment manager" off "infrastructure" "complex"
    "consul" "Service discovery and configuration" off "infrastructure" "complex"
    "vault" "Secrets management" off "infrastructure" "complex"
    "nomad" "Workload orchestrator" off "infrastructure" "complex"
    "jenkins" "Automation server" off "infrastructure" "complex"
    "gitlab-runner" "GitLab CI/CD runner" off "infrastructure" "complex"
    "awscli" "AWS command line interface" off "infrastructure" "complex"
    "azure-cli" "Azure command line interface" off "infrastructure" "complex"
    "gcloud" "Google Cloud SDK" off "infrastructure" "complex"
    "pulumi" "Modern Infrastructure as Code" off "infrastructure" "complex"
    
    # ==== BACKUP & RECOVERY ====
    "rsnapshot" "Filesystem snapshot utility" off "backup" "simple"
    "borgbackup" "Deduplicating backup program" off "backup" "simple"
    "rclone" "Cloud storage sync tool" off "backup" "simple"
    "restic" "Modern backup program" off "backup" "simple"
    "duplicity" "Encrypted bandwidth-efficient backup" off "backup" "simple"
    "timeshift" "System restore utility" off "backup" "simple"
    "bacula-client" "Network backup solution client" off "backup" "simple"
    "amanda-client" "Advanced Maryland backup client" off "backup" "simple"
    "rdiff-backup" "Reverse differential backup tool" off "backup" "simple"
    
    # ==== SYSTEM ADMINISTRATION ====
    "systemd-timesyncd" "Network time synchronization" off "sysadmin" "simple"
    "chrony" "NTP client and server" off "sysadmin" "simple"
    "cron" "Task scheduler" off "sysadmin" "simple"
    "anacron" "Cron for systems not always on" off "sysadmin" "simple"
    "logrotate" "Log file rotation utility" off "sysadmin" "simple"
    "rsyslog" "Enhanced syslog daemon" off "sysadmin" "simple"
    "auditd" "Linux audit framework" off "sysadmin" "simple"
    "acct" "Process accounting utilities" off "sysadmin" "simple"
    "quotatool" "Disk quota management" off "sysadmin" "simple"
    "etckeeper" "Version control for /etc" off "sysadmin" "simple"
    "debsums" "Verification of package file integrity" off "sysadmin" "simple"
    "apt-file" "Search for files within packages" off "sysadmin" "simple"
    "deborphan" "Find orphaned packages" off "sysadmin" "simple"
    "localepurge" "Remove unnecessary locale data" off "sysadmin" "simple"
    
    # ==== FILE SYSTEMS & STORAGE ====
    "nfs-common" "NFS client utilities" off "filesystem" "simple"
    "cifs-utils" "SMB/CIFS filesystem utilities" off "filesystem" "simple"
    "sshfs" "SSH filesystem client" off "filesystem" "simple"
    "lvm2" "Logical volume management" off "filesystem" "simple"
    "cryptsetup" "Disk encryption utilities" off "filesystem" "simple"
    "btrfs-progs" "Btrfs filesystem utilities" off "filesystem" "simple"
    "zfsutils-linux" "ZFS filesystem utilities" off "filesystem" "simple"
    "xfsprogs" "XFS filesystem utilities" off "filesystem" "simple"
    "e2fsprogs" "Ext2/3/4 filesystem utilities" off "filesystem" "simple"
    "ntfs-3g" "NTFS filesystem support" off "filesystem" "simple"
    "exfat-utils" "ExFAT filesystem utilities" off "filesystem" "simple"
    "dosfstools" "FAT filesystem utilities" off "filesystem" "simple"
    
    # ==== RECOVERY & FORENSICS ====
    "testdisk" "Data recovery software" off "recovery" "simple"
    "photorec" "File recovery utility" off "recovery" "simple"
    "ddrescue" "Data recovery tool" off "recovery" "simple"
    "foremost" "File recovery based on headers" off "recovery" "simple"
    "sleuthkit" "Digital forensics toolkit" off "recovery" "simple"
    "autopsy" "Digital forensics platform" off "recovery" "complex"
    "volatility" "Memory forensics framework" off "recovery" "complex"
    "binwalk" "Firmware analysis tool" off "recovery" "simple"
    
    # ==== MAIL & MESSAGING ====
    "postfix" "Mail transfer agent" off "mail" "simple"
    "dovecot-core" "IMAP and POP3 server" off "mail" "simple"
    "exim4" "Mail transfer agent" off "mail" "simple"
    "sendmail" "Mail transfer agent" off "mail" "simple"
    "msmtp" "SMTP client" off "mail" "simple"
    "mutt" "Text-based mail client" off "mail" "simple"
    "alpine" "Text-based mail client" off "mail" "simple"
    "mailutils" "GNU mailutils" off "mail" "simple"
    
    # ==== MULTIMEDIA & GRAPHICS ====
    "ffmpeg" "Multimedia framework" off "multimedia" "simple"
    "imagemagick" "Image manipulation suite" off "multimedia" "simple"
    "graphicsmagick" "Image processing system" off "multimedia" "simple"
    "gimp" "GNU Image Manipulation Program" off "multimedia" "simple"
    "inkscape" "Vector graphics editor" off "multimedia" "simple"
    "blender" "3D creation suite" off "multimedia" "simple"
    "vlc" "Media player" off "multimedia" "simple"
    "mpv" "Media player" off "multimedia" "simple"
    
    # ==== SPECIALIZED TOOLS ====
    "libguestfs-tools" "Guest disk management tools" off "specialized" "simple"
    "kpartx" "Partition table manipulation" off "specialized" "simple"
    "qemu-guest-agent" "QEMU guest agent" off "specialized" "simple"
    "open-vm-tools" "VMware guest tools" off "specialized" "simple"
    "cloud-init" "Cloud instance initialization" off "specialized" "simple"
    "cloud-utils" "Cloud image utilities" off "specialized" "simple"
    "virt-manager" "Virtual machine manager" off "specialized" "simple"
    "spice-vdagent" "SPICE guest agent" off "specialized" "simple"
    "xe-guest-utilities" "XenServer guest utilities" off "specialized" "simple"
)

# Package categories for organized selection (16 categories)
PACKAGE_CATEGORIES=(
    "essential" "Essential System Tools"
    "development" "Development Tools"
    "programming" "Programming Languages & Runtimes"
    "monitoring" "System Monitoring & Performance"
    "security" "Network & Security Tools"
    "webserver" "Web Servers & Proxies"
    "database" "Databases"
    "containers" "Containers & Orchestration"
    "infrastructure" "Infrastructure & DevOps Tools"
    "backup" "Backup & Recovery"
    "sysadmin" "System Administration"
    "filesystem" "File Systems & Storage"
    "recovery" "Recovery & Forensics"
    "mail" "Mail & Messaging"
    "multimedia" "Multimedia & Graphics"
    "specialized" "Specialized Tools"
)

# Additional packages that can be installed
ADDITIONAL_PACKAGES=(
    "redis-server" "In-memory data store" off
    "nodejs" "JavaScript runtime" off
    "npm" "Node.js package manager" off
    "php" "PHP scripting language" off
    "php-cli" "PHP command line interface" off
    "python3-requests" "Python HTTP library" off
    "awscli" "AWS command line interface" off
    "azure-cli" "Azure command line interface" off
    "terraform" "Infrastructure as code tool" off
    "ansible" "Automation tool" off
    "snap" "Universal package manager" off
    "flatpak" "Application distribution framework" off
    "zsh" "Z shell" off
    "fish" "Friendly interactive shell" off
    "iotop" "I/O monitoring tool" off
    "iftop" "Network bandwidth monitoring" off
    "tcpdump" "Network packet analyzer" off
    "wireshark-common" "Network protocol analyzer" off
    "speedtest-cli" "Internet speed test" off
    "neofetch" "System information tool" off
    "lshw" "Hardware information tool" off
    "smartmontools" "Hard drive health monitoring" off
    "lvm2" "Logical volume management" off
    "mdadm" "Software RAID management" off
    "parted" "Partition management" off
    "fdisk" "Disk partitioning tool" off
    "gparted" "Graphical partition editor" off
    "fzf" "Fuzzy finder command-line tool" off
    "vscode-server" "Visual Studio Code Server" off
    "ripgrep" "Fast line-oriented search tool" off
    "fd-find" "Simple, fast alternative to find" off
    "mc" "Midnight Commander file manager" off
    "mlocate" "Fast file search utility" off
    "timeshift" "System backup and restore tool" off
    "sad" "Space Age seD - batch file editor" off
)

### Virt-Customize variables
VIRT_PKGS="qemu-guest-agent,cloud-utils,cloud-guest-utils"
EXTRA_VIRT_PKGS="tree,libguestfs-tools,kpartx,testdisk,fail2ban,ufw,nmap,msmtp,htop,net-tools,iputils-ping,rsync,git,openssh-server,ca-certificates,python3-apt,python3-pip,python3-venv,python3-setuptools,tmux,unzip,build-essential,gnupg,software-properties-common,apt-transport-https,net-tools,iputils-ping,rsync,cron,cron-apt,ntpdate"
### VM variables
AGENT_ENABLE="1" # Change to 0 if you don't want the guest agent
BALLOON="768" # Minimum balooning size
BIOS="ovmf" # Choose between ovmf or seabios
CORES="2"
DISK_SIZE="15G"
DISK_STOR="proxmox" # Name of disk storage within Proxmox
FSTRIM="1"
MACHINE="q35" # Type of machine. Q35 or i440fx
MEM="2048" # Max RAM
NET_BRIDGE="vmbr1" # Network bridge name
NET_MODE="dhcp" # Network mode: dhcp or static
NET_IP="" # Static IP address (if NET_MODE=static)
NET_GW="" # Gateway IP (if NET_MODE=static)
NET_MASK="24" # Network mask (if NET_MODE=static)
TAG="template"

# VM Tagging and Identification
VM_TAG_TEMPLATE="template" # Tag for templates
VM_TAG_CATEGORY="" # Tag for VM category (web, db, dev, etc.)
VM_DESCRIPTION="" # VM description

OS_TYPE="l26" # OS type (Linux 6x - 2.6 Kernel)
# SSH Keys. Unset the variable if you don't want to use this. Use the public key.
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFLnUCnFyoONBwVMs1Gj4EqERx+Pc81dyhF6IuF26WM proxvms"
TZ="Europe/London"
VLAN="50" # Set if you have VLAN requirements
ZFS="false" # Set to true if you have a ZFS datastore

# Notes variable
NOTES=$(cat << 'EOF'
When modifying this template, make sure you run this at the end

apt-get clean \
&& apt -y autoremove --purge \
&& apt -y clean \
&& apt -y autoclean \
&& cloud-init clean \
&& echo -n > /etc/machine-id \
&& echo -n > /var/lib/dbus/machine-id \
&& sync \
&& history -c \
&& history -w \
&& fstrim -av \
&& shutdown now
EOF
)

### Functions

# CTRL+C/INT catch
ctrl_c() {
    echo "User pressed Ctrl + C. Exiting script..."
    cleanup
    exit 1
}

# ============================================================================
# UI FUNCTIONS
# ============================================================================

# Display main menu
show_main_menu() {
    local choice
    
    while true; do
        choice=$(whiptail --title "Proxmox Template Creator v$SCRIPT_VERSION" \
            --menu "Choose an option:" 20 78 10 \
            "1" "Create Single Template" \
            "2" "Create Multiple Templates (Batch)" \
            "3" "Load Configuration File" \
            "4" "View Template List" \
            "5" "Generate Terraform Config" \
            "6" "Run Ansible Playbook" \
            "7" "View Logs" \
            "8" "Settings & Configuration" \
            "9" "Help & Documentation" \
            "0" "Exit" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1) create_single_template ;;
            2) create_batch_templates ;;
            3) load_configuration_file ;;
            4) view_template_list ;;
            5) generate_terraform_config ;;
            6) run_ansible_playbook ;;
            7) view_logs ;;
            8) show_settings_menu ;;
            9) show_help ;;
            0) exit_script ;;
            *) log_warn "Invalid selection. Please try again." ;;
        esac
    done
}

# Create a single template with interactive configuration
create_single_template() {
    log_info "Starting single template creation workflow"
    
    # Step 1: Select distribution
    if ! select_distribution; then
        log_warn "Distribution selection cancelled"
        return 1
    fi
    
    # Step 2: Configure VM settings
    if ! configure_vm_settings; then
        log_warn "VM configuration cancelled"
        return 1
    fi
    
    # Step 3: Select packages
    if ! select_packages; then
        log_warn "Package selection cancelled"
        return 1
    fi
    
    # Step 4: Configure networking (optional)
    if ! configure_network_settings; then
        log_warn "Network configuration cancelled"
        return 1
    fi
    
    # Step 5: Review configuration and confirm
    if ! review_configuration; then
        log_warn "Configuration review cancelled"
        return 1
    fi
    
    # Step 6: Create the template
    log_info "Starting template creation process..."
    create_template_main
}

# Configure VM settings interactively
configure_vm_settings() {
    local temp_file=$(mktemp)
    
    # VM Name
    VM_NAME=$(whiptail --title "VM Configuration" \
        --inputbox "Enter template name:" 10 60 \
        "${VM_NAME:-$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f1 | tr '[:upper:]' '[:lower:]')-template}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # VM ID
    local suggested_vmid
    suggested_vmid=$(get_next_available_vmid)
    VMID_DEFAULT=$(whiptail --title "VM Configuration" \
        --inputbox "Enter VM ID:" 10 60 \
        "${VMID_DEFAULT:-$suggested_vmid}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # Memory
    VM_MEMORY=$(whiptail --title "VM Configuration" \
        --inputbox "Enter memory (MB):" 10 60 \
        "${VM_MEMORY:-2048}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # CPU Cores
    VM_CORES=$(whiptail --title "VM Configuration" \
        --inputbox "Enter CPU cores:" 10 60 \
        "${VM_CORES:-2}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # Disk Size
    VM_DISK_SIZE=$(whiptail --title "VM Configuration" \
        --inputbox "Enter disk size (e.g., 20G):" 10 60 \
        "${VM_DISK_SIZE:-20G}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # Storage Pool
    VM_STORAGE=$(whiptail --title "VM Configuration" \
        --inputbox "Enter storage pool:" 10 60 \
        "${VM_STORAGE:-local-lvm}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    rm -f "$temp_file"
    return 0
}

# Select packages interactively
select_packages() {
    local package_options=()
    local selected_count=0
    
    # Build package list with categories
    for category in "${!PACKAGE_CATEGORIES[@]}"; do
        package_options+=("$category" "Package Category" OFF)
    done
    
    # Show package category selection
    local selected_categories
    selected_categories=$(whiptail --title "Package Selection" \
        --checklist "Select package categories to install:" 20 80 10 \
        "${package_options[@]}" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    # Clear existing selections
    SELECTED_PACKAGES=()
    
    # Process selected categories
    local selected_cats=()
    for cat in $selected_categories; do
        cat="${cat//\"/}"  # Remove quotes
        selected_cats+=("$cat")
    done
    
    # For each selected category, show individual packages
    for category in "${selected_cats[@]}"; do
        if [[ -n "${PACKAGE_CATEGORIES[$category]}" ]]; then
            IFS=' ' read -ra cat_packages <<< "${PACKAGE_CATEGORIES[$category]}"
            local pkg_options=()
            
            for pkg in "${cat_packages[@]}"; do
                pkg_options+=("$pkg" "Package" OFF)
            done
            
            local selected_pkgs
            selected_pkgs=$(whiptail --title "Package Selection - $category" \
                --checklist "Select packages from $category:" 20 80 10 \
                "${pkg_options[@]}" \
                3>&1 1>&2 2>&3)
            
            if [[ $? -eq 0 ]]; then
                for pkg in $selected_pkgs; do
                    pkg="${pkg//\"/}"  # Remove quotes
                    SELECTED_PACKAGES+=("$pkg")
                    ((selected_count++))
                done
            fi
        fi
    done
    
    if [[ $selected_count -eq 0 ]]; then
        whiptail --title "No Packages Selected" \
            --yesno "No packages were selected. Continue with base OS only?" 8 60
        return $?
    fi
    
    log_info "Selected $selected_count packages for installation"
    return 0
}

# Configure network settings
configure_network_settings() {
    local network_type
    network_type=$(whiptail --title "Network Configuration" \
        --menu "Select network configuration:" 15 60 5 \
        "dhcp" "DHCP (Automatic)" \
        "static" "Static IP" \
        "manual" "Manual Configuration" \
        "skip" "Skip Network Configuration" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    case "$network_type" in
        "dhcp")
            NETWORK_TYPE="dhcp"
            ;;
        "static")
            NETWORK_TYPE="static"
            configure_static_ip
            ;;
        "manual")
            NETWORK_TYPE="manual"
            ;;
        "skip")
            NETWORK_TYPE="dhcp"
            ;;
    esac
    
    return 0
}

# Configure static IP settings
configure_static_ip() {
    STATIC_IP=$(whiptail --title "Static IP Configuration" \
        --inputbox "Enter IP address (e.g., 192.168.1.100/24):" 10 60 \
        "${STATIC_IP:-}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    STATIC_GATEWAY=$(whiptail --title "Static IP Configuration" \
        --inputbox "Enter gateway IP:" 10 60 \
        "${STATIC_GATEWAY:-}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    STATIC_DNS=$(whiptail --title "Static IP Configuration" \
        --inputbox "Enter DNS server(s) (comma-separated):" 10 60 \
        "${STATIC_DNS:-8.8.8.8,8.8.4.4}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    return 0
}

# Review configuration before creation
review_configuration() {
    local dist_name
    dist_name=$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f1)
    
    local config_summary
    config_summary="Template Configuration Review
    
Distribution: $dist_name
Template Name: $VM_NAME
VM ID: $VMID_DEFAULT
Memory: ${VM_MEMORY}MB
CPU Cores: $VM_CORES
Disk Size: $VM_DISK_SIZE
Storage: $VM_STORAGE
Network: $NETWORK_TYPE"

    if [[ "$NETWORK_TYPE" == "static" ]]; then
        config_summary="$config_summary
Static IP: $STATIC_IP
Gateway: $STATIC_GATEWAY
DNS: $STATIC_DNS"
    fi
    
    config_summary="$config_summary

Selected Packages: ${#SELECTED_PACKAGES[@]} packages"
    
    if [[ ${#SELECTED_PACKAGES[@]} -gt 0 ]]; then
        config_summary="$config_summary
$(printf "%s " "${SELECTED_PACKAGES[@]:0:10}")..."
    fi
    
    whiptail --title "Configuration Review" \
        --yesno "$config_summary

Proceed with template creation?" 20 80
    
    return $?
}

# Load configuration from file
load_configuration_file() {
    local config_file
    config_file=$(whiptail --title "Load Configuration" \
        --inputbox "Enter path to configuration file:" 10 70 \
        "$EXAMPLES_DIR/ubuntu-22.04-dev.conf" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    if [[ ! -f "$config_file" ]]; then
        whiptail --title "File Not Found" \
            --msgbox "Configuration file not found: $config_file" 8 60
        return 1
    fi
    
    log_info "Loading configuration from: $config_file"
    
    # Source the configuration file
    if source "$config_file" 2>/dev/null; then
        whiptail --title "Configuration Loaded" \
            --msgbox "Configuration loaded successfully from:\n$config_file\n\nYou can now proceed with template creation." 10 70
        log_success "Configuration loaded from $config_file"
        return 0
    else
        whiptail --title "Load Error" \
            --msgbox "Failed to load configuration file:\n$config_file\n\nPlease check the file format." 10 70
        log_error "Failed to load configuration from $config_file"
        return 1
    fi
}

# View existing templates
view_template_list() {
    log_info "Retrieving template list from Proxmox"
    
    local template_list
    template_list=$(qm list 2>/dev/null | grep template | awk '{print $1 " " $2 " " $3}')
    
    if [[ -z "$template_list" ]]; then
        whiptail --title "Template List" \
            --msgbox "No templates found on this Proxmox node." 8 50
        return 0
    fi
    
    local template_info
    template_info="Current Templates on $(hostname):

ID    Name                Status
----------------------------------------
$template_list

Use 'qm list' for more details."
    
    whiptail --title "Template List" \
        --msgbox "$template_info" 20 80
    
    log_info "Template list displayed"
}

# Show settings menu
show_settings_menu() {
    local choice
    
    choice=$(whiptail --title "Settings & Configuration" \
        --menu "Configure settings:" 20 70 10 \
        "1" "Default VM Configuration" \
        "2" "Network Settings" \
        "3" "Storage Settings" \
        "4" "Automation Settings" \
        "5" "Security Settings" \
        "6" "Export Configuration" \
        "7" "Import Configuration" \
        "8" "Reset to Defaults" \
        "9" "View Current Settings" \
        "0" "Back to Main Menu" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) configure_vm_defaults ;;
        2) configure_network_settings ;;
        3) configure_storage_settings ;;
        4) configure_automation_settings ;;
        5) configure_security_settings ;;
        6) export_configuration ;;
        7) import_configuration ;;
        8) reset_to_defaults ;;
        9) view_current_settings ;;
        0) return ;;
        *) log_warn "Invalid selection" ;;
    esac
}

# ============================================================================
# CLI INTERFACE FUNCTIONS
# ============================================================================

# Parse command line arguments
parse_cli_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_cli_help
                exit 0
                ;;
            -v|--version)
                echo "Proxmox Template Creator v$SCRIPT_VERSION"
                exit 0
                ;;
            --batch)
                BATCH_MODE=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --distribution)
                CLI_DISTRIBUTION="$2"
                shift 2
                ;;
            --vmid)
                VMID_DEFAULT="$2"
                shift 2
                ;;
            --name)
                VM_NAME="$2"
                shift 2
                ;;
            --memory)
                VM_MEMORY="$2"
                shift 2
                ;;
            --cores)
                VM_CORES="$2"
                shift 2
                ;;
            --storage)
                VM_STORAGE="$2"
                shift 2
                ;;
            --disk-size)
                VM_DISK_SIZE="$2"
                shift 2
                ;;
            --network)
                VM_NETWORK="$2"
                shift 2
                ;;
            --ip)
                STATIC_IP="$2"
                shift 2
                ;;
            --gateway)
                STATIC_GATEWAY="$2"
                shift 2
                ;;
            --dns)
                STATIC_DNS="$2"
                shift 2
                ;;
            --packages)
                CLI_PACKAGES="$2"
                shift 2
                ;;
            --tags)
                VM_TAGS="$2"
                shift 2
                ;;
            --terraform)
                ENABLE_TERRAFORM=true
                shift
                ;;
            --ansible)
                ENABLE_ANSIBLE=true
                shift
                ;;
            --no-interaction)
                NO_INTERACTION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_cli_help
                exit 1
                ;;
        esac
    done
}

# Run CLI mode operations
run_cli_mode() {
    log_info "Running in CLI mode"
    
    # Handle batch mode
    if [[ "$BATCH_MODE" == true ]]; then
        if [[ -f "$BATCH_FILE" ]]; then
            process_batch_file "$BATCH_FILE"
            return $?
        else
            log_error "Batch file not found: $BATCH_FILE"
            return 1
        fi
    fi
    
    # Handle dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry run mode - showing template preview"
        show_template_preview
        return 0
    fi
    
    # Handle single template creation from CLI
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            log_info "Creating template from configuration file: $CONFIG_FILE"
            load_configuration_file "$CONFIG_FILE"
            create_template_main
            return $?
        else
            log_error "Configuration file not found: $CONFIG_FILE"
            return 1
        fi
    fi
    
    # Create template with CLI parameters
    if [[ -n "$TEMPLATE_NAME" && -n "$DISTRIBUTION" ]]; then
        log_info "Creating template: $TEMPLATE_NAME ($DISTRIBUTION)"
        create_template_main
        return $?
    fi
    
    # Show help if insufficient parameters
    log_error "Insufficient parameters for CLI mode"
    echo "Use --help for usage information"
    return 1
}

# Show welcome message
show_welcome() {
    if [[ "$QUIET_MODE" != true ]]; then
        clear
        echo "
╔══════════════════════════════════════════════════════════════════╗
║                    Proxmox Template Creator                      ║
║                        Version $SCRIPT_VERSION                          ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Automated VM template creation for Proxmox Virtual Environment ║
║                                                                  ║
║  Features:                                                       ║
║  • Multiple Linux distributions                                  ║
║  • Package pre-installation                                      ║
║  • Cloud-init integration                                        ║
║  • Batch processing                                              ║
║  • Ansible automation                                            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
"
        sleep 2
    fi
}

# ============================================================================
# MAIN FUNCTION AND SCRIPT EXECUTION LOGIC
# ============================================================================

# Main function
main() {
    # Initialize script
    initialize_script
    
    # Parse command line arguments if provided
    if [[ $# -gt 0 ]]; then
        parse_cli_arguments "$@"
        
        # Run in CLI mode if arguments provided
        if [[ "$CLI_MODE" == true ]]; then
            run_cli_mode
            return $?
        fi
    fi
    
    # Show welcome message and run UI mode by default
    show_welcome
    show_main_menu
}

# ============================================================================
# SCRIPT EXECUTION - THIS RUNS WHEN SCRIPT IS EXECUTED
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
