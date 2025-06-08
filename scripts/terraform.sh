#!/bin/bash
# Proxmox Template Creator - Terraform Module
# Deploy and manage infrastructure using Terraform

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
Proxmox Template Creator - Terraform Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual deployments)
  --help, -h          Show this help message

Functions:
  - Install Terraform if not present
  - Discover available Terraform modules
  - Collect and validate variables
  - Generate Terraform configurations
  - Manage Terraform state
  - Execute plan/apply workflows

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
TERRAFORM_DIR="/opt/terraform"
TERRAFORM_MODULES_DIR="/opt/terraform/modules"
TERRAFORM_STATE_DIR="/opt/terraform/state"
TERRAFORM_VERSION="1.6.0"

# Function to check if Terraform is installed
check_terraform() {
    if command -v terraform >/dev/null 2>&1; then
        local version
        version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | awk '{print $2}' | cut -d'v' -f2)
        log "INFO" "Terraform is installed (version: $version)"
        return 0
    else
        log "INFO" "Terraform is not installed"
        return 1
    fi
}

# Function to install Terraform
install_terraform() {
    log "INFO" "Installing Terraform v${TERRAFORM_VERSION}..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would install Terraform v${TERRAFORM_VERSION}"
        return 0
    fi
    
    # Create terraform directory
    mkdir -p "$TERRAFORM_DIR"
    cd "$TERRAFORM_DIR"
    
    # Detect architecture
    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        arm*) arch="arm" ;;
        *) 
            log "ERROR" "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
    
    # Download and install Terraform
    local download_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
    
    log "INFO" "Downloading Terraform from: $download_url"
    
    # Install required packages
    if ! command -v wget >/dev/null 2>&1; then
        apt-get update && apt-get install -y wget
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        apt-get update && apt-get install -y unzip
    fi
    
    # Download and extract
    wget -q "$download_url" -O terraform.zip
    unzip -q terraform.zip
    chmod +x terraform
    
    # Move to system path
    mv terraform /usr/local/bin/
    
    # Clean up
    rm -f terraform.zip
    
    # Verify installation
    if terraform version >/dev/null 2>&1; then
        log "INFO" "Terraform installed successfully"
        return 0
    else
        log "ERROR" "Terraform installation failed"
        return 1
    fi
}

# Function to discover available Terraform modules
discover_modules() {
    log "INFO" "Discovering available Terraform modules..."
    
    local modules_found=()
    
    # Check for modules in the project directory
    if [ -d "$SCRIPT_DIR/../terraform" ]; then
        log "INFO" "Found project terraform directory"
        for module_dir in "$SCRIPT_DIR/../terraform"/*; do
            if [ -d "$module_dir" ] && [ -f "$module_dir/main.tf" ]; then
                local module_name
                module_name=$(basename "$module_dir")
                modules_found+=("$module_name")
                log "INFO" "Found module: $module_name"
            fi
        done
    fi
    
    # Check for modules in system terraform directory
    if [ -d "$TERRAFORM_MODULES_DIR" ]; then
        for module_dir in "$TERRAFORM_MODULES_DIR"/*; do
            if [ -d "$module_dir" ] && [ -f "$module_dir/main.tf" ]; then
                local module_name
                module_name=$(basename "$module_dir")
                modules_found+=("$module_name")
                log "INFO" "Found system module: $module_name"
            fi
        done
    fi
    
    if [ ${#modules_found[@]} -eq 0 ]; then
        log "WARN" "No Terraform modules found"
        return 1
    fi
    
    printf '%s\n' "${modules_found[@]}"
    return 0
}

# Function to collect variables for a module
collect_variables() {
    local module_path="$1"
    
    if [ ! -f "$module_path/variables.tf" ]; then
        log "INFO" "No variables.tf found in module"
        return 0
    fi
    
    log "INFO" "Collecting variables for module: $(basename "$module_path")"
    
    # Parse variables.tf to extract variable definitions
    local variables
    variables=$(grep -E '^variable\s+"[^"]+"\s*{' "$module_path/variables.tf" | sed 's/variable "\([^"]*\)".*/\1/' || true)
    
    if [ -z "$variables" ]; then
        log "INFO" "No variables found in module"
        return 0
    fi
    
    local vars_file="$module_path/terraform.tfvars"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would collect variables: $variables"
        return 0
    fi
    
    # Create variables file if it doesn't exist
    if [ ! -f "$vars_file" ]; then
        log "INFO" "Creating variables file: $vars_file"
        touch "$vars_file"
    fi
    
    # Interactive variable collection using whiptail
    for var in $variables; do
        # Check if variable already has a value
        if grep -q "^${var}\s*=" "$vars_file" 2>/dev/null; then
            log "INFO" "Variable '$var' already has a value"
            continue
        fi
        
        # Get variable description from variables.tf
        local description
        description=$(awk "/^variable \"${var}\"/,/^}/" "$module_path/variables.tf" | grep -E '^\s*description\s*=' | sed 's/.*description\s*=\s*"\([^"]*\)".*/\1/' || echo "")
        
        # Get variable type
        local var_type
        var_type=$(awk "/^variable \"${var}\"/,/^}/" "$module_path/variables.tf" | grep -E '^\s*type\s*=' | sed 's/.*type\s*=\s*\([^[:space:]]*\).*/\1/' || echo "string")
        
        # Prompt for value
        local prompt="Enter value for variable '$var'"
        if [ -n "$description" ]; then
            prompt="$prompt\n\nDescription: $description"
        fi
        prompt="$prompt\nType: $var_type"
        
        local value
        if [ -t 0 ]; then  # If running interactively
            value=$(whiptail --title "Terraform Variable" --inputbox "$prompt" 15 60 3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$value" ]; then
                # Add variable to tfvars file
                if [[ "$var_type" == "string" ]]; then
                    echo "${var} = \"${value}\"" >> "$vars_file"
                else
                    echo "${var} = ${value}" >> "$vars_file"
                fi
                log "INFO" "Set variable '$var' to '$value'"
            fi
        else
            log "WARN" "Running non-interactively, skipping variable '$var'"
        fi
    done
    
    return 0
}

# Function to validate Terraform configuration
validate_config() {
    local module_path="$1"
    
    log "INFO" "Validating Terraform configuration in: $module_path"
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would validate Terraform configuration"
        return 0
    fi
    
    cd "$module_path"
    
    # Initialize Terraform
    if ! terraform init -no-color; then
        log "ERROR" "Terraform initialization failed"
        return 1
    fi
    
    # Validate configuration
    if ! terraform validate -no-color; then
        log "ERROR" "Terraform validation failed"
        return 1
    fi
    
    log "INFO" "Terraform configuration is valid"
    return 0
}

# Function to plan Terraform deployment
plan_deployment() {
    local module_path="$1"
    local plan_file="$2"
    
    log "INFO" "Creating Terraform plan..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would create Terraform plan"
        return 0
    fi
    
    cd "$module_path"
    
    # Create plan
    if terraform plan -no-color -out="$plan_file"; then
        log "INFO" "Terraform plan created successfully: $plan_file"
        return 0
    else
        log "ERROR" "Terraform plan failed"
        return 1
    fi
}

# Function to apply Terraform deployment
apply_deployment() {
    local module_path="$1"
    local plan_file="$2"
    
    log "INFO" "Applying Terraform deployment..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would apply Terraform deployment"
        return 0
    fi
    
    cd "$module_path"
    
    # Apply plan
    if terraform apply -no-color -auto-approve "$plan_file"; then
        log "INFO" "Terraform deployment applied successfully"
        return 0
    else
        log "ERROR" "Terraform deployment failed"
        return 1
    fi
}

# Function to destroy Terraform deployment
destroy_deployment() {
    local module_path="$1"
    
    log "INFO" "Destroying Terraform deployment..."
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would destroy Terraform deployment"
        return 0
    fi
    
    cd "$module_path"
    
    # Confirm destruction
    if [ -t 0 ]; then  # If running interactively
        if ! whiptail --title "Confirm Destruction" --yesno "Are you sure you want to destroy the Terraform deployment?\n\nThis action cannot be undone!" 10 60; then
            log "INFO" "Destruction cancelled by user"
            return 0
        fi
    fi
    
    # Destroy deployment
    if terraform destroy -no-color -auto-approve; then
        log "INFO" "Terraform deployment destroyed successfully"
        return 0
    else
        log "ERROR" "Terraform destruction failed"
        return 1
    fi
}

# Function to show Terraform status
show_status() {
    local module_path="$1"
    
    log "INFO" "Showing Terraform status..."
    
    if [ ! -d "$module_path" ]; then
        log "ERROR" "Module path does not exist: $module_path"
        return 1
    fi
    
    cd "$module_path"
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        log "INFO" "Terraform not initialized in this directory"
        return 1
    fi
    
    # Show state
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would show Terraform state"
    else
        terraform show -no-color
    fi
    
    return 0
}

# Function to backup Terraform state
backup_state() {
    local module_path="$1"
    
    log "INFO" "Backing up Terraform state..."
    
    if [ ! -f "$module_path/terraform.tfstate" ]; then
        log "WARN" "No Terraform state file found"
        return 1
    fi
    
    if [ "$TEST_MODE" ]; then
        log "INFO" "[TEST MODE] Would backup Terraform state"
        return 0
    fi
    
    # Create backup directory
    local backup_dir="$TERRAFORM_STATE_DIR/backups"
    mkdir -p "$backup_dir"
    
    # Create backup with timestamp
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_dir/terraform_state_${timestamp}.tfstate"
    
    cp "$module_path/terraform.tfstate" "$backup_file"
    
    log "INFO" "State backed up to: $backup_file"
    return 0
}

# Main function to display menu and handle user selection
main() {
    log "INFO" "Starting Terraform Module v${VERSION}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check/install dependencies
    if ! command -v jq >/dev/null 2>&1; then
        log "INFO" "Installing jq..."
        apt-get update && apt-get install -y jq
    fi
    
    # Check/install Terraform
    if ! check_terraform; then
        if [ -t 0 ]; then  # If running interactively
            if whiptail --title "Install Terraform" --yesno "Terraform is not installed. Would you like to install it now?" 10 60; then
                install_terraform
            else
                log "ERROR" "Terraform is required but not installed"
                exit 1
            fi
        else
            log "INFO" "Installing Terraform automatically..."
            install_terraform
        fi
    fi
    
    # Main menu loop
    while true; do
        if [ -t 0 ]; then  # If running interactively
            local choice
            choice=$(whiptail --title "Terraform Module v${VERSION}" \
                --menu "Choose an action:" 20 70 10 \
                "1" "Discover Terraform Modules" \
                "2" "Deploy Infrastructure" \
                "3" "Plan Deployment" \
                "4" "Show Status" \
                "5" "Backup State" \
                "6" "Destroy Deployment" \
                "7" "Validate Configuration" \
                "8" "Exit" \
                3>&1 1>&2 2>&3)
            
            case $choice in
                1)
                    log "INFO" "Discovering Terraform modules..."
                    if modules=$(discover_modules); then
                        if [ -n "$modules" ]; then
                            whiptail --title "Available Modules" --msgbox "Found modules:\n\n$modules" 20 60
                        else
                            whiptail --title "No Modules" --msgbox "No Terraform modules found." 10 60
                        fi
                    else
                        whiptail --title "No Modules" --msgbox "No Terraform modules found." 10 60
                    fi
                    ;;
                2)
                    # Deploy infrastructure workflow
                    log "INFO" "Starting infrastructure deployment workflow..."
                    
                    # Get available modules
                    if ! modules=$(discover_modules); then
                        whiptail --title "Error" --msgbox "No Terraform modules found." 10 60
                        continue
                    fi
                    
                    # Convert modules to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r module; do
                        menu_items+=("$i" "$module")
                        ((i++))
                    done <<< "$modules"
                    
                    # Let user select module
                    local selected_index
                    selected_index=$(whiptail --title "Select Module" \
                        --menu "Choose a module to deploy:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_module
                        selected_module=$(echo "$modules" | sed -n "${selected_index}p")
                        
                        # Find module path
                        local module_path=""
                        if [ -d "$SCRIPT_DIR/../terraform/$selected_module" ]; then
                            module_path="$SCRIPT_DIR/../terraform/$selected_module"
                        elif [ -d "$TERRAFORM_MODULES_DIR/$selected_module" ]; then
                            module_path="$TERRAFORM_MODULES_DIR/$selected_module"
                        fi
                        
                        if [ -n "$module_path" ]; then
                            log "INFO" "Selected module: $selected_module at $module_path"
                            
                            # Collect variables
                            collect_variables "$module_path"
                            
                            # Validate configuration
                            if validate_config "$module_path"; then
                                # Create plan
                                local plan_file="$module_path/terraform.plan"
                                if plan_deployment "$module_path" "$plan_file"; then
                                    # Apply deployment
                                    if apply_deployment "$module_path" "$plan_file"; then
                                        whiptail --title "Success" --msgbox "Infrastructure deployed successfully!" 10 60
                                        # Backup state after successful deployment
                                        backup_state "$module_path"
                                    else
                                        whiptail --title "Error" --msgbox "Deployment failed. Check logs for details." 10 60
                                    fi
                                else
                                    whiptail --title "Error" --msgbox "Planning failed. Check logs for details." 10 60
                                fi
                            else
                                whiptail --title "Error" --msgbox "Configuration validation failed. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Module path not found." 10 60
                        fi
                    fi
                    ;;
                3)
                    # Plan deployment only
                    log "INFO" "Creating deployment plan..."
                    
                    # Get available modules
                    if ! modules=$(discover_modules); then
                        whiptail --title "Error" --msgbox "No Terraform modules found." 10 60
                        continue
                    fi
                    
                    # Convert modules to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r module; do
                        menu_items+=("$i" "$module")
                        ((i++))
                    done <<< "$modules"
                    
                    # Let user select module
                    local selected_index
                    selected_index=$(whiptail --title "Select Module for Planning" \
                        --menu "Choose a module to plan:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_module
                        selected_module=$(echo "$modules" | sed -n "${selected_index}p")
                        
                        # Find module path
                        local module_path=""
                        if [ -d "$SCRIPT_DIR/../terraform/$selected_module" ]; then
                            module_path="$SCRIPT_DIR/../terraform/$selected_module"
                        elif [ -d "$TERRAFORM_MODULES_DIR/$selected_module" ]; then
                            module_path="$TERRAFORM_MODULES_DIR/$selected_module"
                        fi
                        
                        if [ -n "$module_path" ]; then
                            log "INFO" "Selected module for planning: $selected_module at $module_path"
                            
                            # Collect variables if needed
                            collect_variables "$module_path"
                            
                            # Validate configuration
                            if validate_config "$module_path"; then
                                # Create plan only
                                local plan_file="$module_path/terraform.plan"
                                if plan_deployment "$module_path" "$plan_file"; then
                                    whiptail --title "Plan Created" --msgbox "Terraform plan created successfully!\n\nPlan file: $plan_file\n\nYou can review the plan and apply it later using the 'Deploy Infrastructure' option." 15 80
                                else
                                    whiptail --title "Error" --msgbox "Planning failed. Check logs for details." 10 60
                                fi
                            else
                                whiptail --title "Error" --msgbox "Configuration validation failed. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Module path not found." 10 60
                        fi
                    fi
                    ;;
                4)
                    # Show status
                    log "INFO" "Showing Terraform status..."
                    
                    # Get available modules
                    if ! modules=$(discover_modules); then
                        whiptail --title "Error" --msgbox "No Terraform modules found." 10 60
                        continue
                    fi
                    
                    # Convert modules to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r module; do
                        menu_items+=("$i" "$module")
                        ((i++))
                    done <<< "$modules"
                    
                    # Let user select module
                    local selected_index
                    selected_index=$(whiptail --title "Select Module for Status" \
                        --menu "Choose a module to check status:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_module
                        selected_module=$(echo "$modules" | sed -n "${selected_index}p")
                        
                        # Find module path
                        local module_path=""
                        if [ -d "$SCRIPT_DIR/../terraform/$selected_module" ]; then
                            module_path="$SCRIPT_DIR/../terraform/$selected_module"
                        elif [ -d "$TERRAFORM_MODULES_DIR/$selected_module" ]; then
                            module_path="$TERRAFORM_MODULES_DIR/$selected_module"
                        fi
                        
                        if [ -n "$module_path" ]; then
                            log "INFO" "Showing status for module: $selected_module"
                            
                            # Show status in a scrollable text box
                            local status_output
                            if [ "$TEST_MODE" ]; then
                                status_output="[TEST MODE] Would show Terraform state for module: $selected_module\n\nModule path: $module_path\nState file: $module_path/terraform.tfstate"
                            else
                                status_output=$(show_status "$module_path" 2>&1 || echo "No state information available or module not initialized.")
                            fi
                            
                            # Display status in a scrollable dialog
                            whiptail --title "Terraform Status - $selected_module" --scrolltext --msgbox "$status_output" 25 100
                        else
                            whiptail --title "Error" --msgbox "Module path not found." 10 60
                        fi
                    fi
                    ;;
                5)
                    # Backup state
                    log "INFO" "Backing up Terraform state..."
                    
                    # Get available modules
                    if ! modules=$(discover_modules); then
                        whiptail --title "Error" --msgbox "No Terraform modules found." 10 60
                        continue
                    fi
                    
                    # Convert modules to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r module; do
                        menu_items+=("$i" "$module")
                        ((i++))
                    done <<< "$modules"
                    
                    # Let user select module
                    local selected_index
                    selected_index=$(whiptail --title "Select Module for Backup" \
                        --menu "Choose a module to backup state:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_module
                        selected_module=$(echo "$modules" | sed -n "${selected_index}p")
                        
                        # Find module path
                        local module_path=""
                        if [ -d "$SCRIPT_DIR/../terraform/$selected_module" ]; then
                            module_path="$SCRIPT_DIR/../terraform/$selected_module"
                        elif [ -d "$TERRAFORM_MODULES_DIR/$selected_module" ]; then
                            module_path="$TERRAFORM_MODULES_DIR/$selected_module"
                        fi
                        
                        if [ -n "$module_path" ]; then
                            log "INFO" "Backing up state for module: $selected_module"
                            
                            if backup_state "$module_path"; then
                                whiptail --title "Backup Success" --msgbox "Terraform state backed up successfully for module: $selected_module\n\nBackup location: $TERRAFORM_STATE_DIR/backups/" 12 70
                            else
                                whiptail --title "Backup Failed" --msgbox "Failed to backup Terraform state. Check logs for details." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Module path not found." 10 60
                        fi
                    fi
                    ;;
                6)
                    # Destroy deployment
                    log "INFO" "Destroying deployment..."
                    
                    # Get available modules
                    if ! modules=$(discover_modules); then
                        whiptail --title "Error" --msgbox "No Terraform modules found." 10 60
                        continue
                    fi
                    
                    # Convert modules to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r module; do
                        menu_items+=("$i" "$module")
                        ((i++))
                    done <<< "$modules"
                    
                    # Let user select module
                    local selected_index
                    selected_index=$(whiptail --title "Select Module for Destruction" \
                        --menu "Choose a module to destroy:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_module
                        selected_module=$(echo "$modules" | sed -n "${selected_index}p")
                        
                        # Find module path
                        local module_path=""
                        if [ -d "$SCRIPT_DIR/../terraform/$selected_module" ]; then
                            module_path="$SCRIPT_DIR/../terraform/$selected_module"
                        elif [ -d "$TERRAFORM_MODULES_DIR/$selected_module" ]; then
                            module_path="$TERRAFORM_MODULES_DIR/$selected_module"
                        fi
                        
                        if [ -n "$module_path" ]; then
                            log "INFO" "Selected module for destruction: $selected_module"
                            
                            # Additional confirmation for destruction
                            if whiptail --title "DANGER - Confirm Destruction" --yesno "WARNING: You are about to DESTROY all infrastructure for module:\n\n$selected_module\n\nThis action is IRREVERSIBLE and will delete all resources!\n\nAre you absolutely sure you want to proceed?" 15 80; then
                                # Backup state before destruction
                                log "INFO" "Creating backup before destruction..."
                                backup_state "$module_path"
                                
                                # Destroy deployment
                                if destroy_deployment "$module_path"; then
                                    whiptail --title "Destruction Complete" --msgbox "Infrastructure destroyed successfully for module: $selected_module\n\nAll resources have been removed." 12 70
                                else
                                    whiptail --title "Destruction Failed" --msgbox "Failed to destroy infrastructure. Check logs for details.\n\nSome resources may still exist and require manual cleanup." 12 70
                                fi
                            else
                                log "INFO" "Destruction cancelled by user"
                                whiptail --title "Cancelled" --msgbox "Destruction cancelled. No changes were made." 10 60
                            fi
                        else
                            whiptail --title "Error" --msgbox "Module path not found." 10 60
                        fi
                    fi
                    ;;
                7)
                    # Validate configuration
                    log "INFO" "Validating configuration..."
                    
                    # Get available modules
                    if ! modules=$(discover_modules); then
                        whiptail --title "Error" --msgbox "No Terraform modules found." 10 60
                        continue
                    fi
                    
                    # Convert modules to menu format
                    local menu_items=()
                    local i=1
                    while IFS= read -r module; do
                        menu_items+=("$i" "$module")
                        ((i++))
                    done <<< "$modules"
                    
                    # Let user select module
                    local selected_index
                    selected_index=$(whiptail --title "Select Module for Validation" \
                        --menu "Choose a module to validate:" 20 70 10 \
                        "${menu_items[@]}" \
                        3>&1 1>&2 2>&3)
                    
                    if [ $? -eq 0 ]; then
                        local selected_module
                        selected_module=$(echo "$modules" | sed -n "${selected_index}p")
                        
                        # Find module path
                        local module_path=""
                        if [ -d "$SCRIPT_DIR/../terraform/$selected_module" ]; then
                            module_path="$SCRIPT_DIR/../terraform/$selected_module"
                        elif [ -d "$TERRAFORM_MODULES_DIR/$selected_module" ]; then
                            module_path="$TERRAFORM_MODULES_DIR/$selected_module"
                        fi
                        
                        if [ -n "$module_path" ]; then
                            log "INFO" "Validating configuration for module: $selected_module"
                            
                            if validate_config "$module_path"; then
                                whiptail --title "Validation Success" --msgbox "Terraform configuration is valid for module: $selected_module\n\nAll syntax and configuration checks passed." 12 70
                            else
                                whiptail --title "Validation Failed" --msgbox "Terraform configuration validation failed for module: $selected_module\n\nCheck logs for detailed error information." 12 70
                            fi
                        else
                            whiptail --title "Error" --msgbox "Module path not found." 10 60
                        fi
                    fi
                    ;;
                8)
                    log "INFO" "Exiting Terraform module"
                    exit 0
                    ;;
                *)
                    log "ERROR" "Invalid selection"
                    ;;
            esac
        else
            # Non-interactive mode - show available modules and exit
            log "INFO" "Running in non-interactive mode"
            discover_modules
            exit 0
        fi
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
