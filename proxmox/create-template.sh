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
    # ==== NETWORK/FIREWALL DISTROS ====
    ["opnsense-latest"]="OPNsense (Latest)|https://mirror.dns-root.de/opnsense/releases/24.1/OPNsense-24.1-OpenSSL-dvd-amd64.iso|iso|-|bsd|root|8G|Firewall/Router"
    ["pfsense-latest"]="pfSense (Latest)|https://atxfiles.netgate.com/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz|iso|-|bsd|root|8G|Firewall/Router"
    ["vyos-latest"]="VyOS (Latest)|https://github.com/vyos/vyos-rolling-nightly-builds/releases/download/current/vyos-1.4-rolling-202406040317-amd64.iso|iso|apt|l26|vyos|4G|Network OS"
    ["routeros-latest"]="MikroTik RouterOS (Latest)|https://download.mikrotik.com/routeros/7.14.2/chr-7.14.2.img.zip|raw|-|l26|admin|2G|Router/Firewall"
    # ==== MINIMAL DISTROS ====
    ["tinycorelinux"]="TinyCore Linux (Latest)|http://tinycorelinux.net/14.x/x86_64/release/TinyCorePure64-current.iso|iso|tce|l26|tc|1G|Ultra-minimal"
    ["slitaz"]="SliTaz GNU/Linux (Latest)|http://mirror.slitaz.org/iso/rolling/slitaz-rolling-core64.iso|iso|tazpkg|l26|tux|1G|Minimal/Lightweight"
    ["puppy-linux"]="Puppy Linux (FossaPup64)|https://distro.ibiblio.org/puppylinux/puppy-fossa/puppy-fossapup64-9.5.iso|iso|pet|l26|root|2G|Minimal/Lightweight"
    # ==== SPECIALIZED DISTROS ====
    ["clearlinux"]="Clear Linux OS (Latest)|https://cdn.download.clearlinux.org/releases/41890/clear/clear-41890-cloud.img.xz|raw|swupd|l26|clr|8G|Performance-optimized"
    ["rescuezilla"]="Rescuezilla (Latest)|https://github.com/rescuezilla/rescuezilla/releases/download/2.5.7/rescuezilla-2.5.7-64bit.iso|iso|apt|l26|user|2G|Rescue/Backup"
    ["gparted-live"]="GParted Live (Latest)|https://downloads.sourceforge.net/gparted/gparted-live-1.6.0-6-amd64.iso|iso|apt|l26|user|1G|Partition/Rescue"
    # ==== CUSTOM ISO/IMAGE (UI/CLI Option) ====
    ["custom-iso"]="Custom ISO/Image|prompt|custom|auto|custom|custom|auto|User-supplied ISO or image"
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

# List all supported distributions (CLI and UI)
list_supported_distributions() {
    echo "\nSupported Distributions (Key | Name | Version | Notes):"
    for key in "${!DISTRO_LIST[@]}"; do
        IFS='|' read -r name url fmt pkgmgr ostype user size notes <<< "${DISTRO_LIST[$key]}"
        printf "  %-20s | %-30s | %-8s | %s\n" "$key" "$name" "$fmt" "$notes"
    done | sort
    echo
}

# === DYNAMIC DISCOVERY OF ANSIBLE PLAYBOOKS AND TERRAFORM MODULES ===

# List available Ansible playbooks (from ansible/playbooks/templates/ dir)
list_ansible_playbooks() {
    local playbook_dir="$REPO_ROOT/ansible/playbooks/templates"
    if [[ -d "$playbook_dir" ]]; then
        find "$playbook_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -exec basename {} \; 2>/dev/null | sort
    else
        log_warn "Ansible playbooks directory not found: $playbook_dir"
        return 1
    fi
}

# List available Terraform modules/scripts (from terraform dir)
list_terraform_modules() {
    local tf_dir="$REPO_ROOT/terraform"
    if [[ -d "$tf_dir" ]]; then {
        find "$tf_dir" -maxdepth 1 -type f -name '*.tf' -exec basename {} \; 2>/dev/null | sort
    else
        log_warn "Terraform directory not found: $tf_dir"
        return 1
    fi
}

# UI: Select Ansible playbooks
select_ansible_playbooks_ui() {
    local playbooks=( $(list_ansible_playbooks) )
    local options=()
    for pb in "${playbooks[@]}"; do
        options+=("$pb" "" OFF)
    done
    local selected
    selected=$(whiptail --title "Select Ansible Playbooks" --checklist "Choose Ansible playbooks to run after template creation:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    # Remove quotes and store
    SELECTED_ANSIBLE_PLAYBOOKS=()
    for pb in $selected; do
        pb="${pb//\"/}"
        SELECTED_ANSIBLE_PLAYBOOKS+=("$pb")
    done
    return 0
}

# UI: Select Terraform modules/scripts
select_terraform_modules_ui() {
    local modules=( $(list_terraform_modules) )
    local options=()
    for mod in "${modules[@]}"; do
        options+=("$mod" "" OFF)
    done
    local selected
    selected=$(whiptail --title "Select Terraform Modules" --checklist "Choose Terraform modules/scripts to apply after template creation:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3)
    [[ $? -ne 0 ]] && return 1
    # Remove quotes and store
    SELECTED_TERRAFORM_MODULES=()
    for mod in $selected; do
        mod="${mod//\"/}"
        SELECTED_TERRAFORM_MODULES+=("$mod")
    done
    return 0
}

# UI: Collect Ansible/Terraform variables
collect_ansible_vars_ui() {
    ANSIBLE_EXTRA_VARS=()
    while true; do
        local var
        var=$(whiptail --title "Ansible Variable" --inputbox "Enter Ansible variable (key=value), or leave blank to finish:" 10 60 "" 3>&1 1>&2 2>&3)
        [[ -z "$var" ]] && break
        ANSIBLE_EXTRA_VARS+=("$var")
    done
}

collect_terraform_vars_ui() {
    TERRAFORM_EXTRA_VARS=()
    while true; do
        local var
        var=$(whiptail --title "Terraform Variable" --inputbox "Enter Terraform variable (key=value), or leave blank to finish:" 10 60 "" 3>&1 1>&2 2>&3)
        [[ -z "$var" ]] && break
        TERRAFORM_EXTRA_VARS+=("$var")
    done
}

# CLI: Parse Ansible/Terraform playbook/module and variable flags
# Add to parse_cli_arguments:
#   --ansible-playbook PB1[,PB2,...]
#   --terraform-module MOD1[,MOD2,...]
#   --ansible-var key=value (repeatable)
#   --terraform-var key=value (repeatable)
parse_cli_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_cli_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME v$SCRIPT_VERSION"
                exit 0
                ;;
            --list-distributions)
                list_supported_distributions
                exit 0
                ;;
            --validate-config)
                VALIDATE_CONFIG=true
                shift
                ;;
            --import-config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --export-config)
                EXPORT_CONFIG_FILE="$2"
                shift 2
                ;;
            --batch)
                BATCH_MODE=true
                shift
                ;;
            --queue)
                QUEUE_MODE=true
                shift
                ;;
            --ansible)
                ANSIBLE_ENABLED=true
                shift
                ;;
            --terraform)
                TERRAFORM_ENABLED=true
                shift
                ;;
            --distribution|-d)
                CLI_DISTRIBUTION="$2"
                shift 2
                ;;
            --version)
                CLI_VERSION="$2"
                shift 2
                ;;
            --name|-n)
                CLI_TEMPLATE_NAME="$2"
                shift 2
                ;;
            --vmid|-i)
                CLI_VMID="$2"
                shift 2
                ;;
            --cores|-c)
                CLI_CORES="$2"
                shift 2
                ;;
            --memory|-m)
                CLI_MEMORY="$2"
                shift 2
                ;;
            --storage|-s)
                CLI_STORAGE="$2"
                shift 2
                ;;
            --disk-size)
                CLI_DISK_SIZE="$2"
                shift 2
                ;;
            --bridge)
                CLI_BRIDGE="$2"
                shift 2
                ;;
            --vlan)
                CLI_VLAN="$2"
                shift 2
                ;;
            --ssh-key)
                CLI_SSH_KEY="$2"
                shift 2
                ;;
            --user)
                CLI_USER="$2"
                shift 2
                ;;
            --packages)
                CLI_PACKAGES="$2"
                shift 2
                ;;
            --ansible-playbook)
                IFS=',' read -ra SELECTED_ANSIBLE_PLAYBOOKS <<< "$2"
                shift 2
                ;;
            --terraform-module)
                IFS=',' read -ra SELECTED_TERRAFORM_MODULES <<< "$2"
                shift 2
                ;;
            --ansible-var)
                ANSIBLE_EXTRA_VARS+=("$2")
                shift 2
                ;;
            --terraform-var)
                TERRAFORM_EXTRA_VARS+=("$2")
                shift 2
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

# Process batch file for queue mode
process_batch_file() {
    local batch_file="$1"
    if [[ ! -f "$batch_file" ]]; then
        log_error "Batch file not found: $batch_file"
        return 1
    fi
    log_info "Processing batch file: $batch_file"
    local current_template=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        # Parse config (simple key=value or sectioned INI)
        if [[ "$line" =~ ^\[TEMPLATE_ ]]; then
            ((current_template++))
            continue
        fi
        # Export variables for each template
        eval "$line"
        # After each template section, create the template
        if [[ "$line" =~ ^TEMPL_NAME_DEFAULT ]]; then
            log_info "Creating template #$current_template: $TEMPL_NAME_DEFAULT"
            create_template_main
        fi
    done < "$batch_file"
    log_success "Batch processing complete."
}

# Show welcome message
show_welcome() {
    if [[ "$QUIET_MODE" != true ]]; then
        clear
        echo "
╔══════════════════════════════════════════════════════════════════╗
║                    Proxmox Template Creator                      ║
║                        Version $SCRIPT_VERSION                   ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  Automated VM template creation for Proxmox Virtual Environment  ║
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

# Show CLI help
show_cli_help() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage:
  ./create-template.sh [OPTIONS]

Options:
  -h, --help                Show this help message
  -v, --version             Show script version
  --list-distributions      List all supported distributions
  --validate-config         Validate current configuration
  --import-config FILE      Import configuration file
  --export-config FILE      Export current configuration
  --batch                   Enable batch mode (process queue)
  --queue                   Enable queue mode (interactive)
  --ansible                 Enable Ansible integration
  --terraform               Enable Terraform integration
  -d, --distribution DIST   Set distribution key (see --list-distributions)
  --version VERSION         Set distribution version (if applicable)
  -n, --name NAME           Set template name
  -i, --vmid VMID           Set VM ID
  -c, --cores CORES         Set CPU cores
  -m, --memory MB           Set memory (MB)
  -s, --storage POOL        Set storage pool
  --disk-size SIZE          Set disk size (e.g., 20G)
  --bridge BRIDGE           Set network bridge
  --vlan VLAN               Set VLAN tag
  --ssh-key PATH            Set SSH public key file
  --user USER               Set cloud-init username
  --packages PKGS           Comma-separated package list
  --ansible-playbook PB1[,PB2,...]   Select Ansible playbooks to run
  --terraform-module MOD1[,MOD2,...] Select Terraform modules/scripts to apply
  --ansible-var key=value            Pass variable to Ansible (repeatable)
  --terraform-var key=value          Pass variable to Terraform (repeatable)
  --no-interaction          Non-interactive mode
  --dry-run                 Show actions without executing
  --verbose                 Enable verbose output
  --log-level LEVEL         Set log level (info, debug, warn, error)

Examples:
  ./create-template.sh -d ubuntu-22.04 -n dev-template -i 9000 --ansible --terraform
  ./create-template.sh --import-config my-template.conf --batch
  ./create-template.sh --list-distributions

EOF
}

# === ANSIBLE AND TERRAFORM EXECUTION FUNCTIONS ===

# Execute selected Ansible playbooks on VMs (not templates)
execute_ansible_playbooks() {
    local vm_id="$1"
    local vm_ip="$2"
    
    if [[ ${#SELECTED_ANSIBLE_PLAYBOOKS[@]} -eq 0 ]]; then
        log_info "No Ansible playbooks selected, skipping Ansible execution"
        return 0
    fi
    
    log_info "Executing Ansible playbooks on VM $vm_id ($vm_ip)"
    
    # Create temporary inventory file for this VM
    local temp_inventory="/tmp/proxmox-vm-$vm_id.yml"
    cat > "$temp_inventory" <<EOF
all:
  hosts:
    vm-$vm_id:
      ansible_host: $vm_ip
      ansible_user: ${CLOUD_USER_DEFAULT:-ubuntu}
      ansible_ssh_private_key_file: ~/.ssh/id_rsa
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    # Execute each selected playbook
    for playbook in "${SELECTED_ANSIBLE_PLAYBOOKS[@]}"; do
        local playbook_path="$REPO_ROOT/ansible/playbooks/templates/$playbook"
        if [[ -f "$playbook_path" ]]; then
            log_info "Running Ansible playbook: $playbook"
            
            # Build ansible-playbook command with variables
            local ansible_cmd="ansible-playbook -i $temp_inventory $playbook_path"
            
            # Add extra variables if provided
            for var in "${ANSIBLE_EXTRA_VARS[@]}"; do
                ansible_cmd="$ansible_cmd -e $var"
            done
            
            # Execute playbook
            if eval "$ansible_cmd"; then
                log_success "Ansible playbook $playbook completed successfully"
            else
                log_error "Ansible playbook $playbook failed"
            fi
        else
            log_warn "Ansible playbook not found: $playbook_path"
        fi
    done
    
    # Cleanup temporary inventory
    rm -f "$temp_inventory"
}

# Execute Terraform modules for template deployment
execute_terraform_modules() {
    local template_id="$1"
    local template_name="$2"
    
    if [[ ${#SELECTED_TERRAFORM_MODULES[@]} -eq 0 ]]; then
        log_info "No Terraform modules selected, skipping Terraform execution"
        return 0
    fi
    
    log_info "Executing Terraform modules for template $template_id ($template_name)"
    
    # Create temporary Terraform directory
    local temp_tf_dir="/tmp/proxmox-terraform-$$"
    mkdir -p "$temp_tf_dir"
    
    # Copy selected modules to temporary directory
    for module in "${SELECTED_TERRAFORM_MODULES[@]}"; do
        local module_path="$REPO_ROOT/terraform/$module"
        if [[ -f "$module_path" ]]; then
            cp "$module_path" "$temp_tf_dir/"
            log_info "Copied Terraform module: $module"
        else
            log_warn "Terraform module not found: $module_path"
        fi
    done
    
    # Create terraform.tfvars file with provided variables
    local tfvars_file="$temp_tf_dir/terraform.tfvars"
    cat > "$tfvars_file" <<EOF
# Auto-generated terraform.tfvars for template deployment
template_id = "$template_id"
vm_name_prefix = "${template_name}-vm-"
EOF
    
    # Add extra variables if provided
    for var in "${TERRAFORM_EXTRA_VARS[@]}"; do
        echo "$var" >> "$tfvars_file"
    done
    
    # Execute Terraform commands
    cd "$temp_tf_dir"
    
    log_info "Initializing Terraform..."
    if terraform init; then
        log_success "Terraform initialized successfully"
        
        log_info "Planning Terraform deployment..."
        if terraform plan; then
            log_success "Terraform plan completed successfully"
            
            # Ask for confirmation before applying
            if whiptail --title "Terraform Apply" \
                --yesno "Terraform plan completed. Apply changes to deploy VMs from template?" 8 60; then
                
                log_info "Applying Terraform configuration..."
                if terraform apply -auto-approve; then
                    log_success "Terraform apply completed successfully"
                    
                    # Show outputs if available
                    log_info "Terraform outputs:"
                    terraform output
                else
                    log_error "Terraform apply failed"
                fi
            else
                log_info "Terraform apply cancelled by user"
            fi
        else
            log_error "Terraform plan failed"
        fi
    else
        log_error "Terraform initialization failed"
    fi
    
    # Return to original directory
    cd - > /dev/null
    
    # Cleanup (optional - user might want to inspect)
    if [[ "$TERRAFORM_CLEANUP_TEMP" == "true" ]]; then
        rm -rf "$temp_tf_dir"
    else
        log_info "Terraform files preserved in: $temp_tf_dir"
    fi
}

# Create VM from template and run Ansible if configured
deploy_vm_from_template() {
    local template_id="$1"
    local vm_name="$2"
    local vm_id="$3"
    
    log_info "Deploying VM $vm_name (ID: $vm_id) from template $template_id"
    
    # Clone template to create VM
    if qm clone "$template_id" "$vm_id" --name "$vm_name"; then
        log_success "VM $vm_name created from template"
        
        # Start the VM
        if qm start "$vm_id"; then
            log_success "VM $vm_name started"
            
            # Wait for VM to get IP address
            log_info "Waiting for VM to obtain IP address..."
            local vm_ip=""
            local retry_count=0
            local max_retries=30
            
            while [[ -z "$vm_ip" && $retry_count -lt $max_retries ]]; do
                sleep 10
                vm_ip=$(qm guest cmd "$vm_id" network-get-interfaces 2>/dev/null | jq -r '.[] | select(.name=="eth0") | .["ip-addresses"][] | select(.["ip-address-type"]=="ipv4") | .["ip-address"]' 2>/dev/null | head -1)
                ((retry_count++))
            done
            
            if [[ -n "$vm_ip" ]]; then
                log_success "VM IP address: $vm_ip"
                
                # Execute Ansible playbooks if configured
                if [[ "$ANSIBLE_ENABLED" == "true" && ${#SELECTED_ANSIBLE_PLAYBOOKS[@]} -gt 0 ]]; then
                    log_info "Waiting for SSH to be available..."
                    sleep 30  # Additional wait for SSH service
                    execute_ansible_playbooks "$vm_id" "$vm_ip"
                fi
            else
                log_warn "Could not determine VM IP address"
            fi
        else
            log_error "Failed to start VM $vm_name"
        fi
    else
        log_error "Failed to create VM from template"
        return 1
    fi
}
#===============================================================================
# MISSING CORE FUNCTIONS IMPLEMENTATION
#===============================================================================

# Main entry point function
main() {
    # Initialize script
    initialize_script
    
    # Parse command line arguments
    if [[ $# -gt 0 ]]; then
        parse_cli_arguments "$@"
        run_cli_mode
    else
        # Show welcome and run interactive mode
        show_welcome
        show_main_menu
    fi
}

# Select distribution interactively
select_distribution() {
    local dist_options=()
    local categories=()
    
    # Build distribution list by categories
    for category in ubuntu debian rhel fedora suse arch security container bsd minimal network specialized custom; do
        local category_dists=()
        for key in "${!DISTRO_LIST[@]}"; do
            case "$key" in
                ubuntu-*) [[ "$category" == "ubuntu" ]] && category_dists+=("$key") ;;
                debian-*) [[ "$category" == "debian" ]] && category_dists+=("$key") ;;
                centos-*|rhel-*|rocky-*|almalinux-*|oracle-*) [[ "$category" == "rhel" ]] && category_dists+=("$key") ;;
                fedora-*) [[ "$category" == "fedora" ]] && category_dists+=("$key") ;;
                opensuse-*) [[ "$category" == "suse" ]] && category_dists+=("$key") ;;
                arch*) [[ "$category" == "arch" ]] && category_dists+=("$key") ;;
                kali-*|parrot-*) [[ "$category" == "security" ]] && category_dists+=("$key") ;;
                talos-*|flatcar|bottlerocket) [[ "$category" == "container" ]] && category_dists+=("$key") ;;
                freebsd-*|openbsd-*|netbsd-*) [[ "$category" == "bsd" ]] && category_dists+=("$key") ;;
                alpine-*|tinycorelinux|slitaz|puppy-*) [[ "$category" == "minimal" ]] && category_dists+=("$key") ;;
                opnsense-*|pfsense-*|vyos-*|routeros-*) [[ "$category" == "network" ]] && category_dists+=("$key") ;;
                clearlinux|rescuezilla|gparted-*) [[ "$category" == "specialized" ]] && category_dists+=("$key") ;;
                custom-*) [[ "$category" == "custom" ]] && category_dists+=("$key") ;;
            esac
        done
        
        if [[ ${#category_dists[@]} -gt 0 ]]; then
            categories+=("$category")
        fi
    done
    
    # Select category first
    local cat_options=()
    for cat in "${categories[@]}"; do
        case "$cat" in
            ubuntu) cat_options+=("$cat" "Ubuntu Family (LTS and Latest)") ;;
            debian) cat_options+=("$cat" "Debian Family (Stable and Testing)") ;;
            rhel) cat_options+=("$cat" "Red Hat Enterprise Family") ;;
            fedora) cat_options+=("$cat" "Fedora") ;;
            suse) cat_options+=("$cat" "SUSE Family") ;;
            arch) cat_options+=("$cat" "Arch Linux Family") ;;
            security) cat_options+=("$cat" "Security-Focused Distributions") ;;
            container) cat_options+=("$cat" "Container-Optimized") ;;
            bsd) cat_options+=("$cat" "BSD Systems") ;;
            minimal) cat_options+=("$cat" "Minimal/Lightweight") ;;
            network) cat_options+=("$cat" "Network/Firewall") ;;
            specialized) cat_options+=("$cat" "Specialized/Rescue") ;;
            custom) cat_options+=("$cat" "Custom ISO/Image") ;;
        esac
    done
    
    local selected_category
    selected_category=$(whiptail --title "Select Distribution Category" \
        --menu "Choose a distribution category:" 20 80 10 \
        "${cat_options[@]}" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    # Now show distributions in selected category
    local dist_options=()
    for key in "${!DISTRO_LIST[@]}"; do
        local match=false
        case "$key" in
            ubuntu-*) [[ "$selected_category" == "ubuntu" ]] && match=true ;;
            debian-*) [[ "$selected_category" == "debian" ]] && match=true ;;
            centos-*|rhel-*|rocky-*|almalinux-*|oracle-*) [[ "$selected_category" == "rhel" ]] && match=true ;;
            fedora-*) [[ "$selected_category" == "fedora" ]] && match=true ;;
            opensuse-*) [[ "$selected_category" == "suse" ]] && match=true ;;
            arch*) [[ "$selected_category" == "arch" ]] && match=true ;;
            kali-*|parrot-*) [[ "$selected_category" == "security" ]] && match=true ;;
            talos-*|flatcar|bottlerocket) [[ "$selected_category" == "container" ]] && match=true ;;
            freebsd-*|openbsd-*|netbsd-*) [[ "$selected_category" == "bsd" ]] && match=true ;;
            alpine-*|tinycorelinux|slitaz|puppy-*) [[ "$selected_category" == "minimal" ]] && match=true ;;
            opnsense-*|pfsense-*|vyos-*|routeros-*) [[ "$selected_category" == "network" ]] && match=true ;;
            clearlinux|rescuezilla|gparted-*) [[ "$selected_category" == "specialized" ]] && match=true ;;
            custom-*) [[ "$selected_category" == "custom" ]] && match=true ;;
        esac
        
        if [[ "$match" == true ]]; then
            IFS='|' read -r name url fmt pkgmgr ostype user size notes <<< "${DISTRO_LIST[$key]}"
            dist_options+=("$key" "$name - $notes")
        fi
    done
    
    local selected_dist
    selected_dist=$(whiptail --title "Select Distribution" \
        --menu "Choose a distribution:" 20 80 10 \
        "${dist_options[@]}" \
        3>&1 1>&2 2>&3)
    
    [[ $? -ne 0 ]] && return 1
    
    SELECTED_DISTRIBUTION="${DISTRO_LIST[$selected_dist]}"
    SELECTED_DISTRIBUTION_KEY="$selected_dist"
    
    log_info "Selected distribution: $selected_dist"
    return 0
}

# Core template creation function
create_template_main() {
    log_info "Starting template creation process"
    
    # Parse distribution details
    IFS='|' read -r dist_name dist_url dist_format dist_pkgmgr dist_ostype dist_user dist_size dist_notes <<< "$SELECTED_DISTRIBUTION"
    
    # Set defaults from distribution if not already set
    VM_NAME="${VM_NAME:-${SELECTED_DISTRIBUTION_KEY}-template}"
    VMID_DEFAULT="${VMID_DEFAULT:-$(get_next_available_vmid)}"
    VM_MEMORY="${VM_MEMORY:-2048}"
    VM_CORES="${VM_CORES:-2}"
    VM_DISK_SIZE="${VM_DISK_SIZE:-$dist_size}"
    VM_STORAGE="${VM_STORAGE:-local-lvm}"
    CLOUD_USER_DEFAULT="${CLOUD_USER_DEFAULT:-$dist_user}"
    
    log_info "Creating template: $VM_NAME (ID: $VMID_DEFAULT)"
    log_info "Distribution: $dist_name"
    log_info "Format: $dist_format, Package Manager: $dist_pkgmgr"
    
    # Download image if needed
    local image_path
    image_path=$(download_distribution_image "$dist_url" "$dist_format")
    [[ $? -ne 0 ]] && return 1
    
    # Create VM
    if ! create_vm_from_image "$image_path" "$dist_format"; then
        log_error "Failed to create VM from image"
        return 1
    fi
    
    # Configure cloud-init
    if ! configure_cloud_init; then
        log_error "Failed to configure cloud-init"
        return 1
    fi
    
    # Install packages if selected
    if [[ ${#SELECTED_PACKAGES[@]} -gt 0 ]]; then
        if ! install_packages_virt_customize "$image_path" "$dist_pkgmgr"; then
            log_error "Failed to install packages"
            return 1
        fi
    fi
    
    # Convert to template
    if ! convert_to_template; then
        log_error "Failed to convert VM to template"
        return 1
    fi
    
    # Execute Terraform modules if selected (for template deployment)
    if [[ "$TERRAFORM_ENABLED" == "true" && ${#SELECTED_TERRAFORM_MODULES[@]} -gt 0 ]]; then
        execute_terraform_modules "$VMID_DEFAULT" "$VM_NAME"
    fi
    
    log_success "Template creation completed successfully!"
    log_info "Template ID: $VMID_DEFAULT"
    log_info "Template Name: $VM_NAME"
    
    return 0
}

# Get next available VM ID
get_next_available_vmid() {
    local start_id="${VMID_DEFAULT:-9000}"
    local current_id="$start_id"
    
    while qm status "$current_id" &>/dev/null; do
        ((current_id++))
    done
    
    echo "$current_id"
}

# Download distribution image
download_distribution_image() {
    local url="$1"
    local format="$2"
    local filename=$(basename "$url")
    local download_path="$SCRIPT_DIR/temp/$filename"
    
    # Create temp directory
    mkdir -p "$SCRIPT_DIR/temp"
    
    # Skip download if file already exists and is valid
    if [[ -f "$download_path" ]]; then
        log_info "Image already exists: $download_path"
        echo "$download_path"
        return 0
    fi
    
    log_info "Downloading image: $url"
    if wget -q --show-progress -O "$download_path" "$url"; then
        log_success "Image downloaded: $download_path"
        echo "$download_path"
        return 0
    else
        log_error "Failed to download image: $url"
        return 1
    fi
}

# Create VM from image
create_vm_from_image() {
    local image_path="$1"
    local format="$2"
    
    log_info "Creating VM from image: $image_path"
    
    # Create VM with basic configuration
    if qm create "$VMID_DEFAULT" \
        --name "$VM_NAME" \
        --memory "$VM_MEMORY" \
        --cores "$VM_CORES" \
        --net0 "virtio,bridge=$NETWORK_BRIDGE" \
        --ostype "$OS_TYPE" \
        --agent 1; then
        
        log_success "VM $VMID_DEFAULT created successfully"
        
        # Import disk
        local disk_import_cmd="qm importdisk $VMID_DEFAULT $image_path $VM_STORAGE"
        if $disk_import_cmd; then
            log_success "Disk imported successfully"
            
            # Set boot disk
            if qm set "$VMID_DEFAULT" --scsi0 "$VM_STORAGE:vm-$VMID_DEFAULT-disk-0"; then
                log_success "Boot disk configured"
                return 0
            else
                log_error "Failed to configure boot disk"
                return 1
            fi
        else
            log_error "Failed to import disk"
            return 1
        fi
    else
        log_error "Failed to create VM"
        return 1
    fi
}

# Configure cloud-init
configure_cloud_init() {
    log_info "Configuring cloud-init for VM $VMID_DEFAULT"
    
    local cloud_init_cmd="qm set $VMID_DEFAULT"
    cloud_init_cmd="$cloud_init_cmd --ide2 $VM_STORAGE:cloudinit"
    cloud_init_cmd="$cloud_init_cmd --boot c --bootdisk scsi0"
    cloud_init_cmd="$cloud_init_cmd --serial0 socket --vga serial0"
    
    # Set cloud-init user
    if [[ -n "$CLOUD_USER_DEFAULT" ]]; then
        cloud_init_cmd="$cloud_init_cmd --ciuser $CLOUD_USER_DEFAULT"
    fi
    
    # Set SSH key if provided
    if [[ -n "$SSH_KEY" ]]; then
        cloud_init_cmd="$cloud_init_cmd --sshkey \"$SSH_KEY\""
    fi
    
    # Execute cloud-init configuration
    if eval "$cloud_init_cmd"; then
        log_success "Cloud-init configured successfully"
        return 0
    else
        log_error "Failed to configure cloud-init"
        return 1
    fi
}

# Install packages using virt-customize
install_packages_virt_customize() {
    local image_path="$1"
    local pkg_manager="$2"
    
    log_info "Installing ${#SELECTED_PACKAGES[@]} packages using virt-customize"
    
    local install_cmd="virt-customize -a $image_path"
    
    # Build package installation command based on package manager
    case "$pkg_manager" in
        apt)
            install_cmd="$install_cmd --update"
            install_cmd="$install_cmd --install $(IFS=','; echo "${SELECTED_PACKAGES[*]}")"
            ;;
        dnf|yum)
            install_cmd="$install_cmd --run-command 'dnf update -y'"
            install_cmd="$install_cmd --install $(IFS=','; echo "${SELECTED_PACKAGES[*]}")"
            ;;
        zypper)
            install_cmd="$install_cmd --run-command 'zypper refresh'"
            install_cmd="$install_cmd --install $(IFS=','; echo "${SELECTED_PACKAGES[*]}")"
            ;;
        *)
            log_warn "Package manager $pkg_manager not fully supported, skipping package installation"
            return 0
            ;;
    esac
    
    # Execute package installation
    if eval "$install_cmd"; then
        log_success "Packages installed successfully"
        return 0
    else
        log_error "Failed to install packages"
        return 1
    fi
}

# Convert VM to template
convert_to_template() {
    log_info "Converting VM $VMID_DEFAULT to template"
    
    if qm template "$VMID_DEFAULT"; then
        log_success "VM successfully converted to template"
        
        # Add template tag
        if qm set "$VMID_DEFAULT" --tags "template"; then
            log_success "Template tagged successfully"
        fi
        
        return 0
    else
        log_error "Failed to convert VM to template"
        return 1
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
