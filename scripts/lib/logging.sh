#!/bin/bash

# --- Configuration ---
# LOG_FILE is the primary log file path.
# HL_LOG_LEVEL environment variable can override the default log level.
# Recognized HL_LOG_LEVEL values: ERROR, WARN, INFO, DEBUG
LOG_FILE="/var/log/homelab_bootstrap.log"
HL_LOG_LEVEL="${HL_LOG_LEVEL:-INFO}" # Default to INFO if not set via environment

# --- Colors ---
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
# BOLD_WHITE='\033[1;37m' # Example if more colors are needed

# --- Log Levels Numeric Values ---
# Higher number means more severe. Error=3, Warn=2, Info=1, Debug=0
# This allows easy comparison: log if message_level >= configured_threshold
declare -A LOG_LEVEL_VALUES
LOG_LEVEL_VALUES["DEBUG"]=0
LOG_LEVEL_VALUES["INFO"]=1
LOG_LEVEL_VALUES["WARN"]=2
LOG_LEVEL_VALUES["ERROR"]=3

# Determine the numeric threshold for the current log level
CURRENT_LOG_THRESHOLD=${LOG_LEVEL_VALUES[$HL_LOG_LEVEL]}

# Validate HL_LOG_LEVEL and set a default if invalid
if [ -z "$CURRENT_LOG_THRESHOLD" ]; then
    # Output a direct echo to stderr as logging might not be fully set up.
    echo -e "${YELLOW}[$(date +"%Y-%m-%d %H:%M:%S")] [WARN] Invalid HL_LOG_LEVEL: '$HL_LOG_LEVEL'. Defaulting to INFO.${RESET}" >&2
    HL_LOG_LEVEL="INFO"
    CURRENT_LOG_THRESHOLD=${LOG_LEVEL_VALUES["INFO"]}
fi

# --- Internal Logging Function ---
_log() {
    local level_name="$1"
    local message="$2"
    local message_level_value=${LOG_LEVEL_VALUES[$level_name]}

    # Only log if the message's level is at or above the current threshold
    if [ "$message_level_value" -lt "$CURRENT_LOG_THRESHOLD" ]; then
        return # Skip logging
    fi

    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color="$RESET"
    local output_stream="/dev/stdout" # Default to stdout

    case "$level_name" in
        INFO) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR)
            color="$RED"
            output_stream="/dev/stderr" # Errors go to stderr
            ;;
        DEBUG) color="$BLUE" ;;
    esac

    local formatted_message="[${timestamp}] [${level_name}] ${message}"

    # Echo to console
    echo -e "${color}${formatted_message}${RESET}" >"$output_stream"

    # Append to log file, if LOG_FILE is set and writable
    if [ -n "$LOG_FILE" ]; then
        # The init_logging function should handle directory creation and initial writability checks.
        # Here, we just append. If it fails, we report to stderr.
        if ! echo "${formatted_message}" >>"$LOG_FILE"; then
            echo -e "${RED}[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] Failed to write to log file: $LOG_FILE. Check permissions and path.${RESET}" >&2
        fi
    fi
}

# --- User-facing Logging Functions ---
log_info() {
    _log "INFO" "$*"
}

log_warn() {
    _log "WARN" "$*"
}

log_error() {
    _log "ERROR" "$*"
}

log_debug() {
    # Explicitly check HL_LOG_LEVEL for DEBUG messages,
    # as _log's threshold check handles general filtering.
    # This ensures DEBUG is only ever processed if level is DEBUG.
    if [ "$HL_LOG_LEVEL" = "DEBUG" ]; then
        _log "DEBUG" "$*"
    fi
}

# --- Initialization Function ---
# Call this at the beginning of a script to set up logging.
# arg1: Optional name of the script/module being initialized (e.g., "Bootstrap", "TemplateScript")
init_logging() {
    local script_name="${1:-Main}" # Default to "Main" if no script name provided

    if [ -z "$LOG_FILE" ]; then
        # If LOG_FILE is empty, only console logging will occur.
        log_warn "$script_name: LOG_FILE variable is not set. Logging to console only."
        return
    fi

    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    # Create log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        # Use sudo if not root, assuming bootstrap context might need it for /var/log
        # However, for bootstrap.sh, it's run as root. Other scripts might need to adapt.
        if ! mkdir -p "$log_dir"; then
            log_error "$script_name: Failed to create log directory: $log_dir. Check permissions. Logging to console only for now."
            LOG_FILE="" # Disable file logging if directory can't be made
            return
        fi
    fi

    # Touch the log file to ensure it's creatable/writable
    if ! touch "$LOG_FILE" 2>/dev/null; then
        log_error "$script_name: Log file $LOG_FILE is not writable. Check permissions. Logging to console only for now."
        LOG_FILE="" # Disable file logging if not writable
        return
    fi

    log_info "$script_name: Logging initialized. Log Level: $HL_LOG_LEVEL. Log File: $LOG_FILE"
}

# --- Error Handling Function ---
# To be used with `trap 'handle_error $? $LINENO' ERR`
# It logs the error and where it occurred.
handle_error() {
    local exit_code=$1
    local line_num=$2
    # BASH_SOURCE[0] is this file (logging.sh).
    # BASH_SOURCE[1] is the script that sourced logging.sh and where the error occurred.
    # If error is in a function in logging.sh itself, BASH_SOURCE[1] might be empty or logging.sh.
    local script_name="${BASH_SOURCE[1]}"
    if [ -z "$script_name" ] || [ "$script_name" == "${BASH_SOURCE[0]}" ]; then
        script_name="UnknownScript(or logging.sh internal)"
    else
        script_name=$(basename "$script_name")
    fi

    local error_message="An error occurred in $script_name at line $line_num (exit code: $exit_code)."

    # Log the error using the error logging function
    log_error "$error_message"

    # Additional context for the user
    if [ -n "$LOG_FILE" ]; then
        log_error "Execution failed. Please check logs at $LOG_FILE and console output for details."
    else
        log_error "Execution failed. Please check console output for details."
    fi
    # The script will exit due to the `set -e` or the trap itself.
    # Explicitly exiting here `exit "$exit_code"` is often redundant with `trap ... ERR`
    # and can sometimes interfere with the trap's own exit signal.
}

# Example of how to set the trap in the main script:
# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# source "$SCRIPT_DIR/lib/logging.sh"
# trap 'handle_error $? $LINENO' ERR
# init_logging "MyScript"
# log_info "Script started."
# # ... rest of the script ...
# log_debug "This is a debug." # Will only show if HL_LOG_LEVEL=DEBUG
# # Example: command_that_fails # This would trigger handle_error
# log_info "Script finished."
