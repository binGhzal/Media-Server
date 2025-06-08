#!/bin/bash
# Proxmox Template Creator - Main Controller

set -e

# Logging function (reuse from bootstrap)
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# Welcome message
whiptail --title "Proxmox Template Creator" --msgbox "Welcome to the Proxmox Template Creator!\n\nSelect a module to begin." 10 60

# List available modules
MODULES=(
    "template.sh" "VM Template Creation"
    "containers.sh" "Container Workloads"
    "terraform.sh" "Infrastructure as Code"
    "config.sh" "Configuration Management"
    "monitoring.sh" "Monitoring Stack"
    "registry.sh" "Container Registry"
    "update.sh" "Auto-Update"
)

# Build menu arguments from MODULES array
MENU_ARGS=()
for ((i=0; i<${#MODULES[@]}; i+=2)); do
    MENU_ARGS+=("${MODULES[i]}" "${MODULES[i+1]}")
done

CHOICE=$(whiptail --title "Select Module" --menu "Choose a module to run:" 20 60 8 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)

if [ $? -eq 0 ]; then
    log "INFO" "Selected module: $CHOICE"
    MODULE_PATH="$(dirname "$0")/$CHOICE"
    if [ -x "$MODULE_PATH" ]; then
        "$MODULE_PATH"
    else
        whiptail --title "Error" --msgbox "Module script not found or not executable: $MODULE_PATH" 10 60
        log "ERROR" "Module script not found or not executable: $MODULE_PATH"
        exit 1
    fi
else
    log "INFO" "User exited main menu."
    exit 0
fi
