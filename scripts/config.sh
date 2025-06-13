#!/usr/bin/env bash
# Proxmox Template Creator - Configuration Management Module
# Centralized configuration management for all modules

# Enable strict mode for better error handling and debugging
set -o errexit          # Exit on any error
set -o nounset          # Exit on unset variables
set -o pipefail         # Ensure pipelines fail on any error
set -o errtrace         # Ensure ERR traps are inherited in functions

# Set IFS to newline and tab only to prevent word splitting issues
IFS=$'\n\t'

# Disable globbing to prevent unwanted filename expansion
set -o noglob

# Script metadata
readonly VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "${0}")
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly LOCK_FILE="/var/run/${SCRIPT_NAME%.*}.lock"

# Export necessary variables
export SCRIPT_NAME SCRIPT_DIR VERSION

# Source logging library if available
if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
    # shellcheck source=lib/logging.sh
    source "${SCRIPT_DIR}/lib/logging.sh"
    if ! init_logging "ConfigModule" 2>/dev/null; then
        echo "Failed to initialize logging" >&2
        exit 1
    fi
else
    # Fallback logging function
    log() {
        local level="${1}"
        local message="${2:-}"
        local color=""
        local reset="\033[0m"

        case "${level}" in
            INFO) color="\033[0;32m" ;;
            WARN) color="\033[0;33m" ;;
            ERROR) color="\033[0;31m" ;;
            DEBUG) color="\033[0;36m" ;;
            *) color="" ;;
        esac

        # Use printf instead of echo -e for better portability
        printf "%b[%s] [%s] %s%b\n" \
            "${color}" "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "${message}" "${reset}" >&2
    }

    # Define log level functions for compatibility
    log_info() { log "INFO" "${1:-}"; }
    log_warn() { log "WARN" "${1:-}"; }
    log_error() { log "ERROR" "${1:-}"; }
    log_debug() { log "DEBUG" "${1:-}"; }
fi

# Log script start
log_info "Starting ${SCRIPT_NAME} v${VERSION}"
log_debug "Script directory: ${SCRIPT_DIR}"

# Configuration directories and files
readonly CONFIG_DIR="${CONFIG_DIR:-/etc/homelab}"
readonly USER_CONFIG="${CONFIG_DIR}/user.conf"
readonly SYSTEM_CONFIG="${CONFIG_DIR}/system.conf"
readonly MODULE_CONFIG_DIR="${CONFIG_DIR}/modules"
readonly BACKUP_DIR="${CONFIG_DIR}/backups"
readonly TEMPLATES_DIR="${CONFIG_DIR}/templates"

# Ensure required variables are set
: "${USER:?USER environment variable not set}"
: "${HOME:?HOME environment variable not set}"

# Default configuration values
declare -rA DEFAULT_CONFIG=(
    [AUTO_UPDATE]="true"
    [LOG_LEVEL]="INFO"
    [BACKUP_RETENTION_DAYS]="30"
    [DEFAULT_VM_STORAGE]="local-lvm"
    [DEFAULT_VM_BRIDGE]="vmbr0"
    [DEFAULT_VM_MEMORY]="2048"
    [DEFAULT_VM_CORES]="2"
    [DEFAULT_VM_DISK_SIZE]="20"
    [ENABLE_CLOUD_INIT]="true"
    [DEFAULT_SSH_USER]="${SUDO_USER:-$USER}"
    [MONITORING_ENABLED]="false"
    [REGISTRY_ENABLED]="false"
    [TERRAFORM_ENABLED]="false"
    [ANSIBLE_ENABLED]="false"
)

# Validate configuration values
for key in "${!DEFAULT_CONFIG[@]}"; do
    if [[ -z "${DEFAULT_CONFIG[$key]}" ]]; then
        log_error "Empty default value for key: ${key}"
        exit 1
    fi
done

# Error handling function
handle_error() {
    local -r exit_code="${1:-1}"
    local -r line_no="${2:-0}"
    local -r script_name="${BASH_SOURCE[1]##*/}"
    local -r func_name="${FUNCNAME[1]:-main}"

    # Log the error
    log_error "Error in ${script_name}:${line_no} (function: ${func_name}): ${BASH_COMMAND}"

    # If we have a line number and file, show more context
    if [[ ${line_no} -gt 0 ]]; then
        log_error "Near line ${line_no} in ${script_name} (function: ${func_name}):"
        if [[ -f "${BASH_SOURCE[1]}" ]]; then
            local -r context_lines=5
            local -r start_line=$((line_no > context_lines ? line_no - context_lines : 1))
            local -r end_line=$((line_no + context_lines))

            log_error "Context (${start_line}-${end_line}):"
            # Use sed to extract context lines with line numbers
            sed -n "${start_line},${end_line}p;${end_line}q" "${BASH_SOURCE[1]}" 2>/dev/null | \
            while IFS= read -r line; do
                log_error "  ${start_line}: ${line}"
                start_line=$((start_line + 1))
            done
        fi
    fi

    # If running interactively, show a dialog
    if [[ -t 0 ]] && command -v whiptail >/dev/null 2>&1; then
        whiptail --title "Error" --msgbox "An error occurred (code: ${exit_code}). Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi

    # Exit with the provided status code
    exit "${exit_code}"
}

# Set up error trap
trap 'handle_error $? ${LINENO}' ERR

# Parse command line arguments
parse_arguments() {
    local -r script_name="${0##*/}"

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --test)
                readonly TEST_MODE=1
                log_info "Test mode enabled - no changes will be made"
                shift
                ;;
            --quiet | -q)
                # QUIET_MODE option is deprecated and ignored
                log_warn "--quiet/-q option is deprecated and will be removed in a future version"
                shift
                ;;
            --debug)
                set -x
                log_info "Debug mode enabled"
                shift
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            --version | -v)
                echo "${script_name} v${VERSION}"
                exit 0
                ;;
            -*)
                log_error "Unknown option: ${1}"
                show_usage
                exit 1
                ;;
            *)
                log_error "Unexpected argument: ${1}"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    cat << EOF
Proxmox Template Creator - Configuration Management Module v${VERSION}

Usage: ${0##*/} [OPTIONS]

Options:
  --test              Run in test mode (no actual changes)
  --quiet, -q         Run in quiet mode (minimal output) [DEPRECATED]
  --debug             Enable debug output
  --help, -h          Show this help message
  --version, -v       Show version information

Functions:
  - Centralized configuration management
  - User and system preferences
  - Module-specific settings
  - Configuration validation and migration
  - Import/export configuration profiles
  - Backup and restore configurations

Environment Variables:
  CONFIG_DIR          Override the default configuration directory
  LOG_LEVEL           Set the log level (DEBUG, INFO, WARN, ERROR)

Examples:
  ${0##*/} --test      # Run in test mode
  LOG_LEVEL=DEBUG ${0##*/}  # Enable debug logging

Report bugs to: <your-email@example.com>
Project home: <https://github.com/yourusername/proxmox-template-creator>
EOF
}

# Initialize the script
initialize() {
    # Parse command line arguments
    parse_arguments "$@"

    # Check for required commands
    local -a required_commands=("basename" "dirname" "date" "mkdir" "chmod")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_error "Required command not found: ${cmd}"
            exit 1
        fi
    done

    # Create configuration directories if they don't exist
    create_config_dirs

    # Initialize default configuration
    init_default_config

    log_info "Initialization completed successfully"
}

# Function to check if running as root or with sudo
check_privileges() {
    local -r user_id=$(id -u)

    if [[ ${user_id} -eq 0 ]]; then
        log_debug "Running with root privileges"
        return 0
    fi

    log_error "This script must be run as root or with sudo"
    exit 1
}

# Function to acquire an exclusive lock
acquire_lock() {
    local -r lock_file="${1}"
    local -r lock_timeout=300  # 5 minutes
    local -r pid=$$

    # Try to create the lock file
    if ( set -o noclobber; echo "${pid}" > "${lock_file}" ) 2>/dev/null; then
        # Set a trap to remove the lock file on exit
        trap 'rm -f "${lock_file}"' EXIT
        return 0
    fi

    # Check if the lock file is stale
    if [[ -f "${lock_file}" ]]; then
        local -r lock_pid=$(cat "${lock_file}" 2>/dev/null)

        # Check if the process that created the lock is still running
        if ! ps -p "${lock_pid}" >/dev/null 2>&1; then
            log_warn "Removing stale lock file (PID: ${lock_pid})"
            rm -f "${lock_file}"

            # Try to acquire the lock again
            if ( set -o noclobber; echo "${pid}" > "${lock_file}" ) 2>/dev/null; then
                trap 'rm -f "${lock_file}"' EXIT
                return 0
            fi
        fi
    fi

    log_error "Failed to acquire lock. Another instance might be running."
    exit 1
}

# Function to create configuration directories
create_config_dirs() {
    log "INFO" "Creating configuration directories..."

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would create configuration directories"
        return 0
    fi

    # Create main directories
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$MODULE_CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$TEMPLATES_DIR"

    # Set proper permissions
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$MODULE_CONFIG_DIR"
    chmod 700 "$BACKUP_DIR"
    chmod 755 "$TEMPLATES_DIR"

    log "INFO" "Configuration directories created successfully"
    return 0
}

# Function to initialize default configuration
init_default_config() {
    log "INFO" "Initializing default configuration..."

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would initialize default configuration"
        return 0
    fi

    # Create system config if it doesn't exist
    if [ ! -f "$SYSTEM_CONFIG" ]; then
        log "INFO" "Creating system configuration file"

        cat > "$SYSTEM_CONFIG" << EOF
# Proxmox Template Creator - System Configuration
# This file contains system-wide settings
# Generated on $(date)

# System Information
HOMELAB_VERSION="$VERSION"
INSTALL_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
INSTALL_PATH="/opt/homelab"

# Default Settings
EOF

        # Add default configuration values
        for key in "${!DEFAULT_CONFIG[@]}"; do
            echo "${key}=\"${DEFAULT_CONFIG[$key]}\"" >> "$SYSTEM_CONFIG"
        done

        chmod 644 "$SYSTEM_CONFIG"
        log "INFO" "System configuration file created"
    fi

    # Create user config if it doesn't exist
    if [ ! -f "$USER_CONFIG" ]; then
        log "INFO" "Creating user configuration file"

        cat > "$USER_CONFIG" << EOF
# Proxmox Template Creator - User Configuration
# This file contains user-specific settings and overrides
# Generated on $(date)

# User Preferences (override system defaults here)
# Example: DEFAULT_VM_MEMORY="4096"

EOF

        chmod 644 "$USER_CONFIG"
        log "INFO" "User configuration file created"
    fi

    return 0
}

# Function to get configuration value
get_config() {
    local key="$1"
    local default_value="$2"
    local config_file="$3"

    # If no config file specified, check user config first, then system config
    if [ -z "$config_file" ]; then
        # Check user config first
        if [ -f "$USER_CONFIG" ] && grep -q "^${key}=" "$USER_CONFIG"; then
            grep "^${key}=" "$USER_CONFIG" | cut -d'=' -f2- | sed 's/^"//;s/"$//'
            return 0
        fi

        # Check system config
        if [ -f "$SYSTEM_CONFIG" ] && grep -q "^${key}=" "$SYSTEM_CONFIG"; then
            grep "^${key}=" "$SYSTEM_CONFIG" | cut -d'=' -f2- | sed 's/^"//;s/"$//'
            return 0
        fi

        # Return default value if provided
        if [ -n "$default_value" ]; then
            echo "$default_value"
            return 0
        fi

        # Return empty if no default
        echo ""
        return 1
    else
        # Check specific config file
        if [ -f "$config_file" ] && grep -q "^${key}=" "$config_file"; then
            grep "^${key}=" "$config_file" | cut -d'=' -f2- | sed 's/^"//;s/"$//'
            return 0
        fi

        # Return default value if provided
        if [ -n "$default_value" ]; then
            echo "$default_value"
            return 0
        fi

        echo ""
        return 1
    fi
}

# Function to set configuration value
set_config() {
    local key="$1"
    local value="$2"
    local config_file="${3:-$USER_CONFIG}"
    local scope="${4:-user}"  # user or system

    if [ -z "$key" ] || [ -z "$value" ]; then
        log "ERROR" "Key and value are required for set_config"
        return 1
    fi

    # Validate key format
    if ! [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        log "ERROR" "Invalid key format: $key (use uppercase letters, numbers, and underscores)"
        return 1
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would set $key=$value in $config_file"
        return 0
    fi

    # Determine config file based on scope
    if [ "$scope" = "system" ]; then
        config_file="$SYSTEM_CONFIG"
    else
        config_file="$USER_CONFIG"
    fi

    # Create config file if it doesn't exist
    if [ ! -f "$config_file" ]; then
        if [ "$scope" = "system" ]; then
            init_default_config
        else
            touch "$config_file"
            chmod 644 "$config_file"
        fi
    fi

    # Backup current config
    backup_config_file "$config_file"

    # Check if key exists
    if grep -q "^${key}=" "$config_file"; then
        # Update existing key
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
        log "INFO" "Updated configuration: $key=$value"
    else
        # Add new key
        echo "${key}=\"${value}\"" >> "$config_file"
        log "INFO" "Added configuration: $key=$value"
    fi

    return 0
}

# Function to remove configuration value
remove_config() {
    local key="$1"
    local config_file="${2:-$USER_CONFIG}"

    if [ -z "$key" ]; then
        log "ERROR" "Key is required for remove_config"
        return 1
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would remove $key from $config_file"
        return 0
    fi

    if [ ! -f "$config_file" ]; then
        log "WARN" "Configuration file does not exist: $config_file"
        return 1
    fi

    # Backup current config
    backup_config_file "$config_file"

    # Remove key
    if grep -q "^${key}=" "$config_file"; then
        sed -i "/^${key}=/d" "$config_file"
        log "INFO" "Removed configuration: $key"
        return 0
    else
        log "WARN" "Configuration key not found: $key"
        return 1
    fi
}

# Function to backup configuration file
backup_config_file() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file
    backup_file="$BACKUP_DIR/$(basename "$config_file").backup.$timestamp"

    cp "$config_file" "$backup_file"

    # Keep only last 10 backups per file
    local base_name
    base_name=$(basename "$config_file")
    find "$BACKUP_DIR" -name "${base_name}.backup.*" -type f | sort -r | tail -n +11 | xargs -r rm -f

    return 0
}

# Function to validate configuration
validate_config() {
    local config_file="${1:-$USER_CONFIG}"
    local errors=0

    log "INFO" "Validating configuration file: $config_file"

    if [ ! -f "$config_file" ]; then
        log "ERROR" "Configuration file does not exist: $config_file"
        return 1
    fi

    # Check for syntax errors
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Check for valid key=value format
        if ! [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=.*$ ]]; then
            log "ERROR" "Invalid configuration line: $line"
            ((errors++))
        fi
    done < "$config_file"

    # Validate specific configuration values
    local auto_update
    auto_update=$(get_config "AUTO_UPDATE" "" "$config_file")
    if [ -n "$auto_update" ] && [[ ! "$auto_update" =~ ^(true|false)$ ]]; then
        log "ERROR" "AUTO_UPDATE must be 'true' or 'false', got: $auto_update"
        ((errors++))
    fi

    local log_level
    log_level=$(get_config "LOG_LEVEL" "" "$config_file")
    if [ -n "$log_level" ] && [[ ! "$log_level" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]]; then
        log "ERROR" "LOG_LEVEL must be one of: DEBUG, INFO, WARN, ERROR, got: $log_level"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        log "INFO" "Configuration validation passed"
        return 0
    else
        log "ERROR" "Configuration validation failed with $errors errors"
        return 1
    fi
}

# Function to list all configuration values
list_config() {
    local config_file="${1:-all}"
    local show_defaults="${2:-false}"

    log "INFO" "Configuration Settings:"
    echo "========================"

    if [ "$config_file" = "all" ] || [ "$config_file" = "system" ]; then
        if [ -f "$SYSTEM_CONFIG" ]; then
            echo ""
            echo "System Configuration ($SYSTEM_CONFIG):"
            echo "----------------------------------------"
            grep -E '^[A-Z_][A-Z0-9_]*=' "$SYSTEM_CONFIG" | sort
        fi
    fi

    if [ "$config_file" = "all" ] || [ "$config_file" = "user" ]; then
        if [ -f "$USER_CONFIG" ]; then
            echo ""
            echo "User Configuration ($USER_CONFIG):"
            echo "-----------------------------------"
            if [ -s "$USER_CONFIG" ]; then
                grep -E '^[A-Z_][A-Z0-9_]*=' "$USER_CONFIG" | sort
            else
                echo "(No user overrides configured)"
            fi
        fi
    fi

    if [ "$show_defaults" = "true" ]; then
        echo ""
        echo "Default Values:"
        echo "---------------"
        for key in "${!DEFAULT_CONFIG[@]}"; do
            echo "${key}=\"${DEFAULT_CONFIG[$key]}\""
        done | sort
    fi

    echo ""
    return 0
}

# Function to export configuration
export_config() {
    local output_file="$1"
    local include_system="${2:-true}"
    local include_user="${3:-true}"

    if [ -z "$output_file" ]; then
        log "ERROR" "Output file is required for export_config"
        return 1
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would export configuration to $output_file"
        return 0
    fi

    log "INFO" "Exporting configuration to: $output_file"

    # Create export file with header
    cat > "$output_file" << EOF
# Proxmox Template Creator - Configuration Export
# Generated on $(date)
# Export includes: system=$include_system, user=$include_user

EOF

    if [ "$include_system" = "true" ] && [ -f "$SYSTEM_CONFIG" ]; then
        echo "# System Configuration" >> "$output_file"
        grep -E '^[A-Z_][A-Z0-9_]*=' "$SYSTEM_CONFIG" >> "$output_file"
        echo "" >> "$output_file"
    fi

    if [ "$include_user" = "true" ] && [ -f "$USER_CONFIG" ]; then
        echo "# User Configuration" >> "$output_file"
        grep -E '^[A-Z_][A-Z0-9_]*=' "$USER_CONFIG" >> "$output_file"
        echo "" >> "$output_file"
    fi

    log "INFO" "Configuration exported successfully"
    return 0
}

# Function to import configuration
import_config() {
    local input_file="$1"
    local target_scope="${2:-user}"  # user or system
    local backup_existing="${3:-true}"

    if [ -z "$input_file" ]; then
        log "ERROR" "Input file is required for import_config"
        return 1
    fi

    if [ ! -f "$input_file" ]; then
        log "ERROR" "Input file does not exist: $input_file"
        return 1
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would import configuration from $input_file to $target_scope scope"
        return 0
    fi

    log "INFO" "Importing configuration from: $input_file"

    # Determine target config file
    local target_file
    if [ "$target_scope" = "system" ]; then
        target_file="$SYSTEM_CONFIG"
    else
        target_file="$USER_CONFIG"
    fi

    # Backup existing configuration
    if [ "$backup_existing" = "true" ]; then
        backup_config_file "$target_file"
    fi

    # Validate import file first
    if ! validate_config "$input_file"; then
        log "ERROR" "Import file validation failed"
        return 1
    fi

    # Import configuration values
    local imported=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Extract key and value
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes if present
            value=$(echo "$value" | sed 's/^"//;s/"$//')

            # Set configuration
            if set_config "$key" "$value" "$target_file" "$target_scope"; then
                ((imported++))
            fi
        fi
    done < "$input_file"

    log "INFO" "Configuration import completed: $imported values imported"
    return 0
}

# Function to reset configuration to defaults
reset_config() {
    local scope="${1:-user}"  # user, system, or all
    local confirm="${2:-true}"

    if [ "$confirm" = "true" ] && [ -t 0 ]; then
        if ! whiptail --title "Reset Configuration" --yesno "Are you sure you want to reset $scope configuration to defaults?\n\nThis action cannot be undone!" 10 60; then
            log "INFO" "Configuration reset cancelled"
            return 0
        fi
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would reset $scope configuration to defaults"
        return 0
    fi

    log "INFO" "Resetting $scope configuration to defaults..."

    case "$scope" in
        "user")
            if [ -f "$USER_CONFIG" ]; then
                backup_config_file "$USER_CONFIG"
                cat > "$USER_CONFIG" << EOF
# Proxmox Template Creator - User Configuration
# This file contains user-specific settings and overrides
# Reset to defaults on $(date)

# User Preferences (override system defaults here)
# Example: DEFAULT_VM_MEMORY="4096"

EOF
                log "INFO" "User configuration reset to defaults"
            fi
            ;;
        "system")
            if [ -f "$SYSTEM_CONFIG" ]; then
                backup_config_file "$SYSTEM_CONFIG"
                rm -f "$SYSTEM_CONFIG"
                init_default_config
                log "INFO" "System configuration reset to defaults"
            fi
            ;;
        "all")
            reset_config "user" "false"
            reset_config "system" "false"
            log "INFO" "All configuration reset to defaults"
            ;;
        *)
            log "ERROR" "Invalid scope: $scope (use: user, system, or all)"
            return 1
            ;;
    esac

    return 0
}

# Function to manage module-specific configuration
manage_module_config() {
    local module_name="$1"

    # Show available modules if no module name provided
    if [ -z "$module_name" ]; then
        local modules=()
        if [ -d "$MODULE_CONFIG_DIR" ]; then
            for config_file in "$MODULE_CONFIG_DIR"/*.conf; do
                if [ -f "$config_file" ]; then
                    local module
                    module=$(basename "$config_file" .conf)
                    modules+=("$module")
                fi
            done
        fi

        # Add known modules even if no config exists yet
        local known_modules=("template" "containers" "terraform" "ansible" "monitoring" "registry")
        for module in "${known_modules[@]}"; do
            if [[ ! " ${modules[*]} " =~ \ ${module}\  ]]; then
                modules+=("$module")
            fi
        done

        if [ ${#modules[@]} -eq 0 ]; then
            whiptail --title "Module Configuration" --msgbox "No modules available for configuration." 10 60
            return 0
        fi

        # Create menu options
        local menu_options=()
        for module in "${modules[@]}"; do
            menu_options+=("$module" "Configure $module module")
        done

        module_name=$(whiptail --title "Module Configuration" --menu "Select a module to configure:" 20 70 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ] || [ -z "$module_name" ]; then
            return 0
        fi
    fi

    local module_config="$MODULE_CONFIG_DIR/${module_name}.conf"

    # Create module config if it doesn't exist
    if [ ! -f "$module_config" ]; then
        log "INFO" "Creating configuration for module: $module_name"

        if [ -n "$TEST_MODE" ]; then
            log "INFO" "[TEST MODE] Would create module config: $module_config"
        else
            cat > "$module_config" << EOF
# Proxmox Template Creator - $module_name Module Configuration
# Generated on $(date)

# Module-specific settings for $module_name
# Add your custom configuration below

EOF
            chmod 644 "$module_config"
        fi
    fi

    # Module configuration menu
    while true; do
        local choice
        choice=$(whiptail --title "$module_name Module Configuration" --menu "Choose an action:" 18 70 8 \
            "1" "View current configuration" \
            "2" "Edit configuration" \
            "3" "Add new setting" \
            "4" "Remove setting" \
            "5" "Reset to defaults" \
            "6" "Export configuration" \
            "7" "Import configuration" \
            "8" "Back to main menu" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                if [ -f "$module_config" ] && [ -s "$module_config" ]; then
                    whiptail --title "$module_name Configuration" --textbox "$module_config" 20 80
                else
                    whiptail --title "$module_name Configuration" --msgbox "No configuration found for $module_name module." 10 60
                fi
                ;;
            2)
                if command -v nano >/dev/null 2>&1; then
                    nano "$module_config"
                elif command -v vi >/dev/null 2>&1; then
                    vi "$module_config"
                else
                    whiptail --title "Error" --msgbox "No text editor available (nano or vi required)." 10 60
                fi
                ;;
            3)
                add_module_setting "$module_name"
                ;;
            4)
                remove_module_setting "$module_name"
                ;;
            5)
                reset_module_config "$module_name"
                ;;
            6)
                export_module_config "$module_name"
                ;;
            7)
                import_module_config "$module_name"
                ;;
            8|"")
                break
                ;;
        esac
    done
}

# Function to add module setting
add_module_setting() {
    local module_name="$1"
    local module_config="$MODULE_CONFIG_DIR/${module_name}.conf"

    local key
    key=$(whiptail --title "Add Setting" --inputbox "Enter setting name (uppercase, underscores allowed):" 10 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$key" ]; then
        return 0
    fi

    # Validate key format
    if ! [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        whiptail --title "Error" --msgbox "Invalid setting name. Use uppercase letters, numbers, and underscores only." 10 60
        return 1
    fi

    local value
    value=$(whiptail --title "Add Setting" --inputbox "Enter value for $key:" 10 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return 0
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would add $key=$value to $module_name module config"
        return 0
    fi

    # Add setting to module config
    backup_config_file "$module_config"

    if grep -q "^${key}=" "$module_config"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$module_config"
        log "INFO" "Updated $module_name module setting: $key=$value"
    else
        echo "${key}=\"${value}\"" >> "$module_config"
        log "INFO" "Added $module_name module setting: $key=$value"
    fi

    whiptail --title "Success" --msgbox "Setting added successfully:\n$key=$value" 10 60
}

# Function to remove module setting
remove_module_setting() {
    local module_name="$1"
    local module_config="$MODULE_CONFIG_DIR/${module_name}.conf"

    if [ ! -f "$module_config" ]; then
        whiptail --title "Error" --msgbox "No configuration file found for $module_name module." 10 60
        return 1
    fi

    # Get list of current settings
    local settings=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]]; then
            settings+=("${BASH_REMATCH[1]}" "")
        fi
    done < "$module_config"

    if [ ${#settings[@]} -eq 0 ]; then
        whiptail --title "Info" --msgbox "No settings found in $module_name module configuration." 10 60
        return 0
    fi

    local key
    key=$(whiptail --title "Remove Setting" --menu "Select setting to remove:" 18 70 10 "${settings[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$key" ]; then
        return 0
    fi

    if whiptail --title "Confirm" --yesno "Are you sure you want to remove setting '$key'?" 10 60; then
        if [ -n "$TEST_MODE" ]; then
            log "INFO" "[TEST MODE] Would remove $key from $module_name module config"
        else
            backup_config_file "$module_config"
            sed -i "/^${key}=/d" "$module_config"
            log "INFO" "Removed $module_name module setting: $key"
            whiptail --title "Success" --msgbox "Setting '$key' removed successfully." 10 60
        fi
    fi
}

# Function to reset module configuration
reset_module_config() {
    local module_name="$1"
    local module_config="$MODULE_CONFIG_DIR/${module_name}.conf"

    if whiptail --title "Reset Module Configuration" --yesno "Are you sure you want to reset $module_name module configuration?\n\nThis will remove all custom settings!" 10 60; then
        if [ -n "$TEST_MODE" ]; then
            log "INFO" "[TEST MODE] Would reset $module_name module configuration"
        else
            backup_config_file "$module_config"
            cat > "$module_config" << EOF
# Proxmox Template Creator - $module_name Module Configuration
# Reset to defaults on $(date)

# Module-specific settings for $module_name
# Add your custom configuration below

EOF
            log "INFO" "Reset $module_name module configuration"
            whiptail --title "Success" --msgbox "$module_name module configuration reset to defaults." 10 60
        fi
    fi
}

# Function to export module configuration
export_module_config() {
    local module_name="$1"
    local module_config="$MODULE_CONFIG_DIR/${module_name}.conf"

    if [ ! -f "$module_config" ]; then
        whiptail --title "Error" --msgbox "No configuration file found for $module_name module." 10 60
        return 1
    fi

    local output_file
    output_file=$(whiptail --title "Export Module Configuration" --inputbox "Enter output file path:" 10 60 "/tmp/${module_name}_config.conf" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$output_file" ]; then
        return 0
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would export $module_name module config to $output_file"
    else
        cp "$module_config" "$output_file"
        log "INFO" "Exported $module_name module configuration to: $output_file"
        whiptail --title "Success" --msgbox "Module configuration exported to:\n$output_file" 10 60
    fi
}

# Function to import module configuration
import_module_config() {
    local module_name="$1"
    local module_config="$MODULE_CONFIG_DIR/${module_name}.conf"

    local input_file
    input_file=$(whiptail --title "Import Module Configuration" --inputbox "Enter input file path:" 10 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$input_file" ]; then
        return 0
    fi

    if [ ! -f "$input_file" ]; then
        whiptail --title "Error" --msgbox "Input file does not exist:\n$input_file" 10 60
        return 1
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would import $module_name module config from $input_file"
    else
        backup_config_file "$module_config"
        cp "$input_file" "$module_config"
        log "INFO" "Imported $module_name module configuration from: $input_file"
        whiptail --title "Success" --msgbox "Module configuration imported from:\n$input_file" 10 60
    fi
}

# Function to show configuration summary
show_config_summary() {
    local summary=""

    # System information
    summary+="System Configuration Summary\n"
    summary+="============================\n\n"

    # Version and install info
    local version
    version=$(get_config "HOMELAB_VERSION" "Unknown")
    summary+="Version: $version\n"

    local install_date
    install_date=$(get_config "INSTALL_DATE" "Unknown")
    summary+="Installed: $install_date\n\n"

    # Key settings
    summary+="Key Settings:\n"
    summary+="-------------\n"

    local auto_update
    auto_update=$(get_config "AUTO_UPDATE" "true")
    summary+="Auto Update: $auto_update\n"

    local log_level
    log_level=$(get_config "LOG_LEVEL" "INFO")
    summary+="Log Level: $log_level\n"

    local default_storage
    default_storage=$(get_config "DEFAULT_VM_STORAGE" "local-lvm")
    summary+="Default VM Storage: $default_storage\n"

    local default_memory
    default_memory=$(get_config "DEFAULT_VM_MEMORY" "2048")
    summary+="Default VM Memory: ${default_memory}MB\n"

    local cloud_init
    cloud_init=$(get_config "ENABLE_CLOUD_INIT" "true")
    summary+="Cloud-init Enabled: $cloud_init\n\n"

    # Module status
    summary+="Module Status:\n"
    summary+="--------------\n"

    local monitoring
    monitoring=$(get_config "MONITORING_ENABLED" "false")
    summary+="Monitoring: $monitoring\n"

    local registry
    registry=$(get_config "REGISTRY_ENABLED" "false")
    summary+="Registry: $registry\n"

    local terraform
    terraform=$(get_config "TERRAFORM_ENABLED" "false")
    summary+="Terraform: $terraform\n"

    local ansible
    ansible=$(get_config "ANSIBLE_ENABLED" "false")
    summary+="Ansible: $ansible\n"

    # Configuration files status
    summary+="\nConfiguration Files:\n"
    summary+="--------------------\n"

    if [ -f "$SYSTEM_CONFIG" ]; then
        summary+="System Config: ✓ Present\n"
    else
        summary+="System Config: ✗ Missing\n"
    fi

    if [ -f "$USER_CONFIG" ] && [ -s "$USER_CONFIG" ]; then
        local user_settings
        user_settings=$(grep -c '^[A-Z_][A-Z0-9_]*=' "$USER_CONFIG" 2>/dev/null || echo "0")
        summary+="User Config: ✓ Present ($user_settings overrides)\n"
    else
        summary+="User Config: ○ Empty\n"
    fi

    # Module configs
    local module_count=0
    if [ -d "$MODULE_CONFIG_DIR" ]; then
        module_count=$(find "$MODULE_CONFIG_DIR" -name "*.conf" -type f | wc -l)
    fi
    summary+="Module Configs: $module_count configured\n"

    echo -e "$summary"
}

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Configuration Management v${VERSION}" --menu "Choose an action:" 22 70 14 \
            "1" "View configuration summary" \
            "2" "List all configuration values" \
            "3" "Set configuration value" \
            "4" "Remove configuration value" \
            "5" "Validate configuration" \
            "6" "Export configuration" \
            "7" "Import configuration" \
            "8" "Reset configuration" \
            "9" "Manage module configurations" \
            "10" "View configuration files" \
            "11" "Backup configuration" \
            "12" "Restore configuration" \
            "13" "Help and documentation" \
            "14" "Exit" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                show_config_summary | whiptail --title "Configuration Summary" --textbox /dev/stdin 25 80
                ;;
            2)
                local scope
                scope=$(whiptail --title "List Configuration" --menu "Select scope:" 12 60 4 \
                    "all" "All configurations" \
                    "system" "System configuration only" \
                    "user" "User configuration only" \
                    "defaults" "Show default values" 3>&1 1>&2 2>&3)

                if [ $? -eq 0 ] && [ -n "$scope" ]; then
                    if [ "$scope" = "defaults" ]; then
                        list_config "all" "true" | whiptail --title "Configuration Values" --textbox /dev/stdin 25 80
                    else
                        list_config "$scope" | whiptail --title "Configuration Values" --textbox /dev/stdin 25 80
                    fi
                fi
                ;;
            3)
                set_config_interactive
                ;;
            4)
                remove_config_interactive
                ;;
            5)
                validate_all_configs
                ;;
            6)
                export_config_interactive
                ;;
            7)
                import_config_interactive
                ;;
            8)
                reset_config_interactive
                ;;
            9)
                manage_module_config ""
                ;;
            10)
                view_config_files
                ;;
            11)
                backup_all_configs
                ;;
            12)
                restore_config_interactive
                ;;
            13)
                show_help
                ;;
            14|"")
                log "INFO" "Exiting configuration management"
                exit 0
                ;;
        esac
    done
}

# Interactive function to set configuration
set_config_interactive() {
    local scope
    scope=$(whiptail --title "Set Configuration" --menu "Select scope:" 10 60 2 \
        "user" "User configuration (recommended)" \
        "system" "System configuration" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$scope" ]; then
        return 0
    fi

    local key
    key=$(whiptail --title "Set Configuration" --inputbox "Enter configuration key (uppercase, underscores allowed):" 10 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$key" ]; then
        return 0
    fi

    # Show current value if it exists
    local current_value
    current_value=$(get_config "$key")
    local prompt="Enter value for $key:"
    if [ -n "$current_value" ]; then
        prompt="Enter value for $key (current: $current_value):"
    fi

    local value
    value=$(whiptail --title "Set Configuration" --inputbox "$prompt" 10 60 "$current_value" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        return 0
    fi

    if set_config "$key" "$value" "" "$scope"; then
        whiptail --title "Success" --msgbox "Configuration set successfully:\n$key=$value" 10 60
    else
        whiptail --title "Error" --msgbox "Failed to set configuration value." 10 60
    fi
}

# Interactive function to remove configuration
remove_config_interactive() {
    local config_file
    config_file=$(whiptail --title "Remove Configuration" --menu "Select configuration file:" 10 60 2 \
        "$USER_CONFIG" "User configuration" \
        "$SYSTEM_CONFIG" "System configuration" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$config_file" ]; then
        return 0
    fi

    if [ ! -f "$config_file" ]; then
        whiptail --title "Error" --msgbox "Configuration file does not exist." 10 60
        return 1
    fi

    # Get list of current settings
    local settings=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)= ]]; then
            local key="${BASH_REMATCH[1]}"
            local value
            value=$(echo "$line" | cut -d'=' -f2- | sed 's/^"//;s/"$//')
            settings+=("$key" "$value")
        fi
    done < "$config_file"

    if [ ${#settings[@]} -eq 0 ]; then
        whiptail --title "Info" --msgbox "No settings found in configuration file." 10 60
        return 0
    fi

    local key
    key=$(whiptail --title "Remove Configuration" --menu "Select setting to remove:" 18 70 10 "${settings[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$key" ]; then
        return 0
    fi

    if whiptail --title "Confirm" --yesno "Are you sure you want to remove setting '$key'?" 10 60; then
        if remove_config "$key" "$config_file"; then
            whiptail --title "Success" --msgbox "Configuration removed successfully: $key" 10 60
        else
            whiptail --title "Error" --msgbox "Failed to remove configuration." 10 60
        fi
    fi
}

# Function to validate all configurations
validate_all_configs() {
    local errors=0
    local total=0

    log "INFO" "Validating all configuration files..."

    # Validate system config
    if [ -f "$SYSTEM_CONFIG" ]; then
        ((total++))
        if validate_config "$SYSTEM_CONFIG"; then
            log "INFO" "System configuration: VALID"
        else
            log "ERROR" "System configuration: INVALID"
            ((errors++))
        fi
    fi

    # Validate user config
    if [ -f "$USER_CONFIG" ]; then
        ((total++))
        if validate_config "$USER_CONFIG"; then
            log "INFO" "User configuration: VALID"
        else
            log "ERROR" "User configuration: INVALID"
            ((errors++))
        fi
    fi

    # Validate module configs
    if [ -d "$MODULE_CONFIG_DIR" ]; then
        for config_file in "$MODULE_CONFIG_DIR"/*.conf; do
            if [ -f "$config_file" ]; then
                ((total++))
                local module_name
                module_name=$(basename "$config_file" .conf)
                if validate_config "$config_file"; then
                    log "INFO" "$module_name module configuration: VALID"
                else
                    log "ERROR" "$module_name module configuration: INVALID"
                    ((errors++))
                fi
            fi
        done
    fi

    local result_msg="Validation complete: $((total - errors))/$total configurations valid"
    if [ $errors -eq 0 ]; then
        whiptail --title "Validation Results" --msgbox "$result_msg\n\nAll configurations are valid!" 10 60
    else
        whiptail --title "Validation Results" --msgbox "$result_msg\n\n$errors configuration(s) have errors.\nCheck the logs for details." 12 60
    fi
}

# Function to export configuration interactively
export_config_interactive() {
    local output_file
    output_file=$(whiptail --title "Export Configuration" --inputbox "Enter output file path:" 10 60 "/tmp/homelab_config_$(date +%Y%m%d_%H%M%S).conf" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$output_file" ]; then
        return 0
    fi

    local include_system="true"
    local include_user="true"

    if whiptail --title "Export Options" --yesno "Include system configuration?" 10 60; then
        include_system="true"
    else
        include_system="false"
    fi

    if whiptail --title "Export Options" --yesno "Include user configuration?" 10 60; then
        include_user="true"
    else
        include_user="false"
    fi

    if export_config "$output_file" "$include_system" "$include_user"; then
        whiptail --title "Success" --msgbox "Configuration exported successfully to:\n$output_file" 10 60
    else
        whiptail --title "Error" --msgbox "Failed to export configuration." 10 60
    fi
}

# Function to import configuration interactively
import_config_interactive() {
    local input_file
    input_file=$(whiptail --title "Import Configuration" --inputbox "Enter input file path:" 10 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$input_file" ]; then
        return 0
    fi

    if [ ! -f "$input_file" ]; then
        whiptail --title "Error" --msgbox "Input file does not exist:\n$input_file" 10 60
        return 1
    fi

    local scope
    scope=$(whiptail --title "Import Configuration" --menu "Select target scope:" 10 60 2 \
        "user" "User configuration" \
        "system" "System configuration" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$scope" ]; then
        return 0
    fi

    local backup="true"
    if ! whiptail --title "Import Options" --yesno "Backup existing configuration before import?" 10 60; then
        backup="false"
    fi

    if import_config "$input_file" "$scope" "$backup"; then
        whiptail --title "Success" --msgbox "Configuration imported successfully from:\n$input_file" 10 60
    else
        whiptail --title "Error" --msgbox "Failed to import configuration." 10 60
    fi
}

# Function to reset configuration interactively
reset_config_interactive() {
    local scope
    scope=$(whiptail --title "Reset Configuration" --menu "Select scope to reset:" 12 60 3 \
        "user" "User configuration only" \
        "system" "System configuration only" \
        "all" "All configurations" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$scope" ]; then
        return 0
    fi

    reset_config "$scope" "true"
}

# Function to view configuration files
view_config_files() {
    local file_choice
    file_choice=$(whiptail --title "View Configuration Files" --menu "Select file to view:" 15 70 6 \
        "system" "System configuration" \
        "user" "User configuration" \
        "modules" "Module configurations" \
        "backups" "Configuration backups" \
        "all" "All configuration info" \
        "directories" "Configuration directories" 3>&1 1>&2 2>&3)

    case $file_choice in
        "system")
            if [ -f "$SYSTEM_CONFIG" ]; then
                whiptail --title "System Configuration" --textbox "$SYSTEM_CONFIG" 25 80
            else
                whiptail --title "System Configuration" --msgbox "System configuration file not found." 10 60
            fi
            ;;
        "user")
            if [ -f "$USER_CONFIG" ]; then
                whiptail --title "User Configuration" --textbox "$USER_CONFIG" 25 80
            else
                whiptail --title "User Configuration" --msgbox "User configuration file not found." 10 60
            fi
            ;;
        "modules")
            view_module_configs
            ;;
        "backups")
            view_config_backups
            ;;
        "all")
            show_all_config_info
            ;;
        "directories")
            show_config_directories
            ;;
    esac
}

# Function to view module configurations
view_module_configs() {
    if [ ! -d "$MODULE_CONFIG_DIR" ]; then
        whiptail --title "Module Configurations" --msgbox "Module configuration directory not found." 10 60
        return 1
    fi

    local modules=()
    for config_file in "$MODULE_CONFIG_DIR"/*.conf; do
        if [ -f "$config_file" ]; then
            local module_name
            module_name=$(basename "$config_file" .conf)
            modules+=("$module_name" "$config_file")
        fi
    done

    if [ ${#modules[@]} -eq 0 ]; then
        whiptail --title "Module Configurations" --msgbox "No module configurations found." 10 60
        return 0
    fi

    local module
    module=$(whiptail --title "Module Configurations" --menu "Select module to view:" 18 70 10 "${modules[@]}" 3>&1 1>&2 2>&3)

    if [ $? -eq 0 ] && [ -n "$module" ]; then
        local config_file="$MODULE_CONFIG_DIR/${module}.conf"
        whiptail --title "$module Module Configuration" --textbox "$config_file" 25 80
    fi
}

# Function to view configuration backups
view_config_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        whiptail --title "Configuration Backups" --msgbox "Backup directory not found." 10 60
        return 1
    fi

    local backups=()
    for backup_file in "$BACKUP_DIR"/*.backup.*; do
        if [ -f "$backup_file" ]; then
            local backup_name
            backup_name=$(basename "$backup_file")
            local backup_date
            backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            backups+=("$backup_name" "$backup_date")
        fi
    done

    if [ ${#backups[@]} -eq 0 ]; then
        whiptail --title "Configuration Backups" --msgbox "No configuration backups found." 10 60
        return 0
    fi

    local backup
    backup=$(whiptail --title "Configuration Backups" --menu "Select backup to view:" 18 70 10 "${backups[@]}" 3>&1 1>&2 2>&3)

    if [ $? -eq 0 ] && [ -n "$backup" ]; then
        local backup_file="$BACKUP_DIR/$backup"
        whiptail --title "Configuration Backup: $backup" --textbox "$backup_file" 25 80
    fi
}

# Function to show all configuration info
show_all_config_info() {
    local info=""

    info+="Configuration System Information\n"
    info+="===============================\n\n"

    info+="Directories:\n"
    info+="------------\n"
    info+="Config Dir: $CONFIG_DIR\n"
    info+="Module Dir: $MODULE_CONFIG_DIR\n"
    info+="Backup Dir: $BACKUP_DIR\n"
    info+="Templates Dir: $TEMPLATES_DIR\n\n"

    info+="Configuration Files:\n"
    info+="-------------------\n"

    if [ -f "$SYSTEM_CONFIG" ]; then
        local sys_size
        sys_size=$(wc -l < "$SYSTEM_CONFIG")
        info+="System Config: ✓ ($sys_size lines)\n"
    else
        info+="System Config: ✗ Missing\n"
    fi

    if [ -f "$USER_CONFIG" ]; then
        local user_size
        user_size=$(wc -l < "$USER_CONFIG")
        info+="User Config: ✓ ($user_size lines)\n"
    else
        info+="User Config: ✗ Missing\n"
    fi

    # Module configs
    local module_count=0
    if [ -d "$MODULE_CONFIG_DIR" ]; then
        for config_file in "$MODULE_CONFIG_DIR"/*.conf; do
            if [ -f "$config_file" ]; then
                ((module_count++))
                local module_name
                module_name=$(basename "$config_file" .conf)
                local mod_size
                mod_size=$(wc -l < "$config_file")
                info+="$module_name Module: ✓ ($mod_size lines)\n"
            fi
        done
    fi

    if [ $module_count -eq 0 ]; then
        info+="Module Configs: None configured\n"
    fi

    # Backup info
    local backup_count=0
    if [ -d "$BACKUP_DIR" ]; then
        backup_count=$(find "$BACKUP_DIR" -name "*.backup.*" -type f | wc -l)
    fi
    info+="\nBackups: $backup_count files\n"

    echo -e "$info" | whiptail --title "Configuration System Info" --textbox /dev/stdin 25 80
}

# Function to show configuration directories
show_config_directories() {
    local dir_info=""

    dir_info+="Configuration Directory Structure\n"
    dir_info+="=================================\n\n"

    if [ -d "$CONFIG_DIR" ]; then
        dir_info+="$CONFIG_DIR/\n"

        if [ -f "$SYSTEM_CONFIG" ]; then
            dir_info+="├── system.conf (system configuration)\n"
        else
            dir_info+="├── system.conf (missing)\n"
        fi

        if [ -f "$USER_CONFIG" ]; then
            dir_info+="├── user.conf (user configuration)\n"
        else
            dir_info+="├── user.conf (missing)\n"
        fi

        if [ -d "$MODULE_CONFIG_DIR" ]; then
            dir_info+="├── modules/\n"
            for config_file in "$MODULE_CONFIG_DIR"/*.conf; do
                if [ -f "$config_file" ]; then
                    local module_name
                    module_name=$(basename "$config_file" .conf)
                    dir_info+="│   ├── ${module_name}.conf\n"
                fi
            done
        else
            dir_info+="├── modules/ (missing)\n"
        fi

        if [ -d "$BACKUP_DIR" ]; then
            local backup_count
            backup_count=$(find "$BACKUP_DIR" -name "*.backup.*" -type f | wc -l)
            dir_info+="├── backups/ ($backup_count files)\n"
        else
            dir_info+="├── backups/ (missing)\n"
        fi

        if [ -d "$TEMPLATES_DIR" ]; then
            local template_count
            template_count=$(find "$TEMPLATES_DIR" -name "*.conf" -type f | wc -l)
            dir_info+="└── templates/ ($template_count files)\n"
        else
            dir_info+="└── templates/ (missing)\n"
        fi
    else
        dir_info+="Configuration directory not found: $CONFIG_DIR\n"
    fi

    echo -e "$dir_info" | whiptail --title "Configuration Directories" --textbox /dev/stdin 25 80
}

# Function to backup all configurations
backup_all_configs() {
    log "INFO" "Creating backup of all configurations..."

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_archive="/tmp/homelab_config_backup_$timestamp.tar.gz"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would create backup archive: $backup_archive"
        whiptail --title "Backup" --msgbox "Test mode: Would create backup archive:\n$backup_archive" 10 60
        return 0
    fi

    # Create backup archive
    if tar -czf "$backup_archive" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>/dev/null; then
        log "INFO" "Configuration backup created: $backup_archive"
        whiptail --title "Backup Complete" --msgbox "Configuration backup created successfully:\n\n$backup_archive\n\nThis archive contains all configuration files and can be used for disaster recovery." 12 70
    else
        log "ERROR" "Failed to create configuration backup"
        whiptail --title "Backup Failed" --msgbox "Failed to create configuration backup.\nCheck the logs for details." 10 60
        return 1
    fi
}

# Function to restore configuration interactively
restore_config_interactive() {
    local backup_file
    backup_file=$(whiptail --title "Restore Configuration" --inputbox "Enter backup file path:" 10 60 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$backup_file" ]; then
        return 0
    fi

    if [ ! -f "$backup_file" ]; then
        whiptail --title "Error" --msgbox "Backup file does not exist:\n$backup_file" 10 60
        return 1
    fi

    if ! whiptail --title "Restore Configuration" --yesno "Are you sure you want to restore configuration from backup?\n\nThis will overwrite all current configuration!\n\nBackup file: $backup_file" 12 70; then
        return 0
    fi

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would restore configuration from: $backup_file"
        whiptail --title "Restore" --msgbox "Test mode: Would restore configuration from:\n$backup_file" 10 60
        return 0
    fi

    # Create backup of current config before restore
    backup_all_configs

    # Extract backup
    if tar -xzf "$backup_file" -C "$(dirname "$CONFIG_DIR")" 2>/dev/null; then
        log "INFO" "Configuration restored from: $backup_file"
        whiptail --title "Restore Complete" --msgbox "Configuration restored successfully from:\n$backup_file" 10 60
    else
        log "ERROR" "Failed to restore configuration from: $backup_file"
        whiptail --title "Restore Failed" --msgbox "Failed to restore configuration.\nCheck the logs for details." 10 60
        return 1
    fi
}

# Function to show help
show_help() {
    local help_text=""

    help_text+="Configuration Management Help\n"
    help_text+="============================\n\n"

    help_text+="The Configuration Management module provides centralized\n"
    help_text+="configuration for all homelab components.\n\n"

    help_text+="Configuration Hierarchy:\n"
    help_text+="1. Default values (built-in)\n"
    help_text+="2. System configuration (/etc/homelab/system.conf)\n"
    help_text+="3. User configuration (/etc/homelab/user.conf)\n"
    help_text+="4. Module-specific configurations\n\n"

    help_text+="Key Features:\n"
    help_text+="- Centralized configuration management\n"
    help_text+="- User and system-level settings\n"
    help_text+="- Module-specific configurations\n"
    help_text+="- Configuration validation\n"
    help_text+="- Import/export capabilities\n"
    help_text+="- Automatic backups\n"
    help_text+="- Configuration templates\n\n"

    help_text+="Common Configuration Keys:\n"
    help_text+="- AUTO_UPDATE: Enable automatic updates\n"
    help_text+="- LOG_LEVEL: Logging verbosity (DEBUG/INFO/WARN/ERROR)\n"
    help_text+="- DEFAULT_VM_STORAGE: Default Proxmox storage\n"
    help_text+="- DEFAULT_VM_MEMORY: Default VM memory (MB)\n"
    help_text+="- DEFAULT_VM_CORES: Default VM CPU cores\n"
    help_text+="- ENABLE_CLOUD_INIT: Enable cloud-init by default\n"
    help_text+="- MONITORING_ENABLED: Enable monitoring stack\n"
    help_text+="- REGISTRY_ENABLED: Enable container registry\n\n"

    help_text+="For more information, see the system documentation."

    echo -e "$help_text" | whiptail --title "Configuration Management Help" --textbox /dev/stdin 25 80
}

# Main execution
main() {
    log "INFO" "Starting Configuration Management v${VERSION}"

    # Check if running as root
    check_root

    # Create configuration directories
    create_config_dirs

    # Initialize default configuration
    init_default_config

    # If running in test mode, show test message and exit
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Configuration Management module loaded successfully (test mode)"
        return 0
    fi

    # If running non-interactively, just initialize and exit
    if [ ! -t 0 ]; then
        log "INFO" "Configuration Management module initialized"
        return 0
    fi

    # Run main menu
    main_menu
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
