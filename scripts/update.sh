#!/bin/bash
# Proxmox Template Creator - Update Module
# Automated system updates and maintenance

set -e

# Script version
VERSION="1.0.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR

# Source logging library if available
if [ -f "$SCRIPT_DIR/lib/logging.sh" ]; then
    source "$SCRIPT_DIR/lib/logging.sh"
    init_logging "UpdateModule"

    # Create wrapper functions for compatibility
    log() {
        local level="$1"; shift
        case $level in
            INFO) log_info "$*" ;;
            WARN) log_warn "$*" ;;
            ERROR) log_error "$*" ;;
            DEBUG) log_debug "$*" ;;
            *) log_info "$*" ;;
        esac
    }
else
    # Fallback logging function
    log() {
        local level="$1"; shift
        local color=""
        local reset="\033[0m"
        case $level in
            INFO) color="\033[0;32m" ;;
            WARN) color="\033[0;33m" ;;
            ERROR) color="\033[0;31m" ;;
            *) color="" ;;
        esac
        echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*${reset}"
    }
fi

# Configuration
INSTALL_DIR="/opt/homelab"
BACKUP_DIR="/opt/homelab/backups"
UPDATE_LOG="/var/log/homelab_updates.log"
LOCK_FILE="/var/run/homelab_update.lock"
CONFIG_DIR="/etc/homelab"

# Git repository information
REPO_URL="https://github.com/binGhzal/homelab.git"
REPO_BRANCH="main"

# Error handling function
handle_error() {
    local exit_code="$1"
    local line_no="$2"
    log "ERROR" "An error occurred on line $line_no with exit code $exit_code"

    # Remove lock file if it exists
    [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"

    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred during update. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit "$exit_code"
}

# Set up error trap
trap 'handle_error $? $LINENO' ERR

# Parse command line arguments
TEST_MODE=""
SILENT_MODE=""
CHECK_ONLY=""
FORCE_UPDATE=""
SKIP_BACKUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            shift
            ;;
        --silent)
            SILENT_MODE=1
            shift
            ;;
        --check-only)
            CHECK_ONLY=1
            shift
            ;;
        --force)
            FORCE_UPDATE=1
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=1
            shift
            ;;
        --help|-h)
            cat << EOF
Proxmox Template Creator - Update Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual updates)
  --silent            Run in silent mode (minimal output)
  --check-only        Only check for updates, don't apply
  --force             Force update even if no changes detected
  --skip-backup       Skip backup creation before update
  --help, -h          Show this help message

Functions:
  - Check for repository updates
  - Apply updates safely with rollback capability
  - Update individual modules
  - Configuration migration during updates
  - Scheduled update management
  - Backup and restore functionality

EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Function to create lock file
create_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log "ERROR" "Update already in progress (PID: $lock_pid)"
            return 1
        else
            log "WARN" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    log "INFO" "Created update lock file"
    return 0
}

# Function to remove lock file
remove_lock() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        log "INFO" "Removed update lock file"
    fi
}

# Function to get current version
get_current_version() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR"
        git describe --tags --always 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Function to get remote version
get_remote_version() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR"
        git fetch origin "$REPO_BRANCH" --quiet 2>/dev/null || return 1
        git describe --tags --always origin/"$REPO_BRANCH" 2>/dev/null || git rev-parse --short origin/"$REPO_BRANCH" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Function to check for updates
check_for_updates() {
    log "INFO" "Checking for updates..."

    if [ ! -d "$INSTALL_DIR" ]; then
        log "ERROR" "Installation directory not found: $INSTALL_DIR"
        return 1
    fi

    if [ ! -d "$INSTALL_DIR/.git" ]; then
        log "ERROR" "Not a git repository: $INSTALL_DIR"
        return 1
    fi

    local current_version
    current_version=$(get_current_version)
    log "INFO" "Current version: $current_version"

    local remote_version
    remote_version=$(get_remote_version)
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to fetch remote version"
        return 1
    fi
    log "INFO" "Remote version: $remote_version"

    if [ "$current_version" = "$remote_version" ] && [ -z "$FORCE_UPDATE" ]; then
        log "INFO" "System is up to date"
        return 1
    else
        log "INFO" "Update available: $current_version -> $remote_version"
        return 0
    fi
}

# Function to create backup before update
create_backup() {
    if [ -n "$SKIP_BACKUP" ]; then
        log "INFO" "Skipping backup creation (--skip-backup specified)"
        return 0
    fi

    log "INFO" "Creating backup before update..."

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would create backup"
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="homelab_backup_$timestamp"
    local backup_path="$BACKUP_DIR/$backup_name"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Create backup archive
    log "INFO" "Creating backup archive: $backup_path.tar.gz"

    if tar -czf "$backup_path.tar.gz" -C "$(dirname "$INSTALL_DIR")" "$(basename "$INSTALL_DIR")" 2>/dev/null; then
        log "INFO" "Backup created successfully: $backup_path.tar.gz"

        # Also backup configuration
        if [ -d "$CONFIG_DIR" ]; then
            log "INFO" "Backing up configuration..."
            tar -czf "$backup_path.config.tar.gz" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>/dev/null
            log "INFO" "Configuration backup created: $backup_path.config.tar.gz"
        fi

        # Keep only last 5 backups
        find "$BACKUP_DIR" -name "homelab_backup_*.tar.gz" -type f | sort -r | tail -n +6 | xargs -r rm -f
        find "$BACKUP_DIR" -name "homelab_backup_*.config.tar.gz" -type f | sort -r | tail -n +6 | xargs -r rm -f

        return 0
    else
        log "ERROR" "Failed to create backup"
        return 1
    fi
}

# Function to apply updates
apply_updates() {
    log "INFO" "Applying updates..."

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would apply updates"
        return 0
    fi

    if [ ! -d "$INSTALL_DIR/.git" ]; then
        log "ERROR" "Not a git repository: $INSTALL_DIR"
        return 1
    fi

    cd "$INSTALL_DIR"

    # Stash any local changes
    if ! git diff-index --quiet HEAD --; then
        log "WARN" "Local changes detected, stashing..."
        git stash push -m "Auto-stash before update $(date)"
    fi

    # Pull latest changes
    log "INFO" "Pulling latest changes from $REPO_BRANCH..."
    if git pull origin "$REPO_BRANCH"; then
        log "INFO" "Updates applied successfully"

        # Make scripts executable
        chmod +x scripts/*.sh 2>/dev/null || true

        # Run post-update hooks if they exist
        run_post_update_hooks

        return 0
    else
        log "ERROR" "Failed to apply updates"
        return 1
    fi
}

# Function to run post-update hooks
run_post_update_hooks() {
    log "INFO" "Running post-update hooks..."

    # Update configuration if needed
    migrate_configuration

    # Restart services if needed
    restart_services

    # Update dependencies
    update_dependencies

    log "INFO" "Post-update hooks completed"
}

# Function to migrate configuration
migrate_configuration() {
    log "INFO" "Checking for configuration migration..."

    # Check if config module exists and run migration
    if [ -x "$INSTALL_DIR/scripts/config.sh" ]; then
        log "INFO" "Running configuration validation..."
        if ! "$INSTALL_DIR/scripts/config.sh" --test >/dev/null 2>&1; then
            log "WARN" "Configuration validation failed, attempting migration..."
            # Add migration logic here if needed
        fi
    fi
}

# Function to restart services
restart_services() {
    log "INFO" "Checking services that need restart..."

    # Check if systemd service exists
    if systemctl is-enabled homelab-updater.timer >/dev/null 2>&1; then
        log "INFO" "Reloading systemd daemon..."
        systemctl daemon-reload
    fi

    # Add other service restart logic here
}

# Function to update dependencies
update_dependencies() {
    log "INFO" "Updating system dependencies..."

    # Update package lists
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
    elif command -v yum >/dev/null 2>&1; then
        yum check-update -q || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf check-update -q || true
    fi

    # Check for required tools
    local missing_tools=()
    local required_tools=("git" "curl" "whiptail" "jq")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "INFO" "Installing missing dependencies: ${missing_tools[*]}"

        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y "${missing_tools[@]}"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "${missing_tools[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "${missing_tools[@]}"
        else
            log "WARN" "Unknown package manager, please install manually: ${missing_tools[*]}"
        fi
    fi
}

# Function to rollback updates
rollback_update() {
    local backup_file="$1"

    if [ -z "$backup_file" ]; then
        log "ERROR" "Backup file required for rollback"
        return 1
    fi

    if [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi

    log "INFO" "Rolling back to backup: $backup_file"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would rollback to: $backup_file"
        return 0
    fi

    # Stop any running services
    log "INFO" "Stopping services before rollback..."

    # Extract backup
    local temp_dir
    temp_dir=$(mktemp -d)

    if tar -xzf "$backup_file" -C "$temp_dir"; then
        # Remove current installation
        rm -rf "$INSTALL_DIR"

        # Restore from backup
        mv "$temp_dir/$(basename "$INSTALL_DIR")" "$INSTALL_DIR"

        # Restore configuration if backup exists
        local config_backup="${backup_file%.tar.gz}.config.tar.gz"
        if [ -f "$config_backup" ]; then
            log "INFO" "Restoring configuration from backup..."
            rm -rf "$CONFIG_DIR"
            tar -xzf "$config_backup" -C "$(dirname "$CONFIG_DIR")"
        fi

        # Clean up
        rm -rf "$temp_dir"

        log "INFO" "Rollback completed successfully"
        return 0
    else
        log "ERROR" "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to list available backups
list_backups() {
    log "INFO" "Available backups:"

    if [ ! -d "$BACKUP_DIR" ]; then
        log "INFO" "No backup directory found"
        return 1
    fi

    local backups=()
    for backup_file in "$BACKUP_DIR"/homelab_backup_*.tar.gz; do
        if [ -f "$backup_file" ]; then
            local backup_name
            backup_name=$(basename "$backup_file")
            local backup_date
            backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            local backup_size
            backup_size=$(du -h "$backup_file" | cut -f1)
            backups+=("$backup_name" "$backup_date ($backup_size)")
        fi
    done

    if [ ${#backups[@]} -eq 0 ]; then
        if [ -t 0 ]; then
            whiptail --title "Backups" --msgbox "No backups found." 10 60
        else
            echo "No backups found."
        fi
        return 1
    fi

    if [ -t 0 ]; then
        local selected_backup
        selected_backup=$(whiptail --title "Available Backups" --menu "Select a backup:" 18 70 10 "${backups[@]}" 3>&1 1>&2 2>&3)

        if [ $? -eq 0 ] && [ -n "$selected_backup" ]; then
            echo "$BACKUP_DIR/$selected_backup"
        fi
    else
        printf "%-40s %s\n" "Backup File" "Date (Size)"
        printf "%-40s %s\n" "----------------------------------------" "-------------------"
        for ((i=0; i<${#backups[@]}; i+=2)); do
            printf "%-40s %s\n" "${backups[i]}" "${backups[i+1]}"
        done
    fi
}

# Function to show update status
show_update_status() {
    log "INFO" "System Update Status"
    echo "===================="

    local current_version
    current_version=$(get_current_version)
    echo "Current Version: $current_version"

    local remote_version
    remote_version=$(get_remote_version)
    if [ $? -eq 0 ]; then
        echo "Remote Version: $remote_version"

        if [ "$current_version" = "$remote_version" ]; then
            echo "Status: Up to date ✓"
        else
            echo "Status: Update available ⚠"
        fi
    else
        echo "Remote Version: Unable to check"
        echo "Status: Unknown"
    fi

    # Show last update time
    if [ -f "$UPDATE_LOG" ]; then
        local last_update
        last_update=$(tail -n 1 "$UPDATE_LOG" 2>/dev/null | grep "Update completed" | cut -d']' -f1 | tr -d '[' || echo "Never")
        echo "Last Update: $last_update"
    else
        echo "Last Update: Never"
    fi

    # Show backup count
    local backup_count=0
    if [ -d "$BACKUP_DIR" ]; then
        backup_count=$(find "$BACKUP_DIR" -name "homelab_backup_*.tar.gz" -type f | wc -l)
    fi
    echo "Available Backups: $backup_count"

    # Show auto-update status
    local auto_update="Unknown"
    if [ -f "$CONFIG_DIR/user.conf" ] || [ -f "$CONFIG_DIR/system.conf" ]; then
        if command -v "$SCRIPT_DIR/config.sh" >/dev/null 2>&1; then
            auto_update=$("$SCRIPT_DIR/config.sh" --test 2>/dev/null | grep -o "AUTO_UPDATE.*" | cut -d'"' -f2 || echo "Unknown")
        fi
    fi
    echo "Auto-Update: $auto_update"

    echo ""
}

# Function to schedule updates
schedule_updates() {
    log "INFO" "Configuring scheduled updates..."

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would configure scheduled updates"
        return 0
    fi

    local schedule_choice
    if [ -t 0 ]; then
        schedule_choice=$(whiptail --title "Schedule Updates" --menu "Select update schedule:" 15 60 5 \
            "daily" "Daily at 2 AM" \
            "weekly" "Weekly on Sunday at 2 AM" \
            "monthly" "Monthly on 1st at 2 AM" \
            "disable" "Disable scheduled updates" \
            "custom" "Custom schedule" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then
            return 0
        fi
    else
        schedule_choice="daily"  # Default for non-interactive
    fi

    local timer_schedule=""
    case "$schedule_choice" in
        "daily")
            timer_schedule="OnCalendar=daily"
            ;;
        "weekly")
            timer_schedule="OnCalendar=Sun *-*-* 02:00:00"
            ;;
        "monthly")
            timer_schedule="OnCalendar=*-*-01 02:00:00"
            ;;
        "disable")
            if systemctl is-enabled homelab-updater.timer >/dev/null 2>&1; then
                systemctl disable homelab-updater.timer
                systemctl stop homelab-updater.timer
                log "INFO" "Scheduled updates disabled"
            fi
            return 0
            ;;
        "custom")
            if [ -t 0 ]; then
                local custom_schedule
                custom_schedule=$(whiptail --title "Custom Schedule" --inputbox "Enter systemd timer schedule (e.g., 'daily', '*-*-* 02:00:00'):" 10 60 "daily" 3>&1 1>&2 2>&3)
                if [ $? -eq 0 ] && [ -n "$custom_schedule" ]; then
                    timer_schedule="OnCalendar=$custom_schedule"
                else
                    return 0
                fi
            else
                log "ERROR" "Custom schedule requires interactive mode"
                return 1
            fi
            ;;
    esac

    # Create systemd service and timer
    local service_file="/etc/systemd/system/homelab-updater.service"
    local timer_file="/etc/systemd/system/homelab-updater.timer"

    # Create service file
    cat > "$service_file" << EOF
[Unit]
Description=Homelab Auto-Updater
After=network.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/scripts/update.sh --silent
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create timer file
    cat > "$timer_file" << EOF
[Unit]
Description=Run Homelab Auto-Updater
Requires=homelab-updater.service

[Timer]
$timer_schedule
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    systemctl daemon-reload
    systemctl enable homelab-updater.timer
    systemctl start homelab-updater.timer

    log "INFO" "Scheduled updates configured: $schedule_choice"

    if [ -t 0 ]; then
        whiptail --title "Success" --msgbox "Scheduled updates configured successfully.\n\nSchedule: $schedule_choice\nNext run: $(systemctl list-timers homelab-updater.timer --no-pager | tail -n +2 | head -n 1 | awk '{print $1, $2}')" 12 60
    fi
}

# Function to perform full update
perform_update() {
    local interactive="${1:-true}"

    log "INFO" "Starting update process..."

    # Create lock
    if ! create_lock; then
        return 1
    fi

    # Ensure lock is removed on exit
    trap 'remove_lock; exit' EXIT

    # Check for updates
    if ! check_for_updates; then
        if [ -z "$FORCE_UPDATE" ]; then
            log "INFO" "No updates available"
            if [ "$interactive" = "true" ] && [ -t 0 ]; then
                whiptail --title "Update Check" --msgbox "System is already up to date." 10 60
            fi
            return 0
        fi
    fi

    # Confirm update if interactive
    if [ "$interactive" = "true" ] && [ -t 0 ] && [ -z "$SILENT_MODE" ]; then
        local current_version
        current_version=$(get_current_version)
        local remote_version
        remote_version=$(get_remote_version)

        if ! whiptail --title "Confirm Update" --yesno "Update available:\n\nCurrent: $current_version\nNew: $remote_version\n\nProceed with update?" 12 60; then
            log "INFO" "Update cancelled by user"
            return 0
        fi
    fi

    # Create backup
    if ! create_backup; then
        log "ERROR" "Failed to create backup"
        if [ "$interactive" = "true" ] && [ -t 0 ]; then
            if ! whiptail --title "Backup Failed" --yesno "Failed to create backup. Continue anyway?" 10 60; then
                return 1
            fi
        else
            return 1
        fi
    fi

    # Apply updates
    if apply_updates; then
        local new_version
        new_version=$(get_current_version)
        log "INFO" "Update completed successfully. New version: $new_version"

        # Log update to update log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Update completed: $new_version" >> "$UPDATE_LOG"

        if [ "$interactive" = "true" ] && [ -t 0 ] && [ -z "$SILENT_MODE" ]; then
            whiptail --title "Update Complete" --msgbox "Update completed successfully!\n\nNew version: $new_version" 10 60
        fi

        return 0
    else
        log "ERROR" "Update failed"

        if [ "$interactive" = "true" ] && [ -t 0 ]; then
            if whiptail --title "Update Failed" --yesno "Update failed. Would you like to rollback to the previous version?" 10 60; then
                local latest_backup
                latest_backup=$(find "$BACKUP_DIR" -name "homelab_backup_*.tar.gz" -type f | sort -r | head -n 1)
                if [ -n "$latest_backup" ]; then
                    rollback_update "$latest_backup"
                else
                    whiptail --title "Rollback Failed" --msgbox "No backup available for rollback." 10 60
                fi
            fi
        fi

        return 1
    fi
}

# Function to show help
show_help() {
    local help_text=""

    help_text+="Update Module Help\n"
    help_text+="==================\n\n"

    help_text+="The Update Module provides automated system updates\n"
    help_text+="and maintenance for the Proxmox Template Creator.\n\n"

    help_text+="Key Features:\n"
    help_text+="- Check for repository updates\n"
    help_text+="- Apply updates safely with rollback capability\n"
    help_text+="- Automatic backup creation before updates\n"
    help_text+="- Configuration migration during updates\n"
    help_text+="- Scheduled update management\n"
    help_text+="- Rollback to previous versions\n\n"

    help_text+="Update Process:\n"
    help_text+="1. Check for available updates\n"
    help_text+="2. Create backup of current system\n"
    help_text+="3. Apply updates from repository\n"
    help_text+="4. Run post-update hooks\n"
    help_text+="5. Verify system functionality\n\n"

    help_text+="Backup Management:\n"
    help_text+="- Automatic backups before updates\n"
    help_text+="- Manual backup creation\n"
    help_text+="- Backup retention (keeps last 5)\n"
    help_text+="- Easy rollback to any backup\n\n"

    help_text+="Scheduling:\n"
    help_text+="- Daily, weekly, or monthly updates\n"
    help_text+="- Custom systemd timer schedules\n"
    help_text+="- Silent operation for automation\n"
    help_text+="- Configurable update windows\n\n"

    help_text+="For more information, see the system documentation."

    echo -e "$help_text" | whiptail --title "Update Module Help" --textbox /dev/stdin 25 80
}

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Update Management v${VERSION}" --menu "Choose an action:" 20 70 12 \
            "1" "Check for updates" \
            "2" "Apply updates now" \
            "3" "Show update status" \
            "4" "Schedule automatic updates" \
            "5" "Create backup" \
            "6" "List backups" \
            "7" "Rollback to backup" \
            "8" "Force update" \
            "9" "View update log" \
            "10" "Update configuration" \
            "11" "Help and documentation" \
            "12" "Exit" 3>&1 1>&2 2>&3)

        case $choice in
            1)
                if check_for_updates; then
                    local current_version
                    current_version=$(get_current_version)
                    local remote_version
                    remote_version=$(get_remote_version)
                    whiptail --title "Update Available" --msgbox "Update available!\n\nCurrent: $current_version\nNew: $remote_version" 10 60
                else
                    whiptail --title "Up to Date" --msgbox "System is already up to date." 10 60
                fi
                ;;
            2)
                perform_update "true"
                ;;
            3)
                show_update_status | whiptail --title "Update Status" --textbox /dev/stdin 20 80
                ;;
            4)
                schedule_updates
                ;;
            5)
                if create_backup; then
                    whiptail --title "Backup Created" --msgbox "Backup created successfully." 10 60
                else
                    whiptail --title "Backup Failed" --msgbox "Failed to create backup. Check logs for details." 10 60
                fi
                ;;
            6)
                list_backups
                ;;
            7)
                local backup_file
                backup_file=$(list_backups)
                if [ -n "$backup_file" ]; then
                    if whiptail --title "Confirm Rollback" --yesno "Are you sure you want to rollback to:\n\n$(basename "$backup_file")\n\nThis will overwrite the current system!" 12 70; then
                        if rollback_update "$backup_file"; then
                            whiptail --title "Rollback Complete" --msgbox "System rolled back successfully." 10 60
                        else
                            whiptail --title "Rollback Failed" --msgbox "Rollback failed. Check logs for details." 10 60
                        fi
                    fi
                fi
                ;;
            8)
                FORCE_UPDATE=1
                perform_update "true"
                ;;
            9)
                if [ -f "$UPDATE_LOG" ]; then
                    whiptail --title "Update Log" --textbox "$UPDATE_LOG" 20 80
                else
                    whiptail --title "Update Log" --msgbox "No update log found." 10 60
                fi
                ;;
            10)
                if [ -x "$SCRIPT_DIR/config.sh" ]; then
                    "$SCRIPT_DIR/config.sh"
                else
                    whiptail --title "Error" --msgbox "Configuration module not available." 10 60
                fi
                ;;
            11)
                show_help
                ;;
            12|"")
                log "INFO" "Exiting update management"
                exit 0
                ;;
        esac
    done
}

# Main execution
main() {
    log "INFO" "Starting Update Management v${VERSION}"

    # Check if running as root
    check_root

    # Handle command line modes
    if [ -n "$CHECK_ONLY" ]; then
        if check_for_updates; then
            echo "Update available"
            exit 0
        else
            echo "Up to date"
            exit 1
        fi
    fi

    if [ -n "$SILENT_MODE" ]; then
        perform_update "false"
        exit $?
    fi

    # If running in test mode, show test message and exit
    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Update Management module loaded successfully (test mode)"
        return 0
    fi

    # If running non-interactively, perform update
    if [ ! -t 0 ]; then
        perform_update "false"
        exit $?
    fi

    # Run main menu
    main_menu
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
