#!/bin/bash
# Proxmox Template Creator - Main Controller

set -e

# Script version
VERSION="0.2.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

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
    log "ERROR" "An error occurred on line $1 with exit code $exit_code"
    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            shift
            ;;
        --help|-h)
            cat << EOF
Proxmox Template Creator v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test         Run in test mode (no actual VM creation)
  --help, -h     Show this help message
  --version, -v  Show version information
  --list-modules Show available modules

EOF
            exit 0
            ;;
        --version|-v)
            echo "Proxmox Template Creator v${VERSION}"
            exit 0
            ;;
        --list-modules)
            echo "Available modules:"
            for module in "$SCRIPT_DIR"/*.sh; do
                if [ "$(basename "$module")" != "main.sh" ] && [ "$(basename "$module")" != "bootstrap.sh" ]; then
                    echo "- $(basename "$module")"
                fi
            done
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Load configuration
CONFIG_DIR="/etc/homelab"
USER_CONFIG="$CONFIG_DIR/user.conf"
if [ -f "$USER_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$USER_CONFIG"
fi

# Check for updates if not in test mode
if [ -z "$TEST_MODE" ] && [ "$AUTO_UPDATE" != "false" ]; then
    if [ -x "$SCRIPT_DIR/update.sh" ]; then
        "$SCRIPT_DIR/update.sh" --check-only
    fi
fi

# Welcome message
whiptail --title "Proxmox Template Creator v${VERSION}" --msgbox "Welcome to the Proxmox Template Creator!\n\nSelect a module to begin." 10 60 3>&1 1>&2 2>&3

# Define available modules with descriptions
# Format: "script_name|Display Name|Description"
AVAILABLE_MODULES=(
    "template.sh|VM Templates|Create and manage VM templates"
    "containers.sh|Containers|Deploy Docker and Kubernetes workloads"
    "terraform.sh|Terraform|Infrastructure as Code automation"
    "config.sh|Configuration|System and user configuration options"
    "monitoring.sh|Monitoring|Setup monitoring solutions"
    "registry.sh|Registry|Container registry management"
    "update.sh|Update|Check for and apply updates"
)

# Build menu arguments from AVAILABLE_MODULES array
MENU_ARGS=()
for module_entry in "${AVAILABLE_MODULES[@]}"; do
    IFS='|' read -r script_name display_name description <<< "$module_entry"
    
    # Check if the module script exists and is executable
    if [ -x "$SCRIPT_DIR/$script_name" ]; then
        MENU_ARGS+=("$script_name" "$display_name - $description")
    fi
done

# Display the menu if there are modules available
if [ ${#MENU_ARGS[@]} -eq 0 ]; then
    whiptail --title "Error" --msgbox "No modules found or accessible in $SCRIPT_DIR.\nPlease check your installation." 10 60 3>&1 1>&2 2>&3
    log "ERROR" "No modules found or accessible in $SCRIPT_DIR"
    exit 1
fi

# Show module selection menu
CHOICE=$(whiptail --title "Select Module" --menu "Choose a module to run:" 20 70 10 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
EXIT_STATUS=$?

if [ $EXIT_STATUS -eq 0 ]; then
    log "INFO" "Selected module: $CHOICE"
    MODULE_PATH="$SCRIPT_DIR/$CHOICE"
    
    # Run the selected module with test flag if in test mode
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Running in test mode"
        "$MODULE_PATH" --test
    else
        "$MODULE_PATH"
    fi
    
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -ne 0 ]; then
        log "ERROR" "Module $CHOICE exited with status $EXIT_STATUS"
        whiptail --title "Module Error" --msgbox "The selected module encountered an error.\nPlease check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    
    # Ask if user wants to return to main menu or exit
    if (whiptail --title "Continue" --yesno "Return to main menu?" 10 60 3>&1 1>&2 2>&3); then
        exec "$SCRIPT_DIR/main.sh"
    else
        log "INFO" "User exited after module completion."
        exit 0
    fi
else
    log "INFO" "User exited main menu."
    exit 0
fi
