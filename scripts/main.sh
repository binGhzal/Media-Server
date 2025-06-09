#!/bin/bash
# Proxmox Template Creator - Main Controller

set -e

# Script version
VERSION="0.2.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Source the centralized logging library
source "$SCRIPT_DIR/lib/logging.sh"

# Initialize logging system
init_logging "main"

# Set up error trap using the centralized error handler
trap 'handle_error $? $LINENO' ERR

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
        log_error "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Configuration management functions
create_default_config() {
    local config_file="$1"
    local config_dir
    config_dir="$(dirname "$config_file")"
    
    # Create config directory if it doesn't exist
    if [ "$EUID" -eq 0 ]; then
        mkdir -p "$config_dir"
    else
        mkdir -p "$config_dir" 2>/dev/null || {
            log_warn "Cannot create system config directory, using user config"
            config_file="$HOME/.config/homelab/user.conf"
            config_dir="$(dirname "$config_file")"
            mkdir -p "$config_dir"
        }
    fi
    
    # Create default config if it doesn't exist
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
# Proxmox Template Creator Configuration
# Auto-generated on $(date)

# Auto-update settings
AUTO_UPDATE=true
UPDATE_CHECK_INTERVAL=86400  # 24 hours in seconds

# Default VM settings
DEFAULT_CPU_CORES=2
DEFAULT_RAM_MB=2048
DEFAULT_DISK_GB=20

# Network settings
DEFAULT_BRIDGE=vmbr0
DEFAULT_NETWORK_MODEL=virtio

# Cloud-init defaults
DEFAULT_CLOUD_INIT_USER=clouduser
DEFAULT_DNS_SERVERS="1.1.1.1,8.8.8.8"

# Logging settings
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30

# Module settings
ENABLE_DOCKER=true
ENABLE_KUBERNETES=true
ENABLE_MONITORING=true
ENABLE_TERRAFORM=true
EOF
        log_info "Created default configuration at $config_file"
    fi
    
    echo "$config_file"
}

# Function to get configuration value
get_config() {
    local key="$1"
    local default="$2"
    local value
    
    if [ -f "$USER_CONFIG" ]; then
        value=$(grep "^$key=" "$USER_CONFIG" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Function to set configuration value
set_config() {
    local key="$1"
    local value="$2"
    
    if [ ! -f "$USER_CONFIG" ]; then
        USER_CONFIG=$(create_default_config "$USER_CONFIG")
    fi
    
    if grep -q "^$key=" "$USER_CONFIG" 2>/dev/null; then
        sed -i "s/^$key=.*/$key=$value/" "$USER_CONFIG"
    else
        echo "$key=$value" >> "$USER_CONFIG"
    fi
    
    log_info "Updated configuration: $key=$value"
}

# Load configuration
CONFIG_DIR="/etc/homelab"
USER_CONFIG="$CONFIG_DIR/user.conf"

# Create default config if needed
USER_CONFIG=$(create_default_config "$USER_CONFIG")

# Source configuration file
if [ -f "$USER_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$USER_CONFIG"
    log_info "Loaded configuration from $USER_CONFIG"
else
    log_warn "Configuration file not found, using defaults"
fi

# Dependency management functions
check_dependencies() {
    local missing_deps=()
    local required_deps=(curl wget whiptail jq git)
    
    log_info "Checking dependencies..."
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        
        if [ -t 0 ]; then  # If running interactively
            if whiptail --title "Missing Dependencies" --yesno "Missing required tools: ${missing_deps[*]}\n\nAttempt to install them automatically?" 12 70; then
                install_dependencies "${missing_deps[@]}"
            else
                log_error "Cannot proceed without required dependencies"
                exit 1
            fi
        else
            log_error "Cannot proceed without required dependencies"
            exit 1
        fi
    else
        log_info "All dependencies satisfied"
    fi
}

install_dependencies() {
    local deps=("$@")
    log_info "Installing dependencies: ${deps[*]}"
    
    # Detect package manager and install dependencies
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y "${deps[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${deps[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${deps[@]}"
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y "${deps[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm "${deps[@]}"
    else
        log_error "No supported package manager found"
        return 1
    fi
}

# Check for updates if not in test mode
if [ -z "$TEST_MODE" ]; then
    # Check dependencies first
    check_dependencies
    
    # Check for updates
    if [ "$(get_config "AUTO_UPDATE" "true")" = "true" ]; then
        if [ -x "$SCRIPT_DIR/update.sh" ]; then
            "$SCRIPT_DIR/update.sh" --check-only
        fi
    fi
fi

# Welcome message
whiptail --title "Proxmox Template Creator v${VERSION}" --msgbox "Welcome to the Proxmox Template Creator!\n\nSelect a module to begin." 10 60 3>&1 1>&2 2>&3

# Dynamic module discovery function
discover_modules() {
    local modules=()
    
    # Define module metadata
    declare -A MODULE_INFO=(
        ["template.sh"]="VM Templates|Create and manage VM templates|Complete"
        ["containers.sh"]="Containers|Deploy Docker and Kubernetes workloads|Partial"
        ["terraform.sh"]="Terraform|Infrastructure as Code automation|Skeleton"
        ["config.sh"]="Configuration|System and user configuration options|Skeleton"
        ["monitoring.sh"]="Monitoring|Setup monitoring solutions|Skeleton"
        ["registry.sh"]="Registry|Container registry management|Skeleton"
        ["update.sh"]="Update|Check for and apply updates|Complete"
    )
    
    # Discover modules dynamically
    for script in "$SCRIPT_DIR"/*.sh; do
        local script_name
        script_name="$(basename "$script")"
        
        # Skip main script and bootstrap
        if [ "$script_name" = "main.sh" ] || [ "$script_name" = "bootstrap.sh" ] || [ "$script_name" = "test_functions.sh" ]; then
            continue
        fi
        
        # Check if script exists and is executable
        if [ -x "$script" ]; then
            local info="${MODULE_INFO[$script_name]}"
            if [ -n "$info" ]; then
                modules+=("$script_name|$info")
            else
                # Unknown module, add with basic info
                modules+=("$script_name|Unknown|Auto-discovered module|Unknown")
            fi
        fi
    done
    
    printf '%s\n' "${modules[@]}"
}

# Check module status
check_module_status() {
    local module="$1"
    local status="Working"
    
    # Check if module has basic structure
    if [ -x "$SCRIPT_DIR/$module" ]; then
        if grep -q "#!/bin/bash" "$SCRIPT_DIR/$module" && grep -q "set -e" "$SCRIPT_DIR/$module"; then
            status="Working"
        else
            status="Incomplete"
        fi
    else
        status="Missing"
    fi
    
    echo "$status"
}

# Build menu from discovered modules
build_module_menu() {
    local modules
    local menu_args=()
    
    readarray -t modules < <(discover_modules)
    
    for module_entry in "${modules[@]}"; do
        IFS='|' read -r script_name display_name description status <<< "$module_entry"
        
        # Get current module status
        local current_status
        current_status=$(check_module_status "$script_name")
        
        # Format menu entry with status
        if [ "$current_status" = "Working" ]; then
            menu_args+=("$script_name" "✓ $display_name - $description")
        elif [ "$current_status" = "Incomplete" ]; then
            menu_args+=("$script_name" "⚠ $display_name - $description (Incomplete)")
        else
            menu_args+=("$script_name" "✗ $display_name - $description (Issues)")
        fi
    done
    
    printf '%s\n' "${menu_args[@]}"
}

# Get available modules for menu
readarray -t MENU_ARGS < <(build_module_menu)

# Display the menu if there are modules available
if [ ${#MENU_ARGS[@]} -eq 0 ]; then
    whiptail --title "Error" --msgbox "No modules found or accessible in $SCRIPT_DIR.\nPlease check your installation." 10 60 3>&1 1>&2 2>&3
    log_error "No modules found or accessible in $SCRIPT_DIR"
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
