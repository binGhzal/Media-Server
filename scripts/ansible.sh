#!/bin/bash
# Proxmox Template Creator - Ansible Module
# Deploy and manage infrastructure using Ansible

set -e

# Script version
VERSION="0.1.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR

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
    local exit_code="$1"
    local line_no="$2"
    log "ERROR" "An error occurred on line $line_no with exit code $exit_code"
    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit "$exit_code"
}

# Set up error trap
trap 'handle_error $? $LINENO' ERR

# Parse command line arguments
TEST_MODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            shift
            ;;
        --help|-h)
            cat << EOF
Proxmox Template Creator - Ansible Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual deployments)
  --help, -h          Show this help message

Functions:
  - Install Ansible if not present
  - Discover available Ansible playbooks
  - Collect and validate variables
  - Manage Ansible roles
  - Execute playbook workflows

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

# Configuration
ANSIBLE_PLAYBOOKS_DIR="/opt/ansible/playbooks"
ANSIBLE_ROLES_DIR="/opt/ansible/roles"

# Function to check if Ansible is installed
check_ansible() {
    if command -v ansible >/dev/null 2>&1; then
        local version
        version=$(ansible --version | head -n1 | awk '{print $3}')
        log "INFO" "Ansible is installed (version: $version)"
        return 0
    else
        log "INFO" "Ansible is not installed"
        return 1
    fi
}

# Function to install Ansible
install_ansible() {
    log "INFO" "Installing Ansible..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would install Ansible"
        return 0
    fi
    
    # Update package index
    apt-get update
    
    # Install required packages
    apt-get install -y software-properties-common
    
    # Add Ansible PPA and install
    add-apt-repository --yes --update ppa:ansible/ansible
    apt-get install -y ansible
    
    # Install additional useful collections
    ansible-galaxy collection install community.general
    ansible-galaxy collection install ansible.posix
    
    # Verify installation
    if ansible --version >/dev/null 2>&1; then
        log "INFO" "Ansible installed successfully"
        return 0
    else
        log "ERROR" "Ansible installation failed"
        return 1
    fi
}

# Function to discover available Ansible playbooks
discover_playbooks() {
    log "INFO" "Discovering available Ansible playbooks..."
    
    local playbooks_found=()
    
    # Check for playbooks in the project directory
    if [ -d "$SCRIPT_DIR/../ansible" ]; then
        log "INFO" "Found project ansible directory"
        for playbook_file in "$SCRIPT_DIR/../ansible"/*.yml "$SCRIPT_DIR/../ansible"/*.yaml; do
            if [ -f "$playbook_file" ]; then
                local playbook_name
                playbook_name=$(basename "$playbook_file" | sed 's/\.(yml|yaml)$//')
                playbooks_found+=("$playbook_name")
                log "INFO" "Found playbook: $playbook_name"
            fi
        done
    fi
    
    # Check for playbooks in system ansible directory
    if [ -d "$ANSIBLE_PLAYBOOKS_DIR" ]; then
        for playbook_file in "$ANSIBLE_PLAYBOOKS_DIR"/*.yml "$ANSIBLE_PLAYBOOKS_DIR"/*.yaml; do
            if [ -f "$playbook_file" ]; then
                local playbook_name
                playbook_name=$(basename "$playbook_file" | sed 's/\.(yml|yaml)$//')
                playbooks_found+=("$playbook_name")
                log "INFO" "Found system playbook: $playbook_name"
            fi
        done
    fi
    
    if [ ${#playbooks_found[@]} -eq 0 ]; then
        log "WARN" "No Ansible playbooks found"
        return 1
    fi
    
    printf '%s\n' "${playbooks_found[@]}"
    return 0
}

# Function to discover available Ansible roles
discover_roles() {
    log "INFO" "Discovering available Ansible roles..."
    
    local roles_found=()
    
    # Check for roles in the project directory
    if [ -d "$SCRIPT_DIR/../ansible/roles" ]; then
        log "INFO" "Found project ansible roles directory"
        for role_dir in "$SCRIPT_DIR/../ansible/roles"/*; do
            if [ -d "$role_dir" ] && [ -f "$role_dir/tasks/main.yml" ]; then
                local role_name
                role_name=$(basename "$role_dir")
                roles_found+=("$role_name")
                log "INFO" "Found role: $role_name"
            fi
        done
    fi
    
    # Check for roles in system ansible directory
    if [ -d "$ANSIBLE_ROLES_DIR" ]; then
        for role_dir in "$ANSIBLE_ROLES_DIR"/*; do
            if [ -d "$role_dir" ] && [ -f "$role_dir/tasks/main.yml" ]; then
                local role_name
                role_name=$(basename "$role_dir")
                roles_found+=("$role_name")
                log "INFO" "Found system role: $role_name"
            fi
        done
    fi
    
    if [ ${#roles_found[@]} -eq 0 ]; then
        log "WARN" "No Ansible roles found"
        return 1
    fi
    
    printf '%s\n' "${roles_found[@]}"
    return 0
}

# Function to collect variables for a playbook
collect_variables() {
    local playbook_path="$1"
    
    log "INFO" "Collecting variables for playbook: $(basename "$playbook_path")"
    
    # Check for group_vars and host_vars
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    
    local vars_file="$playbook_dir/vars.yml"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would collect variables for playbook"
        return 0
    fi
    
    # Create basic inventory if it doesn't exist
    local inventory_file="$playbook_dir/inventory.ini"
    if [ ! -f "$inventory_file" ]; then
        log "INFO" "Creating basic inventory file: $inventory_file"
        cat > "$inventory_file" << EOF
[proxmox_hosts]
# Add your Proxmox hosts here
# Example: 192.168.1.100 ansible_user=root

[all:vars]
# Global variables
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    fi
    
    # Interactive variable collection using whiptail
    if [ -t 0 ]; then  # If running interactively
        # Ask for basic configuration
        local target_hosts
        target_hosts=$(whiptail --title "Ansible Variables" --inputbox "Enter target hosts (comma-separated IP addresses or hostnames):" 10 60 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$target_hosts" ]; then
            # Update inventory file
            echo "" >> "$inventory_file"
            echo "# Hosts added by terraform script" >> "$inventory_file"
            IFS=',' read -ra HOSTS <<< "$target_hosts"
            for host in "${HOSTS[@]}"; do
                host=$(echo "$host" | xargs)  # Trim whitespace
                echo "$host" >> "$inventory_file"
            done
            log "INFO" "Added hosts to inventory: $target_hosts"
        fi
        
        # Ask for ansible user
        local ansible_user
        ansible_user=$(whiptail --title "Ansible Variables" --inputbox "Enter Ansible user (default: root):" 10 60 "root" 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$ansible_user" ]; then
            echo "ansible_user=$ansible_user" >> "$vars_file"
            log "INFO" "Set ansible_user to '$ansible_user'"
        fi
        
        # Ask for SSH key path
        local ssh_key_path
        ssh_key_path=$(whiptail --title "Ansible Variables" --inputbox "Enter SSH private key path (optional):" 10 60 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$ssh_key_path" ]; then
            echo "ansible_ssh_private_key_file=$ssh_key_path" >> "$vars_file"
            log "INFO" "Set SSH private key path to '$ssh_key_path'"
        fi
    else
        log "WARN" "Running non-interactively, using default configuration"
    fi
    
    return 0
}

# Function to validate Ansible playbook
validate_playbook() {
    local playbook_path="$1"
    
    log "INFO" "Validating Ansible playbook: $playbook_path"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would validate Ansible playbook"
        return 0
    fi
    
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    
    # Check for inventory file
    local inventory_file="$playbook_dir/inventory.ini"
    if [ ! -f "$inventory_file" ]; then
        log "ERROR" "No inventory file found: $inventory_file"
        return 1
    fi
    
    # Validate playbook syntax
    if ansible-playbook --syntax-check -i "$inventory_file" "$playbook_path"; then
        log "INFO" "Ansible playbook syntax is valid"
        return 0
    else
        log "ERROR" "Ansible playbook syntax validation failed"
        return 1
    fi
}

# Function to run dry-run (check mode)
dry_run_playbook() {
    local playbook_path="$1"
    
    log "INFO" "Running Ansible playbook dry-run..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would run Ansible playbook dry-run"
        return 0
    fi
    
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    local inventory_file="$playbook_dir/inventory.ini"
    
    # Run in check mode
    if ansible-playbook --check -i "$inventory_file" "$playbook_path"; then
        log "INFO" "Ansible playbook dry-run completed successfully"
        return 0
    else
        log "ERROR" "Ansible playbook dry-run failed"
        return 1
    fi
}

# Function to execute Ansible playbook
execute_playbook() {
    local playbook_path="$1"
    
    log "INFO" "Executing Ansible playbook..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would execute Ansible playbook"
        return 0
    fi
    
    local playbook_dir
    playbook_dir=$(dirname "$playbook_path")
    local inventory_file="$playbook_dir/inventory.ini"
    
    # Execute playbook
    if ansible-playbook -i "$inventory_file" "$playbook_path"; then
        log "INFO" "Ansible playbook executed successfully"
        return 0
    else
        log "ERROR" "Ansible playbook execution failed"
        return 1
    fi
}

# Function to install Ansible role from Ansible Galaxy
install_role() {
    local role_name="$1"
    
    log "INFO" "Installing Ansible role: $role_name"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would install Ansible role: $role_name"
        return 0
    fi
    
    # Create roles directory if it doesn't exist
    mkdir -p "$ANSIBLE_ROLES_DIR"
    
    # Install role
    if ansible-galaxy install -p "$ANSIBLE_ROLES_DIR" "$role_name"; then
        log "INFO" "Ansible role installed successfully: $role_name"
        return 0
    else
        log "ERROR" "Ansible role installation failed: $role_name"
        return 1
    fi
}

# Function to show Ansible configuration
show_config() {
    log "INFO" "Showing Ansible configuration..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would show Ansible configuration"
        return 0
    fi
    
    echo "Ansible Configuration:"
    echo "====================="
    ansible --version
    echo ""
    echo "Ansible Config File:"
    ansible-config view
    echo ""
    echo "Available Collections:"
    ansible-galaxy collection list
    
    return 0
}

# Main function to display menu and handle user selection
main() {
    log "INFO" "Starting Ansible Module v${VERSION}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check/install dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        log "INFO" "Installing Python3..."
        apt-get update && apt-get install -y python3 python3-pip
    fi
    
    # Check/install Ansible
    if ! check_ansible; then
        if [ -t 0 ]; then  # If running interactively
            if whiptail --title "Install Ansible" --yesno "Ansible is not installed. Would you like to install it now?" 10 60; then
                install_ansible
            else
                log "ERROR" "Ansible is required but not installed"
                exit 1
            fi
        else
            log "INFO" "Installing Ansible automatically..."
            install_ansible
        fi
    fi
    
    # Main menu loop
    while true; do
        if [ -t 0 ]; then  # If running interactively
            local choice
            choice=$(whiptail --title "Ansible Module v${VERSION}" \
                --menu "Choose an action:" 20 70 12 \
                "1" "Discover Ansible Playbooks" \
                "2" "Discover Ansible Roles" \
                "3" "Execute Playbook" \
                "4" "Dry-run Playbook" \
                "5" "Validate Playbook" \
                "6" "Install Role from Galaxy" \
                "7" "Show Configuration" \
                "8" "Create Sample Playbook" \
                "9" "Exit" \
                3>&1 1>&2 2>&3)
            
            case $choice in
                1)
                    log "INFO" "Discovering Ansible playbooks..."
                    if playbooks=$(discover_playbooks); then
                        if [ -n "$playbooks" ]; then
                            whiptail --title "Available Playbooks" --msgbox "Found playbooks:\n\n$playbooks" 20 60
                        else
                            whiptail --title "No Playbooks" --msgbox "No Ansible playbooks found." 10 60
                        fi
                    else
                        whiptail --title "No Playbooks" --msgbox "No Ansible playbooks found." 10 60
                    fi
                    ;;
                2)
                    log "INFO" "Discovering Ansible roles..."
                    if roles=$(discover_roles); then
                        if [ -n "$roles" ]; then
                            whiptail --title "Available Roles" --msgbox "Found roles:\n\n$roles" 20 60
                        else
                            whiptail --title "No Roles" --msgbox "No Ansible roles found." 10 60
                        fi
                    else
                        whiptail --title "No Roles" --msgbox "No Ansible roles found." 10 60
                    fi
                    ;;
                3)
                    # Execute playbook workflow
                    log "INFO" "Starting playbook execution workflow..."
                    
                    # Get available playbooks
                    if ! playbooks=$(discover_playbooks); then
                        whiptail --title "Error" --msgbox "No Ansible playbooks found." 10 60
                        continue
                    fi
                    
                    # Convert playbooks to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r playbook; do
                        menu_items+=("$i" "$playbook")
                        ((i++))
                    done <<< "$playbooks"
                    
                    # Let user select playbook
                    local selected_index
                    selected_index=$(whiptail --title "Select Playbook" \
                        --menu "Choose a playbook to execute:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_playbook
                        selected_playbook=$(echo "$playbooks" | sed -n "${selected_index}p")
                        
                        # Find playbook path
                        local playbook_path=""
                        if [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yml"
                        elif [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yaml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yaml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml"
                        fi
                        
                        if [ -n "$playbook_path" ]; then
                            log "INFO" "Selected playbook: $selected_playbook at $playbook_path"
                            
                            # Collect variables
                            collect_variables "$playbook_path"
                            
                            # Validate playbook
                            if validate_playbook "$playbook_path"; then
                                # Execute playbook
                                if execute_playbook "$playbook_path"; then
                                    whiptail --title "Success" --msgbox "Playbook executed successfully!" 10 60
                                else
                                    whiptail --title "Error" --msgbox "Playbook execution failed. Check logs for details." 10 60
                                fi
                            else
                                whiptail --title "Error" --msgbox "Playbook validation failed. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Playbook file not found." 10 60
                        fi
                    fi
                    ;;
                4)
                    # Dry-run playbook
                    log "INFO" "Starting playbook dry-run workflow..."
                    
                    # Get available playbooks
                    if ! playbooks=$(discover_playbooks); then
                        whiptail --title "Error" --msgbox "No Ansible playbooks found." 10 60
                        continue
                    fi
                    
                    # Convert playbooks to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r playbook; do
                        menu_items+=("$i" "$playbook")
                        ((i++))
                    done <<< "$playbooks"
                    
                    # Let user select playbook
                    local selected_index
                    selected_index=$(whiptail --title "Select Playbook for Dry-run" \
                        --menu "Choose a playbook for dry-run (check mode):" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_playbook
                        selected_playbook=$(echo "$playbooks" | sed -n "${selected_index}p")
                        
                        # Find playbook path
                        local playbook_path=""
                        if [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yml"
                        elif [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yaml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yaml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml"
                        fi
                        
                        if [ -n "$playbook_path" ]; then
                            log "INFO" "Selected playbook for dry-run: $selected_playbook at $playbook_path"
                            
                            # Collect variables
                            collect_variables "$playbook_path"
                            
                            # Validate playbook first
                            if validate_playbook "$playbook_path"; then
                                # Run dry-run
                                if dry_run_playbook "$playbook_path"; then
                                    whiptail --title "Dry-run Success" --msgbox "Playbook dry-run completed successfully!\n\nNo changes were made to target systems.\nCheck logs for detailed output." 12 70
                                else
                                    whiptail --title "Dry-run Failed" --msgbox "Playbook dry-run failed. Check logs for details." 10 60
                                fi
                            else
                                whiptail --title "Error" --msgbox "Playbook validation failed. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Playbook file not found." 10 60
                        fi
                    fi
                    ;;
                5)
                    # Validate playbook
                    log "INFO" "Starting playbook validation workflow..."
                    
                    # Get available playbooks
                    if ! playbooks=$(discover_playbooks); then
                        whiptail --title "Error" --msgbox "No Ansible playbooks found." 10 60
                        continue
                    fi
                    
                    # Convert playbooks to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r playbook; do
                        menu_items+=("$i" "$playbook")
                        ((i++))
                    done <<< "$playbooks"
                    
                    # Let user select playbook
                    local selected_index
                    selected_index=$(whiptail --title "Select Playbook for Validation" \
                        --menu "Choose a playbook to validate:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_playbook
                        selected_playbook=$(echo "$playbooks" | sed -n "${selected_index}p")
                        
                        # Find playbook path
                        local playbook_path=""
                        if [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yml"
                        elif [ -f "$SCRIPT_DIR/../ansible/$selected_playbook.yaml" ]; then
                            playbook_path="$SCRIPT_DIR/../ansible/$selected_playbook.yaml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yml"
                        elif [ -f "$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml" ]; then
                            playbook_path="$ANSIBLE_PLAYBOOKS_DIR/$selected_playbook.yaml"
                        fi
                        
                        if [ -n "$playbook_path" ]; then
                            log "INFO" "Validating playbook: $selected_playbook at $playbook_path"
                            
                            if validate_playbook "$playbook_path"; then
                                whiptail --title "Validation Success" --msgbox "Playbook validation successful!\n\nPlaybook: $selected_playbook\nSyntax: Valid\nStructure: Valid" 12 70
                            else
                                whiptail --title "Validation Failed" --msgbox "Playbook validation failed for: $selected_playbook\n\nCheck logs for detailed error information." 12 70
                            fi
                        else
                            whiptail --title "Error" --msgbox "Playbook file not found." 10 60
                        fi
                    fi
                    ;;
                6)
                    # Install role from Galaxy
                    local role_name
                    role_name=$(whiptail --title "Install Role" --inputbox "Enter role name from Ansible Galaxy:" 10 60 3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ] && [ -n "$role_name" ]; then
                        install_role "$role_name"
                        if [ $? -eq 0 ]; then
                            whiptail --title "Success" --msgbox "Role installed successfully: $role_name" 10 60
                        else
                            whiptail --title "Error" --msgbox "Role installation failed. Check logs for details." 10 60
                        fi
                    fi
                    ;;
                7)
                    # Show configuration
                    log "INFO" "Displaying Ansible configuration..."
                    
                    # Collect configuration information
                    local config_info=""
                    if [ "$TEST_MODE" ]; then
                        config_info="[TEST MODE] Ansible Configuration Information\n\n"
                        config_info+="Ansible Version: 2.x.x (simulated)\n"
                        config_info+="Config File: /etc/ansible/ansible.cfg\n"
                        config_info+="Module Path: /usr/share/ansible\n"
                        config_info+="Collections: community.general, ansible.posix\n\n"
                        config_info+="Project Ansible Directory: $SCRIPT_DIR/../ansible\n"
                        config_info+="System Playbooks Directory: $ANSIBLE_PLAYBOOKS_DIR\n"
                        config_info+="System Roles Directory: $ANSIBLE_ROLES_DIR"
                    else
                        # Get real configuration information
                        local temp_file=$(mktemp)
                        {
                            echo "=== ANSIBLE VERSION ==="
                            ansible --version 2>/dev/null || echo "Ansible not installed"
                            echo ""
                            echo "=== ANSIBLE CONFIGURATION ==="
                            ansible-config dump 2>/dev/null | head -20 || echo "No configuration available"
                            echo ""
                            echo "=== INSTALLED COLLECTIONS ==="
                            ansible-galaxy collection list 2>/dev/null | head -10 || echo "No collections found"
                            echo ""
                            echo "=== PROJECT DIRECTORIES ==="
                            echo "Project Ansible Directory: $SCRIPT_DIR/../ansible"
                            echo "System Playbooks Directory: $ANSIBLE_PLAYBOOKS_DIR"
                            echo "System Roles Directory: $ANSIBLE_ROLES_DIR"
                        } > "$temp_file"
                        
                        config_info=$(cat "$temp_file")
                        rm -f "$temp_file"
                    fi
                    
                    # Display in scrollable dialog
                    whiptail --title "Ansible Configuration" --scrolltext --msgbox "$config_info" 25 100
                    ;;
                8)
                    # Create sample playbook
                    log "INFO" "Creating sample playbook..."
                    whiptail --title "Info" --msgbox "Sample playbook creation - would create example playbook" 10 60
                    ;;
                9)
                    log "INFO" "Exiting Ansible module"
                    exit 0
                    ;;
                *)
                    log "ERROR" "Invalid selection"
                    ;;
            esac
        else
            # Non-interactive mode - show available playbooks and exit
            log "INFO" "Running in non-interactive mode"
            discover_playbooks
            exit 0
        fi
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
