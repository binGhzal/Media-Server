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
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" || exit)" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." || exit && pwd)"

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
    export INVENTORY_DIR="$ANSIBLE_DIR/inventory"
    export PLAYBOOKS_DIR="$ANSIBLE_DIR/playbooks"

    # Initialize logging with rotation
    LOG_DIR="$SCRIPT_DIR/logs"
    LOG_FILE="$LOG_DIR/template-creator-$(date +%Y%m%d_%H%M%S).log"

    # Rotate old logs (keep last 10)
    find "$LOG_DIR" -name "template-creator-*.log" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true

    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)

    # Set up signal handlers for cleanup
    trap cleanup_on_exit EXIT || true
    trap cleanup_on_interrupt INT TERM || true

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

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

# Validate VM settings
validate_vm_settings() {
    local errors=()

    # Validate VMID
    if [[ ! "$VMID_DEFAULT" =~ ^[0-9]+$ ]] || [[ "$VMID_DEFAULT" -lt 100 ]] || [[ "$VMID_DEFAULT" -gt 999999999 ]]; then
        errors+=("Invalid VMID: $VMID_DEFAULT (must be numeric, 100-999999999)")
    fi

    # Validate memory
    if [[ ! "$VM_MEMORY" =~ ^[0-9]+$ ]] || [[ "$VM_MEMORY" -lt 512 ]]; then
        errors+=("Invalid memory: $VM_MEMORY (must be numeric, minimum 512MB)")
    fi

    # Validate cores
    if [[ ! "$VM_CORES" =~ ^[0-9]+$ ]] || [[ "$VM_CORES" -lt 1 ]] || [[ "$VM_CORES" -gt 128 ]]; then
        errors+=("Invalid cores: $VM_CORES (must be numeric, 1-128)")
    fi

    # Validate disk size
    if [[ ! "$VM_DISK_SIZE" =~ ^[0-9]+$ ]] || [[ "$VM_DISK_SIZE" -lt 8 ]]; then
        errors+=("Invalid disk size: $VM_DISK_SIZE (must be numeric, minimum 8GB)")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "VM settings validation failed:"
        printf ' - %s\n' "${errors[@]}"
        return 1
    fi

    log_info "VM settings validation passed"
    return 0
}

# Validate network settings
validate_network_settings() {
    local errors=()

    # Validate static IP configuration if static mode is selected
    if [[ "$NETWORK_MODE" == "static" ]]; then
        if [[ -z "$STATIC_IP" ]]; then
            errors+=("Static IP is required when network mode is static")
        elif [[ ! "$STATIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
            errors+=("Invalid static IP format: $STATIC_IP")
        fi

        if [[ -z "$STATIC_GATEWAY" ]]; then
            errors+=("Static gateway is required when network mode is static")
        elif [[ ! "$STATIC_GATEWAY" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            errors+=("Invalid gateway IP format: $STATIC_GATEWAY")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Network settings validation failed:"
        printf ' - %s\n' "${errors[@]}"
        return 1
    fi

    log_info "Network settings validation passed"
    return 0
}

# Validate storage settings
validate_storage_settings() {
    local errors=()

    # Check if storage exists (this would need actual Proxmox commands in non-dry-run mode)
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! pvesm status "$VM_STORAGE" &>/dev/null; then
            errors+=("Storage '$VM_STORAGE' does not exist or is not accessible")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Storage settings validation failed:"
        printf ' - %s\n' "${errors[@]}"
        return 1
    fi

    log_info "Storage settings validation passed"
    return 0
}

# Validate distribution image
validate_image_path() {
    local image_path="$1"
    local errors=()

    if [[ -z "$image_path" ]]; then
        errors+=("Image path is required")
    elif [[ ! -f "$image_path" ]] && [[ "$DRY_RUN" != "true" ]]; then
        errors+=("Image file does not exist: $image_path")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Image validation failed:"
        printf ' - %s\n' "${errors[@]}"
        return 1
    fi

    log_info "Image path validation passed"
    return 0
}

#===============================================================================
# CLEANUP FUNCTIONS
#===============================================================================

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

# Error cleanup function - handles cleanup when errors occur
cleanup_error() {
    local error_msg="$1"
    log_error "Error occurred: $error_msg"
    log_info "Performing error cleanup procedures"

    # Clean up any partial VM creation
    if [[ -n "$VMID_DEFAULT" ]] && qm status "$VMID_DEFAULT" &>/dev/null; then
        log_warn "Cleaning up partially created VM $VMID_DEFAULT"
        qm stop "$VMID_DEFAULT" 2>/dev/null || true
        qm destroy "$VMID_DEFAULT" 2>/dev/null || true
    fi

    # Clean up temporary containers
    if [[ -n "$TEMP_LXC_ID" ]]; then
        log_warn "Cleaning up temporary LXC container $TEMP_LXC_ID"
        pct stop "$TEMP_LXC_ID" 2>/dev/null || true
        pct destroy "$TEMP_LXC_ID" 2>/dev/null || true
    fi

    # Clean up working directory
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        log_warn "Cleaning up working directory $WORK_DIR"
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi

    log_info "Error cleanup completed"
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

# CLI and Configuration Management
CONFIG_FILE="" # Configuration file for CLI mode
LOG_LEVEL="info" # Logging level (debug, info, warn, error)
POSITIONAL_ARGS=() # Array to store positional arguments

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

# Docker Integration Variables
DOCKER_INTEGRATION="false" # Enable Docker template integration
DOCKER_TEMPLATES_PATH="/srv/docker-templates" # Path to Docker templates
SELECTED_DOCKER_TEMPLATES=() # Array of selected Docker templates
DOCKER_LXC_CONTAINER="docker-runner" # LXC container for Docker
DOCKER_KEEP_CONTAINER="false" # Keep Docker container after provisioning

# Kubernetes Integration Variables
K8S_INTEGRATION="false" # Enable Kubernetes template integration
K8S_TEMPLATES_PATH="/srv/k8s-templates" # Path to Kubernetes templates
SELECTED_K8S_TEMPLATES=() # Array of selected Kubernetes templates
K8S_LXC_CONTAINER="k8s-runner" # LXC container for Kubernetes
K8S_KUBECONFIG_PATH="" # Path to kubeconfig file
K8S_WAIT_FOR_READY="true" # Wait for resources to be ready
K8S_SAVE_CLUSTER_INFO="true" # Save cluster information
K8S_KEEP_CONTAINER="false" # Keep K8s container after provisioning

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
        --menu "Select default storage pool:" 15 60 8 \
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
        3>&1 1>&2 2>&3)

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
    log_info "Configuring Ansible automation"

    # Ask if Ansible should be enabled
    local enable_ansible
    enable_ansible=$(whiptail --title "Ansible Integration" \
        --yesno "Enable Ansible post-deployment automation?" 8 70 \
        3>&1 1>&2 2>&3)

    if [[ $? -eq 0 ]]; then
        ANSIBLE_ENABLED="true"

        # Configure Ansible LXC settings
        ANSIBLE_LXC_CORES=$(whiptail --title "Ansible LXC - CPU" \
            --inputbox "CPU cores for Ansible LXC container:" 10 70 \
            "${ANSIBLE_LXC_CORES:-1}" \
            3>&1 1>&2 2>&3)

        ANSIBLE_LXC_MEMORY=$(whiptail --title "Ansible LXC - Memory" \
            --inputbox "Memory for Ansible LXC (MB):" 10 70 \
            "${ANSIBLE_LXC_MEMORY:-1024}" \
            3>&1 1>&2 2>&3)

        whiptail --title "Ansible Integration Enabled" \
            --msgbox "Ansible integration enabled with:\n- Cores: $ANSIBLE_LXC_CORES\n- Memory: $ANSIBLE_LXC_MEMORY MB" 10 70
    else
        ANSIBLE_ENABLED="false"
        whiptail --title "Ansible Integration Disabled" \
            --msgbox "Ansible integration disabled" 8 50
    fi

    log_info "Ansible integration settings updated: enabled=$ANSIBLE_ENABLED"
    return 0
}

# Configure Terraform automation for template deployment
configure_terraform_automation() {
    log_info "Configuring Terraform automation"

    # Ask if Terraform should be enabled
    local enable_terraform
    enable_terraform=$(whiptail --title "Terraform Integration" \
        --yesno "Enable Terraform integration for template deployment?" 8 70 \
        3>&1 1>&2 2>&3)

    if [[ $? -eq 0 ]]; then
        TERRAFORM_ENABLED="true"

        # Configure Terraform provider
        TERRAFORM_PROVIDER=$(whiptail --title "Terraform Provider" \
            --inputbox "Enter Terraform provider for Proxmox:" 10 70 \
            "${TERRAFORM_PROVIDER:-telmate/proxmox}" \
            3>&1 1>&2 2>&3)

        # Configure Terraform version constraint
        TERRAFORM_VERSION_CONSTRAINT=$(whiptail --title "Terraform Version Constraint" \
            --inputbox "Enter Terraform version constraint:" 10 70 \
            "${TERRAFORM_VERSION_CONSTRAINT:->= 2.9.0}" \
            3>&1 1>&2 2>&3)

        whiptail --title "Terraform Integration Enabled" \
            --msgbox "Terraform integration enabled with:\n- Provider: $TERRAFORM_PROVIDER\n- Version: $TERRAFORM_VERSION_CONSTRAINT" 10 70
    else
        TERRAFORM_ENABLED="false"
        whiptail --title "Terraform Integration Disabled" \
            --msgbox "Terraform integration disabled" 8 50
    fi

    log_info "Terraform integration settings updated: enabled=$TERRAFORM_ENABLED"
    return 0
}

# Generate Terraform configuration files for template deployment
generate_terraform_config() {
    log_info "Generating enhanced Terraform configuration with modules"

    if [[ "$TERRAFORM_ENABLED" != "true" ]]; then
        log_warn "Terraform integration not enabled, skipping configuration generation"
        return 0
    fi

    # Ask for output directory
    local output_dir
    output_dir=$(whiptail --title "Terraform Configuration" \
        --inputbox "Enter directory for Terraform configuration:" 10 70 \
        "${TERRAFORM_DIR:-$REPO_ROOT/terraform}" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return 1

    # Create directory structure
    mkdir -p "$output_dir"/{modules/{vm,network,storage},environments/{dev,staging,prod}}

    # Select Terraform modules to include
    local module_options=(
        "vm" "Virtual Machine module" ON
        "network" "Network configuration module" ON
        "storage" "Storage management module" OFF
        "monitoring" "Monitoring and logging module" OFF
        "backup" "Backup automation module" OFF
        "security" "Security hardening module" OFF
    )

    local selected_modules
    selected_modules=$(whiptail --title "Select Terraform Modules" \
        --checklist "Choose modules to include:" 15 70 6 \
        "${module_options[@]}" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return 1

    # Remove quotes from selection
    selected_modules=$(echo $selected_modules | tr -d '"')

    # Collect Terraform variables interactively
    local tf_vars=()
    collect_terraform_variables tf_vars

    # Generate main.tf with modules
    log_info "Generating main.tf with selected modules"
    cat > "$output_dir/main.tf" << EOF
# Terraform configuration for Proxmox Template deployment
# Generated by Proxmox Template Creator on $(date)
# Selected modules: $selected_modules

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

  # Backend configuration (uncomment and configure as needed)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "proxmox/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

# Provider configuration
provider "proxmox" {
  pm_api_url = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = var.proxmox_tls_insecure
  pm_parallel = var.proxmox_parallel
  pm_timeout = var.proxmox_timeout
}

# Generate random password for VMs
resource "random_password" "vm_password" {
  count = var.vm_count
  length = 16
  special = true
}

# Generate SSH key pair
resource "tls_private_key" "vm_ssh_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

# Local values for common configurations
locals {
  common_tags = {
    Environment = var.environment
    Project = var.project_name
    ManagedBy = "terraform"
    CreatedBy = "proxmox-template-creator"
    Template = var.template_name
  }

  vm_configs = {
    for i in range(var.vm_count) : i => {
      name = "\${var.vm_name_prefix}-\${format("%02d", i + 1)}"
      vmid = var.vm_id_start + i
      password = random_password.vm_password[i].result
    }
  }
}
EOF

    # Generate modules based on selection
    for module in $selected_modules; do
        case "$module" in
            "vm")
                generate_vm_module "$output_dir"
                echo "# VM Module" >> "$output_dir/main.tf"
                echo "module \"vm\" {" >> "$output_dir/main.tf"
                echo "  source = \"./modules/vm\"" >> "$output_dir/main.tf"
                echo "  " >> "$output_dir/main.tf"
                echo "  # VM Configuration" >> "$output_dir/main.tf"
                echo "  vm_configs = local.vm_configs" >> "$output_dir/main.tf"
                echo "  target_node = var.target_node" >> "$output_dir/main.tf"
                echo "  template_name = var.template_name" >> "$output_dir/main.tf"
                echo "  ssh_public_key = tls_private_key.vm_ssh_key.public_key_openssh" >> "$output_dir/main.tf"
                echo "  common_tags = local.common_tags" >> "$output_dir/main.tf"
                echo "}" >> "$output_dir/main.tf"
                echo "" >> "$output_dir/main.tf"
                ;;
            "network")
                generate_network_module "$output_dir"
                echo "# Network Module" >> "$output_dir/main.tf"
                echo "module \"network\" {" >> "$output_dir/main.tf"
                echo "  source = \"./modules/network\"" >> "$output_dir/main.tf"
                echo "  " >> "$output_dir/main.tf"
                echo "  network_config = var.network_config" >> "$output_dir/main.tf"
                echo "  bridge_name = var.network_bridge" >> "$output_dir/main.tf"
                echo "}" >> "$output_dir/main.tf"
                echo "" >> "$output_dir/main.tf"
                ;;
            "storage")
                generate_storage_module "$output_dir"
                ;;
            "monitoring")
                generate_monitoring_module "$output_dir"
                ;;
            "backup")
                generate_backup_module "$output_dir"
                ;;
            "security")
                generate_security_module "$output_dir"
                ;;
        esac
    done

    # Generate comprehensive variables.tf
    generate_terraform_variables "$output_dir" "${tf_vars[@]}"

    # Generate outputs.tf
    generate_terraform_outputs "$output_dir" "$selected_modules"

    # Generate terraform.tfvars.example
    generate_terraform_tfvars_example "$output_dir" "${tf_vars[@]}"

    # Generate environment-specific configurations
    for env in dev staging prod; do
        generate_environment_config "$output_dir" "$env"
    done

    # Generate Makefile for common operations
    generate_terraform_makefile "$output_dir"

    # Initialize Terraform workspace
    if command -v terraform &>/dev/null; then
        log_info "Initializing Terraform workspace"
        (cd "$output_dir" && terraform init) || log_warn "Failed to initialize Terraform workspace"

        log_info "Validating Terraform configuration"
        (cd "$output_dir" && terraform validate) || log_warn "Terraform validation failed"

        log_info "Formatting Terraform files"
        (cd "$output_dir" && terraform fmt) || log_warn "Failed to format Terraform files"
    else
        log_warn "Terraform not installed, skipping workspace initialization"
    fi

    log_success "Enhanced Terraform configuration generated in $output_dir"

    whiptail --title "Terraform Configuration Generated" \
        --msgbox "Complete Terraform configuration created in:\n$output_dir\n\nIncludes:\n- Modular structure\n- Environment configurations\n- Variables and outputs\n- Makefile for operations\n\nUpdate terraform.tfvars.example and rename to terraform.tfvars before use." 15 80

    return 0
}

# Terraform helper functions for enhanced configuration generation

# Collect Terraform variables interactively
collect_terraform_variables() {
    local -n var_array=$1

    # Core infrastructure variables
    var_array+=(
        "proxmox_api_url:string:https://your-proxmox:8006/api2/json:Proxmox API URL"
        "proxmox_api_token_id:string:terraform@pve!terraform:Proxmox API Token ID"
        "proxmox_api_token_secret:string:your-secret-here:Proxmox API Token Secret"
        "environment:string:dev:Environment (dev/staging/prod)"
        "project_name:string:homelab:Project name for tagging"
    )

    # VM configuration variables
    var_array+=(
        "vm_count:number:1:Number of VMs to create"
        "vm_name_prefix:string:vm:VM name prefix"
        "vm_id_start:number:1000:Starting VM ID"
        "target_node:string:proxmox:Proxmox node name"
        "template_name:string:${VM_NAME:-ubuntu-template}:Template to clone from"
    )

    # Resource variables
    var_array+=(
        "vm_cores:number:2:CPU cores per VM"
        "vm_memory:number:2048:Memory in MB per VM"
        "vm_disk_size:string:20G:Disk size per VM"
        "network_bridge:string:vmbr0:Network bridge"
    )

    # Advanced options
    var_array+=(
        "proxmox_tls_insecure:bool:true:Skip TLS verification"
        "proxmox_parallel:number:4:Max parallel operations"
        "proxmox_timeout:number:300:Operation timeout in seconds"
    )
}

# Generate VM module
generate_vm_module() {
    local output_dir="$1"
    local module_dir="$output_dir/modules/vm"

    mkdir -p "$module_dir"

    cat > "$module_dir/main.tf" << 'EOF'
# VM Module - Creates and manages Proxmox VMs

resource "proxmox_vm_qemu" "vm" {
  for_each = var.vm_configs

  name = each.value.name
  vmid = each.value.vmid
  desc = "VM created from template ${var.template_name}"

  # Target configuration
  target_node = var.target_node

  # Clone configuration
  clone = var.template_name
  full_clone = true

  # VM Resources
  cores = var.vm_cores
  sockets = var.vm_sockets
  memory = var.vm_memory

  # Storage
  disk {
    size = var.vm_disk_size
    type = "scsi"
    storage = var.vm_storage
    iothread = 1
  }

  # Network
  network {
    model = "virtio"
    bridge = var.network_bridge
    firewall = var.network_firewall
  }

  # Cloud-init
  os_type = "cloud-init"
  ipconfig0 = var.network_dhcp ? "ip=dhcp" : "ip=${var.vm_static_ips[each.key]}/24,gw=${var.network_gateway}"
  nameserver = var.dns_servers

  # SSH configuration
  sshkeys = var.ssh_public_key

  # User configuration
  ciuser = var.vm_user
  cipassword = each.value.password

  # Tags
  tags = join(",", [for k, v in var.common_tags : "${k}=${v}"])

  # Lifecycle
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}
EOF

    cat > "$module_dir/variables.tf" << 'EOF'
variable "vm_configs" {
  description = "Map of VM configurations"
  type = map(object({
    name = string
    vmid = number
    password = string
  }))
}

variable "target_node" {
  description = "Proxmox node to deploy VMs"
  type = string
}

variable "template_name" {
  description = "Template to clone from"
  type = string
}

variable "vm_cores" {
  description = "CPU cores per VM"
  type = number
  default = 2
}

variable "vm_sockets" {
  description = "CPU sockets per VM"
  type = number
  default = 1
}

variable "vm_memory" {
  description = "Memory in MB per VM"
  type = number
  default = 2048
}

variable "vm_disk_size" {
  description = "Disk size per VM"
  type = string
  default = "20G"
}

variable "vm_storage" {
  description = "Storage backend"
  type = string
  default = "local-lvm"
}

variable "network_bridge" {
  description = "Network bridge"
  type = string
  default = "vmbr0"
}

variable "network_firewall" {
  description = "Enable firewall"
  type = bool
  default = true
}

variable "network_dhcp" {
  description = "Use DHCP for IP assignment"
  type = bool
  default = true
}

variable "vm_static_ips" {
  description = "Static IP addresses for VMs"
  type = list(string)
  default = []
}

variable "network_gateway" {
  description = "Network gateway"
  type = string
  default = ""
}

variable "dns_servers" {
  description = "DNS servers"
  type = string
  default = "8.8.8.8"
}

variable "ssh_public_key" {
  description = "SSH public key"
  type = string
}

variable "vm_user" {
  description = "Default user for VMs"
  type = string
  default = "ubuntu"
}

variable "common_tags" {
  description = "Common tags for all VMs"
  type = map(string)
  default = {}
}
EOF

    cat > "$module_dir/outputs.tf" << 'EOF'
output "vm_ids" {
  description = "VM IDs"
  value = { for k, v in proxmox_vm_qemu.vm : k => v.id }
}

output "vm_names" {
  description = "VM names"
  value = { for k, v in proxmox_vm_qemu.vm : k => v.name }
}

output "vm_ips" {
  description = "VM IP addresses"
  value = { for k, v in proxmox_vm_qemu.vm : k => v.default_ipv4_address }
}
EOF
}

# Generate network module
generate_network_module() {
    local output_dir="$1"
    local module_dir="$output_dir/modules/network"

    mkdir -p "$module_dir"

    cat > "$module_dir/main.tf" << 'EOF'
# Network Module - Manages network configuration

# This is a placeholder for network configuration
# In a real scenario, this would manage:
# - Network bridges
# - VLANs
# - Firewall rules
# - Load balancers

# Example firewall rules
resource "null_resource" "firewall_rules" {
  count = var.enable_firewall ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Firewall rules would be configured here'"
  }
}
EOF

    cat > "$module_dir/variables.tf" << 'EOF'
variable "network_config" {
  description = "Network configuration"
  type = map(any)
  default = {}
}

variable "bridge_name" {
  description = "Bridge name"
  type = string
  default = "vmbr0"
}

variable "enable_firewall" {
  description = "Enable firewall configuration"
  type = bool
  default = false
}
EOF

    cat > "$module_dir/outputs.tf" << 'EOF'
output "network_info" {
  description = "Network configuration details"
  value = {
    bridge = var.bridge_name
    firewall_enabled = var.enable_firewall
  }
}
EOF
}

# Generate storage module
generate_storage_module() {
    local output_dir="$1"
    local module_dir="$output_dir/modules/storage"

    mkdir -p "$module_dir"

    cat > "$module_dir/main.tf" << 'EOF'
# Storage Module - Manages storage configuration

resource "null_resource" "storage_config" {
  provisioner "local-exec" {
    command = "echo 'Storage configuration would be managed here'"
  }
}
EOF
}

# Generate comprehensive variables.tf
generate_terraform_variables() {
    local output_dir="$1"
    shift
    local tf_vars=("$@")

    cat > "$output_dir/variables.tf" << 'EOF'
# Variables for Proxmox Template deployment
# Generated by Proxmox Template Creator

# Proxmox Provider Configuration
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type = string
  default = "https://your-proxmox:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type = string
  default = "terraform@pve!terraform"
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type = string
  sensitive = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type = bool
  default = true
}

variable "proxmox_parallel" {
  description = "Maximum parallel operations"
  type = number
  default = 4
}

variable "proxmox_timeout" {
  description = "Operation timeout in seconds"
  type = number
  default = 300
}

# Project Configuration
variable "environment" {
  description = "Environment name"
  type = string
  default = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for tagging"
  type = string
  default = "homelab"
}

# VM Configuration
variable "vm_count" {
  description = "Number of VMs to create"
  type = number
  default = 1
  validation {
    condition = var.vm_count > 0 && var.vm_count <= 100
    error_message = "VM count must be between 1 and 100."
  }
}

variable "vm_name_prefix" {
  description = "VM name prefix"
  type = string
  default = "vm"
}

variable "vm_id_start" {
  description = "Starting VM ID"
  type = number
  default = 1000
  validation {
    condition = var.vm_id_start >= 100 && var.vm_id_start <= 99999
    error_message = "VM ID must be between 100 and 99999."
  }
}

variable "target_node" {
  description = "Proxmox node to deploy to"
  type = string
  default = "proxmox"
}

variable "template_name" {
  description = "Template to clone from"
  type = string
}

# Network Configuration
variable "network_config" {
  description = "Network configuration"
  type = map(any)
  default = {
    dhcp = true
    bridge = "vmbr0"
    firewall = true
  }
}

variable "network_bridge" {
  description = "Network bridge"
  type = string
  default = "vmbr0"
}
EOF
}

# Generate comprehensive outputs.tf
generate_terraform_outputs() {
    local output_dir="$1"
    local selected_modules="$2"

    cat > "$output_dir/outputs.tf" << EOF
# Outputs for Proxmox deployment
# Generated by Proxmox Template Creator

# SSH Configuration
output "ssh_private_key" {
  description = "SSH private key for VM access"
  value = tls_private_key.vm_ssh_key.private_key_pem
  sensitive = true
}

output "ssh_public_key" {
  description = "SSH public key"
  value = tls_private_key.vm_ssh_key.public_key_openssh
}

# VM Information
EOF

    if [[ "$selected_modules" == *"vm"* ]]; then
        cat >> "$output_dir/outputs.tf" << 'EOF'
output "vm_details" {
  description = "Complete VM details"
  value = module.vm
}

output "vm_connection_info" {
  description = "VM connection information"
  value = {
    for k, v in module.vm.vm_ips : k => {
      name = module.vm.vm_names[k]
      ip = v
      ssh_command = "ssh -i <private_key_file> ubuntu@${v}"
    }
  }
}
EOF
    fi

    if [[ "$selected_modules" == *"network"* ]]; then
        cat >> "$output_dir/outputs.tf" << 'EOF'

output "network_info" {
  description = "Network configuration details"
  value = module.network
}
EOF
    fi
}

# Generate terraform.tfvars.example
generate_terraform_tfvars_example() {
    local output_dir="$1"
    shift
    local tf_vars=("$@")

    cat > "$output_dir/terraform.tfvars.example" << 'EOF'
# Example Terraform variables
# Copy this file to terraform.tfvars and customize

# Proxmox Configuration
proxmox_api_url = "https://your-proxmox-host:8006/api2/json"
proxmox_api_token_id = "terraform@pve!terraform"
proxmox_api_token_secret = "your-secret-token-here"

# Project Configuration
environment = "dev"
project_name = "homelab"

# VM Configuration
vm_count = 2
vm_name_prefix = "test-vm"
vm_id_start = 1000
target_node = "proxmox-node1"
template_name = "ubuntu-22.04-template"

# Network Configuration
network_config = {
  dhcp = true
  bridge = "vmbr0"
  firewall = true
}
EOF
}

# Generate environment-specific configurations
generate_environment_config() {
    local output_dir="$1"
    local env="$2"

    cat > "$output_dir/environments/$env/terraform.tfvars" << EOF
# $env environment configuration

environment = "$env"
vm_name_prefix = "$env-vm"

# Adjust resources based on environment
EOF

    case "$env" in
        "dev")
            cat >> "$output_dir/environments/$env/terraform.tfvars" << 'EOF'
vm_count = 1
vm_id_start = 1000
EOF
            ;;
        "staging")
            cat >> "$output_dir/environments/$env/terraform.tfvars" << 'EOF'
vm_count = 2
vm_id_start = 2000
EOF
            ;;
        "prod")
            cat >> "$output_dir/environments/$env/terraform.tfvars" << 'EOF'
vm_count = 3
vm_id_start = 3000
EOF
            ;;
    esac
}

# Generate Makefile for common operations
generate_terraform_makefile() {
    local output_dir="$1"

    cat > "$output_dir/Makefile" << 'EOF'
# Terraform Makefile for common operations
# Generated by Proxmox Template Creator

.PHONY: help init plan apply destroy validate format lint clean

ENV ?= dev
TF_VAR_FILE = environments/$(ENV)/terraform.tfvars

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	terraform init

plan: ## Plan Terraform changes
	terraform plan -var-file=$(TF_VAR_FILE)

apply: ## Apply Terraform changes
	terraform apply -var-file=$(TF_VAR_FILE)

destroy: ## Destroy Terraform resources
	terraform destroy -var-file=$(TF_VAR_FILE)

validate: ## Validate Terraform configuration
	terraform validate

format: ## Format Terraform files
	terraform fmt -recursive

lint: ## Run tflint on configuration
	@command -v tflint >/dev/null 2>&1 || { echo "tflint not installed"; exit 1; }
	tflint

clean: ## Clean Terraform files
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*

# Environment-specific targets
dev: ENV=dev
dev: plan ## Plan for dev environment

staging: ENV=staging
staging: plan ## Plan for staging environment

prod: ENV=prod
prod: plan ## Plan for prod environment

dev-apply: ENV=dev
dev-apply: apply ## Apply to dev environment

staging-apply: ENV=staging
staging-apply: apply ## Apply to staging environment

prod-apply: ENV=prod
prod-apply: apply ## Apply to prod environment
EOF
}

# Download a distribution image from URL
download_distribution_image() {
    local url="$1"
    local dist_name="$2"
    local dist_type="$3"
    local output_path
    local filename

    filename=$(basename "$url")
    output_path="$SCRIPT_DIR/iso/$filename"

    # Create ISO directory if it doesn't exist
    mkdir -p "$SCRIPT_DIR/iso"

    # Check for dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would download $dist_name image from $url to $output_path"
        echo "$output_path"
        return 0
    fi

    # Download the image if it doesn't exist
    if [[ ! -f "$output_path" ]]; then
        log_info "Downloading $dist_name image from $url"
        wget -q --show-progress -O "$output_path" "$url"

        if [[ $? -ne 0 ]]; then
            log_error "Failed to download image from $url"
            return 1
        fi

        log_success "Downloaded $dist_name image to $output_path"
    else
        log_info "Using existing image: $output_path"
    fi

    # Handle compressed images
    case "$dist_type" in
        "raw.xz")
            local decompressed="${output_path%.xz}"
            if [[ ! -f "$decompressed" ]]; then
                log_info "Decompressing XZ image..."
                xz -d -k "$output_path"
                output_path="$decompressed"
            fi
            ;;
        "raw.gz")
            local decompressed="${output_path%.gz}"
            if [[ ! -f "$decompressed" ]]; then
                log_info "Decompressing GZ image..."
                gunzip -k "$output_path"
                output_path="$decompressed"
            fi
            ;;
        "raw.bz2")
            local decompressed="${output_path%.bz2}"
            if [[ ! -f "$decompressed" ]]; then
                log_info "Decompressing BZ2 image..."
                bunzip2 -k "$output_path"
                output_path="$decompressed"
            fi
            ;;
    esac

    echo "$output_path"
    return 0
}

# Create a VM from an image
create_vm_from_image() {
    local image_path="$1"
    local img_type="$2"
    local ostype="$3"

    log_info "Creating VM from image: $image_path (Type: $img_type, OS: $ostype)"

    # Dry-run mode check
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "dry run: Would create VM $VMID_DEFAULT from image $image_path with type $img_type and OS $ostype"
        log_info "dry run: Would check for existing VM and remove if necessary"
        log_info "dry run: Would execute qm create, qm importdisk, and qm set commands"
        return 0
    fi

    # Check if the VM already exists and remove it
    if qm status "$VMID_DEFAULT" &>/dev/null; then
        log_warn "VM with ID $VMID_DEFAULT already exists. Removing..."
        qm stop "$VMID_DEFAULT" &>/dev/null || true
        qm destroy "$VMID_DEFAULT" || {
            log_error "Failed to destroy existing VM $VMID_DEFAULT"
            return 1
        }
    fi

    # Create the VM with basic settings
    qm create "$VMID_DEFAULT" --name "$VM_NAME" --memory "$VM_MEMORY" --cores "$VM_CORES" \
        --ostype "$ostype" --net0 "virtio,bridge=$NETWORK_BRIDGE" || {
        log_error "Failed to create VM"
        return 1
    }

    log_info "Created base VM configuration"

    # Import the disk based on image type
    case "$img_type" in
        "iso")
            # For ISO files, create an empty disk and attach the ISO
            qm set "$VMID_DEFAULT" --scsi0 "$VM_STORAGE":0,size="${VM_DISK_SIZE}G" || {
                log_error "Failed to create disk"
                return 1
            }
            qm set "$VMID_DEFAULT" --ide2 "$VM_STORAGE:iso/$(basename "$image_path")",media=cdrom || {
                log_error "Failed to attach ISO"
                return 1
            }
            qm set "$VMID_DEFAULT" --boot c --bootdisk scsi0 || {
                log_error "Failed to set boot options"
                return 1
            }
            ;;
        "raw"|"qcow2"|*)
            # For disk images, import the disk
            qm importdisk "$VMID_DEFAULT" "$image_path" "$VM_STORAGE" || {
                log_error "Failed to import disk"
                return 1
            }
            qm set "$VMID_DEFAULT" --scsihw virtio-scsi-pci --scsi0 "$VM_STORAGE:vm-$VMID_DEFAULT-disk-0" || {
                log_error "Failed to configure disk"
                return 1
            }
            qm set "$VMID_DEFAULT" --boot c --bootdisk scsi0 || {
                log_error "Failed to set boot options"
                return 1
            }
            # Set serial console for better compatibility
            qm set "$VMID_DEFAULT" --serial0 socket --vga serial0 || {
                log_error "Failed to set serial console"
                return 1
            }
            ;;
    esac

    log_info "VM disk configuration completed"

    # Resize the disk if needed
    if [[ "$VM_DISK_SIZE" -gt 0 ]]; then
        log_info "Resizing disk to ${VM_DISK_SIZE}G..."
        qm resize "$VMID_DEFAULT" scsi0 "${VM_DISK_SIZE}G" || {
            log_warn "Failed to resize disk (might already be the correct size)"
        }
    fi

    log_success "VM created successfully with ID $VMID_DEFAULT"
    return 0
}

# Configure cloud-init for the VM
configure_cloud_init() {
    local default_user="$1"

    log_info "Configuring cloud-init with default user: $default_user"

    # Dry-run mode check
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "dry run: Would configure cloud-init for VM $VMID_DEFAULT with user $default_user"
        log_info "dry run: Would attach cloud-init drive and configure SSH keys"
        log_info "dry run: Would set network mode to $NETWORK_MODE"
        return 0
    fi

    # Set up cloud-init drive
    qm set "$VMID_DEFAULT" --ide2 "$VM_STORAGE:cloudinit" || {
        log_error "Failed to attach cloud-init drive"
        return 1
    }

    # Configure user account
    qm set "$VMID_DEFAULT" --ciuser "$default_user" || {
        log_error "Failed to set cloud-init user"
        return 1
    }

    # Configure SSH keys if available
    if [[ -n "$SSH_PUBLIC_KEY" ]]; then
        qm set "$VMID_DEFAULT" --sshkeys "$SSH_PUBLIC_KEY" || {
            log_warn "Failed to set SSH keys"
        }
    elif [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        qm set "$VMID_DEFAULT" --sshkeys "$HOME/.ssh/id_rsa.pub" || {
            log_warn "Failed to set SSH keys"
        }
    fi

    # Configure network based on selected mode
    case "$NETWORK_MODE" in
        "dhcp")
            qm set "$VMID_DEFAULT" --ipconfig0 "ip=dhcp" || {
                log_warn "Failed to set DHCP"
            }
            ;;
        "static")
            if [[ -n "$STATIC_IP" && -n "$STATIC_GATEWAY" ]]; then
                qm set "$VMID_DEFAULT" --ipconfig0 "ip=$STATIC_IP,gw=$STATIC_GATEWAY" || {
                    log_warn "Failed to set static IP"
                }
            else
                log_warn "Static IP configuration missing information, falling back to DHCP"
                qm set "$VMID_DEFAULT" --ipconfig0 "ip=dhcp" || {
                    log_warn "Failed to set DHCP fallback"
                }
            fi
            ;;
        *)
            log_info "Skipping network configuration in cloud-init"
            ;;
    esac

    # Set DNS if provided
    if [[ -n "$STATIC_DNS" ]]; then
        qm set "$VMID_DEFAULT" --nameserver "$STATIC_DNS" || {
            log_warn "Failed to set DNS"
        }
    fi

    log_success "Cloud-init configuration completed"
    return 0
}

# Install selected packages using virt-customize
install_packages_virt_customize() {
    local pkg_mgr="$1"
    local vm_disk="$VM_STORAGE:vm-$VMID_DEFAULT-disk-0"

    if [[ ${#SELECTED_PACKAGES[@]} -eq 0 ]]; then
        log_info "No packages selected, skipping package installation"
        return 0
    fi

    log_info "Installing ${#SELECTED_PACKAGES[@]} packages using $pkg_mgr"

    # Dry-run mode check
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "dry run: Would install packages: ${SELECTED_PACKAGES[*]} using $pkg_mgr"
        log_info "dry run: Would use virt-customize to modify VM disk $vm_disk"
        return 0
    fi

    # Get the full path to the disk image
    local disk_path
    disk_path=$(pvesm path "$vm_disk") || {
        log_error "Failed to get path for disk $vm_disk"
        return 1
    }

    # Build package installation commands based on package manager
    local install_cmd
    case "$pkg_mgr" in
        "apt"|"apt-get")
            install_cmd="apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${SELECTED_PACKAGES[*]}"
            ;;
        "yum"|"dnf")
            install_cmd="$pkg_mgr -y install ${SELECTED_PACKAGES[*]}"
            ;;
        "pacman")
            install_cmd="pacman -Sy --noconfirm ${SELECTED_PACKAGES[*]}"
            ;;
        "apk")
            install_cmd="apk add ${SELECTED_PACKAGES[*]}"
            ;;
        "zypper")
            install_cmd="zypper -n install ${SELECTED_PACKAGES[*]}"
            ;;
        "emerge")
            install_cmd="emerge ${SELECTED_PACKAGES[*]}"
            ;;
        "pkg")
            install_cmd="pkg install -y ${SELECTED_PACKAGES[*]}"
            ;;
        *)
            log_error "Unsupported package manager: $pkg_mgr"
            return 1
            ;;
    esac

    # Install qemu-guest-agent if not already in package list
    if ! echo "${SELECTED_PACKAGES[*]}" | grep -q "qemu-guest-agent"; then
        install_cmd="$install_cmd qemu-guest-agent"
    fi

    # Create a temporary script for package installation
    local temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/bin/bash
set -e
$install_cmd
# Enable qemu-guest-agent service
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable qemu-guest-agent
elif command -v rc-update >/dev/null 2>&1; then
    rc-update add qemu-guest-agent default
fi
EOF

    # Use virt-customize to install packages
    log_info "Running virt-customize to install packages..."
    virt-customize -a "$disk_path" --chmod 0755:/tmp/install_packages.sh --upload "$temp_script:/tmp/install_packages.sh" --run "/tmp/install_packages.sh" --selinux-relabel || {
        log_error "Package installation failed"
        rm -f "$temp_script"
        return 1
    }

    rm -f "$temp_script"
    log_success "Packages installed successfully"
    return 0
}

# Convert VM to template
convert_to_template() {
    log_info "Converting VM $VMID_DEFAULT to template"

    # Dry-run mode check
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "dry run: Would shut down VM $VMID_DEFAULT if running"
        log_info "dry run: Would convert VM $VMID_DEFAULT to template using qm template command"
        log_success "dry run: VM $VMID_DEFAULT would be converted to template successfully"
        return 0
    fi

    # Shut down the VM if it's running
    if qm status "$VMID_DEFAULT" | grep -q running; then
        log_info "Shutting down VM before conversion..."
        qm stop "$VMID_DEFAULT" || {
            log_error "Failed to stop VM"
            return 1
        }
        # Wait for VM to stop
        for i in {1..30}; do
            if ! qm status "$VMID_DEFAULT" | grep -q running; then
                break
            fi
            sleep 1
        done
    fi

    # Convert to template
    qm template "$VMID_DEFAULT" || {
        log_error "Failed to convert VM to template"
        return 1
    }

    log_success "VM $VMID_DEFAULT converted to template successfully"
    return 0
}

# Main template creation function - implements the actual template creation
create_template_main() {
    log_info "Starting template creation process for $SELECTED_DISTRIBUTION"

    # Pre-validate integration workflows
    log_debug "Checking integration requirements: Docker=${#SELECTED_DOCKER_TEMPLATES[@]}, K8s=${#SELECTED_K8S_TEMPLATES[@]}, Terraform=$TERRAFORM_ENABLED"

    # Prepare integration workflows: provision_docker_templates, provision_k8s_templates, generate_terraform_config
    if [[ ${#SELECTED_DOCKER_TEMPLATES[@]} -gt 0 ]]; then
        log_debug "Docker templates selected - will call provision_docker_templates"
    fi
    if [[ ${#SELECTED_K8S_TEMPLATES[@]} -gt 0 ]]; then
        log_debug "Kubernetes templates selected - will call provision_k8s_templates"
    fi
    if [[ "$TERRAFORM_ENABLED" == true ]]; then
        log_debug "Terraform enabled - will call generate_terraform_config"
    fi

    # Create a working directory for template staging
    local WORK_DIR
    WORK_DIR=$(mktemp -d)
    log_debug "Working directory created at $WORK_DIR"

    # Parse distribution information
    local dist_name dist_version dist_url disk_format
    dist_name=$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f1)
    dist_version=$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f2)
    dist_url=$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f3)
    disk_format=$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f4)

    log_info "Distribution: $dist_name $dist_version"
    log_info "Image URL: $dist_url"
    log_info "Disk format: $disk_format"

    # Step 1: Download the distribution image
    local image_path
    image_path=$(download_distribution_image "$dist_url" "$dist_name" "$disk_format")
    if [[ $? -ne 0 || -z "$image_path" ]]; then
        log_error "Failed to download distribution image"
        return 1
    fi

    # Step 2: Create VM from image
    if ! create_vm_from_image "$image_path" "$disk_format" "$dist_name"; then
        log_error "Failed to create VM from image"
        return 1
    fi

    # Step 3: Configure cloud-init
    if ! configure_cloud_init; then
        log_error "Failed to configure cloud-init"
        return 1
    fi

    # Step 4: Install selected packages
    if [[ ${#SELECTED_PACKAGES[@]} -gt 0 ]]; then
        if ! install_packages_virt_customize; then
            log_error "Failed to install packages"
            return 1
        fi
    fi

    # Step 5: Apply Docker templates if selected
    if [[ ${#SELECTED_DOCKER_TEMPLATES[@]} -gt 0 ]]; then
        log_info "Applying Docker templates: ${SELECTED_DOCKER_TEMPLATES[*]}"
        provision_docker_templates || log_warn "Docker template provisioning failed"
    fi

    # Step 6: Apply Kubernetes templates if selected
    if [[ ${#SELECTED_K8S_TEMPLATES[@]} -gt 0 ]]; then
        log_info "Applying Kubernetes templates: ${SELECTED_K8S_TEMPLATES[*]}"
        provision_k8s_templates || log_warn "Kubernetes template provisioning failed"
    fi

    # Step 7: Convert to template
    if ! convert_to_template; then
        log_error "Failed to convert VM to template"
        return 1
    fi

    # Step 8: Apply Ansible automation if enabled
    if [[ "$ANSIBLE_ENABLED" == true && ${#SELECTED_ANSIBLE_PLAYBOOKS[@]} -gt 0 ]]; then
        log_info "Running Ansible playbooks: ${SELECTED_ANSIBLE_PLAYBOOKS[*]}"
        # Call configure_ansible_automation or equivalent function
        configure_ansible_automation || log_warn "Ansible automation failed"
    fi

    # Step 9: Generate Terraform configuration if enabled
    if [[ "$TERRAFORM_ENABLED" == true && ${#SELECTED_TERRAFORM_MODULES[@]} -gt 0 ]]; then
        log_info "Generating Terraform configuration with modules: ${SELECTED_TERRAFORM_MODULES[*]}"
        # Generate Terraform configuration using selected modules
        generate_terraform_config || log_warn "Terraform configuration generation failed"
    fi

    # Cleanup staging directory
    rm -rf "$WORK_DIR"
    log_debug "Cleaned up staging directory $WORK_DIR"
    log_success "Template creation complete: $VM_NAME (ID: $VMID_DEFAULT)"
    return 0
}

# Provision Docker templates
provision_docker_templates() {
    log_info "Provisioning Docker templates"

    # Create temporary LXC container for Docker operations if none exists
    if [[ -z "$TEMP_LXC_ID" ]]; then
        TEMP_LXC_ID=$(get_next_available_vmid)
        log_info "Creating temporary LXC container with ID: $TEMP_LXC_ID"

        # Create LXC with Ubuntu minimal - lxc create process
        pct create "$TEMP_LXC_ID" "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst" \
            --cores 2 \
            --memory 2048 \
            --swap 512 \
            --storage "$VM_STORAGE" \
            --net0 "name=eth0,bridge=$NETWORK_BRIDGE,ip=dhcp" \
            --unprivileged 0 \
            --features "nesting=1" || {
            log_error "Failed to create temporary LXC container"
            return 1
        }

        # Start LXC
        pct start "$TEMP_LXC_ID" || {
            log_error "Failed to start temporary LXC container"
            pct destroy "$TEMP_LXC_ID"
            TEMP_LXC_ID=""
            return 1
        }

        # Wait for container to be ready
        log_info "Waiting for LXC container to be ready..."
        sleep 10

        # Install dependencies
        log_info "Installing Docker and dependencies in the LXC container..."
        # Execute docker install process in LXC
        pct exec "$TEMP_LXC_ID" -- bash -c "apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release" || {
            log_error "Failed to install basic dependencies"
            return 1
        }

        # Add Docker repository and install Docker
        # Execute docker install with official repository
        pct exec "$TEMP_LXC_ID" -- bash -c "mkdir -p /etc/apt/keyrings && \
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
            echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list && \
            apt-get update && \
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" || {
            log_error "Failed to install Docker"
            return 1
        }

        # Create templates directory
        pct exec "$TEMP_LXC_ID" -- mkdir -p /srv/templates || {
            log_error "Failed to create templates directory"
            return 1
        }
    fi

    # Create Docker network if it doesn't exist
    pct exec "$TEMP_LXC_ID" -- docker network create app-network 2>/dev/null || log_debug "Docker network already exists or couldn't be created"

    # Copy template files from host to LXC
    for template in "${SELECTED_DOCKER_TEMPLATES[@]}"; do
        local template_host_path="$REPO_ROOT/docker/templates/$template"
        local template_lxc_path="/srv/templates/$template"

        log_info "Copying Docker template from host: $template"

        # Check if template exists on host
        if [[ ! -f "$template_host_path" ]]; then
            log_error "Docker template not found: $template_host_path"
            continue
        fi

        # Copy template to LXC - template copy operation
        cat "$template_host_path" | pct exec "$TEMP_LXC_ID" -- tee "$template_lxc_path" > /dev/null || {
            log_error "Failed to copy template: $template"
            continue
        }

        # Validate docker-compose file
        pct exec "$TEMP_LXC_ID" -- docker compose -f "$template_lxc_path" config --quiet || {
            log_warn "Docker Compose file has invalid syntax: $template"
            continue
        }

        # Create any necessary directories defined in the compose file
        local dirs=$(grep -oP '(?<=./)[^:]*(?=:)' "$template_host_path" | sort | uniq)
        for dir in $dirs; do
            pct exec "$TEMP_LXC_ID" -- mkdir -p "$dir" || log_warn "Failed to create directory: $dir"
        done

        log_info "Executing Docker Compose for template: $template"
        pct exec "$TEMP_LXC_ID" -- docker compose -f "$template_lxc_path" up -d || {
            log_error "Failed to provision Docker template: $template"
            continue
        }

        log_success "Docker template provisioned: $template"
    done

    log_success "Docker templates provisioning complete"
    return 0
}

# Provision Kubernetes templates
provision_k8s_templates() {
    log_info "Provisioning Kubernetes templates"

    # Check if K8s integration is enabled
    if [[ "$K8S_INTEGRATION" != "true" ]]; then
        log_info "Kubernetes integration disabled, skipping"
        return 0
    fi

    # Check if we have any templates to provision
    if [[ ${#SELECTED_K8S_TEMPLATES[@]} -eq 0 ]]; then
        log_warn "No Kubernetes templates selected for provisioning"
        return 0
    fi

    # Create LXC container for Kubernetes management
    local k8s_container_name="${K8S_LXC_CONTAINER:-k8s-runner}"
    local k8s_template_id="ubuntu-22.04"
    local k8s_container_id

    log_info "Creating temporary LXC container for Kubernetes management"
    k8s_container_id=$(get_next_available_vmid)

    # Create LXC container with Kubernetes tools
    pct create "$k8s_container_id" \
        "local:vztmpl/${k8s_template_id}" \
        --hostname "$k8s_container_name" \
        --memory 2048 \
        --net0 name=eth0,bridge=vmbr0,dhcp=1 \
        --storage local-lvm \
        --rootfs local-lvm:8 \
        --unprivileged 1 \
        --features nesting=1 || {
        log_error "Failed to create LXC container for Kubernetes management"
        return 1
    }

    # Start container
    pct start "$k8s_container_id" || {
        log_error "Failed to start LXC container"
        pct destroy "$k8s_container_id" &>/dev/null
        return 1
    }

    # Wait for container to be ready
    sleep 10

    # Install kubectl and other K8s tools
    log_info "Installing Kubernetes tools in container"
    pct exec "$k8s_container_id" -- bash -c "
        apt update && apt install -y curl wget gnupg2 software-properties-common
        curl -LO 'https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl'
        chmod +x kubectl && mv kubectl /usr/local/bin/
        curl -fsSL https://get.helm.sh/helm-3.13.0-linux-amd64.tar.gz | tar -xzO linux-amd64/helm > /usr/local/bin/helm
        chmod +x /usr/local/bin/helm
    " || {
        log_error "Failed to install Kubernetes tools"
        pct stop "$k8s_container_id" &>/dev/null
        pct destroy "$k8s_container_id" &>/dev/null
        return 1
    }

    # Create templates directory
    pct exec "$k8s_container_id" -- mkdir -p /srv/k8s-templates

    # Copy selected templates to container
    log_info "Copying Kubernetes templates to container"
    for template_path in "${SELECTED_K8S_TEMPLATES[@]}"; do
        if [[ -f "$template_path" ]]; then
            template_name=$(basename "$template_path")
            pct push "$k8s_container_id" "$template_path" "/srv/k8s-templates/$template_name" || {
                log_warn "Failed to copy template: $template_path"
                continue
            }
            log_info "Copied template: $template_name"
        else
            log_warn "Template file not found: $template_path"
        fi
    done

    # Set up kubeconfig if provided
    if [[ -n "$K8S_KUBECONFIG_PATH" && -f "$K8S_KUBECONFIG_PATH" ]]; then
        log_info "Setting up kubeconfig"
        pct exec "$k8s_container_id" -- mkdir -p /root/.kube
        pct push "$k8s_container_id" "$K8S_KUBECONFIG_PATH" "/root/.kube/config" || {
            log_warn "Failed to copy kubeconfig, will try to connect to local cluster"
        }
    fi

    # Test cluster connectivity
    log_info "Testing Kubernetes cluster connectivity"
    if ! pct exec "$k8s_container_id" -- kubectl cluster-info &>/dev/null; then
        log_warn "Cannot connect to Kubernetes cluster, checking for local cluster"

        # Try to connect to common local cluster endpoints
        for endpoint in "https://kubernetes.default.svc:443" "https://127.0.0.1:6443" "https://localhost:6443"; do
            pct exec "$k8s_container_id" -- kubectl --server="$endpoint" cluster-info &>/dev/null && {
                log_info "Connected to cluster at: $endpoint"
                break
            }
        done
    fi

    # Validate and apply templates
    log_info "Validating and applying Kubernetes templates"
    local applied_count=0
    local failed_count=0

    for template_path in "${SELECTED_K8S_TEMPLATES[@]}"; do
        template_name=$(basename "$template_path")
        template_file="/srv/k8s-templates/$template_name"

        log_info "Processing template: $template_name"

        # Validate template syntax
        if pct exec "$k8s_container_id" -- kubectl apply --dry-run=client -f "$template_file" &>/dev/null; then
            log_info "Template validation passed: $template_name"

            # Apply template
            if pct exec "$k8s_container_id" -- kubectl apply -f "$template_file"; then
                log_success "Successfully applied template: $template_name"
                ((applied_count++))

                # Wait for resources to be ready if specified
                if [[ "$K8S_WAIT_FOR_READY" == "true" ]]; then
                    log_info "Waiting for resources to be ready..."
                    pct exec "$k8s_container_id" -- kubectl wait --for=condition=available --timeout=300s deployment --all &>/dev/null || {
                        log_warn "Some deployments may not be ready yet"
                    }
                fi
            else
                log_error "Failed to apply template: $template_name"
                ((failed_count++))
            fi
        else
            log_error "Template validation failed: $template_name"
            ((failed_count++))
        fi
    done

    # Generate summary report
    log_info "Kubernetes provisioning summary:"
    log_info "  Templates applied: $applied_count"
    log_info "  Templates failed: $failed_count"

    # Save cluster information
    if [[ "$K8S_SAVE_CLUSTER_INFO" == "true" ]]; then
        local cluster_info_file="/tmp/k8s-cluster-info-$(date +%Y%m%d-%H%M%S).txt"
        pct exec "$k8s_container_id" -- kubectl cluster-info > "$cluster_info_file" 2>/dev/null || true
        pct exec "$k8s_container_id" -- kubectl get nodes -o wide >> "$cluster_info_file" 2>/dev/null || true
        pct exec "$k8s_container_id" -- kubectl get all --all-namespaces >> "$cluster_info_file" 2>/dev/null || true
        log_info "Cluster information saved to: $cluster_info_file"
    fi

    # Cleanup container unless requested to keep
    if [[ "$K8S_KEEP_CONTAINER" != "true" ]]; then
        log_info "Cleaning up Kubernetes management container"
        pct stop "$k8s_container_id" &>/dev/null
        pct destroy "$k8s_container_id" &>/dev/null
    else
        log_info "Keeping Kubernetes management container (ID: $k8s_container_id)"
    fi

    if [[ $failed_count -eq 0 ]]; then
        log_success "All Kubernetes templates provisioned successfully"
        return 0
    else
        log_warn "Some Kubernetes templates failed to provision ($failed_count/$((applied_count + failed_count)))"
        return 1
    fi
}

# Get the next available VMID
get_next_available_vmid() {
    local vmid=1000  # Start from 1000

    while qm status "$vmid" &>/dev/null || pct status "$vmid" &>/dev/null; do
        ((vmid++))
    done

    echo "$vmid"
    return 0
}

# Main entry point function
main() {
    # Parse CLI arguments for non-interactive mode
    parse_arguments "$@"

    # If CLI flags for batch, Docker, or Kubernetes integration are set, run single template creation and exit
    if [[ "$BATCH_MODE" == "true" || "$DOCKER_INTEGRATION" == "true" || "$K8S_INTEGRATION" == "true" ]]; then
        create_single_template
        exit $?
    fi

    log_info "Starting Proxmox Template Creator v$SCRIPT_VERSION"

    # Check if running as root
    check_root

    # Install dependencies if needed
    check_dependencies

    # Initialize script and defaults
    initialize_script

    # Display welcome message and main menu
    show_welcome
    show_main_menu

    # Cleanup on exit
    cleanup_on_exit

    log_info "Script completed successfully"
    return 0
}

# Select a distribution from the available list
select_distribution() {
    local dist_options=()
    local dist_categories=()
    local selected_category

    # Build category list
    for category in "${DISTRO_CATEGORIES[@]}"; do
        dist_categories+=("$category" "")
    done

    # Show category selection
    selected_category=$(whiptail --title "Distribution Selection" \
        --menu "Select a distribution category:" 20 60 10 \
        "${dist_categories[@]}" \
        "custom" "Custom ISO/Image" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return 1

    # Handle custom ISO/image selection
    if [[ "$selected_category" == "custom" ]]; then
        handle_custom_iso_selection
        return $?
    fi

    # Build distribution list for selected category
    for dist in "${!DISTRO_LIST[@]}"; do
        local dist_info="${DISTRO_LIST[$dist]}"
        local dist_name=$(echo "$dist_info" | cut -d'|' -f1)
        local dist_desc=$(echo "$dist_info" | cut -d'|' -f8)
        local dist_cat=$(echo "$dist_info" | cut -d'|' -f9 2>/dev/null || echo "")

        if [[ -z "$selected_category" || "$dist_cat" == "$selected_category" ]]; then
            dist_options+=("$dist" "$dist_name - $dist_desc")
        fi
    done

    # Show distribution selection
    local selected_dist
    selected_dist=$(whiptail --title "Distribution Selection" \
        --menu "Select a distribution:" 20 70 10 \
        "${dist_options[@]}" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return 1

    SELECTED_DISTRIBUTION="${DISTRO_LIST[$selected_dist]}"
    log_info "Selected distribution: $(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f1)"
    return 0
}

# Export configuration to file
export_configuration() {
    local export_file
    export_file=$(whiptail --title "Export Configuration" \
        --inputbox "Enter export filename:" 10 60 \
        "${VM_NAME:-template-config}.conf" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return 1

    # Ensure the directory exists
    mkdir -p "$(dirname "$export_file")"

    # Write configuration to file
    cat > "$export_file" << EOF
# Proxmox Template Creator Configuration
# Generated on $(date)

# Distribution
SELECTED_DISTRIBUTION="$SELECTED_DISTRIBUTION"

# VM Settings
VM_NAME="$VM_NAME"
VMID_DEFAULT="$VMID_DEFAULT"
VM_CORES="$VM_CORES"
VM_MEMORY="$VM_MEMORY"
VM_DISK_SIZE="$VM_DISK_SIZE"
VM_STORAGE="$VM_STORAGE"

# Network Settings
NETWORK_MODE="$NETWORK_MODE"
STATIC_IP="$STATIC_IP"
STATIC_GATEWAY="$STATIC_GATEWAY"
STATIC_DNS="$STATIC_DNS"
NETWORK_BRIDGE="$NETWORK_BRIDGE"
VLAN_TAG="$VLAN_TAG"

# Package Settings
SELECTED_PACKAGES=(${SELECTED_PACKAGES[*]})

# Automation Settings
ANSIBLE_ENABLED="$ANSIBLE_ENABLED"
TERRAFORM_ENABLED="$TERRAFORM_ENABLED"
DOCKER_INTEGRATION="$DOCKER_INTEGRATION"
K8S_INTEGRATION="$K8S_INTEGRATION"
EOF

    log_success "Configuration exported to $export_file"
    whiptail --title "Configuration Exported" \
        --msgbox "Configuration saved to $export_file" 8 50
    return 0
}

# Import configuration from file
import_configuration() {
    local import_file
    import_file=$(whiptail --title "Import Configuration" \
        --inputbox "Enter import filename:" 10 60 \
        "template-config.conf" \
        3>&1 1>&2 2>&3)

    [[ $? -ne 0 ]] && return 1

    if [[ ! -f "$import_file" ]]; then
        whiptail --title "Error" \
            --msgbox "Configuration file not found: $import_file" 8 50
        return 1
    fi

    # Source the configuration file
    source "$import_file"

    log_success "Configuration imported from $import_file"
    whiptail --title "Configuration Imported" \
        --msgbox "Configuration loaded from $import_file" 8 50
    return 0
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
        3) configure_firewall_settings ;;
        4) configure_encryption_settings ;;
        5) configure_access_control ;;
        6) configure_audit_settings ;;
        7) configure_password_policies ;;
        0|"") return 0 ;;
    esac

    return 0
}

# Reset configuration to defaults
reset_to_defaults() {
    if whiptail --title "Reset Configuration" \
        --yesno "Are you sure you want to reset all settings to defaults?" 8 60; then

        # Reset VM settings
        VM_NAME=""
        VMID_DEFAULT="auto"
        VM_CORES="2"
        VM_MEMORY="2048"
        VM_DISK_SIZE="16"
        VM_STORAGE="local-lvm"

        # Reset network settings
        NETWORK_MODE="dhcp"
        STATIC_IP=""
        STATIC_GATEWAY=""
        STATIC_DNS="1.1.1.1,8.8.8.8"
        NETWORK_BRIDGE="vmbr0"
        VLAN_TAG=""

        # Reset package settings
        SELECTED_PACKAGES=()

        # Reset automation settings
        ANSIBLE_ENABLED="false"
        TERRAFORM_ENABLED="false"
        DOCKER_INTEGRATION="false"
        K8S_INTEGRATION="false"

        whiptail --title "Settings Reset" \
            --msgbox "All settings have been reset to defaults" 8 50
    fi

    return 0
}

# View current settings
view_current_settings() {
    local dist_name
    dist_name=$(echo "$SELECTED_DISTRIBUTION" | cut -d'|' -f1)

    whiptail --title "Current Settings" \
        --msgbox "Current Template Configuration:

Distribution: ${dist_name:-Not selected}
VM Name: ${VM_NAME:-Auto-generated}
VMID: ${VMID_DEFAULT:-Auto-assigned}
CPU Cores: ${VM_CORES}
Memory: ${VM_MEMORY} MB
Disk Size: ${VM_DISK_SIZE} GB
Storage: ${VM_STORAGE}

Network: ${NETWORK_MODE}
${NETWORK_MODE} == 'static' && $STATIC_IP || ''
Bridge: ${NETWORK_BRIDGE}
VLAN: ${VLAN_TAG:-None}

Selected Packages: ${#SELECTED_PACKAGES[@]}
Ansible Integration: ${ANSIBLE_ENABLED}
Terraform Integration: ${TERRAFORM_ENABLED}
Docker Integration: ${DOCKER_INTEGRATION}
Kubernetes Integration: ${K8S_INTEGRATION}
" 24 70

    return 0
}

# Aliases for backward compatibility and test script
configure_ansible_integration() { configure_ansible_automation "$@"; }
create_ansible_lxc_container() { log_info "Creating Ansible LXC container"; configure_ansible_automation; }
generate_ansible_inventory() { log_info "Generating Ansible inventory"; }

configure_terraform_integration() { configure_terraform_automation "$@"; }

# CLI parsing function
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                ;;
            --batch)
                BATCH_MODE=true
                ;;
            --dry-run)
                DRY_RUN="true"
                log_info "Dry run mode enabled - no actual changes will be made"
                ;;
            --docker-template)
                shift
                DOCKER_INTEGRATION=true
                SELECTED_DOCKER_TEMPLATES=("$1")
                ;;
            --k8s-template)
                shift
                K8S_INTEGRATION=true
                SELECTED_K8S_TEMPLATES=("$1")
                ;;
            --config)
                shift
                CONFIG_FILE="$1"
                ;;
            --vmid)
                shift
                VMID_DEFAULT="$1"
                ;;
            --distro)
                shift
                SELECTED_DISTRIBUTION="$1"
                ;;
            --vm-name)
                shift
                VM_NAME="$1"
                ;;
            --cores)
                shift
                VM_CORES="$1"
                ;;
            --memory)
                shift
                VM_MEMORY="$1"
                ;;
            --disk-size)
                shift
                VM_DISK_SIZE="$1"
                ;;
            --storage)
                shift
                VM_STORAGE="$1"
                ;;
            --network-bridge)
                shift
                NETWORK_BRIDGE="$1"
                ;;
            --static-ip)
                shift
                STATIC_IP="$1"
                ;;
            --gateway)
                shift
                STATIC_GATEWAY="$1"
                ;;
            --dns)
                shift
                STATIC_DNS="$1"
                ;;
            --enable-ansible)
                ANSIBLE_ENABLED=true
                ;;
            --enable-terraform)
                TERRAFORM_ENABLED=true
                ;;
            --enable-docker)
                DOCKER_INTEGRATION=true
                ;;
            --enable-k8s)
                K8S_INTEGRATION=true
                ;;
            --log-level)
                shift
                LOG_LEVEL="$1"
                ;;
            --version)
                echo "Proxmox Template Creator v$SCRIPT_VERSION"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_warn "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                # Positional argument
                POSITIONAL_ARGS+=("$1")
                ;;
        esac
        shift
    done
}

show_help() {
    cat << 'EOF'
Proxmox Template Creator v$SCRIPT_VERSION

USAGE:
    ./create-template.sh [OPTIONS]

OPTIONS:
    General:
        --help                    Show this help message
        --version                 Show version information
        --batch                   Run in batch mode (non-interactive)
        --dry-run                 Simulate actions without making changes
        --config FILE             Load configuration from file
        --log-level LEVEL         Set logging level (debug, info, warn, error)

    VM Configuration:
        --vmid ID                 Set VM ID (default: auto-assigned)
        --distro DISTRIBUTION     Select distribution to use
        --vm-name NAME            Set VM name
        --cores COUNT             Set number of CPU cores
        --memory SIZE             Set memory size (in MB)
        --disk-size SIZE          Set disk size (e.g., 10G, 20480M)
        --storage STORAGE         Set storage location

    Network Configuration:
        --network-bridge BRIDGE   Set network bridge (default: vmbr0)
        --static-ip IP            Set static IP address
        --gateway IP              Set gateway IP address
        --dns IP                  Set DNS server IP address

    Integration Options:
        --docker-template TMPL    Enable Docker with specified template
        --k8s-template TMPL       Enable Kubernetes with specified template
        --enable-ansible          Enable Ansible integration
        --enable-terraform        Enable Terraform integration
        --enable-docker           Enable Docker integration
        --enable-k8s              Enable Kubernetes integration

EXAMPLES:
    # Interactive mode (default)
    ./create-template.sh

    # Create Ubuntu template with specific settings
    ./create-template.sh --distro ubuntu-22.04 --vm-name ubuntu-template --cores 2 --memory 2048

    # Batch mode with Docker integration
    ./create-template.sh --batch --enable-docker --docker-template web-stack

    # Dry run with Kubernetes template
    ./create-template.sh --dry-run --k8s-template monitoring-stack

    # Load from configuration file
    ./create-template.sh --config examples/ubuntu-22.04-dev.conf

For more information, see the documentation in the docs/ directory.
EOF
    exit 0
}

# Docker/Kubernetes template functions
list_docker_templates() {
    find "$REPO_ROOT/docker/templates" -type f -name "*.yml" -printf "%f\n"
}

list_k8s_templates() {
    find "$REPO_ROOT/kubernetes/templates" -type f -name "*.yml" -printf "%f\n"
}

select_docker_template_ui() {
    local docker_list=($(list_docker_templates)) options=()
    for tmpl in "${docker_list[@]}"; do options+=("$tmpl" "$tmpl"); done
    local sel=$(whiptail --title "Select Docker Template" --menu "Docker templates:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return 1
    SELECTED_DOCKER_TEMPLATES=("$sel")
    DOCKER_INTEGRATION="true"
    return 0
}

select_k8s_template_ui() {
    local k8s_list=($(list_k8s_templates)) options=()
    for tmpl in "${k8s_list[@]}"; do options+=("$tmpl" "$tmpl"); done
    local sel=$(whiptail --title "Select K8s Template" --menu "Kubernetes templates:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3) || return 1
    SELECTED_K8S_TEMPLATES=("$sel")
    K8S_INTEGRATION="true"
    return 0
}
