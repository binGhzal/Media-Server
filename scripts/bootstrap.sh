#!/bin/bash
# Proxmox Template Creator - Bootstrap Script
# Phase 1: Initial version with root and dependency checks, repo handling, and main controller launch

set -e

# Source logging library
# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
if [ -f "$SCRIPT_DIR/lib/logging.sh" ]; then
    source "$SCRIPT_DIR/lib/logging.sh"
else
    # Fallback basic logging if library not found (should not happen in normal execution)
    log_info() { echo "[INFO] [bootstrap] $*"; } # Added script name for clarity
    log_warn() { echo "[WARN] [bootstrap] $*"; } # Added script name for clarity
    log_error() { echo "[ERROR] [bootstrap] $*"; } # Added script name for clarity
    log_debug() { echo "[DEBUG] [bootstrap] $*"; } # Added script name for clarity
    echo "ERROR: logging.sh library not found. Using basic fallback logging." >&2
    # Define a basic handle_error if logging.sh is not available
    # This basic version won't know about LOG_FILE from the library.
    handle_error() {
        local exit_code=${1:-$?} # Use first arg if provided, else current exit status
        local line_num=${2:-$LINENO} # Use second arg if provided, else current line number
        echo "[ERROR] [bootstrap] Error in script on line $line_num with exit code $exit_code." >&2
        exit "$exit_code"
    }
fi

# Initialize logging (call function from the library, if sourced)
if command -v init_logging >/dev/null 2>&1; then
    init_logging "Bootstrap"
else
    log_info "init_logging function not found. Skipping explicit logging initialization."
fi

# Set up error trap to use handle_error from logging.sh (or fallback)
# Pass exit code ($?) and line number ($LINENO)
trap 'handle_error $? $LINENO' ERR

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root or with sudo. Exiting with code 3 (Permission Denied)."
        exit 3 # Exit code 3 for Permission Denied, as per project standards
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
    local deps_to_check=(curl git whiptail jq wget qemu-img) # Removed duplicate curl
    local unique_deps=()
    # Create a unique list of dependencies
    eval "$(printf "%s\n" "${deps_to_check[@]}" | sort -u | awk '{printf "unique_deps+=(\"%s\")\n", $1}')"

    log_info "Checking dependencies: ${unique_deps[*]}..."
    local missing_deps=()
    for dep in "${unique_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_info "Installing missing dependencies: ${missing_deps[*]}"

        # Determine package manager
        if command -v apt-get >/dev/null 2>&1; then # Changed to apt-get
            log_info "Using apt-get package manager"
            apt-get update -qq # Added -qq
            apt-get install -y -qq "${missing_deps[@]}" || { # Added -qq
                log_error "Failed to install packages with apt-get."
                exit 1
            }
        elif command -v dnf >/dev/null 2>&1; then
            log_info "Using dnf package manager"
            dnf install -y "${missing_deps[@]}" || { # dnf typically doesn't need explicit update first
                log_error "Failed to install packages with dnf."
                exit 1
            }
        elif command -v yum >/dev/null 2>&1; then
            log_info "Using yum package manager"
            yum install -y "${missing_deps[@]}" || {
                log_error "Failed to install packages with yum."
                exit 1
            }
        elif command -v zypper >/dev/null 2>&1; then # Corrected missing `then` from previous read
            log_info "Using zypper package manager"
            zypper --non-interactive install "${missing_deps[@]}" || { # Added --non-interactive
                log_error "Failed to install packages with zypper."
                exit 1
            }
        else
            log_error "No supported package manager found. Please install manually: ${missing_deps[*]}"
            exit 1
        fi

        # Verify installation
        local still_missing=()
        for dep in "${missing_deps[@]}"; do
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
        if [ -t 0 ]; then # Check if stdin is a terminal
            # Use whiptail for a more consistent UI if available, otherwise fallback to read
            if command -v whiptail >/dev/null 2>&1; then
                if whiptail --title "Proxmox Detection" --yesno "Proxmox VE not detected. Some features may not be available. Continue anyway?" 8 78; then
                    log_info "User chose to continue without Proxmox VE."
                else
                    log_info "Installation cancelled by user."
                    exit 0
                fi
            else
                read -p "Continue without Proxmox VE? [y/N] " -n 1 -r REPLY
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Installation cancelled by user."
                    exit 0
                fi
            fi
        else
            log_warn "Non-interactive mode: Assuming 'yes' to continue without Proxmox VE."
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
        git clone --depth 1 "$repo_url" "$repo_dir" || { # Added --depth 1
            log_error "Failed to clone repository from $repo_url to $repo_dir."
            exit 1
        }
    else
        log_info "Updating repository in $repo_dir..."
        # Ensure we are in a git repository before attempting git operations
        if [ ! -d "$repo_dir/.git" ]; then # This check is a bit redundant given the outer if/else, but good for robustness
            log_error "$repo_dir is not a git repository. Cannot update. Please check or remove the directory and run again."
            exit 1
        fi

        # Stash local changes if any, to prevent conflicts with reset --hard
        if ! git -C "$repo_dir" diff-index --quiet HEAD --; then
            log_warn "Local changes detected in $repo_dir. Stashing before update..."
            if ! git -C "$repo_dir" stash push -u -m "Bootstrap auto-stash"; then
                log_warn "Failed to stash local changes. Update may fail if there are conflicts."
            else
                log_info "Local changes stashed with message 'Bootstrap auto-stash'."
            fi
        fi

        git -C "$repo_dir" fetch origin main || {
            log_error "Failed to fetch from repository in $repo_dir."
            if git -C "$repo_dir" stash list | grep -q "Bootstrap auto-stash"; then
                 log_info "Attempting to restore stashed changes due to fetch failure..."
                 git -C "$repo_dir" stash pop || log_warn "Failed to restore stashed changes. Please check manually: git -C $repo_dir stash list"
            fi
            exit 1
        }
        git -C "$repo_dir" reset --hard origin/main || {
            log_error "Failed to reset repository to origin/main in $repo_dir."
            if git -C "$repo_dir" stash list | grep -q "Bootstrap auto-stash"; then
                 log_info "Attempting to restore stashed changes due to reset failure..."
                 git -C "$repo_dir" stash pop || log_warn "Failed to restore stashed changes. Please check manually: git -C $repo_dir stash list"
            fi
            exit 1
        }
        # Log if changes were stashed and remain so.
        if git -C "$repo_dir" stash list | grep -q "Bootstrap auto-stash"; then
            log_info "Local changes were stashed prior to update and remain stashed. To reapply: git -C $repo_dir stash pop"
        fi
    fi

    # Set proper permissions for scripts
    if [ -d "$repo_dir/scripts" ]; then
        chmod -R u+rwx,g+rx,o-rwx "$repo_dir/scripts" || { # More specific permissions
            log_warn "Failed to set permissions on scripts directory $repo_dir/scripts. Execution of some scripts might fail."
        }
    else
        log_warn "Scripts directory $repo_dir/scripts not found. Skipping permission settings."
    fi

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
