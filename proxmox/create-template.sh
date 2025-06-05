#!/bin/bash

#===============================================================================
# Proxmox Template Creator
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
# NOTE: This script must be run as ROOT!
# Direct root execution required for Proxmox operations and system configuration.
# 
# Run as: ./create-template.sh (when logged in as root)
# Do NOT use: sudo ./create-template.sh
#
#===============================================================================

# Script version and metadata
SCRIPT_VERSION="5.0"
SCRIPT_NAME="Proxmox Template Creator Ultra Enhanced"
SCRIPT_AUTHOR="binghzal"
SCRIPT_DATE="2025"

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
        echo "ERROR: This script must be run as root!"
        echo "Run: ./create-template.sh"
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
    mkdir -p "$REPO_ROOT/docker/templates"
    mkdir -p "$REPO_ROOT/kubernetes/templates"
    
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
# LOGGING FUNCTIONS
#===============================================================================

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG_FILE:-/tmp/template-creator.log}"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG_FILE:-/tmp/template-creator.log}" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG_FILE:-/tmp/template-creator.log}"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG_FILE:-/tmp/template-creator.log}"
}

log_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG_FILE:-/tmp/template-creator.log}"
    fi
}

# Cleanup functions
cleanup_on_exit() {
    log_info "Performing cleanup on exit"
    if [[ -n "$TEMP_LXC_ID" ]]; then
        pct stop "$TEMP_LXC_ID" 2>/dev/null || true
        pct destroy "$TEMP_LXC_ID" 2>/dev/null || true
    fi
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
}

cleanup_on_interrupt() {
    log_warn "Script interrupted, performing cleanup"
    cleanup_on_exit
    exit 130
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
        echo "ERROR: This script must be run as root!"
        echo "Run: ./create-template.sh"
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
# COMPREHENSIVE DISTRIBUTION CONFIGURATIONS (50+ DISTROS)
#===============================================================================
# Format: [key]="Display Name|Image URL|Format|Package Manager|OS Type|Default User|Default Disk Size|Notes"
declare -A DISTRO_LIST=(
    # ==== UBUNTU FAMILY ====
    ["ubuntu-20.04"]="Ubuntu 20.04 LTS (Focal)|https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G|LTS release"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS (Jammy)|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G|LTS release"
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS (Noble)|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G|LTS release"
    ["ubuntu-24.10"]="Ubuntu 24.10 (Oracular)|https://cloud-images.ubuntu.com/oracular/current/oracular-server-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|10G|Development"
    ["ubuntu-minimal"]="Ubuntu Minimal (Latest)|https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img|qcow2|apt|l26|ubuntu|5G|Minimal image"
    # ==== DEBIAN FAMILY ====
    ["debian-11"]="Debian 11 (Bullseye)|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|qcow2|apt|l26|debian|8G|Stable"
    ["debian-12"]="Debian 12 (Bookworm)|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|qcow2|apt|l26|debian|8G|Stable"
    ["debian-testing"]="Debian Testing|https://cloud.debian.org/images/cloud/testing/latest/debian-testing-generic-amd64.qcow2|qcow2|apt|l26|debian|8G|Rolling"
    # ==== CENTOS/REDHAT FAMILY ====
    ["centos-7"]="CentOS 7|https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2|qcow2|yum|l26|centos|8G|Legacy"
    ["centos-8"]="CentOS 8|https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud.qcow2|qcow2|dnf|l26|centos|8G|Legacy"
    ["centos-stream-9"]="CentOS Stream 9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|qcow2|dnf|l26|centos|8G|Rolling"
    ["rhel-8"]="Red Hat Enterprise Linux 8|https://access.redhat.com/downloads/content/479/ver=8.0/rhel---8.0-x86_64-kvm.qcow2|qcow2|dnf|l26|cloud-user|8G|Subscription required"
    ["rhel-9"]="Red Hat Enterprise Linux 9|https://access.redhat.com/downloads/content/479/ver=9.0/rhel---9.0-x86_64-kvm.qcow2|qcow2|dnf|l26|cloud-user|8G|Subscription required"
    ["rocky-8"]="Rocky Linux 8|https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud.latest.x86_64.qcow2|qcow2|dnf|l26|rocky|8G|RHEL rebuild"
    ["rocky-9"]="Rocky Linux 9|https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|qcow2|dnf|l26|rocky|8G|RHEL rebuild"
    ["almalinux-8"]="AlmaLinux 8|https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2|qcow2|dnf|l26|almalinux|8G|RHEL rebuild"
    ["almalinux-9"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|qcow2|dnf|l26|almalinux|8G|RHEL rebuild"
    ["oracle-8"]="Oracle Linux 8|https://yum.oracle.com/ISOS/OracleLinux/OL8/u8/x86_64/OracleLinux-R8-U8-x86_64-cloud.qcow2|qcow2|dnf|l26|oracle|8G|Enterprise"
    ["oracle-9"]="Oracle Linux 9|https://yum.oracle.com/ISOS/OracleLinux/OL9/u3/x86_64/OracleLinux-R9-U3-x86_64-cloud.qcow2|qcow2|dnf|l26|oracle|8G|Enterprise"
    # ==== FEDORA FAMILY ====
    ["fedora-38"]="Fedora 38|https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.qcow2|qcow2|dnf|l26|fedora|8G|Stable"
    ["fedora-39"]="Fedora 39|https://download.fedoraproject.org/pub/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2|qcow2|dnf|l26|fedora|8G|Stable"
    ["fedora-40"]="Fedora 40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.6.x86_64.qcow2|qcow2|dnf|l26|fedora|8G|Latest"
    # ==== SUSE FAMILY ====
    ["opensuse-leap-15.4"]="openSUSE Leap 15.4|https://download.opensuse.org/distribution/leap/15.4/appliances/openSUSE-Leap-15.4.x86_64-Cloud.qcow2|qcow2|zypper|l26|opensuse|8G|Stable"
    ["opensuse-leap-15.5"]="openSUSE Leap 15.5|https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5.x86_64-Cloud.qcow2|qcow2|zypper|l26|opensuse|8G|Stable"
    ["opensuse-tumbleweed"]="openSUSE Tumbleweed|https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed.x86_64-Cloud.qcow2|qcow2|zypper|l26|opensuse|8G|Rolling"
    # ==== ARCH FAMILY ====
    ["archlinux-latest"]="Arch Linux (Latest)|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|qcow2|pacman|l26|arch|8G|Rolling"
    # ==== ALPINE FAMILY ====
    ["alpine-3.17"]="Alpine Linux 3.17|https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86_64/alpine-standard-3.17.4-x86_64.iso|iso|apk|l26|alpine|2G|Minimal"
    ["alpine-3.18"]="Alpine Linux 3.18|https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-standard-3.18.4-x86_64.iso|iso|apk|l26|alpine|2G|Minimal"
    ["alpine-3.19"]="Alpine Linux 3.19|https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-standard-3.19.1-x86_64.iso|iso|apk|l26|alpine|2G|Minimal"
    # ==== BSD FAMILY ====
    ["freebsd-13"]="FreeBSD 13|https://download.freebsd.org/ftp/releases/VM-IMAGES/13.3-RELEASE/amd64/Latest/FreeBSD-13.3-RELEASE-amd64.qcow2.xz|qcow2|pkg|bsd|freebsd|8G|General purpose"
    ["freebsd-14"]="FreeBSD 14|https://download.freebsd.org/ftp/releases/VM-IMAGES/14.0-RELEASE/amd64/Latest/FreeBSD-14.0-RELEASE-amd64.qcow2.xz|qcow2|pkg|bsd|freebsd|8G|General purpose"
    ["openbsd-7.3"]="OpenBSD 7.3|https://cdn.openbsd.org/pub/OpenBSD/7.3/amd64/install73.img|raw|pkg_add|bsd|openbsd|8G|Security-focused"
    ["openbsd-7.4"]="OpenBSD 7.4|https://cdn.openbsd.org/pub/OpenBSD/7.4/amd64/install74.img|raw|pkg_add|bsd|openbsd|8G|Security-focused"
    ["netbsd-9"]="NetBSD 9|https://cdn.netbsd.org/pub/NetBSD/NetBSD-9.3/images/NetBSD-9.3-amd64.iso|iso|pkg_add|bsd|netbsd|8G|Portable"
    ["netbsd-10"]="NetBSD 10|https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.0/images/NetBSD-10.0-amd64.iso|iso|pkg_add|bsd|netbsd|8G|Portable"
    # ==== SECURITY/DEVOPS ====
    ["kali-linux"]="Kali Linux (Latest)|https://cdimage.kali.org/kali-2024.2/kali-linux-2024.2-cloud-amd64.qcow2|qcow2|apt|l26|kali|8G|Security testing"
    ["parrot-os"]="Parrot Security OS|https://download.parrot.sh/parrot/iso/5.3/Parrot-security-5.3_amd64.iso|iso|apt|l26|parrot|8G|Security testing"
    ["talos-linux"]="Talos Linux (K8s)|https://github.com/siderolabs/talos/releases/download/v1.7.2/metal-amd64.iso|iso|-|l26|talos|2G|Kubernetes OS"
    # ==== CLOUD-NATIVE ====
    ["flatcar"]="Flatcar Container Linux|https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2|raw|emerge|l26|core|4G|Cloud-native"
    ["bottlerocket"]="Bottlerocket OS|https://github.com/bottlerocket-os/bottlerocket/releases/download/v1.18.2/bottlerocket-vmware-k8s-1.18.2-x86_64-disk.img|raw|rpm-ostree|l26|ec2-user|4G|AWS K8s OS"
    # ==== NEW DISTRIBUTIONS ====
    ["void-linux"]="Void Linux (Stable)|https://alpha.de.repo.voidlinux.org/live/static/20240202/void-x86_64-musl-musl-ROOTFS-20240202.tar.xz|raw|xbps|l26|root|5G|Minimal rolling"
    ["nixos-24.05"]="NixOS 24.05|https://channels.nixos.org/nixos-24.05/latest-nixos-24.05.x86_64-linux.iso|iso|nixos|l26|nixos|8G|Declarative single-file ISO"
    ["gentoo-current"]="Gentoo Current|https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/current-stage3-amd64/stage3-amd64-*.tar.xz|tar.xz|emerge|l26|root|10G|Cutting-edge"
    ["amazonlinux-2"]="Amazon Linux 2|https://cdn.amazonlinux.com/os-images/2.x.x.x/amazon-linux-2-*-cloudimg-x86_64.img|raw|yum|l26|ec2-user|8G|AWS compatible"
    ["custom-iso"]="Custom ISO/Image|prompt|custom|auto|custom|custom|auto|User-supplied image or ISO"
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
    "minimal" "Minimal/Lightweight"
    "network" "Network/Firewall"
    "specialized" "Specialized/Rescue"
    "custom" "Custom ISO/Image"
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
    
    # Step 6: Select Ansible playbooks (if enabled)
    if [[ "$ANSIBLE_ENABLED" == true ]]; then
        select_ansible_playbooks_ui || return 1
        collect_ansible_vars_ui
    fi
    
    # Step 6b: Select Docker/Kubernetes templates (if present)
    if [[ -d "$REPO_ROOT/docker/templates" ]]; then
        select_docker_template_ui || log_warn "Docker template selection skipped"
    fi
    if [[ -d "$REPO_ROOT/kubernetes/templates" ]]; then
        select_k8s_template_ui || log_warn "Kubernetes template selection skipped"
    fi
    
    # Step 7: Select Terraform modules (if enabled)
    if [[ "$TERRAFORM_ENABLED" == true ]]; then
        select_terraform_modules_ui || return 1
        collect_terraform_vars_ui
    fi
    
    # Step 8: Create the template
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

# Configure VM defaults settings
configure_vm_defaults() {
    local temp_file=$(mktemp)
    
    # CPU Cores
    VM_CORES=$(whiptail --title "VM Defaults - CPU" \
        --inputbox "Default CPU cores:" 10 60 \
        "${VM_CORES:-2}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # Memory
    VM_MEMORY=$(whiptail --title "VM Defaults - Memory" \
        --inputbox "Default memory (MB):" 10 60 \
        "${VM_MEMORY:-2048}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # Disk Size
    VM_DISK_SIZE=$(whiptail --title "VM Defaults - Disk" \
        --inputbox "Default disk size:" 10 60 \
        "${VM_DISK_SIZE:-20G}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # Storage
    local storage_list=$(pvesm status | grep -E 'active|enabled' | awk '{print $1}' | tr '\n' ' ')
    local storage_options=()
    for storage in $storage_list; do
        storage_options+=("$storage" "Storage: $storage")
    done
    
    VM_STORAGE=$(whiptail --title "VM Defaults - Storage" \
        --menu "Select default storage:" 15 60 8 \
        "${storage_options[@]}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    # QEMU Agent
    if whiptail --title "VM Defaults - QEMU Agent" \
        --yesno "Enable QEMU agent by default?" 8 60; then
        QEMU_AGENT="1"
    else
        QEMU_AGENT="0"
    fi
    
    # UEFI vs BIOS
    if whiptail --title "VM Defaults - BIOS" \
        --yesno "Use UEFI (OVMF) by default? (Select No for BIOS)" 8 60; then
        BIOS_TYPE="ovmf"
    else
        BIOS_TYPE="seabios"
    fi
    
    whiptail --title "VM Defaults Updated" \
        --msgbox "VM defaults updated successfully:\n\nCPU: $VM_CORES cores\nMemory: $VM_MEMORY MB\nDisk: $VM_DISK_SIZE\nStorage: $VM_STORAGE\nQEMU Agent: $QEMU_AGENT\nBIOS: $BIOS_TYPE" 12 60
    
    log_info "VM defaults updated: CPU=$VM_CORES, Memory=$VM_MEMORY, Disk=$VM_DISK_SIZE, Storage=$VM_STORAGE"
}

# Configure network settings
configure_network_settings() {
    local choice
    
    choice=$(whiptail --title "Network Configuration" \
        --menu "Configure network settings:" 20 70 10 \
        "1" "Network Bridge" \
        "2" "VLAN Configuration" \
        "3" "Default IP Configuration" \
        "4" "DNS Settings" \
        "5" "Firewall Settings" \
        "6" "MAC Address Settings" \
        "0" "Back" \
        3>&1  1>&2 2>&3)
    
    case $choice in
        1) configure_network_bridge ;;
        2) configure_vlan_settings ;;
        3) configure_ip_settings ;;
        4) configure_dns_settings ;;
        5) configure_firewall_settings ;;
        6) configure_mac_settings ;;
        0) return ;;
    esac
}

# Configure network bridge
configure_network_bridge() {
    # List available bridges
    local bridge_list=$(ip link show type bridge | grep -o 'vmbr[0-9]*' | tr '\n' ' ')
    local bridge_options=()
    for bridge in $bridge_list; do
        bridge_options+=("$bridge" "Bridge: $bridge")
    done
    
    NETWORK_BRIDGE=$(whiptail --title "Network Bridge" \
        --menu "Select default network bridge:" 15 60 8 \
        "${bridge_options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        whiptail --title "Bridge Updated" \
            --msgbox "Default network bridge set to: $NETWORK_BRIDGE" 8 50
        log_info "Network bridge updated: $NETWORK_BRIDGE"
    fi
}

# Configure VLAN settings
configure_vlan_settings() {
    # Enable/disable VLAN
    if whiptail --title "VLAN Configuration" \
        --yesno "Enable VLAN tagging by default?" 8 60; then
        VLAN_ENABLED="true"
        
        VLAN_ID=$(whiptail --title "VLAN ID" \
            --inputbox "Enter default VLAN ID (1-4094):" 10 60 \
            "${VLAN_ID:-100}" \
            3>&1 1>&2 2>&3)
        
        if [[ $? -eq 0 ]]; then
            whiptail --title "VLAN Updated" \
                --msgbox "VLAN enabled with ID: $VLAN_ID" 8 50
        fi
    else
        VLAN_ENABLED="false"
        whiptail --title "VLAN Disabled" \
            --msgbox "VLAN tagging disabled" 8 50
    fi
}

# Configure IP settings
configure_ip_settings() {
    local ip_type
    ip_type=$(whiptail --title "IP Configuration" \
        --menu "Select default IP configuration:" 15 60 8 \
        "dhcp" "DHCP (automatic)" \
        "static" "Static IP" \
        "manual" "Manual configuration" \
        3>&1 1>&2 2>&3)
    
    case $ip_type in
        dhcp)
            NETWORK_TYPE="dhcp"
            whiptail --title "IP Updated" \
                --msgbox "Default IP configuration set to DHCP" 8 50
            ;;
        static)
            NETWORK_TYPE="static"
            configure_static_ip_defaults
            ;;
        manual)
            NETWORK_TYPE="manual"
            whiptail --title "IP Updated" \
                --msgbox "Default IP configuration set to manual" 8 50
            ;;
    esac
    
    log_info "IP configuration updated: $NETWORK_TYPE"
}

# Configure static IP defaults
configure_static_ip_defaults() {
    STATIC_IP=$(whiptail --title "Static IP - Default IP" \
        --inputbox "Default static IP (CIDR format):" 10 60 \
        "${STATIC_IP:-192.168.1.100/24}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    STATIC_GATEWAY=$(whiptail --title "Static IP - Gateway" \
        --inputbox "Default gateway:" 10 60 \
        "${STATIC_GATEWAY:-192.168.1.1}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    STATIC_DNS=$(whiptail --title "Static IP - DNS" \
        --inputbox "Default DNS servers (space-separated):" 10 60 \
        "${STATIC_DNS:-8.8.8.8 8.8.4.4}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    whiptail --title "Static IP Updated" \
        --msgbox "Static IP defaults updated:\n\nIP: $STATIC_IP\nGateway: $STATIC_GATEWAY\nDNS: $STATIC_DNS" 10 60
}

# Configure DNS settings
configure_dns_settings() {
    DNS_SERVERS=$(whiptail --title "DNS Configuration" \
        --inputbox "Default DNS servers (space-separated):" 10 60 \
        "${DNS_SERVERS:-8.8.8.8 8.8.4.4 1.1.1.1}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        whiptail --title "DNS Updated" \
            --msgbox "Default DNS servers updated to:\n$DNS_SERVERS" 8 60
        log_info "DNS servers updated: $DNS_SERVERS"
    fi
}

# Configure firewall settings
configure_firewall_settings() {
    if whiptail --title "Firewall Configuration" \
        --yesno "Enable firewall on VMs by default?" 8 60; then
        FIREWALL_ENABLED="true"
        
        local fw_policy
        fw_policy=$(whiptail --title "Firewall Policy" \
            --menu "Select default firewall policy:" 15 60 8 \
            "ACCEPT" "Allow all traffic (open)" \
            "DROP" "Block all traffic (strict)" \
            "REJECT" "Reject all traffic (notify sender)" \
            3>&1 1>&2 2>&3)
        
        if [[ $? -eq 0 ]]; then
            FIREWALL_POLICY="$fw_policy"
            whiptail --title "Firewall Updated" \
                --msgbox "Firewall enabled with policy: $FIREWALL_POLICY" 8 60
        fi
    else
        FIREWALL_ENABLED="false"
        whiptail --title "Firewall Disabled" \
            --msgbox "Firewall disabled by default" 8 50
    fi
    
    log_info "Firewall settings updated: enabled=$FIREWALL_ENABLED, policy=${FIREWALL_POLICY:-N/A}"
}

# Configure MAC address settings
configure_mac_settings() {
    if whiptail --title "MAC Address Configuration" \
        --yesno "Auto-generate MAC addresses?" 8 60; then
        MAC_AUTO_GENERATE="true"
        MAC_PREFIX=$(whiptail --title "MAC Prefix" \
            --inputbox "MAC address prefix (format: XX:XX:XX):" 10 60 \
            "${MAC_PREFIX:-52:54:00}" \
            3>&1 1>&2 2>&3)
    else
        MAC_AUTO_GENERATE="false"
    fi
    
    whiptail --title "MAC Settings Updated" \
        --msgbox "MAC address settings updated:\nAuto-generate: $MAC_AUTO_GENERATE\nPrefix: ${MAC_PREFIX:-N/A}" 8 60
    
    log_info "MAC settings updated: auto=$MAC_AUTO_GENERATE, prefix=${MAC_PREFIX:-N/A}"
}

# Configure storage settings
configure_storage_settings() {
    local choice
    
    choice=$(whiptail --title "Storage Configuration" \
        --menu "Configure storage settings:" 20 70 10 \
        "1" "Default Storage Pool" \
        "2" "Disk Format Settings" \
        "3" "Backup Storage" \
        "4" "ISO Storage" \
        "5" "Template Storage" \
        "6" "Disk Cache Settings" \
        "7" "Storage Quotas" \
        "0" "Back" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) configure_default_storage ;;
        2) configure_disk_format ;;
        3) configure_backup_storage ;;
        4) configure_iso_storage ;;
        5) configure_template_storage ;;
        6) configure_disk_cache ;;
        7) configure_storage_quotas ;;
        0) return ;;
    esac
}

# Configure default storage pool
configure_default_storage() {
    local storage_list=$(pvesm status | grep -E 'active|enabled' | awk '{print $1 " " $2}')
    local storage_options=()
    
    while IFS=' ' read -r storage_name storage_type; do
        [[ -n "$storage_name" ]] && storage_options+=("$storage_name" "Type: $storage_type")
    done <<< "$storage_list"
    
    VM_STORAGE=$(whiptail --title "Default Storage Pool" \
        --menu "Select default storage pool:" 15 70 8 \
        "${storage_options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        whiptail --title "Storage Updated" \
            --msgbox "Default storage pool set to: $VM_STORAGE" 8 50
        log_info "Default storage updated: $VM_STORAGE"
    fi
}

# Configure disk format
configure_disk_format() {
    local disk_format
    disk_format=$(whiptail --title "Disk Format" \
        --menu "Select default disk format:" 15 60 8 \
        "qcow2" "QCOW2 (recommended, supports snapshots)" \
        "raw" "Raw (better performance)" \
        "vmdk" "VMDK (VMware compatibility)" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        DISK_FORMAT="$disk_format"
        whiptail --title "Disk Format Updated" \
            --msgbox "Default disk format set to: $DISK_FORMAT" 8 50
        log_info "Disk format updated: $DISK_FORMAT"
    fi
}

# Configure backup storage
configure_backup_storage() {
    local backup_list=$(pvesm status | grep -E 'backup.*active' | awk '{print $1}')
    local backup_options=()
    
    for backup in $backup_list; do
        backup_options+=("$backup" "Backup storage: $backup")
    done
    
    if [[ ${#backup_options[@]} -eq 0 ]]; then
        whiptail --title "No Backup Storage" \
            --msgbox "No backup storage found. Configure backup storage in Proxmox first." 8 70
        return 1
    fi
    
    BACKUP_STORAGE=$(whiptail --title "Backup Storage" \
        --menu "Select default backup storage:" 15 60 8 \
        "${backup_options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        whiptail --title "Backup Storage Updated" \
            --msgbox "Default backup storage set to: $BACKUP_STORAGE" 8 50
        log_info "Backup storage updated: $BACKUP_STORAGE"
    fi
}

# Configure ISO storage
configure_iso_storage() {
    local iso_list=$(pvesm status | grep -E 'iso.*active' | awk '{print $1}')
    local iso_options=()
    
    for iso in $iso_list; do
        iso_options+=("$iso" "ISO storage: $iso")
    done
    
    if [[ ${#iso_options[@]} -eq 0 ]]; then
        whiptail --title "No ISO Storage" \
            --msgbox "No ISO storage found. Using default 'local' storage." 8 60
        ISO_STORAGE="local"
        return 0
    fi
    
    ISO_STORAGE=$(whiptail --title "ISO Storage" \
        --menu "Select default ISO storage:" 15 60 8 \
        "${iso_options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        whiptail --title "ISO Storage Updated" \
            --msgbox "Default ISO storage set to: $ISO_STORAGE" 8 50
        log_info "ISO storage updated: $ISO_STORAGE"
    fi
}

# Configure template storage
configure_template_storage() {
    local template_list=$(pvesm status | grep -E 'images.*active' | awk '{print $1}')
    local template_options=()
    
    for template in $template_list; do
        template_options+=("$template" "Template storage: $template")
    done
    
    TEMPLATE_STORAGE=$(whiptail --title "Template Storage" \
        --menu "Select template storage:" 15 60 8 \
        "${template_options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        whiptail --title "Template Storage Updated" \
            --msgbox "Template storage set to: $TEMPLATE_STORAGE" 8 50
        log_info "Template storage updated: $TEMPLATE_STORAGE"
    fi
}

# Configure disk cache settings
configure_disk_cache() {
    local cache_mode
    cache_mode=$(whiptail --title "Disk Cache Mode" \
        --menu "Select disk cache mode:" 15 60 8 \
        "none" "No cache (safest)" \
        "writethrough" "Write-through cache" \
        "writeback" "Write-back cache (fastest)" \
        "unsafe" "Unsafe cache (testing only)" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -eq 0 ]]; then
        DISK_CACHE="$cache_mode"
        whiptail --title "Disk Cache Updated" \
            --msgbox "Disk cache mode set to: $DISK_CACHE" 8 50
        log_info "Disk cache updated: $DISK_CACHE"
    fi
}

# Configure storage quotas
configure_storage_quotas() {
    if whiptail --title "Storage Quotas" \
        --yesno "Enable storage quotas for templates?" 8 60; then
        
        TEMPLATE_QUOTA=$(whiptail --title "Template Quota" \
            --inputbox "Maximum template size (GB, 0 for unlimited):" 10 60 \
            "${TEMPLATE_QUOTA:-0}" \
            3>&1 1>&2 2>&3)
        
        VM_QUOTA=$(whiptail --title "VM Quota" \
            --inputbox "Maximum VM disk size (GB, 0 for unlimited):" 10 60 \
            "${VM_QUOTA:-0}" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Quotas Updated" \
            --msgbox "Storage quotas updated:\nTemplate: ${TEMPLATE_QUOTA}GB\nVM: ${VM_QUOTA}GB" 8 60
        
        log_info "Storage quotas updated: template=${TEMPLATE_QUOTA}GB, vm=${VM_QUOTA}GB"
    else
        TEMPLATE_QUOTA="0"
        VM_QUOTA="0"
        whiptail --title "Quotas Disabled" \
            --msgbox "Storage quotas disabled" 8 50
    fi
}

# Configure automation settings
configure_automation_settings() {
    local choice
    
    choice=$(whiptail --title "Automation Configuration" \
        --menu "Configure automation settings:" 20 70 10 \
        "1" "Ansible Settings" \
        "2" "Terraform Settings" \
        "3" "Docker Integration" \
        "4" "Kubernetes Integration" \
        "5" "CI/CD Settings" \
        "6" "Batch Processing" \
        "7" "Auto-cleanup Settings" \
        "0" "Back" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) configure_ansible_automation ;;
        2) configure_terraform_automation ;;
        3) configure_docker_automation ;;
        4) configure_kubernetes_automation ;;
        5) configure_cicd_settings ;;
        6) configure_batch_settings ;;
        7) configure_cleanup_settings ;;
        0) return ;;
    esac
}

# Configure Ansible automation
configure_ansible_automation() {
    if whiptail --title "Ansible Configuration" \
        --yesno "Enable Ansible integration by default?" 8 60; then
        ANSIBLE_ENABLED="true"
        
        # Configure Ansible LXC settings
        ANSIBLE_LXC_CORES=$(whiptail --title "Ansible LXC - CPU" \
            --inputbox "CPU cores for Ansible LXC container:" 10 60 \
            "${ANSIBLE_LXC_CORES:-1}" \
            3>&1 1>&2 2>&3)
        
        ANSIBLE_LXC_MEMORY=$(whiptail --title "Ansible LXC - Memory" \
            --inputbox "Memory for Ansible LXC (MB):" 10 60 \
            "${ANSIBLE_LXC_MEMORY:-1024}" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Ansible Updated" \
            --msgbox "Ansible integration enabled:\nCPU: $ANSIBLE_LXC_CORES cores\nMemory: $ANSIBLE_LXC_MEMORY MB" 8 60
    else
        ANSIBLE_ENABLED="false"
        whiptail --title "Ansible Disabled" \
            --msgbox "Ansible integration disabled" 8 50
    fi
    
    log_info "Ansible settings updated: enabled=$ANSIBLE_ENABLED"
}

# Configure Terraform automation
configure_terraform_automation() {
    if whiptail --title "Terraform Configuration" \
        --yesno "Enable Terraform integration by default?" 8 60; then
        TERRAFORM_ENABLED="true"
        
        TERRAFORM_PROVIDER=$(whiptail --title "Terraform Provider" \
            --inputbox "Terraform provider:" 10 60 \
            "${TERRAFORM_PROVIDER:-telmate/proxmox}" \
            3>&1 1>&2 2>&3)
        
        if whiptail --title "Terraform Cleanup" \
            --yesno "Cleanup temporary Terraform files after execution?" 8 60; then
            TERRAFORM_CLEANUP_TEMP="true"
        else
            TERRAFORM_CLEANUP_TEMP="false"
        fi
        
        whiptail --title "Terraform Updated" \
            --msgbox "Terraform integration enabled:\nProvider: $TERRAFORM_PROVIDER\nCleanup: $TERRAFORM_CLEANUP_TEMP" 8 60
    else
        TERRAFORM_ENABLED="false"
        whiptail --title "Terraform Disabled" \
            --msgbox "Terraform integration disabled" 8 50
    fi
    
    log_info "Terraform settings updated: enabled=$TERRAFORM_ENABLED"
}

# Configure Docker automation
configure_docker_automation() {
    if whiptail --title "Docker Integration" \
        --yesno "Enable Docker template integration?" 8 60; then
        DOCKER_INTEGRATION="true"
        
        DOCKER_TEMPLATE_DIR=$(whiptail --title "Docker Template Directory" \
            --inputbox "Docker template directory:" 10 60 \
            "${DOCKER_TEMPLATE_DIR:-$REPO_ROOT/docker/templates}" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Docker Integration Updated" \
            --msgbox "Docker integration enabled:\nTemplate dir: $DOCKER_TEMPLATE_DIR" 8 70
    else
        DOCKER_INTEGRATION="false"
        whiptail --title "Docker Integration Disabled" \
            --msgbox "Docker template integration disabled" 8 50
    fi
    
    log_info "Docker integration updated: enabled=$DOCKER_INTEGRATION"
}

# Configure Kubernetes automation
configure_kubernetes_automation() {
    if whiptail --title "Kubernetes Integration" \
        --yesno "Enable Kubernetes template integration?" 8 60; then
        K8S_INTEGRATION="true"
        
        K8S_TEMPLATE_DIR=$(whiptail --title "Kubernetes Template Directory" \
            --inputbox "Kubernetes template directory:" 10 60 \
            "${K8S_TEMPLATE_DIR:-$REPO_ROOT/kubernetes/templates}" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Kubernetes Integration Updated" \
            --msgbox "Kubernetes integration enabled:\nTemplate dir: $K8S_TEMPLATE_DIR" 8 70
    else
        K8S_INTEGRATION="false"
        whiptail --title "Kubernetes Integration Disabled" \
            --msgbox "Kubernetes template integration disabled" 8 50
    fi
    
    log_info "Kubernetes integration updated: enabled=$K8S_INTEGRATION"
}

# Configure CI/CD settings
configure_cicd_settings() {
    if whiptail --title "CI/CD Integration" \
        --yesno "Enable CI/CD webhook support?" 8 60; then
        CICD_ENABLED="true"
        
        CICD_WEBHOOK_URL=$(whiptail --title "Webhook URL" \
            --inputbox "CI/CD webhook URL:" 10 70 \
            "${CICD_WEBHOOK_URL:-http://jenkins.local/webhook}" \
            3>&1 1>&2 2>&3)
        
        CICD_API_TOKEN=$(whiptail --title "API Token" \
            --passwordbox "CI/CD API token (will be hidden):" 10 60 \
            3>&1 1>&2 2>&3)
        
        whiptail --title "CI/CD Updated" \
            --msgbox "CI/CD integration enabled:\nWebhook: $CICD_WEBHOOK_URL" 8 70
    else
        CICD_ENABLED="false"
        whiptail --title "CI/CD Disabled" \
            --msgbox "CI/CD webhook support disabled" 8 50
    fi
    
    log_info "CI/CD settings updated: enabled=$CICD_ENABLED"
}

# Configure batch processing settings
configure_batch_settings() {
    BATCH_VMID_START=$(whiptail --title "Batch Processing - Starting VMID" \
        --inputbox "Starting VMID for batch creation:" 10 60 \
        "${BATCH_VMID_START:-52000}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    BATCH_COUNT=$(whiptail --title "Batch Processing - Default Count" \
        --inputbox "Default number of templates in batch:" 10 60 \
        "${BATCH_COUNT:-1}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    if whiptail --title "Auto-increment VMID" \
        --yesno "Auto-increment VMID for batch creation?" 8 60; then
        AUTO_INCREMENT_VMID="true"
    else
        AUTO_INCREMENT_VMID="false"
    fi
    
    whiptail --title "Batch Settings Updated" \
        --msgbox "Batch processing settings:\nStart VMID: $BATCH_VMID_START\nDefault count: $BATCH_COUNT\nAuto-increment: $AUTO_INCREMENT_VMID" 10 60
    
    log_info "Batch settings updated: start=$BATCH_VMID_START, count=$BATCH_COUNT, auto-increment=$AUTO_INCREMENT_VMID"
}

# Configure auto-cleanup settings
configure_cleanup_settings() {
    if whiptail --title "Auto-cleanup" \
        --yesno "Enable automatic cleanup of temporary files?" 8 60; then
        CLEANUP_ENABLED="true"
        
        CLEANUP_TEMP_DAYS=$(whiptail --title "Cleanup - Temp Files" \
            --inputbox "Delete temp files older than (days):" 10 60 \
            "${CLEANUP_TEMP_DAYS:-7}" \
            3>&1 1>&2 2>&3)
        
        CLEANUP_LOG_DAYS=$(whiptail --title "Cleanup - Log Files" \
            --inputbox "Delete log files older than (days):" 10 60 \
            "${CLEANUP_LOG_DAYS:-30}" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Cleanup Updated" \
            --msgbox "Auto-cleanup enabled:\nTemp files: $CLEANUP_TEMP_DAYS days\nLog files: $CLEANUP_LOG_DAYS days" 8 60
    else
        CLEANUP_ENABLED="false"
        whiptail --title "Cleanup Disabled" \
            --msgbox "Auto-cleanup disabled" 8 50
    fi
    
    log_info "Cleanup settings updated: enabled=$CLEANUP_ENABLED"
}

# Configure security settings
configure_security_settings() {
    local choice
    
    choice=$(whiptail --title "Security Configuration" \
        --menu "Configure security settings:" 20 70 10 \
        "1" "SSH Key Settings" \
        "2" "User Account Settings" \
        "3" "Firewall Defaults" \
        "4" "Encryption Settings" \
        "5" "Access Control" \
        "6" "Audit Settings" \
        "7" "Password Policies" \
        "0" "Back" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) configure_ssh_settings ;;
        2) configure_user_settings ;;
        3) configure_security_firewall ;;
        4) configure_encryption_settings ;;
        5) configure_access_control ;;
        6) configure_audit_settings ;;
        7) configure_password_policies ;;
        0) return ;;
    esac
}

# Configure SSH settings
configure_ssh_settings() {
    if whiptail --title "SSH Key Configuration" \
        --yesno "Use SSH key authentication by default?" 8 60; then
        SSH_KEY_ENABLED="true"
        
        SSH_KEY_PATH=$(whiptail --title "SSH Key Path" \
            --inputbox "Default SSH public key path:" 10 70 \
            "${SSH_KEY_PATH:-~/.ssh/id_rsa.pub}" \
            3>&1 1>&2 2>&3)
        
        if whiptail --title "Disable Password Auth" \
            --yesno "Disable password authentication when SSH key is used?" 8 60; then
            SSH_DISABLE_PASSWORD="true"
        else
            SSH_DISABLE_PASSWORD="false"
        fi
        
        whiptail --title "SSH Settings Updated" \
            --msgbox "SSH settings updated:\nKey path: $SSH_KEY_PATH\nDisable password: $SSH_DISABLE_PASSWORD" 8 70
    else
        SSH_KEY_ENABLED="false"
        whiptail --title "SSH Key Disabled" \
            --msgbox "SSH key authentication disabled" 8 50
    fi
    
    log_info "SSH settings updated: key_enabled=$SSH_KEY_ENABLED"
}

# Configure user settings
configure_user_settings() {
    CLOUD_USER_DEFAULT=$(whiptail --title "Default User" \
        --inputbox "Default user account name:" 10 60 \
        "${CLOUD_USER_DEFAULT:-ubuntu}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    if whiptail --title "Sudo Access" \
        --yesno "Grant sudo access to default user?" 8 60; then
        ADD_SUDO_NOPASSWD="true"
    else
        ADD_SUDO_NOPASSWD="false"
    fi
    
    SHELL_DEFAULT=$(whiptail --title "Default Shell" \
        --menu "Select default shell:" 15 60 8 \
        "/bin/bash" "Bash (recommended)" \
        "/bin/zsh" "Zsh" \
        "/bin/fish" "Fish" \
        "/bin/sh" "Bourne Shell" \
        3>&1 1>&2 2>&3)
    
    whiptail --title "User Settings Updated" \
        --msgbox "User settings updated:\nUser: $CLOUD_USER_DEFAULT\nSudo: $ADD_SUDO_NOPASSWD\nShell: $SHELL_DEFAULT" 10 60
    
    log_info "User settings updated: user=$CLOUD_USER_DEFAULT, sudo=$ADD_SUDO_NOPASSWD, shell=$SHELL_DEFAULT"
}

# Configure security firewall
configure_security_firewall() {
    if whiptail --title "Security Firewall" \
        --yesno "Enable restrictive firewall by default?" 8 60; then
        SECURITY_FIREWALL="true"
        
        local fw_ports
        fw_ports=$(whiptail --title "Allowed Ports" \
            --inputbox "Default allowed ports (comma-separated):" 10 60 \
            "${SECURITY_PORTS:-22,80,443}" \
            3>&1 1>&2 2>&3)
        
        if [[ $? -eq 0 ]]; then
            SECURITY_PORTS="$fw_ports"
        fi
        
        whiptail --title "Security Firewall Updated" \
            --msgbox "Security firewall enabled with ports: $SECURITY_PORTS" 8 60
    else
        SECURITY_FIREWALL="false"
        whiptail --title "Security Firewall Disabled" \
            --msgbox "Security firewall disabled" 8 50
    fi
    
    log_info "Security firewall updated: enabled=$SECURITY_FIREWALL"
}

# Configure encryption settings
configure_encryption_settings() {
    if whiptail --title "Disk Encryption" \
        --yesno "Enable disk encryption by default?" 8 60; then
        DISK_ENCRYPTION="true"
        
        ENCRYPTION_TYPE=$(whiptail --title "Encryption Type" \
            --menu "Select encryption type:" 15 60 8 \
            "luks" "LUKS (recommended)" \
            "luks2" "LUKS2 (newer)" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Encryption Updated" \
            --msgbox "Disk encryption enabled with type: $ENCRYPTION_TYPE" 8 60
    else
        DISK_ENCRYPTION="false"
        whiptail --title "Encryption Disabled" \
            --msgbox "Disk encryption disabled" 8 50
    fi
    
    log_info "Encryption settings updated: enabled=$DISK_ENCRYPTION, type=${ENCRYPTION_TYPE:-N/A}"
}

# Configure access control
configure_access_control() {
    if whiptail --title "Access Control" \
        --yesno "Enable role-based access control?" 8 60; then
        RBAC_ENABLED="true"
        
        DEFAULT_ROLE=$(whiptail --title "Default Role" \
            --menu "Select default user role:" 15 60 8 \
            "user" "Standard User" \
            "admin" "Administrator" \
            "developer" "Developer" \
            "operator" "Operator" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Access Control Updated" \
            --msgbox "RBAC enabled with default role: $DEFAULT_ROLE" 8 60
    else
        RBAC_ENABLED="false"
        whiptail --title "Access Control Disabled" \
            --msgbox "Role-based access control disabled" 8 50
    fi
    
    log_info "Access control updated: rbac=$RBAC_ENABLED, role=${DEFAULT_ROLE:-N/A}"
}

# Configure audit settings
configure_audit_settings() {
    if whiptail --title "Audit Logging" \
        --yesno "Enable audit logging for templates?" 8 60; then
        AUDIT_ENABLED="true"
        
        AUDIT_LEVEL=$(whiptail --title "Audit Level" \
            --menu "Select audit level:" 15 60 8 \
            "basic" "Basic (create/delete operations)" \
            "detailed" "Detailed (all operations)" \
            "debug" "Debug (everything)" \
            3>&1 1>&2 2>&3)
        
        whiptail --title "Audit Updated" \
            --msgbox "Audit logging enabled with level: $AUDIT_LEVEL" 8 60
    else
        AUDIT_ENABLED="false"
        whiptail --title "Audit Disabled" \
            --msgbox "Audit logging disabled" 8 50
    fi
    
    log_info "Audit settings updated: enabled=$AUDIT_ENABLED, level=${AUDIT_LEVEL:-N/A}"
}

# Configure password policies
configure_password_policies() {
    PASSWORD_MIN_LENGTH=$(whiptail --title "Password Policy - Length" \
        --inputbox "Minimum password length:" 10 60 \
        "${PASSWORD_MIN_LENGTH:-12}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    if whiptail --title "Password Complexity" \
        --yesno "Require complex passwords (uppercase, lowercase, numbers, symbols)?" 8 60; then
        PASSWORD_COMPLEXITY="true"
    else
        PASSWORD_COMPLEXITY="false"
    fi
    
    PASSWORD_EXPIRY=$(whiptail --title "Password Expiry" \
        --inputbox "Password expiry (days, 0 for never):" 10 60 \
        "${PASSWORD_EXPIRY:-90}" \
        3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    
    whiptail --title "Password Policy Updated" \
        --msgbox "Password policy updated:\nMin length: $PASSWORD_MIN_LENGTH\nComplexity: $PASSWORD_COMPLEXITY\nExpiry: $PASSWORD_EXPIRY days" 10 60
    
    log_info "Password policy updated: length=$PASSWORD_MIN_LENGTH, complexity=$PASSWORD_COMPLEXITY, expiry=$PASSWORD_EXPIRY"
}

# Export configuration to file
export_configuration() {
    local config_file
    config_file=$(whiptail --title "Export Configuration" \
        --inputbox "Enter filename to save configuration:" 10 70 \
        "$SCRIPT_DIR/configs/$(date +%Y%m%d_%H%M%S)_template_config.conf" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    # Create config directory if it doesn't exist
    mkdir -p "$(dirname "$config_file")"
    
    # Export current configuration
    cat > "$config_file" <<EOF
# Proxmox Template Creator Configuration
# Generated: $(date)

# VM Configuration
VM_NAME="$VM_NAME"
VMID_DEFAULT="$VMID_DEFAULT"
VM_MEMORY="$VM_MEMORY"
VM_CORES="$VM_CORES"
VM_DISK_SIZE="$VM_DISK_SIZE"
VM_STORAGE="$VM_STORAGE"
BIOS_TYPE="$BIOS_TYPE"
QEMU_AGENT="$QEMU_AGENT"

# Network Configuration
NETWORK_TYPE="$NETWORK_TYPE"
NETWORK_BRIDGE="$NETWORK_BRIDGE"
VLAN_ENABLED="$VLAN_ENABLED"
VLAN_ID="$VLAN_ID"
STATIC_IP="$STATIC_IP"
STATIC_GATEWAY="$STATIC_GATEWAY"
STATIC_DNS="$STATIC_DNS"
FIREWALL_ENABLED="$FIREWALL_ENABLED"
FIREWALL_POLICY="$FIREWALL_POLICY"

# Storage Configuration
DISK_FORMAT="$DISK_FORMAT"
ISO_STORAGE: "$ISO_STORAGE"
TEMPLATE_STORAGE="$TEMPLATE_STORAGE"
DISK_CACHE="$DISK_CACHE"

# Automation Configuration
ANSIBLE_ENABLED="$ANSIBLE_ENABLED"
TERRAFORM_ENABLED="$TERRAFORM_ENABLED"
DOCKER_INTEGRATION="$DOCKER_INTEGRATION"
K8S_INTEGRATION="$K8S_INTEGRATION"
CICD_ENABLED="$CICD_ENABLED"

# Security Configuration
SSH_KEY_ENABLED="$SSH_KEY_ENABLED"
SSH_KEY_PATH="$SSH_KEY_PATH"
CLOUD_USER_DEFAULT="$CLOUD_USER_DEFAULT"
ADD_SUDO_NOPASSWD="$ADD_SUDO_NOPASSWD"
SECURITY_FIREWALL="$SECURITY_FIREWALL"
DISK_ENCRYPTION="$DISK_ENCRYPTION"

# Cleanup Configuration
CLEANUP_ENABLED="$CLEANUP_ENABLED"
CLEANUP_TEMP_DAYS="$CLEANUP_TEMP_DAYS"
CLEANUP_LOG_DAYS="$CLEANUP_LOG_DAYS"

# Selected Distribution
SELECTED_DISTRIBUTION="$SELECTED_DISTRIBUTION"
SELECTED_DISTRIBUTION_KEY="$SELECTED_DISTRIBUTION_KEY"

# Selected Packages
SELECTED_PACKAGES=($(printf "'%s' " "${SELECTED_PACKAGES[@]}"))

# Selected Ansible Playbooks
SELECTED_ANSIBLE_PLAYBOOKS=($(printf "'%s' " "${SELECTED_ANSIBLE_PLAYBOOKS[@]}"))

# Selected Terraform Modules
SELECTED_TERRAFORM_MODULES=($(printf "'%s' " "${SELECTED_TERRAFORM_MODULES[@]}"))

# Selected Docker Templates
SELECTED_DOCKER_TEMPLATES=($(printf "'%s' " "${SELECTED_DOCKER_TEMPLATES[@]}"))

# Selected K8s Templates
SELECTED_K8S_TEMPLATES=($(printf "'%s' " "${SELECTED_K8S_TEMPLATES[@]}"))
EOF
    
    whiptail --title "Configuration Exported" \
        --msgbox "Configuration exported to:\n$config_file" 8 70
    
    log_info "Configuration exported to: $config_file"
}

# Import configuration from file
import_configuration() {
    local config_file
    config_file=$(whiptail --title "Import Configuration" \
        --inputbox "Enter path to configuration file:" 10 70 \
        "$SCRIPT_DIR/configs/" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    if [[ ! -f "$config_file" ]]; then
        whiptail --title "File Not Found" \
            --msgbox "Configuration file not found:\n$config_file" 8 70
        return 1
    fi
    
    # Source the configuration file
    if source "$config_file" 2>/dev/null; then
        whiptail --title "Configuration Imported" \
            --msgbox "Configuration imported successfully from:\n$config_file" 8 70
        log_info "Configuration imported from: $config_file"
    else
        whiptail --title "Import Error" \
            --msgbox "Failed to import configuration from:\n$config_file\n\nPlease check the file format." 10 70
        log_error "Failed to import configuration from: $config_file"
        return 1
    fi
}

# Reset to defaults
reset_to_defaults() {
    if whiptail --title "Reset to Defaults" \
        --yesno "Are you sure you want to reset all settings to defaults?\n\nThis will clear all current configuration." 10 60; then
        
        # Reset all variables to defaults
        VM_NAME=""
        VMID_DEFAULT="9000"
        VM_MEMORY="2048"
        VM_CORES="2"
        VM_DISK_SIZE="20G"
        VM_STORAGE="local-lvm"
        BIOS_TYPE="seabios"
        QEMU_AGENT="1"
        NETWORK_TYPE="dhcp"
        NETWORK_BRIDGE="vmbr0"
        VLAN_ENABLED="false"
        VLAN_ID="100"
        STATIC_IP=""
        STATIC_GATEWAY=""
        STATIC_DNS=""
        FIREWALL_ENABLED="false"
        FIREWALL_POLICY="ACCEPT"
        DISK_FORMAT="qcow2"
        BACKUP_STORAGE=""
        ISO_STORAGE="local"
        TEMPLATE_STORAGE=""
        DISK_CACHE="none"
        ANSIBLE_ENABLED="false"
        TERRAFORM_ENABLED="false"
        DOCKER_INTEGRATION="false"
        K8S_INTEGRATION="false"
        CICD_ENABLED="false"
        SSH_KEY_ENABLED="true"
        SSH_KEY_PATH="~/.ssh/id_rsa.pub"
        CLOUD_USER_DEFAULT="ubuntu"
        ADD_SUDO_NOPASSWD="true"
        SECURITY_FIREWALL="false"
        DISK_ENCRYPTION="false"
        CLEANUP_ENABLED="true"
        CLEANUP_TEMP_DAYS="7"
        CLEANUP_LOG_DAYS="30"
        
        # Clear arrays
        SELECTED_PACKAGES=()
        SELECTED_ANSIBLE_PLAYBOOKS=()
        SELECTED_TERRAFORM_MODULES=()
        SELECTED_DOCKER_TEMPLATES=()
        SELECTED_K8S_TEMPLATES=()
        
        whiptail --title "Reset Complete" \
            --msgbox "All settings have been reset to defaults." 8 50
        
        log_info "Configuration reset to defaults"
    fi
}

# View current settings
view_current_settings() {
    local settings_summary="Current Configuration Settings:

VM Configuration:
  Name: ${VM_NAME:-<not set>}
  VMID: ${VMID_DEFAULT:-9000}
  Memory: ${VM_MEMORY:-2048} MB
  CPU Cores: ${VM_CORES:-2}
  Disk Size: ${VM_DISK_SIZE:-20G}
  Storage: ${VM_STORAGE:-local-lvm}
  BIOS: ${BIOS_TYPE:-seabios}
  QEMU Agent: ${QEMU_AGENT:-1}

Network Configuration:
  Type: ${NETWORK_TYPE:-dhcp}
  Bridge: ${NETWORK_BRIDGE:-vmbr0}
  VLAN: ${VLAN_ENABLED:-false}
  VLAN ID: ${VLAN_ID:-100}
  Static IP: ${STATIC_IP:-<not set>}
  Gateway: ${STATIC_GATEWAY:-<not set>}
  DNS: ${STATIC_DNS:-<not set>}

Storage Configuration:
  Disk Format: ${DISK_FORMAT:-qcow2}
  ISO Storage: ${ISO_STORAGE:-local}
  Disk Cache: ${DISK_CACHE:-none}

Automation:
  Ansible: ${ANSIBLE_ENABLED:-false}
  Terraform: ${TERRAFORM_ENABLED:-false}
  Docker: ${DOCKER_INTEGRATION:-false}
  Kubernetes: ${K8S_INTEGRATION:-false}

Security:
  SSH Key: ${SSH_KEY_ENABLED:-true}
  Default User: ${CLOUD_USER_DEFAULT:-ubuntu}
  Sudo Access: ${ADD_SUDO_NOPASSWD:-true}
  Firewall: ${SECURITY_FIREWALL:-false}
  Encryption: ${DISK_ENCRYPTION:-false}

Selected Items:
  Packages: ${#SELECTED_PACKAGES[@]} selected
  Ansible Playbooks: ${#SELECTED_ANSIBLE_PLAYBOOKS[@]} selected
  Terraform Modules: ${#SELECTED_TERRAFORM_MODULES[@]} selected
  Docker Templates: ${#SELECTED_DOCKER_TEMPLATES[@]} selected
  K8s Templates: ${#SELECTED_K8S_TEMPLATES[@]} selected"
    
    whiptail --title "Current Settings" \
        --msgbox "$settings_summary" 30 80
    
    log_info "Current settings viewed"
}

#===============================================================================
# MISSING CRITICAL FUNCTIONS IMPLEMENTATION
# ================================================================================

# Select distribution for template creation
select_distribution() {
    log_info "Starting distribution selection"
    
    # Get distribution list
    local dist_list=()
    local dist_keys=()
    
    for key in "${!DISTRO_LIST[@]}"; do
        IFS='|' read -ra dist_info <<< "${DISTRO_LIST[$key]}"
        local display_name="${dist_info[0]}"
        local notes="${dist_info[7]:-}"
        
        dist_list+=("$key" "$display_name ($notes)")
        dist_keys+=("$key")
    done
    
    # Sort the distribution list alphabetically
    local sorted_dist_list=()
    while IFS= read -r -d '' line; do
        sorted_dist_list+=("$line")
    done < <(printf '%s\0' "${dist_list[@]}" | sort -z)
    
    # Show distribution selection dialog
    local selected_key
    selected_key=$(whiptail --title "Distribution Selection" \
        --menu "Select a distribution:" 25 80 15 \
        "${sorted_dist_list[@]}" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -ne 0 ]]; then
        log_warn "Distribution selection cancelled"
        return 1
    fi
    
    # Validate selection
    if [[ -z "${DISTRO_LIST[$selected_key]:-}" ]]; then
        log_error "Invalid distribution selected: $selected_key"
        return 1
    fi
    
    # Store selection
    SELECTED_DISTRIBUTION_KEY="$selected_key"
    SELECTED_DISTRIBUTION="${DISTRO_LIST[$selected_key]}"
    DISTRIBUTION_SELECTED="$SELECTED_DISTRIBUTION"
    
    # Parse distribution info
    IFS='|' read -ra dist_info <<< "$SELECTED_DISTRIBUTION"
    DIST_NAME="${dist_info[0]}"
    IMG_URL="${dist_info[1]}"
    IMG_FORMAT="${dist_info[2]}"
    PKG_MANAGER="${dist_info[3]}"
    OS_TYPE="${dist_info[4]}"
    DEFAULT_USER="${dist_info[5]}"
    DEFAULT_DISK_SIZE="${dist_info[6]:-20G}"
    DIST_NOTES="${dist_info[7]:-}"
    
    # Handle custom ISO selection
    if [[ "$selected_key" == "custom-iso" ]]; then
        if ! handle_custom_iso_selection; then
            log_error "Custom ISO configuration failed"
            return 1
        fi
    fi
    
    log_info "Selected distribution: $DIST_NAME"
    log_info "Image URL: $IMG_URL"
    log_info "Format: $IMG_FORMAT"
    log_info "Package Manager: $PKG_MANAGER"
    
    return 0
}

# Handle custom ISO/image selection
handle_custom_iso_selection() {
    log_info "Configuring custom ISO/image"
    
    # Get custom image URL
    IMG_URL=$(whiptail --title "Custom Image URL" \
        --inputbox "Enter the URL or local path to your image/ISO:" 10 70 \
        3>&1 1>&2 2>&3)
    
    if [[ $? -ne 0 || -z "$IMG_URL" ]]; then
        log_error "Custom image URL is required"
        return 1
    fi
    
    # Detect format from URL/filename
    local detected_format=""
    case "$IMG_URL" in
        *.qcow2) detected_format="qcow2" ;;
        *.img) detected_format="raw" ;;
        *.iso) detected_format="iso" ;;
        *.vmdk) detected_format="vmdk" ;;
        *.raw) detected_format="raw" ;;
        *) detected_format="unknown" ;;
    esac
    
    # Let user select or confirm format
    IMG_FORMAT=$(whiptail --title "Image Format" \
        --menu "Select the image format:" 15 60 8 \
        "qcow2" "QCOW2 (recommended, supports snapshots)" \
        "raw" "Raw disk image" \
        "iso" "ISO file" \
        "vmdk" "VMware disk" \
        "auto" "Auto-detect" \
        3>&1 1>&2 2>&3)
    
    if [[ $? -ne 0 ]]; then
        IMG_FORMAT="$detected_format"
    fi
    
    # Get package manager
    PKG_MANAGER=$(whiptail --title "Package Manager" \
        --menu "Select the package manager:" 15 60 8 \
        "apt" "APT (Debian/Ubuntu)" \
        "dnf" "DNF (Fedora/RHEL 8+)" \
        "yum" "YUM (CentOS/RHEL 7)" \
        "zypper" "Zypper (openSUSE)" \
        "pacman" "Pacman (Arch)" \
        "apk" "APK (Alpine)" \
        "emerge" "Emerge (Gentoo)" \
        "auto" "Auto-detect" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && PKG_MANAGER="auto"
    
    # Set other defaults
    DIST_NAME="Custom Image"
    OS_TYPE="l26"
    DEFAULT_USER="root"
    DEFAULT_DISK_SIZE="20G"
    DIST_NOTES="Custom user-supplied image"
    
    log_info "Custom image configured: $IMG_URL ($IMG_FORMAT)"
    return 0
}

# Get next available VMID
get_next_available_vmid() {
    local start_vmid="${VMID_DEFAULT:-9000}"
    local max_vmid=99999
    local current_vmid="$start_vmid"
    
    # Get list of existing VMIDs
    local existing_vmids
    existing_vmids=$(qm list 2>/dev/null | awk 'NR>1 {print $1}' | sort -n)
    
    # Find next available VMID
    while [[ $current_vmid -le $max_vmid ]]; do
        if ! echo "$existing_vmids" | grep -q "^$current_vmid$"; then
            echo "$current_vmid"
            return 0
        fi
        ((current_vmid++))
    done
    
    log_error "No available VMID found"
    echo "9000"  # fallback
    return 1
}

# Download distribution image
download_distribution_image() {
    log_info "Downloading distribution image"
    
    if [[ -z "$IMG_URL" ]]; then
        log_error "No image URL specified"
        return 1
    fi
    
    # Create download directory
    local download_dir="$WORK_DIR/images"
    mkdir -p "$download_dir"
    
    # Extract filename from URL
    local image_filename
    image_filename=$(basename "$IMG_URL")
    local local_image_path="$download_dir/$image_filename"
    
    # Check if it's a local file
    if [[ -f "$IMG_URL" ]]; then
        log_info "Using local image file: $IMG_URL"
        cp "$IMG_URL" "$local_image_path"
        IMAGE_PATH="$local_image_path"
        return 0
    fi
    
    # Download the image
    log_info "Downloading image from: $IMG_URL"
    if ! wget -O "$local_image_path" "$IMG_URL" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to download image from $IMG_URL"
        return 1
    fi
    
    # Verify download
    if [[ ! -f "$local_image_path" || ! -s "$local_image_path" ]]; then
        log_error "Downloaded image is empty or corrupted"
        return 1
    fi
    
    IMAGE_PATH="$local_image_path"
    log_success "Image downloaded successfully: $IMAGE_PATH"
    return 0
}

# Create VM from downloaded image
create_vm_from_image() {
    log_info "Creating VM from image"
    
    if [[ -z "$IMAGE_PATH" || ! -f "$IMAGE_PATH" ]]; then
        log_error "Image file not found: $IMAGE_PATH"
        return 1
    fi
    
    # Import disk image to storage
    local disk_import_cmd
    case "$IMG_FORMAT" in
        "qcow2"|"vmdk"|"raw")
            disk_import_cmd="qm importdisk $VMID_DEFAULT \"$IMAGE_PATH\" $STORAGE_DEFAULT"
            ;;
        "iso")
            # For ISO files, create a new VM and attach ISO as CD-ROM
            create_vm_with_iso
            return $?
            ;;
        *)
            log_error "Unsupported image format: $IMG_FORMAT"
            return 1
            ;;
    esac
    
    # Create VM configuration
    log_info "Creating VM configuration for VMID: $VMID_DEFAULT"
    
    qm create "$VMID_DEFAULT" \
        --name "$VM_NAME" \
        --memory "$MEMORY_MB_DEFAULT" \
        --cores "$CPU_CORES_DEFAULT" \
        --net0 "virtio,bridge=$BRIDGE_DEFAULT" \
        --scsihw "virtio-scsi-pci" \
        --boot "order=scsi0" \
        --agent 1 \
        --ostype "$OS_TYPE" \
        || {
            log_error "Failed to create VM configuration"
            return 1
        }
    
    # Import and attach disk
    log_info "Importing disk image to storage"
    eval "$disk_import_cmd" || {
        log_error "Failed to import disk image"
        return 1
    }
    
    # Attach the imported disk
    qm set "$VMID_DEFAULT" \
        --scsi0 "$STORAGE_DEFAULT:vm-$VMID_DEFAULT-disk-0,size=$DISK_SIZE_DEFAULT" \
        || {
            log_error "Failed to attach disk to VM"
            return 1
        }
    
    log_success "VM created successfully with VMID: $VMID_DEFAULT"
    return 0
}

# Create VM with ISO (for ISO installations)
create_vm_with_iso() {
    log_info "Creating VM with ISO image"
    
    # Create VM with ISO attached as CD-ROM
    qm create "$VMID_DEFAULT" \
        --name "$VM_NAME" \
        --memory "$MEMORY_MB_DEFAULT" \
        --cores "$CPU_CORES_DEFAULT" \
        --net0 "virtio,bridge=$BRIDGE_DEFAULT" \
        --scsihw "virtio-scsi-pci" \
        --boot "order=ide2,scsi0" \
        --agent 1 \
        --ostype "$OS_TYPE" \
        --ide2 "$STORAGE_DEFAULT:iso/$IMAGE_PATH,media=cdrom" \
        --scsi0 "$STORAGE_DEFAULT:$DISK_SIZE_DEFAULT" \
        || {
            log_error "Failed to create VM with ISO"
            return 1
        }
    
    log_info "VM created with ISO. Manual installation may be required."
    return 0
}

# Configure cloud-init for the VM
configure_cloud_init() {
    log_info "Configuring cloud-init"
    
    # Enable cloud-init
    qm set "$VMID_DEFAULT" --ide2 "$STORAGE_DEFAULT:cloudinit" || {
        log_error "Failed to enable cloud-init"
        return 1
    }
    
    # Set cloud-init user
    local cloud_user="${CLOUD_USER_DEFAULT:-$DEFAULT_USER}"
    qm set "$VMID_DEFAULT" --ciuser "$cloud_user" || {
        log_error "Failed to set cloud-init user"
        return 1
    }
    
    # Set cloud-init password
    if [[ -n "$CLOUD_PASSWORD_DEFAULT" ]]; then
        qm set "$VMID_DEFAULT" --cipassword "$CLOUD_PASSWORD_DEFAULT" || {
            log_warn "Failed to set cloud-init password"
        }
    fi
    
    # Configure SSH keys
    if [[ "$SSH_KEY_ENABLED" == "true" && -f "$SSH_KEY_FILE" ]]; then
        qm set "$VMID_DEFAULT" --sshkeys "$SSH_KEY_FILE" || {
            log_warn "Failed to set SSH keys"
        }
    fi
    
    # Configure network if static
    if [[ "$NETWORK_TYPE" == "static" && -n "$STATIC_IP" ]]; then
        qm set "$VMID_DEFAULT" --ipconfig0 "ip=$STATIC_IP,gw=$STATIC_GATEWAY" || {
            log_warn "Failed to set static IP configuration"
        }
    fi
    
    log_success "Cloud-init configured successfully"
    return 0
}

# Install packages using virt-customize
install_packages_virt_customize() {
    log_info "Installing packages using virt-customize"
    
    if [[ ${#SELECTED_PACKAGES[@]} -eq 0 ]]; then
        log_info "No packages selected for installation"
        return 0
    fi
    
    # Stop the VM if running
    qm stop "$VMID_DEFAULT" 2>/dev/null || true
    
    # Wait for VM to stop
    sleep 5
    
    # Get the disk image path
    local disk_image
    disk_image=$(qm config "$VMID_DEFAULT" | grep 'scsi0:' | awk '{print $2}' | cut -d',' -f1)
    
    if [[ -z "$disk_image" ]]; then
        log_error "Failed to find VM disk image"
        return 1
    fi
    
    # Build package list
    local package_list=""
    for package in "${SELECTED_PACKAGES[@]}"; do
        package_list="$package_list $package"
    done
    
    # Install packages based on package manager
    local install_cmd=""
    case "$PKG_MANAGER" in
        "apt")
            install_cmd="apt-get update && apt-get install -y $package_list"
            ;;
        "dnf")
            install_cmd="dnf install -y $package_list"
            ;;
        "yum")
            install_cmd="yum install -y $package_list"
            ;;
        "zypper")
            install_cmd="zypper install -y $package_list"
            ;;
        "pacman")
            install_cmd="pacman -Sy --noconfirm $package_list"
            ;;
        "apk")
            install_cmd="apk update && apk add $package_list"
            ;;
        *)
            log_warn "Unsupported package manager: $PKG_MANAGER"
            return 0
            ;;
    esac
    
    # Run virt-customize
    log_info "Running virt-customize to install packages"
    if ! virt-customize -a "/dev/pve/$disk_image" --run-command "$install_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to install packages using virt-customize"
        return 1
    fi
    
    log_success "Packages installed successfully"
    return 0
}

# Convert VM to template
convert_to_template() {
    log_info "Converting VM to template"
    
    # Stop the VM if running
    qm stop "$VMID_DEFAULT" 2>/dev/null || true
    
    # Wait for VM to fully stop
    local timeout=60
    local count=0
    
    while qm status "$VMID_DEFAULT" | grep -q "running" && [[ $count -lt $timeout ]]; do
        sleep 2
        ((count += 2))
    done
    
    if qm status "$VMID_DEFAULT" | grep -q "running"; then
        log_error "VM failed to stop within timeout"
        return 1
    fi
    
    # Convert to template
    if ! qm template "$VMID_DEFAULT" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to convert VM to template"
        return 1
    fi
    
    # Add template tags
    qm set "$VMID_DEFAULT" --tags "$TEMPLATE_TAG,${VM_CATEGORY_TAG:-general}" 2>/dev/null || true
    
    # Set template notes
    local template_notes="Template: $DIST_NAME
Created: $(date)
Packages: ${#SELECTED_PACKAGES[@]} packages
Distribution: $SELECTED_DISTRIBUTION_KEY"
    
    qm set "$VMID_DEFAULT" --description "$template_notes" 2>/dev/null || true
    
    log_success "VM converted to template successfully"
    log_success "Template VMID: $VMID_DEFAULT"
    
    return 0
}

# Main template creation function
create_template_main() {
    log_info "Starting main template creation workflow"
    
    # Validate prerequisites
    if [[ -z "$DISTRIBUTION_SELECTED" ]]; then
        log_error "No distribution selected"
        return 1
    fi
    
    # Set default VM name if not set
    if [[ -z "$VM_NAME" ]]; then
        VM_NAME="${SELECTED_DISTRIBUTION_KEY:-unknown}-template"
    fi
    
    # Get next available VMID if not set
    if [[ -z "$VMID_DEFAULT" ]]; then
        VMID_DEFAULT=$(get_next_available_vmid)
    fi
    
    # Create work directory
    WORK_DIR="/tmp/template-creation-$$"
    mkdir -p "$WORK_DIR"
    
    log_info "Creating template: $VM_NAME (VMID: $VMID_DEFAULT)"
    
    # Execute template creation steps
    if ! download_distribution_image; then
        log_error "Failed to download distribution image"
        cleanup_on_exit
        return 1
    fi
    
    if ! create_vm_from_image; then
        log_error "Failed to create VM from image"
        cleanup_on_exit
        return 1
    fi
    
    if ! configure_cloud_init; then
        log_error "Failed to configure cloud-init"
        cleanup_on_exit
        return 1
    fi
    
    if ! install_packages_virt_customize; then
        log_error "Failed to install packages"
        # Continue despite package installation failure
    fi
    
    if ! convert_to_template; then
        log_error "Failed to convert VM to template"
        cleanup_on_exit
        return 1
    fi
    
    log_success "Template creation completed successfully!"
    log_success "Template VMID: $VMID_DEFAULT"
    log_success "Template Name: $VM_NAME"
    
    # Show completion message
    whiptail --title "Template Creation Complete" \
        --msgbox "Template created successfully!

Template Name: $VM_NAME
Template VMID: $VMID_DEFAULT
Distribution: $DIST_NAME
Packages: ${#SELECTED_PACKAGES[@]} packages

The template is now ready for use." 12 60
    
    # Cleanup
    cleanup_on_exit
    
    return 0
}

# Main function to handle script execution
main() {
    log_info "Starting Proxmox Template Creator v$SCRIPT_VERSION"
    
    # Check if running as root
    check_root
    
    # Install dependencies if needed
    check_dependencies
    
    # Initialize defaults
    initialize_defaults
    
    # Set up signal handlers
    trap cleanup_on_interrupt SIGINT SIGTERM
    trap cleanup_on_exit EXIT
    
    # Parse command line arguments if provided
    if [[ $# -gt 0 ]]; then
        parse_arguments "$@"
        
        # If CLI mode is enabled, run non-interactive
        if [[ "$CLI_MODE" == "true" ]]; then
            log_info "Running in CLI mode"
            
            # Validate required parameters for CLI mode
            if [[ -z "$DISTRIBUTION_SELECTED" ]]; then
                log_error "Distribution must be specified in CLI mode"
                show_help
                exit 1
            fi
            
            # Run template creation directly
            if ! create_template_main; then
                log_error "Template creation failed in CLI mode"
                exit 1
            fi
            
            exit 0
        fi
    fi
    
    # Show welcome message
    show_welcome
    
    # Start main menu loop
    main_menu
}

# Call main function with all arguments
main "$@"
