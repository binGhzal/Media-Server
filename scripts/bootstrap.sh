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
check_dependencies
setup_repository
launch_main
