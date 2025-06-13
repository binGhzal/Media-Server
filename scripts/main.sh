#!/usr/bin/env bash
#
# Proxmox Template Creator - Main Controller
#
# Description:
#   This script serves as the main entry point for the Proxmox Template Creator tool.
#   It provides a user interface for managing VM template creation and configuration
#   in a Proxmox VE environment.
#
# Features:
#   - Interactive menu for template management
#   - Module-based architecture for extensibility
#   - Configuration management
#   - Dependency checking and installation
#   - Comprehensive error handling and logging
#
# Usage:
#   ./main.sh [OPTIONS]
#
# Exit Codes:
#   0   - Success
#   1   - General error
#   2   - Missing dependencies
#   3   - Permission denied
#   4   - Configuration error
#   5   - Module error
#
# Dependencies:
#   - bash >= 4.0
#   - coreutils
#   - jq (for JSON processing)
#   - whiptail (for interactive menus)
#
# Author: Homelab Team
# Version: 0.2.0
# License: MIT

set -e

# Script metadata
readonly VERSION="0.2.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LOCK_FILE="/var/run/${SCRIPT_NAME%.*}.lock"

# Source the centralized logging and error handling libraries
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"

# Initialize logging system with enhanced configuration
init_logging "${SCRIPT_NAME%.*}" "${SCRIPT_DIR}/logs"

# Set up error handling
trap 'handle_error ${LINENO} "${BASH_COMMAND}" $?' ERR

# Function to clean up resources on exit
cleanup() {
    local exit_code=$?
    log_debug "Cleaning up before exit (code: ${exit_code})"

    # Remove lock file if it exists
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}" || log_warning "Failed to remove lock file: ${LOCK_FILE}"
    fi

    log_info "Script execution completed with exit code: ${exit_code}"
    exit ${exit_code}
}

# Register cleanup function to run on script exit
trap cleanup EXIT

# Function to acquire an exclusive lock
acquire_lock() {
    if ! (set -o noclobber; > "${LOCK_FILE}") 2>/dev/null; then
        log_error "Another instance of ${SCRIPT_NAME} is already running"
        exit 1
    fi

    # Write the PID to the lock file
    echo "$$"> "${LOCK_FILE}"

    # Ensure lock is removed when we exit
    trap 'rm -f "${LOCK_FILE}" 2>/dev/null' EXIT
}

# Function to check for root privileges
check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_error "This script must be run as root. Please use 'sudo' or run as root user."
        exit 3
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to display usage information
show_usage() {
    cat << EOF
${SCRIPT_NAME} - Proxmox Template Creator v${VERSION}

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --test               Run in test mode (no actual VM creation)
  --verbose, -v        Enable verbose output
  --debug              Enable debug mode (very verbose output)
  --config FILE        Specify an alternative configuration file
  --log-level LEVEL    Set the log level (debug, info, warning, error, critical)
  --help, -h          Show this help message
  --version            Show version information
  --list-modules       Show available modules

Environment Variables:
  PVE_API_TOKEN_ID     Proxmox VE API token ID
  PVE_API_TOKEN_SECRET Proxmox VE API token secret
  PVE_HOST             Proxmox VE hostname or IP
  PVE_USER             Proxmox VE username

Examples:
  ${SCRIPT_NAME} --test
  ${SCRIPT_NAME} --config /path/to/config.conf
  ${SCRIPT_NAME} --log-level debug

Report bugs to: <your-email@example.com>
Project home: <https://github.com/yourusername/proxmox-template-creator>
EOF
    exit 0
}

# Function to validate configuration
validate_config() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi

    # Add configuration validation logic here
    return 0
}

# Function to load configuration
load_config() {
    local config_file="${1:-${SCRIPT_DIR}/config/default.conf}"

    if [[ ! -f "${config_file}" ]]; then
        log_warning "Configuration file not found: ${config_file}. Using defaults."
        return 1
    fi

    log_info "Loading configuration from: ${config_file}"

    # Source the configuration file
    # shellcheck source=/dev/null
    if ! source "${config_file}"; then
        log_error "Failed to load configuration from: ${config_file}"
        return 1
    fi

    # Validate the loaded configuration
    if ! validate_config "${config_file}"; then
        log_error "Invalid configuration in: ${config_file}"
        return 1
    fi

    return 0
}

# Initialize the script
initialize() {
    log_info "Initializing ${SCRIPT_NAME} v${VERSION}"
    log_debug "Script directory: ${SCRIPT_DIR}"
    log_debug "Command line arguments: ${ORIGINAL_ARGS[*]}"

    # Check for root privileges if required
    if [[ ${REQUIRE_ROOT:-1} -eq 1 ]]; then
        check_root
    fi

    # Acquire lock to prevent multiple instances
    acquire_lock

    # Load configuration
    if ! load_config "${CONFIG_FILE:-}"; then
        log_warning "Using default configuration"
    fi

    # Check dependencies
    check_dependencies

    log_info "Initialization completed successfully"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            log_info "Test mode enabled - no changes will be made"
            shift
            ;;
        --verbose|-v)
            LOG_LEVEL="INFO"
            set_log_level "${LOG_LEVEL}"
            log_info "Verbose output enabled"
            shift
            ;;
        --debug)
            LOG_LEVEL="DEBUG"
            set_log_level "${LOG_LEVEL}"
            set -x  # Enable debug mode
            log_debug "Debug mode enabled"
            shift
            ;;
        --config)
            if [[ -z $2 ]] || [[ $2 == --* ]]; then
                log_error "--config requires an argument"
                exit 1
            fi
            CONFIG_FILE="$2"
            log_debug "Using configuration file: ${CONFIG_FILE}"
            shift 2
            ;;
        --log-level)
            if [[ -z $2 ]] || [[ $2 == --* ]]; then
                log_error "--log-level requires an argument (debug, info, warning, error, critical)"
                exit 1
            fi
            LOG_LEVEL="$2"
            if ! set_log_level "${LOG_LEVEL}"; then
                log_error "Invalid log level: ${LOG_LEVEL}"
                exit 1
            fi
            log_info "Log level set to: ${LOG_LEVEL}"
            shift 2
            ;;
        --help|-h)
            show_usage
            ;;
        --version|--version=*)
            echo "Proxmox Template Creator v${VERSION}"
            exit 0
            ;;
        --list-modules)
            # Discover and validate available modules
            discover_modules() {
                log_debug "Discovering available modules..."

                local modules=()
                local module_dirs=(
                    "${SCRIPT_DIR}/modules"
                    "${SCRIPT_DIR}/../modules"
                    "/usr/local/share/proxmox-templates/modules"
                    "${HOME}/.local/share/proxmox-templates/modules"
                )

                # Add any additional module directories from environment
                if [ -n "${PROXMOX_MODULE_PATH:-}" ]; then
                    IFS=':' read -ra extra_dirs <<< "${PROXMOX_MODULE_PATH}"
                    for dir in "${extra_dirs[@]}"; do
                        if [ -d "${dir}" ]; then
                            module_dirs+=("${dir}")
                        fi
                    done
                fi

                local unique_dirs=()
                local seen_dirs=()

                # Remove duplicate directories while preserving order
                for dir in "${module_dirs[@]}"; do
                    if [[ ! " ${seen_dirs[@]} " =~ " ${dir} " ]]; then
                        seen_dirs+=("${dir}")
                        unique_dirs+=("${dir}")
                    fi
                done

                # Find all module files in the module directories
                for dir in "${unique_dirs[@]}"; do
                    if [ ! -d "${dir}" ]; then
                        log_debug "Module directory not found: ${dir}"
                        continue
                    fi

                    log_debug "Searching for modules in: ${dir}"

                    # Find all .sh files that are executable and not named like *test*
                    while IFS= read -r -d '' module; do
                        # Skip files that don't end with .sh or are not executable
                        if [[ ! "${module}" =~ \.sh$ ]] || [ ! -x "${module}" ]; then
                            continue
                        fi

                        # Skip test files
                        if [[ "${module}" == *test* ]] || [[ "${module}" == *Test* ]]; then
                            log_debug "Skipping test module: ${module}"
                            continue
                        fi

                        # Skip disabled modules (files starting with underscore)
                        local module_name
                        module_name=$(basename "${module}")
                        if [[ "${module_name}" = _* ]]; then
                            log_debug "Skipping disabled module: ${module}"
                            continue
                        fi

                        # Check if module has the required functions
                        if ! grep -q '^module_' "${module}"; then
                            log_warning "Module ${module} is missing required module_* functions"
                            continue
                        fi

                        # Get module metadata if available
                        local module_info
                        module_info=$(
                            grep -E '^#\s*@(name|description|version|author):' "${module}" 2>/dev/null | \
                            sed -E 's/^#\s*@(name|description|version|author):\s*//'
                        )

                        if [ -z "${module_info}" ]; then
                            log_warning "Module ${module} is missing metadata headers"
                        fi

                        # Add module to the list
                        modules+=("${module}")
                        log_debug "Found module: ${module}"

                    done < <(find "${dir}" -type f -name '*.sh' -print0 2>/dev/null)
                done

                if [ ${#modules[@]} -eq 0 ]; then
                    log_warning "No valid modules found in any of the search paths"
                    return 1
                fi

                log_info "Discovered ${#modules[@]} modules"

                # Return the list of modules as a space-separated string
                printf '%s\n' "${modules[@]}" | sort -u
            }
            discover_modules
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Configuration management functions
create_default_config() {
    log_info "Checking for default configuration"

    # Create config directory if it doesn't exist
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        log_debug "Creating configuration directory: ${CONFIG_DIR}"
        if ! mkdir -p "${CONFIG_DIR}"; then
            log_error "Failed to create configuration directory: ${CONFIG_DIR}"
            return 1
        fi
        chmod 755 "${CONFIG_DIR}"
    fi

    # Create default user config if it doesn't exist
    if [[ ! -f "${USER_CONFIG}" ]]; then
        log_info "Creating default user configuration: ${USER_CONFIG}"

        # Create a temporary file first for atomic write
        local temp_config
        temp_config="$(mktemp)" || {
            log_error "Failed to create temporary configuration file"
            return 1
        }

        # Create default configuration with comprehensive documentation
        cat > "${temp_config}" << EOF
# Proxmox Template Creator - User Configuration
# This file contains user-specific configuration options
#
# Format: KEY="VALUE"  # Comment
#
# Note: All paths should be absolute. Boolean values should be "true" or "false".

# ===== System Configuration =====

# Default VM settings
DEFAULT_VM_ID=9000                 # Starting VM ID for new VMs
DEFAULT_VM_MEMORY=2048             # Default memory in MB
DEFAULT_VM_CORES=2                 # Default number of CPU cores
DEFAULT_VM_DISK="32G"              # Default disk size with unit (e.g., 32G, 100G)
DEFAULT_VM_STORAGE="local-lvm"     # Default storage ID
DEFAULT_VM_BRIDGE="vmbr0"          # Default network bridge
DEFAULT_VM_IP="dhcp"               # Default IP address or 'dhcp'
DEFAULT_VM_GATEWAY=""              # Default gateway (empty for DHCP)
DEFAULT_VM_DNS="8.8.8.8 8.8.4.4"  # DNS servers (space-separated)
DEFAULT_VM_SSH_KEYS=""             # SSH public keys to inject (newline-separated)

# Default package lists (comma-separated)
DEFAULT_VM_PACKAGES="sudo,curl,wget,gnupg2,software-properties-common,apt-transport-https,ca-certificates"

# System settings
DEFAULT_VM_TIMEZONE="UTC"          # System timezone (e.g., "America/New_York")
DEFAULT_VM_LOCALE="en_US.UTF-8"    # System locale
DEFAULT_VM_KEYBOARD="us"           # Keyboard layout

# ===== Proxmox API Settings =====
# Uncomment and configure if using API instead of CLI
#PVE_HOST=""                       # Proxmox VE hostname or IP
#PVE_USER="root@pam"               # Proxmox VE username with realm
#PVE_PASSWORD=""                   # Password (not recommended, use API tokens)
#PVE_REALM="pam"                   # Authentication realm
#PVE_NODE=""                       # Default node name

# ===== Logging Settings =====
LOG_LEVEL="INFO"                   # DEBUG, INFO, WARNING, ERROR, CRITICAL
LOG_FILE="/var/log/proxmox-template-creator.log"
LOG_MAX_SIZE=10485760              # 10MB
LOG_BACKUP_COUNT=5                 # Number of log files to keep

# ===== Update Settings =====
AUTO_UPDATE=true                   # Enable automatic updates
UPDATE_CHECK_INTERVAL=86400        # 24 hours in seconds

# ===== Path Settings =====
TEMPLATE_DIR="/usr/local/share/proxmox-templates"  # Template files
CACHE_DIR="/var/cache/proxmox-template-creator"    # Cache directory
TEMP_DIR="/tmp/proxmox-template-creator"           # Temporary files

# ===== Security Settings =====
# Enable/disable features (true/false)
ENABLE_SSH_PASSWORD_AUTH=false    # Allow password authentication
ENABLE_ROOT_LOGIN=false            # Allow root login
STRICT_HOST_KEY_CHECKING=true      # Verify host keys

# ===== Network Settings =====
HTTP_PROXY=""                      # HTTP proxy (e.g., http://proxy:3128)
HTTPS_PROXY=""                     # HTTPS proxy
NO_PROXY="localhost,127.0.0.1,::1"  # Addresses to exclude from proxying

# ===== Advanced Settings =====
# Additional environment variables
# These will be available in the template scripts
# Example:
# CUSTOM_VAR1="value1"
# CUSTOM_VAR2="value2"

# ===== End of Configuration =====
EOF

        # Move the temporary file to the final location atomically
        if ! mv -f "${temp_config}" "${USER_CONFIG}"; then
            log_error "Failed to create user configuration: ${USER_CONFIG}"
            rm -f "${temp_config}"  # Clean up temp file on failure
            return 1
        fi

        # Set appropriate permissions
        chmod 600 "${USER_CONFIG}"
        log_info "Default configuration created: ${USER_CONFIG}"
    else
        log_debug "Using existing configuration: ${USER_CONFIG}"
    fi

    return 0
}

# Function to safely get a configuration value
get_config() {
    local key="$1"
    local default_value="${2:-}"
    local config_file="${3:-${USER_CONFIG}}"

    # Validate input parameters
    if [[ -z "${key}" ]]; then
        log_error "Configuration key cannot be empty"
        return 1
    fi

    # Check if config file exists and is readable
    if [[ ! -f "${config_file}" ]]; then
        log_debug "Configuration file not found: ${config_file}"
        echo "${default_value}"
        return 2
    fi

    if [[ ! -r "${config_file}" ]]; then
        log_warning "No read permission for configuration file: ${config_file}"
        echo "${default_value}"
        return 3
    fi

    # Extract the value using a more robust method
    local value
    if value=$(grep -m 1 -E "^\s*${key}\s*=["\']?([^"\']+)["\']?" "${config_file}" 2>/dev/null); then
        # Extract just the value part (after =)
        value=${value#*=}
        # Remove surrounding quotes and trim whitespace
        value=$(echo "${value}" | sed -e 's/^[[:space:]]*["\']//' -e 's/["\'][[:space:]]*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [[ -n "${value}" ]]; then
            # Expand any variables in the value
            value=$(eval "echo ${value}" 2>/dev/null || echo "${value}")
            echo "${value}"
            return 0
        fi
    fi

    # Log debug info if using default value
    if [[ -n "${default_value}" ]]; then
        log_debug "Using default value for ${key}: ${default_value}"
    else
        log_debug "No value found for ${key} and no default provided"
    fi

    echo "${default_value}"
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

# Function to check for required dependencies
check_dependencies() {
    log_info "Checking for required dependencies..."

    # Core system dependencies
    local required_commands=(
        "jq"
        "curl"
        "wget"
        "ssh"
        "scp"
        "whiptail"
        "pv"
        "qemu-img"
        "sshpass"
        "rsync"
        "gpg"
        "tar"
        "gzip"
        "bzip2"
        "xz-utils"
    )

    # Python modules required
    local required_python_modules=(
        "requests"
        "pyyaml"
        "jinja2"
        "paramiko"
        "cryptography"
    )

    local missing_commands=()
    local missing_python_modules=()

{{ ... }}
        fi
    done

    # Check for optional but recommended dependencies
    local recommended_commands=(
        "git"
        "htop"
        "iftop"
        "iotop"
        "ncdu"
    )

    for cmd in "${recommended_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            log_info "Recommended command not found (not required): ${cmd}"
{{ ... }}

    if [ ${#missing_commands[@]} -gt 0 ] || [ ${#missing_python_modules[@]} -gt 0 ]; then
        log_warning "Missing ${#missing_commands[@]} commands and ${#missing_python_modules[@]} Python modules"
        missing_deps=true

        if [ "${AUTO_INSTALL_DEPS:-false}" = "true" ]; then
            log_info "Attempting to install missing dependencies..."

            # Install system packages if we can
            if [ ${#missing_commands[@]} -gt 0 ] && command -v apt-get >/dev/null 2>&1; then
                log_info "Installing system packages..."
{{ ... }}
                if ! sudo apt-get update || ! sudo apt-get install -y "${missing_commands[@]}"; then
                    log_error "Failed to install system packages"
                    missing_deps=true
                else
                    log_info "Successfully installed system packages"
                    missing_deps=false
                fi
            fi

            # Install Python modules if needed
            if [ ${#missing_python_modules[@]} -gt 0 ] && command -v pip3 >/dev/null 2>&1; then
                log_info "Installing Python modules..."
                if ! pip3 install --user "${missing_python_modules[@]}"; then
                    log_error "Failed to install Python modules"
                    missing_deps=true
                else
                    log_info "Successfully installed Python modules"
                    missing_deps=false
                fi
            fi

            if [ "${missing_deps}" = true ]; then
                log_error "Failed to install some dependencies"
                log_info "Please install the following manually:"
                [ ${#missing_commands[@]} -gt 0 ] && log_info "  Commands: ${missing_commands[*]}"
                [ ${#missing_python_modules[@]} -gt 0 ] && log_info "  Python modules: ${missing_python_modules[*]}"
                return 1
            fi
        else
            log_error "Missing dependencies. Please install:"
            [ ${#missing_commands[@]} -gt 0 ] && log_error "  Commands: ${missing_commands[*]}"
            [ ${#missing_python_modules[@]} -gt 0 ] && log_error "  Python modules: ${missing_python_modules[*]}"
            log_info "\nYou can set AUTO_INSTALL_DEPS=true to attempt automatic installation"
            return 1
        fi
    else
        log_info "All required dependencies are installed"
    fi

    return 0
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
        ["containers.sh"]="Containers|Deploy Docker and Kubernetes workloads|Complete"
        ["terraform.sh"]="Terraform|Infrastructure as Code automation|Complete"
        ["config.sh"]="Configuration|System and user configuration options|Complete"
        ["monitoring.sh"]="Monitoring|Setup monitoring solutions|Complete"
        ["registry.sh"]="Registry|Container registry management|Complete"
        ["ansible.sh"]="Ansible|Configuration management automation|Complete"
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
