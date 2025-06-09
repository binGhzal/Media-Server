#!/bin/bash
# Proxmox Template Creator - Bootstrap Script
# Phase 1: Initial version with root and dependency checks, repo handling, and main controller launch

set -e

# Logging function
log() {
    local level="$1"; shift
    local color=""
    local reset="\033[0m"
    case $level in
        INFO)
            color="\033[0;32m" # Green
            ;;
        WARN)
            color="\033[0;33m" # Yellow
            ;;
        ERROR)
            color="\033[0;31m" # Red
            ;;
        *)
            color=""
            ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*${reset}"
}

# Error handling function
handle_error() {
    local exit_code=$?
    log_error "An error occurred on line $1 with exit code $exit_code"
    log_error "Bootstrap failed. Please check the logs and try again."
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root or with sudo."
        exit 1
    fi
    log_info "Running as root: OK"
    return 0
}

# Check OS compatibility
check_os_compatibility() {
    local supported_os=("debian" "ubuntu" "centos" "rocky" "almalinux" "opensuse" "sles")
    local os_id=""
    if [ -f /etc/os-release ]; then
        os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        local os_supported=0
        for os in "${supported_os[@]}"; do
            if [[ "$os_id" == "$os" ]]; then
                os_supported=1
                break
            fi
        done
        
        if [ $os_supported -eq 1 ]; then
            log_info "Detected supported OS: $os_id"
            return 0
        else
            log_error "Unsupported OS: $os_id. Supported: ${supported_os[*]}"
            exit 1
        fi
    else
        log_error "/etc/os-release not found. Cannot determine OS."
        exit 1
    fi
}

# Check and install dependencies
check_dependencies() {
    local deps=(curl git whiptail jq wget curl qemu-img)
    local missing=()

    log_info "Checking dependencies..."
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_info "Installing missing dependencies: ${missing[*]}"
        
        # Determine package manager
        if command -v apt >/dev/null 2>&1; then
            log_info "Using apt package manager"
            apt update -q
            apt install -y "${missing[@]}" || {
                log_error "Failed to install packages with apt"
                exit 1
            }
        elif command -v dnf >/dev/null 2>&1; then
            log_info "Using dnf package manager"
            dnf install -y "${missing[@]}" || {
                log_error "Failed to install packages with dnf"
                exit 1
            }
        elif command -v yum >/dev/null 2>&1; then
            log_info "Using yum package manager"
            yum install -y "${missing[@]}" || {
                log_error "Failed to install packages with yum"
                exit 1
            }
        elif command -v zypper >/dev/null 2>&1; then
            log_info "Using zypper package manager"
            zypper install -y "${missing[@]}" || {
                log_error "Failed to install packages with zypper"
                exit 1
            }
        else
            log_error "No supported package manager found. Please install manually: ${missing[*]}"
            exit 1
        fi
        
        # Verify installation
        local still_missing=()
        for dep in "${missing[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                still_missing+=("$dep")
            fi
        done
        
        if [ ${#still_missing[@]} -gt 0 ]; then
            log_error "Failed to install some dependencies: ${still_missing[*]}"
            exit 1
        fi
    fi
    
    log_info "All dependencies satisfied."
    return 0
}

# Detect Proxmox environment
check_proxmox() {
    if command -v pveversion >/dev/null 2>&1; then
        local pve_version
        pve_version=$(pveversion | grep -oP 'pve-manager\/\K[0-9]+\.[0-9]+')
        log_info "Proxmox VE $pve_version detected"
        
        # Check Proxmox version (minimum recommended 7.0)
        if (( $(echo "$pve_version < 7.0" | bc -l) )); then
            log_warn "Proxmox VE $pve_version is older than the recommended version 7.0. Some features may not work properly."
        fi
        return 0
    else
        log_warn "Proxmox VE not detected. Some features may not be available."
        
        # Ask to continue if run interactively
        if [ -t 0 ]; then
            read -p "Continue without Proxmox VE? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Installation cancelled by user."
                exit 0
            fi
        fi
        return 1
    fi
}

# Clone or update repository
setup_repository() {
    local repo_url="https://github.com/binghzal/homelab.git"
    local repo_dir="/opt/homelab"
    
    log_info "Setting up repository..."
    
    if [ ! -d "$repo_dir" ]; then
        mkdir -p "$repo_dir"
    fi
    
    if [ ! -d "$repo_dir/.git" ]; then
        log_info "Cloning repository to $repo_dir"
        git clone "$repo_url" "$repo_dir" || {
            log_error "Failed to clone repository from $repo_url to $repo_dir"
            exit 1
        }
    else
        log_info "Updating repository in $repo_dir"
        git -C "$repo_dir" fetch
        git -C "$repo_dir" reset --hard origin/main || {
            log_error "Failed to update repository in $repo_dir"
            exit 1
        }
    fi
    
    # Set proper permissions for scripts
    chmod -R 750 "$repo_dir/scripts" || {
        log_warn "Failed to set permissions on scripts directory"
    }
    
    log_info "Repository setup complete."
    return 0
}

# Setup configuration directories and files
setup_config() {
    local config_dir="/etc/homelab"
    local user_config="$config_dir/user.conf"
    local system_config="$config_dir/system.conf"
    
    log_info "Setting up configuration..."
    
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        chmod 750 "$config_dir"
        log_info "Created config directory: $config_dir"
    fi
    
    # Create user config if it doesn't exist
    if [ ! -f "$user_config" ]; then
        cat > "$user_config" << EOF
# Proxmox Template Creator - User Configuration
# Edit this file to customize the behavior of the template creator

# Default values for VM templates
DEFAULT_CPU=2
DEFAULT_MEMORY=2048
DEFAULT_STORAGE=16

# Storage pool to use for templates
STORAGE_POOL=local-lvm

# Network settings
BRIDGE=vmbr0

# Repository settings
REPO_URL=https://github.com/binghzal/homelab.git
REPO_BRANCH=main

# Update settings
AUTO_UPDATE=true
EOF
        chmod 640 "$user_config"
        log_info "Created user config: $user_config"
    fi
    
    # Create system config if it doesn't exist
    if [ ! -f "$system_config" ]; then
        cat > "$system_config" << EOF
# Proxmox Template Creator - System Configuration
# This file is managed by the installer - manual changes may be overwritten

# Installation details
INSTALL_DATE=$(date +%Y-%m-%d)
INSTALL_PATH="/opt/homelab"
VERSION="0.1.0"

# System detection
OS_ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
PROXMOX_DETECTED=$(command -v pveversion >/dev/null 2>&1 && echo "true" || echo "false")
EOF
        chmod 640 "$system_config"
        log_info "Created system config: $system_config"
    fi
    
    log_info "Configuration setup complete."
    return 0
}

# Setup systemd service for auto-updates (if enabled)
setup_service() {
    local service_file="/etc/systemd/system/homelab-updater.service"
    local timer_file="/etc/systemd/system/homelab-updater.timer"
    
    # Check if auto-update is enabled in user config
    local auto_update
    if [ -f "/etc/homelab/user.conf" ]; then
        auto_update=$(grep '^AUTO_UPDATE=' /etc/homelab/user.conf | cut -d'=' -f2)
    else
        auto_update="true"  # Default if config doesn't exist
    fi
    
    if [ "$auto_update" = "true" ]; then
        log_info "Setting up auto-update service..."
        
        # Create service file
        cat > "$service_file" << EOF
[Unit]
Description=Proxmox Template Creator Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/homelab/scripts/update.sh --silent
User=root

[Install]
WantedBy=multi-user.target
EOF
        
        # Create timer file for daily updates
        cat > "$timer_file" << EOF
[Unit]
Description=Run Proxmox Template Creator Updater daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        # Enable the timer
        systemctl daemon-reload
        systemctl enable homelab-updater.timer
        systemctl start homelab-updater.timer
        
        log_info "Auto-update service configured and enabled."
    else
        log_info "Auto-update disabled in configuration. Skipping service setup."
    fi
    
    return 0
}

# Main function - ties everything together
main() {
    log_info "Starting Proxmox Template Creator installation..."
    
    check_root
    check_os_compatibility
    check_dependencies
    check_proxmox
    setup_repository
    setup_config
    setup_service
    
    log_info "Installation complete! Launching main controller..."
    /opt/homelab/scripts/main.sh
    
    exit 0
}

# Run main function directly when this script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
