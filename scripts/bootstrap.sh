#!/bin/bash
# Proxmox Template Creator - Bootstrap Script
# Phase 1: Initial version with root and dependency checks, repo handling, and main controller launch

set -e

# Logging function
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root or with sudo."
        exit 1
    fi
    log "INFO" "Running as root: OK"
}

# Check OS compatibility
check_os_compatibility() {
    local supported_os=("debian" "ubuntu" "centos" "rocky" "almalinux" "opensuse" "sles")
    local os_id
    if [ -f /etc/os-release ]; then
        os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        for os in "${supported_os[@]}"; do
            if [[ "$os_id" == "$os" ]]; then
                log "INFO" "Detected supported OS: $os_id"
                return 0
            fi
        done
        log "ERROR" "Unsupported OS: $os_id. Supported: ${supported_os[*]}"
        exit 1
    else
        log "ERROR" "/etc/os-release not found. Cannot determine OS."
        exit 1
    fi
}

# Check and install dependencies
check_dependencies() {
    local deps=(curl git whiptail jq)
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing[*]}"
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y "${missing[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "${missing[@]}"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "${missing[@]}"
        elif command -v zypper >/dev/null 2>&1; then
            zypper install -y "${missing[@]}"
        else
            log "ERROR" "No supported package manager found. Install dependencies manually: ${missing[*]}"
            exit 1
        fi
    else
        log "INFO" "All dependencies present."
    fi
}

# Detect Proxmox environment
check_proxmox() {
    if pveversion >/dev/null 2>&1; then
        log "INFO" "Proxmox detected: $(pveversion)"
    else
        log "WARN" "Proxmox VE not detected. Some features may not work."
    fi
}

# Clone or update repository
setup_repository() {
    local repo_url="https://github.com/binghzal/homelab.git"
    local repo_dir="/opt/homelab"
    if [ ! -d "$repo_dir/.git" ]; then
        log "INFO" "Cloning repository to $repo_dir"
        git clone "$repo_url" "$repo_dir"
    else
        log "INFO" "Updating repository in $repo_dir"
        git -C "$repo_dir" pull
    fi
    chmod -R 750 "$repo_dir/scripts" || true
}

# Setup configuration directories and files
setup_config() {
    local config_dir="/etc/homelab"
    local user_config="$config_dir/user.conf"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        chmod 750 "$config_dir"
        log "INFO" "Created config directory: $config_dir"
    fi
    if [ ! -f "$user_config" ]; then
        touch "$user_config"
        chmod 640 "$user_config"
        log "INFO" "Created user config: $user_config"
    fi
}

# Launch main controller
launch_main() {
    local main_script="/opt/homelab/scripts/main.sh"
    if [ -x "$main_script" ]; then
        log "INFO" "Launching main controller..."
        "$main_script"
    else
        log "ERROR" "Main controller script not found or not executable: $main_script"
        exit 1
    fi
}

# Main bootstrap flow
check_root
check_os_compatibility
check_dependencies
check_proxmox
setup_repository
setup_config
launch_main
