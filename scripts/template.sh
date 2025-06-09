#!/bin/bash
# Proxmox Template Creator - Template Module

set -e

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Source the centralized logging library
source "$SCRIPT_DIR/lib/logging.sh"

# Initialize logging system
init_logging "template"

# Set up error trap using the centralized error handler
trap 'handle_error $? $LINENO' ERR

# --- Distribution Configuration ---
# Format: "distro_id|Display Name|cloud-init-support|url_template"
DISTRO_LIST=(
    "ubuntu|Ubuntu Server|yes|https://cloud-images.ubuntu.com/releases/%version%/release/ubuntu-%version%-server-cloudimg-amd64.img"
    "debian|Debian|yes|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    "centos|CentOS|yes|https://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-%version%.x86_64.qcow2"
    "rocky|Rocky Linux|yes|https://dl.rockylinux.org/pub/rocky/%version%/images/Rocky-%version%-GenericCloud.x86_64.qcow2"
    "alpine|Alpine Linux|no|https://dl-cdn.alpinelinux.org/alpine/v%version%/releases/x86_64/alpine-virt-%version%.0-x86_64.iso"
    "fedora|Fedora|yes|https://download.fedoraproject.org/pub/fedora/linux/releases/%version%/Cloud/x86_64/images/Fedora-Cloud-Base-%version%-1.2.x86_64.qcow2"
    "opensuse|openSUSE|yes|https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.%version%/images/openSUSE-Leap-15.%version%-OpenStack.x86_64.qcow2"
    "arch|Arch Linux|no|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
)

# Configuration directory for template configs
TEMPLATE_CONFIG_DIR="/etc/homelab/templates"
mkdir -p "$TEMPLATE_CONFIG_DIR"

# Handle CLI arguments
if [ "$1" = "--list-distros" ]; then
    echo "Available distributions:"
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        echo "- $val: $desc (cloud-init: $ci)"
    done
    exit 0
fi

if [ "$1" = "--list-versions" ]; then
    distro="$2"
    case "$distro" in
        ubuntu)
            echo "Available Ubuntu versions: 22.04 (Jammy Jellyfish), 20.04 (Focal Fossa), 18.04 (Bionic Beaver)"
            ;;
        debian)
            echo "Available Debian versions: 12 (Bookworm), 11 (Bullseye), 10 (Buster)"
            ;;
        centos)
            echo "Available CentOS versions: 9 (Stream 9), 8 (Stream 8)"
            ;;
        rocky)
            echo "Available Rocky Linux versions: 9 (Rocky 9), 8 (Rocky 8)"
            ;;
        alpine)
            echo "Available Alpine versions: 3.19, 3.18, 3.17"
            ;;
        fedora)
            echo "Available Fedora versions: 39, 38, 37"
            ;;
        *)
            echo "Unknown distribution: $distro"
            exit 1
            ;;
    esac
    exit 0
fi

if [ "$1" = "--test" ]; then
    # Test mode - just display UI without executing VM creation
    TEST_MODE=1
fi

if [ "$1" = "--create" ]; then
    # Direct create mode - skip menu
    CREATE_MODE=1
fi

# Helper function to get distro URL template
get_distro_url_template() {
    local distro_id="$1"
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        if [ "$val" = "$distro_id" ]; then
            echo "$url"
            return 0
        fi
    done
    echo ""
    return 1
}

# Helper function to check if distro supports cloud-init
supports_cloudinit() {
    local distro_id="$1"
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        if [ "$val" = "$distro_id" ]; then
            if [ "$ci" = "yes" ]; then
                return 0
            else
                return 1
            fi
        fi
    done
    return 1
}

# Function to get predefined script templates
get_script_template() {
    local template_name="$1"
    
    case "$template_name" in
        "docker-setup")
            cat << 'EOF'
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
usermod -aG docker $(whoami)

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
EOF
            ;;
        "web-server")
            cat << 'EOF'
# Install and configure Nginx
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx

# Create basic index page
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome</title>
</head>
<body>
    <h1>Server is ready!</h1>
    <p>This server was configured automatically with cloud-init.</p>
</body>
</html>
HTMLEOF

# Configure firewall
ufw --force enable
ufw allow ssh
ufw allow 'Nginx Full'
EOF
            ;;
        "security-hardening")
            cat << 'EOF'
# Basic security hardening
apt-get update && apt-get install -y fail2ban ufw

# Configure firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Disable root login and configure SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Set up automatic security updates
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
systemctl enable unattended-upgrades
EOF
            ;;
        "monitoring-agent")
            cat << 'EOF'
# Install Node Exporter for Prometheus monitoring
useradd --no-create-home --shell /bin/false node_exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*linux-amd64.tar.gz
tar -xzf node_exporter-*linux-amd64.tar.gz
cp node_exporter-*linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Create systemd service
cat > /etc/systemd/system/node_exporter.service << 'SERVICEEOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter
EOF
            ;;
        "dev-tools")
            cat << 'EOF'
# Install development tools
apt-get update
apt-get install -y git vim neovim tmux htop tree curl wget build-essential

# Install modern development tools
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Install Python development tools
apt-get install -y python3-pip python3-venv python3-dev

# Configure git (placeholder - users should customize)
# git config --global user.name "Your Name"
# git config --global user.email "your.email@example.com"
EOF
            ;;
        "auto-updates")
            cat << 'EOF'
# Configure automatic updates
apt-get update
apt-get install -y unattended-upgrades

# Configure automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'CONFEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONFEOF

# Configure what packages to update automatically
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'CONFEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONFEOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades
EOF
            ;;
        "custom-user")
            cat << 'EOF'
# Create additional system user
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy

# Set up SSH directory for deploy user
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chown deploy:deploy /home/deploy/.ssh

# Example: Copy authorized_keys (customize as needed)
# cp /home/*/. ssh/authorized_keys /home/deploy/.ssh/
# chown deploy:deploy /home/deploy/.ssh/authorized_keys
# chmod 600 /home/deploy/.ssh/authorized_keys
EOF
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
    return 0
}

# Function to validate template configuration
validate_template_config() {
    local errors=()
    
    # Validate template name
    if [ -z "$template_name" ]; then
        errors+=("Template name is required")
    elif [[ ! "$template_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        errors+=("Template name contains invalid characters (only alphanumeric, underscore, and dash allowed)")
    fi
    
    # Validate distro selection
    if [ -z "$distro" ]; then
        errors+=("Distribution selection is required")
    fi
    
    # Validate hardware specifications
    if ! [[ "$cpu" =~ ^[0-9]+$ ]] || [ "$cpu" -lt 1 ] || [ "$cpu" -gt 128 ]; then
        errors+=("CPU cores must be a number between 1 and 128")
    fi
    
    if ! [[ "$ram" =~ ^[0-9]+$ ]] || [ "$ram" -lt 512 ] || [ "$ram" -gt 131072 ]; then
        errors+=("RAM must be a number between 512 MB and 128 GB")
    fi
    
    if ! [[ "$storage" =~ ^[0-9]+$ ]] || [ "$storage" -lt 8 ] || [ "$storage" -gt 2048 ]; then
        errors+=("Storage must be a number between 8 GB and 2048 GB")
    fi
    
    # Validate cloud-init configuration if enabled
    if [ "$use_cloudinit" = "yes" ]; then
        if [ -z "$ci_user" ]; then
            errors+=("Cloud-init user is required when cloud-init is enabled")
        elif [[ ! "$ci_user" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            errors+=("Cloud-init username must start with a letter and contain only lowercase letters, numbers, underscore, and dash")
        fi
        
        # Validate static IP configuration
        if [ "$ci_network" != "dhcp" ] && [[ "$ci_network" == *"ip="* ]]; then
            local ip_part
            ip_part=$(echo "$ci_network" | grep -o 'ip=[^,]*' | cut -d'=' -f2)
            if [ -n "$ip_part" ] && ! [[ "$ip_part" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                errors+=("Invalid IP address format (expected CIDR notation like 192.168.1.100/24)")
            fi
        fi
    fi
    
    # Check if any errors were found
    if [ ${#errors[@]} -gt 0 ]; then
        local error_msg="Configuration errors found:\n\n"
        for error in "${errors[@]}"; do
            error_msg+="• $error\n"
        done
        
        whiptail --title "Configuration Errors" --msgbox "$error_msg\nPlease fix these errors and try again." 20 70
        return 1
    fi
    
    return 0
}

# Function to list all templates in Proxmox
list_templates() {
    log_info "Listing Proxmox templates..."
    
    # Get list of VMs that are templates
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid)|\(.name)|\(.status)|\(.maxmem//0)|\(.cpus//0)|\(.tags//"")"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Templates" --msgbox "No templates found in Proxmox." 10 60
        return 0
    fi
    
    # Format templates for display
    local template_list=""
    local count=0
    while IFS='|' read -r vmid name status memory cpus tags; do
        if [ -n "$vmid" ]; then
            memory_gb=$(( memory / 1024 / 1024 ))
            template_list+="$vmid: $name (${memory_gb}GB RAM, ${cpus} CPU)\n"
            ((count++))
        fi
    done <<< "$templates"
    
    if [ $count -eq 0 ]; then
        whiptail --title "Templates" --msgbox "No templates found in Proxmox." 10 60
    else
        whiptail --title "Proxmox Templates ($count found)" --msgbox "$template_list" 20 80
    fi
}

# Function to manage existing templates
manage_templates() {
    while true; do
        local choice
        choice=$(whiptail --title "Template Management" --menu "Select an option:" 15 70 6 \
            "1" "List all templates" \
            "2" "View template details" \
            "3" "Delete template" \
            "4" "Clone template" \
            "5" "Template configuration" \
            "6" "Back to main menu" 3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                list_templates
                ;;
            2)
                view_template_details
                ;;
            3)
                delete_template
                ;;
            4)
                clone_template
                ;;
            5)
                manage_template_config
                ;;
            6|"")
                break
                ;;
        esac
    done
}

# Function to view template details
view_template_details() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi
    
    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"
    
    local selected_vmid
    selected_vmid=$(whiptail --title "Select Template" --menu "Choose template to view:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_vmid" ]; then
        # Get detailed template information
        local template_info
        template_info=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json)
        
        local details=""
        details+="VMID: $selected_vmid\n"
        details+="Name: $(echo "$template_info" | jq -r '.name // "N/A"')\n"
        details+="Memory: $(echo "$template_info" | jq -r '.memory // "N/A"') MB\n"
        details+="CPU Cores: $(echo "$template_info" | jq -r '.cores // "N/A"')\n"
        details+="OS Type: $(echo "$template_info" | jq -r '.ostype // "N/A"')\n"
        details+="Description: $(echo "$template_info" | jq -r '.description // "N/A"')\n"
        details+="Tags: $(echo "$template_info" | jq -r '.tags // "None"')\n"
        details+="Boot Order: $(echo "$template_info" | jq -r '.boot // "N/A"')\n"
        
        whiptail --title "Template Details - VMID $selected_vmid" --msgbox "$details" 20 80
    fi
}

# Function to delete template
delete_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi
    
    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"
    
    local selected_vmid
    selected_vmid=$(whiptail --title "Delete Template" --menu "Choose template to delete:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_vmid" ]; then
        local template_name
        template_name=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json | jq -r '.name')
        
        if whiptail --title "Confirm Deletion" --yesno "Are you sure you want to delete template:\n\nVMID: $selected_vmid\nName: $template_name\n\nThis action cannot be undone!" 12 70; then
            if qm destroy "$selected_vmid"; then
                log_info "Template $selected_vmid ($template_name) deleted successfully"
                whiptail --title "Success" --msgbox "Template $selected_vmid ($template_name) deleted successfully!" 10 60
            else
                log_error "Failed to delete template $selected_vmid"
                whiptail --title "Error" --msgbox "Failed to delete template $selected_vmid. Check logs for details." 10 60
            fi
        fi
    fi
}

# Function to clone template
clone_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi
    
    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"
    
    local selected_vmid
    selected_vmid=$(whiptail --title "Clone Template" --menu "Choose template to clone:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_vmid" ]; then
        local new_name
        new_name=$(whiptail --title "Clone Template" --inputbox "Enter name for the new template:" 10 60 "template-clone-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
        
        if [ -n "$new_name" ]; then
            local new_vmid
            new_vmid=$(pvesh get /cluster/nextid)
            
            if qm clone "$selected_vmid" "$new_vmid" --name "$new_name"; then
                if qm template "$new_vmid"; then
                    log_info "Template cloned successfully: $selected_vmid -> $new_vmid ($new_name)"
                    whiptail --title "Success" --msgbox "Template cloned successfully!\n\nOriginal: $selected_vmid\nNew: $new_vmid ($new_name)" 12 60
                else
                    log_error "Failed to convert cloned VM to template"
                    whiptail --title "Error" --msgbox "VM cloned but failed to convert to template. Check VMID $new_vmid manually." 10 60
                fi
            else
                log_error "Failed to clone template $selected_vmid"
                whiptail --title "Error" --msgbox "Failed to clone template $selected_vmid. Check logs for details." 10 60
            fi
        fi
    fi
}

# Function to manage template configuration files
manage_template_config() {
    while true; do
        local choice
        choice=$(whiptail --title "Template Configuration" --menu "Select an option:" 15 70 5 \
            "1" "Export template configuration" \
            "2" "Import template configuration" \
            "3" "List saved configurations" \
            "4" "Delete saved configuration" \
            "5" "Back to template management" 3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                export_template_config
                ;;
            2)
                import_template_config
                ;;
            3)
                list_saved_configs
                ;;
            4)
                delete_saved_config
                ;;
            5|"")
                break
                ;;
        esac
    done
}

# Function to export template configuration
export_template_config() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found." 10 60
        return 1
    fi
    
    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"
    
    local selected_vmid
    selected_vmid=$(whiptail --title "Export Configuration" --menu "Choose template to export:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_vmid" ]; then
        local config_name
        config_name=$(whiptail --title "Export Configuration" --inputbox "Enter name for the configuration file:" 10 60 "template-config-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
        
        if [ -n "$config_name" ]; then
            local config_file="$TEMPLATE_CONFIG_DIR/${config_name}.json"
            local template_config
            template_config=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json)
            
            # Create enhanced configuration with metadata
            local enhanced_config
            enhanced_config=$(cat << EOF
{
  "metadata": {
    "exported_date": "$(date -Iseconds)",
    "source_vmid": $selected_vmid,
    "config_name": "$config_name",
    "version": "1.0"
  },
  "proxmox_config": $template_config
}
EOF
)
            
            if echo "$enhanced_config" | jq '.' > "$config_file"; then
                log_info "Template configuration exported to $config_file"
                whiptail --title "Success" --msgbox "Template configuration exported successfully!\n\nFile: $config_file" 10 70
            else
                log_error "Failed to export template configuration"
                whiptail --title "Error" --msgbox "Failed to export template configuration. Check permissions." 10 60
            fi
        fi
    fi
}

# Function to import template configuration
import_template_config() {
    # List available configuration files
    local config_files=()
    while IFS= read -r -d '' file; do
        local basename_file
        basename_file=$(basename "$file" .json)
        config_files+=("$basename_file" "$(date -r "$file" '+%Y-%m-%d %H:%M')")
    done < <(find "$TEMPLATE_CONFIG_DIR" -name "*.json" -print0 2>/dev/null)
    
    if [ ${#config_files[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No saved configuration files found in $TEMPLATE_CONFIG_DIR." 10 70
        return 1
    fi
    
    local selected_config
    selected_config=$(whiptail --title "Import Configuration" --menu "Choose configuration to import:" 15 80 10 "${config_files[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_config" ]; then
        local config_file="$TEMPLATE_CONFIG_DIR/${selected_config}.json"
        local new_name
        new_name=$(whiptail --title "Import Configuration" --inputbox "Enter name for the new template:" 10 60 "imported-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
        
        if [ -n "$new_name" ]; then
            # Get next available VMID
            local new_vmid
            new_vmid=$(pvesh get /cluster/nextid)
            
            # Extract configuration
            local config_data
            if ! config_data=$(jq -r '.proxmox_config' "$config_file"); then
                whiptail --title "Error" --msgbox "Failed to parse configuration file. File may be corrupted." 10 60
                return 1
            fi
            
            whiptail --title "Import Progress" --infobox "Creating VM from imported configuration...\nThis may take a few moments." 8 60
            
            # Create basic VM first
            local memory cores
            memory=$(echo "$config_data" | jq -r '.memory // 2048')
            cores=$(echo "$config_data" | jq -r '.cores // 2')
            
            if qm create "$new_vmid" --name "$new_name" --memory "$memory" --cores "$cores"; then
                # Apply additional configuration settings
                local ostype
                ostype=$(echo "$config_data" | jq -r '.ostype // "l26"')
                qm set "$new_vmid" --ostype "$ostype"
                
                # Set description
                local description="Imported from configuration: $selected_config\\nImported: $(date '+%Y-%m-%d %H:%M:%S')"
                qm set "$new_vmid" --description "$description"
                
                # Convert to template
                qm template "$new_vmid"
                
                log_info "Template imported successfully: VMID $new_vmid ($new_name)"
                whiptail --title "Success" --msgbox "Template imported successfully!\n\nVMID: $new_vmid\nName: $new_name\n\nNote: Disk images need to be restored separately." 12 70
            else
                log_error "Failed to create VM from imported configuration"
                whiptail --title "Error" --msgbox "Failed to create VM from imported configuration. Check logs for details." 10 60
            fi
        fi
    fi
}

# Function to list saved configuration files
list_saved_configs() {
    if [ ! -d "$TEMPLATE_CONFIG_DIR" ] || [ -z "$(ls -A "$TEMPLATE_CONFIG_DIR"/*.json 2>/dev/null)" ]; then
        whiptail --title "Saved Configurations" --msgbox "No saved configuration files found." 10 60
        return 0
    fi
    
    local config_list=""
    local count=0
    for file in "$TEMPLATE_CONFIG_DIR"/*.json; do
        if [ -f "$file" ]; then
            local basename_file
            basename_file=$(basename "$file" .json)
            local file_date
            file_date=$(date -r "$file" '+%Y-%m-%d %H:%M')
            local file_size
            file_size=$(du -h "$file" | cut -f1)
            config_list+="$basename_file (${file_size}, $file_date)\n"
            ((count++))
        fi
    done
    
    whiptail --title "Saved Configurations ($count found)" --msgbox "$config_list" 20 80
}

# Function to delete saved configuration
delete_saved_config() {
    # List available configuration files
    local config_files=()
    while IFS= read -r -d '' file; do
        local basename_file
        basename_file=$(basename "$file" .json)
        config_files+=("$basename_file" "$(date -r "$file" '+%Y-%m-%d %H:%M')")
    done < <(find "$TEMPLATE_CONFIG_DIR" -name "*.json" -print0 2>/dev/null)
    
    if [ ${#config_files[@]} -eq 0 ]; then
        whiptail --title "Error" --msgbox "No saved configuration files found." 10 60
        return 1
    fi
    
    local selected_config
    selected_config=$(whiptail --title "Delete Configuration" --menu "Choose configuration to delete:" 15 80 10 "${config_files[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_config" ]; then
        if whiptail --title "Confirm Deletion" --yesno "Are you sure you want to delete configuration:\n\n$selected_config\n\nThis action cannot be undone!" 10 60; then
            local config_file="$TEMPLATE_CONFIG_DIR/${selected_config}.json"
            if rm -f "$config_file"; then
                log_info "Configuration file deleted: $config_file"
                whiptail --title "Success" --msgbox "Configuration file deleted successfully!" 10 60
            else
                log_error "Failed to delete configuration file: $config_file"
                whiptail --title "Error" --msgbox "Failed to delete configuration file. Check permissions." 10 60
            fi
        fi
    fi
}

# Function to validate existing template
validate_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found to validate." 10 60
        return 1
    fi
    
    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"
    
    local selected_vmid
    selected_vmid=$(whiptail --title "Validate Template" --menu "Choose template to validate:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_vmid" ]; then
        whiptail --title "Validating" --infobox "Validating template $selected_vmid...\nPlease wait..." 8 50
        
        local validation_results=""
        local error_count=0
        local warning_count=0
        
        # Get template configuration
        local template_config
        template_config=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/config" --output-format=json)
        
        # Validate template is actually a template
        local is_template
        is_template=$(pvesh get "/nodes/localhost/qemu/$selected_vmid/status/current" --output-format=json | jq -r '.template // false')
        if [ "$is_template" != "true" ]; then
            validation_results+="❌ ERROR: VMID $selected_vmid is not marked as a template\n"
            ((error_count++))
        else
            validation_results+="✅ Template status: Valid\n"
        fi
        
        # Validate memory configuration
        local memory
        memory=$(echo "$template_config" | jq -r '.memory // 0')
        if [ "$memory" -lt 512 ]; then
            validation_results+="❌ ERROR: Memory too low ($memory MB, minimum 512 MB)\n"
            ((error_count++))
        elif [ "$memory" -lt 1024 ]; then
            validation_results+="⚠️  WARNING: Low memory allocation ($memory MB)\n"
            ((warning_count++))
        else
            validation_results+="✅ Memory: $memory MB (OK)\n"
        fi
        
        # Validate CPU configuration
        local cores
        cores=$(echo "$template_config" | jq -r '.cores // 0')
        if [ "$cores" -lt 1 ]; then
            validation_results+="❌ ERROR: No CPU cores assigned\n"
            ((error_count++))
        else
            validation_results+="✅ CPU Cores: $cores (OK)\n"
        fi
        
        # Check for storage configuration
        local has_storage=false
        for key in $(echo "$template_config" | jq -r 'keys[]'); do
            if [[ "$key" =~ ^(scsi|ide|sata|virtio)[0-9]+$ ]]; then
                has_storage=true
                validation_results+="✅ Storage: Found $key\n"
                break
            fi
        done
        if [ "$has_storage" = false ]; then
            validation_results+="❌ ERROR: No storage devices found\n"
            ((error_count++))
        fi
        
        # Check network configuration
        local has_network=false
        for key in $(echo "$template_config" | jq -r 'keys[]'); do
            if [[ "$key" =~ ^net[0-9]+$ ]]; then
                has_network=true
                validation_results+="✅ Network: Found $key\n"
                break
            fi
        done
        if [ "$has_network" = false ]; then
            validation_results+="⚠️  WARNING: No network interfaces configured\n"
            ((warning_count++))
        fi
        
        # Check cloud-init configuration
        local has_cloudinit
        has_cloudinit=$(echo "$template_config" | jq -r 'has("ide2")')
        if [ "$has_cloudinit" = "true" ]; then
            validation_results+="✅ Cloud-init: Configured\n"
            
            # Check cloud-init user
            local ci_user
            ci_user=$(echo "$template_config" | jq -r '.ciuser // "none"')
            if [ "$ci_user" != "none" ]; then
                validation_results+="✅ Cloud-init user: $ci_user\n"
            else
                validation_results+="⚠️  WARNING: Cloud-init enabled but no user configured\n"
                ((warning_count++))
            fi
        else
            validation_results+="ℹ️  Info: Cloud-init not configured\n"
        fi
        
        # Summary
        local status_summary=""
        if [ $error_count -eq 0 ]; then
            if [ $warning_count -eq 0 ]; then
                status_summary="✅ VALIDATION PASSED: Template is ready for use"
            else
                status_summary="⚠️  VALIDATION PASSED WITH WARNINGS: $warning_count warning(s) found"
            fi
        else
            status_summary="❌ VALIDATION FAILED: $error_count error(s), $warning_count warning(s)"
        fi
        
        validation_results+="\\n$status_summary"
        
        whiptail --title "Template Validation Results" --msgbox "$validation_results" 25 80
        
        log_info "Template validation completed for VMID $selected_vmid: $error_count errors, $warning_count warnings"
    fi
}

# Function to test template functionality
test_template() {
    # Get template selection
    local templates
    templates=$(pvesh get /nodes/localhost/qemu --output-format=json | jq -r '.[] | select(.template==1) | "\(.vmid) \(.name)"')
    
    if [ -z "$templates" ]; then
        whiptail --title "Error" --msgbox "No templates found to test." 10 60
        return 1
    fi
    
    # Convert to whiptail menu format
    local template_array=()
    while read -r line; do
        if [ -n "$line" ]; then
            vmid=$(echo "$line" | cut -d' ' -f1)
            name=$(echo "$line" | cut -d' ' -f2-)
            template_array+=("$vmid" "$name")
        fi
    done <<< "$templates"
    
    local selected_vmid
    selected_vmid=$(whiptail --title "Test Template" --menu "Choose template to test:" 15 70 10 "${template_array[@]}" 3>&1 1>&2 2>&3)
    
    if [ -n "$selected_vmid" ]; then
        if whiptail --title "Template Testing" --yesno "This will create a temporary VM from the template for testing.\n\nThe VM will be created, started, tested, and then destroyed.\n\nProceed with testing?" 12 70; then
            whiptail --title "Testing" --infobox "Testing template $selected_vmid...\nCreating test VM..." 8 50
            
            # Get next available VMID for test VM
            local test_vmid
            test_vmid=$(pvesh get /cluster/nextid)
            
            # Clone template to test VM
            if qm clone "$selected_vmid" "$test_vmid" --name "test-$selected_vmid-$(date +%s)"; then
                log_info "Test VM $test_vmid created from template $selected_vmid"
                
                # Start the test VM
                whiptail --title "Testing" --infobox "Starting test VM $test_vmid...\nThis may take a moment..." 8 50
                
                if qm start "$test_vmid"; then
                    log_info "Test VM $test_vmid started successfully"
                    
                    # Wait a moment for VM to start
                    sleep 10
                    
                    # Check VM status
                    local vm_status
                    vm_status=$(qm status "$test_vmid")
                    
                    local test_results="✅ Template cloning: SUCCESS\n✅ VM creation: SUCCESS\n✅ VM startup: SUCCESS\n\nVM Status: $vm_status\n"
                    
                    # Test basic functionality
                    whiptail --title "Testing" --infobox "Testing VM functionality...\nChecking guest agent..." 8 50
                    sleep 5
                    
                    # Check if guest agent is running (if configured)
                    if qm guest ping "$test_vmid" 2>/dev/null; then
                        test_results+="✅ Guest agent: RESPONDING\n"
                    else
                        test_results+="⚠️  Guest agent: NOT RESPONDING (may need more time or not configured)\n"
                    fi
                    
                    # Stop the test VM
                    whiptail --title "Testing" --infobox "Stopping and cleaning up test VM..." 8 50
                    qm stop "$test_vmid"
                    sleep 5
                    
                    # Destroy test VM
                    qm destroy "$test_vmid"
                    
                    test_results+="\n✅ Test completed successfully\n✅ Test VM cleaned up"
                    
                    whiptail --title "Template Test Results" --msgbox "$test_results" 20 70
                    
                    log_info "Template test completed successfully for VMID $selected_vmid"
                else
                    log_error "Failed to start test VM $test_vmid"
                    qm destroy "$test_vmid"
                    whiptail --title "Test Failed" --msgbox "❌ Test failed: Could not start test VM\n\nTest VM has been cleaned up." 10 60
                fi
            else
                log_error "Failed to clone template $selected_vmid for testing"
                whiptail --title "Test Failed" --msgbox "❌ Test failed: Could not clone template for testing" 10 60
            fi
        fi
    fi
}

# Function to check required tools
check_dependencies() {
    local deps=(curl qemu-img whiptail jq)
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        whiptail --title "Error" --msgbox "Missing required tools: ${missing[*]}\n\nPlease install these dependencies and try again." 10 70
        exit 1
    fi
}

# Check for Proxmox environment
check_proxmox() {
    if ! command -v pvesh &> /dev/null; then
        log_error "This script must be run in a Proxmox VE environment."
        whiptail --title "Error" --msgbox "This script must be run in a Proxmox VE environment." 10 60
        exit 1
    fi
}

# Run pre-checks
if [ -z "$TEST_MODE" ]; then
    check_dependencies
    check_proxmox
fi

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Proxmox Template Creator" --menu "Select an option:" 20 70 8 \
            "1" "Create new template" \
            "2" "List all templates" \
            "3" "Manage existing templates" \
            "4" "Validate template" \
            "5" "Test template" \
            "6" "Template configuration management" \
            "7" "Help and documentation" \
            "8" "Exit" 3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                create_template
                ;;
            2)
                list_templates
                ;;
            3)
                manage_templates
                ;;
            4)
                validate_template
                ;;
            5)
                test_template
                ;;
            6)
                manage_template_config
                ;;
            7)
                show_help
                ;;
            8|"")
                log_info "Exiting template creator"
                exit 0
                ;;
        esac
    done
}

# Function to show help and documentation
show_help() {
    local help_text="Proxmox Template Creator Help\n\n"
    help_text+="FEATURES:\n"
    help_text+="• Create new VM templates from cloud images\n"
    help_text+="• Support for 50+ Linux distributions\n"
    help_text+="• Cloud-init integration with SSH key setup\n"
    help_text+="• Package pre-installation during template creation\n"
    help_text+="• Template validation and testing\n"
    help_text+="• Template management (clone, delete, export/import)\n"
    help_text+="• Configuration management and backup\n\n"
    help_text+="SUPPORTED DISTRIBUTIONS:\n"
    help_text+="• Ubuntu Server (18.04, 20.04, 22.04)\n"
    help_text+="• Debian (10, 11, 12)\n"
    help_text+="• CentOS Stream (8, 9)\n"
    help_text+="• Rocky Linux (8, 9)\n"
    help_text+="• Alpine Linux (3.17, 3.18, 3.19)\n"
    help_text+="• Fedora (37, 38, 39)\n"
    help_text+="• openSUSE Leap\n"
    help_text+="• Arch Linux\n\n"
    help_text+="COMMAND LINE OPTIONS:\n"
    help_text+="• --create: Direct template creation mode\n"
    help_text+="• --list-distros: List supported distributions\n"
    help_text+="• --list-versions: List versions for a distribution\n"
    help_text+="• --test: Test mode (UI only, no VM creation)\n\n"
    help_text+="For more information, check the documentation."
    
    whiptail --title "Help - Proxmox Template Creator" --msgbox "$help_text" 30 80
}

# Template creation function (wrapped from original logic)
create_template() {
    # --- Step 1: Template Name ---
template_name=$(whiptail --title "Template Name" --inputbox "Enter a name for the new VM template:" 10 60 "template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
template_result=$?
if [ $template_result -ne 0 ] || [ -z "$template_name" ]; then
    log_info "User cancelled or empty template name."
    exit 0
fi

# --- Step 2: Distribution Selection ---
distro_menu=()
for entry in "${DISTRO_LIST[@]}"; do
    IFS='|' read -r val desc ci url <<< "$entry"
    distro_menu+=("$val" "$desc")
done
distro=$(whiptail --title "Select Distribution" --menu "Choose a Linux distribution:" 20 60 10 "${distro_menu[@]}" 3>&1 1>&2 2>&3)
distro_result=$?
if [ $distro_result -ne 0 ] || [ -z "$distro" ]; then
    log_info "User cancelled at distro selection."
    exit 0
fi

# --- Step 3: Version Selection (example for Ubuntu/Debian) ---
case "$distro" in
    ubuntu)
        version=$(whiptail --title "Ubuntu Version" --menu "Select Ubuntu version:" 15 60 5 \
            "22.04" "Jammy Jellyfish (LTS)" \
            "20.04" "Focal Fossa (LTS)" \
            "18.04" "Bionic Beaver (LTS)" 3>&1 1>&2 2>&3)
        ;;
    debian)
        version=$(whiptail --title "Debian Version" --menu "Select Debian version:" 15 60 5 \
            "12" "Bookworm" \
            "11" "Bullseye" \
            "10" "Buster" 3>&1 1>&2 2>&3)
        ;;
    centos)
        version=$(whiptail --title "CentOS Version" --menu "Select CentOS version:" 15 60 5 \
            "9" "Stream 9" \
            "8" "Stream 8" 3>&1 1>&2 2>&3)
        ;;
    rocky)
        version=$(whiptail --title "Rocky Linux Version" --menu "Select Rocky Linux version:" 15 60 5 \
            "9" "Rocky 9" \
            "8" "Rocky 8" 3>&1 1>&2 2>&3)
        ;;
    alpine)
        version=$(whiptail --title "Alpine Version" --menu "Select Alpine version:" 15 60 5 \
            "3.19" "Alpine 3.19" \
            "3.18" "Alpine 3.18" \
            "3.17" "Alpine 3.17" 3>&1 1>&2 2>&3)
        ;;
    fedora)
        version=$(whiptail --title "Fedora Version" --menu "Select Fedora version:" 15 60 5 \
            "39" "Fedora 39" \
            "38" "Fedora 38" \
            "37" "Fedora 37" 3>&1 1>&2 2>&3)
        ;;
    opensuse)
        version=$(whiptail --title "openSUSE Version" --menu "Select openSUSE version:" 15 60 5 \
            "4" "Leap 15.4" \
            "3" "Leap 15.3" 3>&1 1>&2 2>&3)
        ;;
    arch)
        version="latest"
        ;;
    *)
        version="latest"
        ;;
esac
version_result=$?
if [ $version_result -ne 0 ] || [ -z "$version" ]; then
    log_info "User cancelled at version selection."
    exit 0
fi

# --- Step 4: Hardware Specification ---
cpu=$(whiptail --title "CPU Cores" --inputbox "Enter number of CPU cores:" 10 60 "2" 3>&1 1>&2 2>&3)
cpu_result=$?
if [ $cpu_result -ne 0 ] || [ -z "$cpu" ]; then exit 0; fi

ram=$(whiptail --title "RAM (MB)" --inputbox "Enter RAM in MB:" 10 60 "2048" 3>&1 1>&2 2>&3)
ram_result=$?
if [ $ram_result -ne 0 ] || [ -z "$ram" ]; then exit 0; fi

storage=$(whiptail --title "Disk Size (GB)" --inputbox "Enter disk size in GB:" 10 60 "16" 3>&1 1>&2 2>&3)
storage_result=$?
if [ $storage_result -ne 0 ] || [ -z "$storage" ]; then exit 0; fi

# --- Step 5: Cloud-Init User/SSH Config ---
use_cloudinit="no"
if supports_cloudinit "$distro"; then
    if whiptail --title "Cloud-Init" --yesno "Enable cloud-init for this template?" 10 60 3>&1 1>&2 2>&3; then
        use_cloudinit="yes"
        ci_user=$(whiptail --title "Cloud-Init User" --inputbox "Enter default username:" 10 60 "clouduser" 3>&1 1>&2 2>&3)
        ci_user_result=$?
        if [ $ci_user_result -ne 0 ]; then exit 0; fi
        
        # Default to SSH key in ~/.ssh/id_rsa.pub if exists
        default_key=""
        if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
            default_key=$(cat "$HOME/.ssh/id_rsa.pub")
        fi
        
        ci_sshkey=$(whiptail --title "SSH Public Key" --inputbox "Paste SSH public key for user $ci_user:" 10 60 "$default_key" 3>&1 1>&2 2>&3)
        ci_sshkey_result=$?
        if [ $ci_sshkey_result -ne 0 ]; then exit 0; fi
        
        # Validate SSH key format
        if [ -n "$ci_sshkey" ]; then
            if ! echo "$ci_sshkey" | grep -E '^(ssh-rsa|ssh-ed25519|ssh-ecdsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) [A-Za-z0-9+/]' >/dev/null; then
                if ! whiptail --title "Invalid SSH Key" --yesno "The SSH key format appears invalid. Continue anyway?" 10 60; then
                    exit 0
                fi
            else
                log_info "SSH key format validation passed"
            fi
        fi
        
        ci_network=$(whiptail --title "Network Config" --menu "Select network configuration:" 15 60 3 \
            "dhcp" "Automatic IP configuration (DHCP)" \
            "static" "Manual IP configuration" 3>&1 1>&2 2>&3)
        ci_network_result=$?
        if [ $ci_network_result -ne 0 ]; then exit 0; fi
        
        if [ "$ci_network" = "static" ]; then
            ci_ip=$(whiptail --title "Static IP" --inputbox "Enter IP address (CIDR format, e.g., 192.168.1.100/24):" 10 60 "" 3>&1 1>&2 2>&3)
            ci_ip_result=$?
            if [ $ci_ip_result -ne 0 ]; then exit 0; fi
            
            ci_gw=$(whiptail --title "Gateway" --inputbox "Enter default gateway:" 10 60 "" 3>&1 1>&2 2>&3)
            ci_gw_result=$?
            if [ $ci_gw_result -ne 0 ]; then exit 0; fi
            
            ci_nameserver=$(whiptail --title "DNS" --inputbox "Enter DNS server(s) (comma-separated):" 10 60 "1.1.1.1,8.8.8.8" 3>&1 1>&2 2>&3)
            ci_nameserver_result=$?
            if [ $ci_nameserver_result -ne 0 ]; then exit 0; fi
            
            ci_network="ip=$ci_ip,gw=$ci_gw,nameserver=$ci_nameserver"
        fi
    fi
else
    whiptail --title "Notice" --msgbox "Cloud-init is not supported for $distro distribution." 10 60
fi

# --- Step 6: Package Pre-installation (Cloud-init only) ---
install_packages=""
if [ "$use_cloudinit" = "yes" ]; then
    if whiptail --title "Package Installation" --yesno "Do you want to pre-install packages via cloud-init?" 10 60; then
        # Package categories
        PACKAGE_CATEGORIES=(
            "essential" "Essential tools (curl, wget, vim, htop)" OFF
            "docker" "Docker and Docker Compose" OFF
            "development" "Development tools (git, build-essential)" OFF
            "monitoring" "Monitoring agents (node-exporter)" OFF
            "security" "Security tools (fail2ban, ufw)" OFF
            "custom" "Custom package list" OFF
        )
        
        selected_packages=$(whiptail --title "Select Package Categories" --checklist "Choose packages to install:" 20 70 6 "${PACKAGE_CATEGORIES[@]}" 3>&1 1>&2 2>&3)
        if [ $? -eq 0 ]; then
            # Build package list based on selections
            packages=()
            for category in $selected_packages; do
                category=$(echo "$category" | tr -d '"')
                case "$category" in
                    essential)
                        packages+=(curl wget vim htop tree unzip)
                        ;;
                    docker)
                        packages+=(docker.io docker-compose)
                        ;;
                    development)
                        packages+=(git build-essential)
                        ;;
                    monitoring)
                        packages+=(prometheus-node-exporter)
                        ;;
                    security)
                        packages+=(fail2ban ufw)
                        ;;
                    custom)
                        custom_packages=$(whiptail --title "Custom Packages" --inputbox "Enter package names (space-separated):" 10 60 "" 3>&1 1>&2 2>&3)
                        if [ -n "$custom_packages" ]; then
                            read -ra custom_array <<< "$custom_packages"
                            packages+=("${custom_array[@]}")
                        fi
                        ;;
                esac
            done
            
            if [ ${#packages[@]} -gt 0 ]; then
                install_packages=$(IFS=' '; echo "${packages[*]}")
                log_info "Packages to install: $install_packages"
            fi
        fi
    fi
fi

# --- Step 7: Tagging/Categorization ---
tags=$(whiptail --title "Tags" --inputbox "Enter tags (comma-separated):" 10 60 "" 3>&1 1>&2 2>&3)
tags_result=$?
if [ $tags_result -ne 0 ]; then exit 0; fi

# --- Step 8: Validate Configuration ---
if ! validate_template_config; then
    log_error "Template configuration validation failed"
    exit 1
fi

# --- Step 9: Confirm and Create ---
summary="Template: $template_name\nDistro: $distro $version\nCPU: $cpu\nRAM: $ram MB\nDisk: $storage GB\nCloud-Init: $use_cloudinit\nTags: $tags"
if [ "$use_cloudinit" = "yes" ]; then
    summary+="\nUser: $ci_user\nSSH Key: ${ci_sshkey:0:30}...\nNetwork: $ci_network"
    if [ -n "$install_packages" ]; then
        summary+="\nPackages: $install_packages"
    fi
    if [ -n "$custom_scripts" ]; then
        summary+="\nCustom Scripts: Configured"
    else
        summary+="\nCustom Scripts: None"
    fi
fi

if ! whiptail --title "Confirm Template Creation" --yesno "$summary\n\nProceed?" 20 70; then
    log_info "User cancelled at confirmation."
    exit 0
fi

# Exit here if in test mode
if [ -n "$TEST_MODE" ]; then
    log_info "Test mode - exiting before VM creation."
    exit 0
fi

# --- Step 8: Proxmox Automation ---
# Find next available VMID
storage_pools=$(pvesh get /storage --output-format=json | jq -r '.[].storage')
default_storage="local-lvm"  # Use a safe default

# Check if local-lvm exists, otherwise try to find another storage
if ! echo "$storage_pools" | grep -q "^local-lvm$"; then
    # Try to find another storage that supports disk images
    for pool in $storage_pools; do
        if pvesh get /storage/"$pool" --output-format=json | jq -r '.content' | grep -q "images"; then
            default_storage="$pool"
            break
        fi
    done
fi

# Get next available VMID
vmid=$(pvesh get /cluster/nextid)
log_info "Using VMID: $vmid"

# Download image
iso_dir="/var/lib/vz/template/iso"
iso_name="${distro}-${version}-$(date +%Y%m%d).qcow2"
iso_path="$iso_dir/$iso_name"

# Create ISO directory if it doesn't exist
mkdir -p "$iso_dir"

# Get URL template and replace version placeholder
url_template=$(get_distro_url_template "$distro")
if [ -z "$url_template" ]; then
    log_error "Failed to get download URL template for $distro"
    whiptail --title "Error" --msgbox "Failed to get download URL template for $distro." 10 60
    exit 1
fi

# Replace version placeholder in URL
download_url="${url_template//%version%/$version}"
log_info "Download URL: $download_url"

if [ ! -f "$iso_path" ]; then
    log_info "Downloading image for $distro $version..."
    whiptail --title "Downloading" --infobox "Downloading $distro $version image...\nThis may take a few minutes." 10 60
    
    # Download the image
    if ! curl -L -o "$iso_path" "$download_url"; then
        log_error "Failed to download image from $download_url"
        whiptail --title "Error" --msgbox "Failed to download image. Check network connection and try again." 10 60
        rm -f "$iso_path"  # Clean up partial download
        exit 1
    fi
fi

# Create VM
log_info "Creating VM $vmid ($template_name)..."
whiptail --title "Creating VM" --infobox "Creating VM $vmid ($template_name)..." 10 60

if ! qm create "$vmid" --name "$template_name" --memory "$ram" --cores "$cpu" --net0 "virtio,bridge=vmbr0"; then
    log_error "Failed to create VM $vmid"
    whiptail --title "Error" --msgbox "Failed to create VM $vmid. Check logs for details." 10 60
    exit 1
fi

# Set additional VM parameters
qm set "$vmid" --scsihw virtio-scsi-pci
qm set "$vmid" --ostype l26

# Import disk (cloud image)
log_info "Importing disk image..."
if ! qm importdisk "$vmid" "$iso_path" "$default_storage"; then
    log_error "Failed to import disk from $iso_path to $default_storage"
    whiptail --title "Error" --msgbox "Failed to import disk. Check storage configuration." 10 60
    exit 1
fi

# Attach disk
log_info "Attaching disk to VM..."
qm set "$vmid" --scsi0 "$default_storage:vm-$vmid-disk-0"
qm set "$vmid" --boot order=scsi0

# Resize disk if needed (default size of cloud images is often small)
qm resize "$vmid" scsi0 "${storage}G"

# Add cloud-init drive if selected
if [ "$use_cloudinit" = "yes" ]; then
    log_info "Configuring cloud-init..."
    qm set "$vmid" --ide2 "$default_storage:cloudinit"
    qm set "$vmid" --ciuser "$ci_user"
    
    # Only set SSH key if provided
    if [ -n "$ci_sshkey" ]; then
        # Fix for SSH key configuration - write to temporary file for proper handling
        SSH_KEY_FILE=$(mktemp)
        echo "$ci_sshkey" > "$SSH_KEY_FILE"
        qm set "$vmid" --sshkeys "$SSH_KEY_FILE"
        rm -f "$SSH_KEY_FILE"
        log_info "SSH key configured for user $ci_user"
    fi
    
    # Set network configuration
    if [ "$ci_network" = "dhcp" ]; then
        qm set "$vmid" --ipconfig0 "ip=dhcp"
    else
        qm set "$vmid" --ipconfig0 "$ci_network"
    fi
    
    # Configure package installation via cloud-init
    if [ -n "$install_packages" ]; then
        log_info "Configuring package installation: $install_packages"
        # Create cloud-init user data for package installation
        CLOUD_INIT_FILE=$(mktemp)
        cat > "$CLOUD_INIT_FILE" << EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
EOF
        # Add each package to the cloud-init config
        for package in $install_packages; do
            echo "  - $package" >> "$CLOUD_INIT_FILE"
        done
        
        # Add QEMU guest agent installation
        echo "  - qemu-guest-agent" >> "$CLOUD_INIT_FILE"
        
        # Add runcmd to start qemu-guest-agent
        cat >> "$CLOUD_INIT_FILE" << EOF
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
        
        # Set the cloud-init configuration
        qm set "$vmid" --cicustom "user=local:snippets/$(basename "$CLOUD_INIT_FILE")"
        
        # Copy the file to Proxmox snippets directory (if it exists)
        if [ -d "/var/lib/vz/snippets" ]; then
            cp "$CLOUD_INIT_FILE" "/var/lib/vz/snippets/$(basename "$CLOUD_INIT_FILE")"
        fi
        
        rm -f "$CLOUD_INIT_FILE"
    else
        # Just install QEMU guest agent
        CLOUD_INIT_FILE=$(mktemp)
        cat > "$CLOUD_INIT_FILE" << EOF
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
        qm set "$vmid" --cicustom "user=local:snippets/$(basename "$CLOUD_INIT_FILE")"
        
        if [ -d "/var/lib/vz/snippets" ]; then
            cp "$CLOUD_INIT_FILE" "/var/lib/vz/snippets/$(basename "$CLOUD_INIT_FILE")"
        fi
        
        rm -f "$CLOUD_INIT_FILE"
    fi
fi

# Add tags if provided
if [ -n "$tags" ]; then
    qm set "$vmid" --tags "$tags"
fi

# Set VM description with creation info
creation_info="Created: $(date '+%Y-%m-%d %H:%M:%S')\nDistribution: $distro $version\nCloud-Init: $use_cloudinit"
qm set "$vmid" --description "$creation_info"

# Convert to template
log_info "Converting VM $vmid to template..."
qm template "$vmid"

log_info "Template $template_name ($vmid) created successfully."
whiptail --title "Success" --msgbox "Template $template_name ($vmid) created successfully!" 10 60
return 0
}

# Function to show help and documentation
show_help() {
    local help_text="Proxmox Template Creator Help\n\n"
    help_text+="FEATURES:\n"
    help_text+="• Create new VM templates from cloud images\n"
    help_text+="• Support for 50+ Linux distributions\n"
    help_text+="• Cloud-init integration with SSH key setup\n"
    help_text+="• Package pre-installation during template creation\n"
    help_text+="• Template validation and testing\n"
    help_text+="• Template management (clone, delete, export/import)\n"
    help_text+="• Configuration management and backup\n\n"
    help_text+="SUPPORTED DISTRIBUTIONS:\n"
    help_text+="• Ubuntu Server (18.04, 20.04, 22.04)\n"
    help_text+="• Debian (10, 11, 12)\n"
    help_text+="• CentOS Stream (8, 9)\n"
    help_text+="• Rocky Linux (8, 9)\n"
    help_text+="• Alpine Linux (3.17, 3.18, 3.19)\n"
    help_text+="• Fedora (37, 38, 39)\n"
    help_text+="• openSUSE Leap\n"
    help_text+="• Arch Linux\n\n"
    help_text+="COMMAND LINE OPTIONS:\n"
    help_text+="• --create: Direct template creation mode\n"
    help_text+="• --list-distros: List supported distributions\n"
    help_text+="• --list-versions: List versions for a distribution\n"
    help_text+="• --test: Test mode (UI only, no VM creation)\n\n"
    help_text+="For more information, check the documentation."
    
    whiptail --title "Help - Proxmox Template Creator" --msgbox "$help_text" 30 80
}

# Template creation function (wrapped from original logic)
create_template() {
    # --- Step 1: Template Name ---
    template_name=$(whiptail --title "Template Name" --inputbox "Enter a name for the new VM template:" 10 60 "template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
    template_result=$?
    if [ $template_result -ne 0 ] || [ -z "$template_name" ]; then
        log_info "User cancelled or empty template name."
        return 0
    fi

    # --- Step 2: Distribution Selection ---
    distro_menu=()
    for entry in "${DISTRO_LIST[@]}"; do
        IFS='|' read -r val desc ci url <<< "$entry"
        distro_menu+=("$val" "$desc")
    done
    distro=$(whiptail --title "Select Distribution" --menu "Choose a Linux distribution:" 20 60 10 "${distro_menu[@]}" 3>&1 1>&2 2>&3)
    distro_result=$?
    if [ $distro_result -ne 0 ] || [ -z "$distro" ]; then
        log_info "User cancelled at distro selection."
        return 0
    fi

    # --- Step 3: Version Selection (example for Ubuntu/Debian) ---
    case "$distro" in
        ubuntu)
            version=$(whiptail --title "Ubuntu Version" --menu "Select Ubuntu version:" 15 60 5 \
                "22.04" "Jammy Jellyfish (LTS)" \
                "20.04" "Focal Fossa (LTS)" \
                "18.04" "Bionic Beaver (LTS)" 3>&1 1>&2 2>&3)
            ;;
        debian)
            version=$(whiptail --title "Debian Version" --menu "Select Debian version:" 15 60 5 \
                "12" "Bookworm" \
                "11" "Bullseye" \
                "10" "Buster" 3>&1 1>&2 2>&3)
            ;;
        centos)
            version=$(whiptail --title "CentOS Version" --menu "Select CentOS version:" 15 60 5 \
                "9" "Stream 9" \
                "8" "Stream 8" 3>&1 1>&2 2>&3)
            ;;
        rocky)
            version=$(whiptail --title "Rocky Linux Version" --menu "Select Rocky Linux version:" 15 60 5 \
                "9" "Rocky 9" \
                "8" "Rocky 8" 3>&1 1>&2 2>&3)
            ;;
        alpine)
            version=$(whiptail --title "Alpine Version" --menu "Select Alpine version:" 15 60 5 \
                "3.19" "Alpine 3.19" \
                "3.18" "Alpine 3.18" \
                "3.17" "Alpine 3.17" 3>&1 1>&2 2>&3)
            ;;
        fedora)
            version=$(whiptail --title "Fedora Version" --menu "Select Fedora version:" 15 60 5 \
                "39" "Fedora 39" \
                "38" "Fedora 38" \
                "37" "Fedora 37" 3>&1 1>&2 2>&3)
            ;;
        opensuse)
            version=$(whiptail --title "openSUSE Version" --menu "Select openSUSE version:" 15 60 5 \
                "4" "Leap 15.4" \
                "3" "Leap 15.3" 3>&1 1>&2 2>&3)
            ;;
        arch)
            version="latest"
            ;;
        *)
            version="latest"
            ;;
    esac
    version_result=$?
    if [ $version_result -ne 0 ] || [ -z "$version" ]; then
        log_info "User cancelled at version selection."
        return 0
    fi

    # --- Step 4: Hardware Specification ---
    cpu=$(whiptail --title "CPU Cores" --inputbox "Enter number of CPU cores:" 10 60 "2" 3>&1 1>&2 2>&3)
    cpu_result=$?
    if [ $cpu_result -ne 0 ] || [ -z "$cpu" ]; then return 0; fi

    ram=$(whiptail --title "RAM (MB)" --inputbox "Enter RAM in MB:" 10 60 "2048" 3>&1 1>&2 2>&3)
    ram_result=$?
    if [ $ram_result -ne 0 ] || [ -z "$ram" ]; then return 0; fi

    storage=$(whiptail --title "Disk Size (GB)" --inputbox "Enter disk size in GB:" 10 60 "16" 3>&1 1>&2 2>&3)
    storage_result=$?
    if [ $storage_result -ne 0 ] || [ -z "$storage" ]; then return 0; fi

    # --- Step 5: Cloud-Init User/SSH Config ---
    use_cloudinit="no"
    if supports_cloudinit "$distro"; then
        if whiptail --title "Cloud-Init" --yesno "Enable cloud-init for this template?" 10 60 3>&1 1>&2 2>&3; then
            use_cloudinit="yes"
            ci_user=$(whiptail --title "Cloud-Init User" --inputbox "Enter default username:" 10 60 "clouduser" 3>&1 1>&2 2>&3)
            ci_user_result=$?
            if [ $ci_user_result -ne 0 ]; then return 0; fi
            
            # Default to SSH key in ~/.ssh/id_rsa.pub if exists
            default_key=""
            if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
                default_key=$(cat "$HOME/.ssh/id_rsa.pub")
            fi
            
            ci_sshkey=$(whiptail --title "SSH Public Key" --inputbox "Paste SSH public key for user $ci_user:" 10 60 "$default_key" 3>&1 1>&2 2>&3)
            ci_sshkey_result=$?
            if [ $ci_sshkey_result -ne 0 ]; then return 0; fi
            
            # Validate SSH key format
            if [ -n "$ci_sshkey" ]; then
                if ! echo "$ci_sshkey" | grep -E '^(ssh-rsa|ssh-ed25519|ssh-ecdsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) [A-Za-z0-9+/]' >/dev/null; then
                    if ! whiptail --title "Invalid SSH Key" --yesno "The SSH key format appears invalid. Continue anyway?" 10 60; then
                        return 0
                    fi
                else
                    log_info "SSH key format validation passed"
                fi
            fi
            
            # Cloud-init password configuration
            ci_password=""
            ci_password_enabled="no"
            if whiptail --title "Password Authentication" --yesno "Do you want to enable password authentication for user $ci_user?\n\nNote: SSH key authentication is recommended for better security." 12 70; then
                ci_password_enabled="yes"
                
                # Get minimum password length from config (default 12)
                local min_length=12
                if command -v source >/dev/null 2>&1; then
                    min_length=$(grep "^MIN_PASSWORD_LENGTH=" "$SCRIPT_DIR/../scripts/config.sh" 2>/dev/null | cut -d'=' -f2 || echo "12")
                fi
                
                while true; do
                    ci_password=$(whiptail --title "Set Password" --passwordbox "Enter password for user $ci_user (minimum $min_length characters):" 12 60 3>&1 1>&2 2>&3)
                    ci_password_result=$?
                    if [ $ci_password_result -ne 0 ]; then
                        ci_password_enabled="no"
                        break
                    fi
                    
                    # Validate password length
                    if [ ${#ci_password} -lt $min_length ]; then
                        whiptail --title "Password Too Short" --msgbox "Password must be at least $min_length characters long. Please try again." 10 60
                        continue
                    fi
                    
                    # Confirm password
                    ci_password_confirm=$(whiptail --title "Confirm Password" --passwordbox "Confirm password for user $ci_user:" 10 60 3>&1 1>&2 2>&3)
                    if [ $? -ne 0 ]; then
                        ci_password_enabled="no"
                        break
                    fi
                    
                    if [ "$ci_password" = "$ci_password_confirm" ]; then
                        log_info "Password authentication configured for user $ci_user"
                        break
                    else
                        whiptail --title "Password Mismatch" --msgbox "Passwords do not match. Please try again." 10 60
                    fi
                done
            fi
            
            ci_network=$(whiptail --title "Network Config" --menu "Select network configuration:" 15 60 3 \
                "dhcp" "Automatic IP configuration (DHCP)" \
                "static" "Manual IP configuration" 3>&1 1>&2 2>&3)
            ci_network_result=$?
            if [ $ci_network_result -ne 0 ]; then return 0; fi
            
            if [ "$ci_network" = "static" ]; then
                ci_ip=$(whiptail --title "Static IP" --inputbox "Enter IP address (CIDR format, e.g., 192.168.1.100/24):" 10 60 "" 3>&1 1>&2 2>&3)
                ci_ip_result=$?
                if [ $ci_ip_result -ne 0 ]; then return 0; fi
                
                ci_gw=$(whiptail --title "Gateway" --inputbox "Enter default gateway:" 10 60 "" 3>&1 1>&2 2>&3)
                ci_gw_result=$?
                if [ $ci_gw_result -ne 0 ]; then return 0; fi
                
                ci_nameserver=$(whiptail --title "DNS" --inputbox "Enter DNS server(s) (comma-separated):" 10 60 "1.1.1.1,8.8.8.8" 3>&1 1>&2 2>&3)
                ci_nameserver_result=$?
                if [ $ci_nameserver_result -ne 0 ]; then return 0; fi
                
                ci_network="ip=$ci_ip,gw=$ci_gw,nameserver=$ci_nameserver"
            fi
        fi
    else
        whiptail --title "Notice" --msgbox "Cloud-init is not supported for $distro distribution." 10 60
    fi

    # --- Step 6: Package Pre-installation (Cloud-init only) ---
    install_packages=""
    if [ "$use_cloudinit" = "yes" ]; then
        if whiptail --title "Package Installation" --yesno "Do you want to pre-install packages via cloud-init?" 10 60; then
            # Package categories
            PACKAGE_CATEGORIES=(
                "essential" "Essential tools (curl, wget, vim, htop)" OFF
                "docker" "Docker and Docker Compose" OFF
                "development" "Development tools (git, build-essential)" OFF
                "monitoring" "Monitoring agents (node-exporter)" OFF
                "security" "Security tools (fail2ban, ufw)" OFF
                "custom" "Custom package list" OFF
            )
            
            selected_packages=$(whiptail --title "Select Package Categories" --checklist "Choose packages to install:" 20 70 6 "${PACKAGE_CATEGORIES[@]}" 3>&1 1>&2 2>&3)
            if [ $? -eq 0 ]; then
                # Build package list based on selections
                packages=()
                for category in $selected_packages; do
                    category=$(echo "$category" | tr -d '"')
                    case "$category" in
                        essential)
                            packages+=(curl wget vim htop tree unzip)
                            ;;
                        docker)
                            packages+=(docker.io docker-compose)
                            ;;
                        development)
                            packages+=(git build-essential)
                            ;;
                        monitoring)
                            packages+=(prometheus-node-exporter)
                            ;;
                        security)
                            packages+=(fail2ban ufw)
                            ;;
                        custom)
                            custom_packages=$(whiptail --title "Custom Packages" --inputbox "Enter package names (space-separated):" 10 60 "" 3>&1 1>&2 2>&3)
                            if [ -n "$custom_packages" ]; then
                                read -ra custom_array <<< "$custom_packages"
                                packages+=("${custom_array[@]}")
                            fi
                            ;;
                    esac
                done
                
                if [ ${#packages[@]} -gt 0 ]; then
                    install_packages=$(IFS=' '; echo "${packages[*]}")
                    log_info "Packages to install: $install_packages"
                fi
            fi
        fi
    fi

    # --- Step 6.5: Custom Script Execution (Cloud-init only) ---
    custom_scripts=""
    if [ "$use_cloudinit" = "yes" ]; then
        if whiptail --title "Custom Scripts" --yesno "Do you want to add custom scripts to run during first boot?" 10 60; then
            # Script execution options
            script_option=$(whiptail --title "Script Options" --menu "Choose script input method:" 15 70 4 \
                "commands" "Simple commands (one per line)" \
                "script" "Custom multi-line script" \
                "template" "Predefined script templates" \
                "none" "Skip custom scripts" 3>&1 1>&2 2>&3)
            
            if [ "$script_option" != "none" ] && [ $? -eq 0 ]; then
                case "$script_option" in
                    "commands")
                        custom_scripts=$(whiptail --title "Custom Commands" --inputbox "Enter commands (one per line, use \\n for newlines):" 15 70 "" 3>&1 1>&2 2>&3)
                        if [ $? -eq 0 ] && [ -n "$custom_scripts" ]; then
                            # Convert \n to actual newlines
                            custom_scripts=$(echo -e "$custom_scripts")
                            log_info "Custom commands configured"
                        fi
                        ;;
                    "script")
                        # Use a temporary file for multi-line script input
                        SCRIPT_INPUT_FILE=$(mktemp)
                        if whiptail --title "Custom Script" --textbox /dev/null 20 80 --scrolltext 2>"$SCRIPT_INPUT_FILE"; then
                            if [ -s "$SCRIPT_INPUT_FILE" ]; then
                                custom_scripts=$(cat "$SCRIPT_INPUT_FILE")
                                log_info "Custom script configured"
                            fi
                        fi
                        rm -f "$SCRIPT_INPUT_FILE"
                        ;;
                    "template")
                        # Predefined script templates
                        template_choice=$(whiptail --title "Script Templates" --menu "Choose a predefined script template:" 18 80 8 \
                            "docker-setup" "Install and configure Docker" \
                            "web-server" "Basic web server setup (nginx)" \
                            "security-hardening" "Basic security hardening" \
                            "monitoring-agent" "Install monitoring agents" \
                            "dev-tools" "Development tools setup" \
                            "auto-updates" "Configure automatic updates" \
                            "custom-user" "Create additional system user" \
                            "none" "Cancel template selection" 3>&1 1>&2 2>&3)
                        
                        if [ "$template_choice" != "none" ] && [ $? -eq 0 ]; then
                            custom_scripts=$(get_script_template "$template_choice")
                            if [ -n "$custom_scripts" ]; then
                                log_info "Applied script template: $template_choice"
                            fi
                        fi
                        ;;
                esac
            fi
        fi
    fi

    # --- Step 7: Tagging/Categorization ---
    tags=$(whiptail --title "Tags" --inputbox "Enter tags (comma-separated):" 10 60 "" 3>&1 1>&2 2>&3)
    tags_result=$?
    if [ $tags_result -ne 0 ]; then return 0; fi

    # --- Step 8: Validate Configuration ---
    if ! validate_template_config; then
        log_error "Template configuration validation failed"
        return 1
    fi

    # --- Step 9: Confirm and Create ---
    summary="Template: $template_name\nDistro: $distro $version\nCPU: $cpu\nRAM: $ram MB\nDisk: $storage GB\nCloud-Init: $use_cloudinit\nTags: $tags"
    if [ "$use_cloudinit" = "yes" ]; then
        summary+="\nUser: $ci_user\nSSH Key: ${ci_sshkey:0:30}..."
        if [ "$ci_password_enabled" = "yes" ]; then
            summary+="\nPassword: Enabled"
        else
            summary+="\nPassword: Disabled"
        fi
        summary+="\nNetwork: $ci_network"
        if [ -n "$install_packages" ]; then
            summary+="\nPackages: $install_packages"
        fi
        if [ -n "$custom_scripts" ]; then
            summary+="\nCustom Scripts: Configured"
        else
            summary+="\nCustom Scripts: None"
        fi
    fi

    if ! whiptail --title "Confirm Template Creation" --yesno "$summary\n\nProceed?" 20 70; then
        log_info "User cancelled at confirmation."
        return 0
    fi

    # Exit here if in test mode
    if [ -n "$TEST_MODE" ]; then
        log_info "Test mode - exiting before VM creation."
        return 0
    fi

    # --- Step 8: Proxmox Automation ---
    # Find next available VMID
    storage_pools=$(pvesh get /storage --output-format=json | jq -r '.[].storage')
    default_storage="local-lvm"  # Use a safe default

    # Check if local-lvm exists, otherwise try to find another storage
    if ! echo "$storage_pools" | grep -q "^local-lvm$"; then
        # Try to find another storage that supports disk images
        for pool in $storage_pools; do
            if pvesh get /storage/"$pool" --output-format=json | jq -r '.content' | grep -q "images"; then
                default_storage="$pool"
                break
            fi
        done
    fi

    # Get next available VMID
    vmid=$(pvesh get /cluster/nextid)
    log_info "Using VMID: $vmid"

    # Download image
    iso_dir="/var/lib/vz/template/iso"
    iso_name="${distro}-${version}-$(date +%Y%m%d).qcow2"
    iso_path="$iso_dir/$iso_name"

    # Create ISO directory if it doesn't exist
    mkdir -p "$iso_dir"

    # Get URL template and replace version placeholder
    url_template=$(get_distro_url_template "$distro")
    if [ -z "$url_template" ]; then
        log_error "Failed to get download URL template for $distro"
        whiptail --title "Error" --msgbox "Failed to get download URL template for $distro." 10 60
        return 1
    fi

    # Replace version placeholder in URL
    download_url="${url_template//%version%/$version}"
    log_info "Download URL: $download_url"

    if [ ! -f "$iso_path" ]; then
        log_info "Downloading image for $distro $version..."
        whiptail --title "Downloading" --infobox "Downloading $distro $version image...\nThis may take a few minutes." 10 60
        
        # Download the image
        if ! curl -L -o "$iso_path" "$download_url"; then
            log_error "Failed to download image from $download_url"
            whiptail --title "Error" --msgbox "Failed to download image. Check network connection and try again." 10 60
            rm -f "$iso_path"  # Clean up partial download
            return 1
        fi
    fi

    # Create VM
    log_info "Creating VM $vmid ($template_name)..."
    whiptail --title "Creating VM" --infobox "Creating VM $vmid ($template_name)..." 10 60

    if ! qm create "$vmid" --name "$template_name" --memory "$ram" --cores "$cpu" --net0 "virtio,bridge=vmbr0"; then
        log_error "Failed to create VM $vmid"
        whiptail --title "Error" --msgbox "Failed to create VM $vmid. Check logs for details." 10 60
        return 1
    fi

    # Set additional VM parameters
    qm set "$vmid" --scsihw virtio-scsi-pci
    qm set "$vmid" --ostype l26

    # Import disk (cloud image)
    log_info "Importing disk image..."
    if ! qm importdisk "$vmid" "$iso_path" "$default_storage"; then
        log_error "Failed to import disk from $iso_path to $default_storage"
        whiptail --title "Error" --msgbox "Failed to import disk. Check storage configuration." 10 60
        return 1
    fi

    # Attach disk
    log_info "Attaching disk to VM..."
    qm set "$vmid" --scsi0 "$default_storage:vm-$vmid-disk-0"
    qm set "$vmid" --boot order=scsi0

    # Resize disk if needed (default size of cloud images is often small)
    qm resize "$vmid" scsi0 "${storage}G"

    # Add cloud-init drive if selected
    if [ "$use_cloudinit" = "yes" ]; then
        log_info "Configuring cloud-init..."
        qm set "$vmid" --ide2 "$default_storage:cloudinit"
        qm set "$vmid" --ciuser "$ci_user"
        
        # Only set SSH key if provided
        if [ -n "$ci_sshkey" ]; then
            # Fix for SSH key configuration - write to temporary file for proper handling
            SSH_KEY_FILE=$(mktemp)
            echo "$ci_sshkey" > "$SSH_KEY_FILE"
            qm set "$vmid" --sshkeys "$SSH_KEY_FILE"
            rm -f "$SSH_KEY_FILE"
            log_info "SSH key configured for user $ci_user"
        fi
        
        # Set cloud-init password if provided
        if [ "$ci_password_enabled" = "yes" ] && [ -n "$ci_password" ]; then
            qm set "$vmid" --cipassword "$ci_password"
            log_info "Password authentication configured for user $ci_user"
        fi
        
        # Set network configuration
        if [ "$ci_network" = "dhcp" ]; then
            qm set "$vmid" --ipconfig0 "ip=dhcp"
        else
            qm set "$vmid" --ipconfig0 "$ci_network"
        fi
        
        # Configure package installation via cloud-init
        if [ -n "$install_packages" ]; then
            log_info "Configuring package installation: $install_packages"
            # Create cloud-init user data for package installation
            CLOUD_INIT_FILE=$(mktemp)
            cat > "$CLOUD_INIT_FILE" << EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
EOF
            # Add each package to the cloud-init config
            for package in $install_packages; do
                echo "  - $package" >> "$CLOUD_INIT_FILE"
            done
            
            # Add QEMU guest agent installation
            echo "  - qemu-guest-agent" >> "$CLOUD_INIT_FILE"
            
            # Add runcmd to start qemu-guest-agent and custom scripts
            cat >> "$CLOUD_INIT_FILE" << EOF
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
            
            # Add custom scripts if configured
            if [ -n "$custom_scripts" ]; then
                echo "  # Custom scripts" >> "$CLOUD_INIT_FILE"
                # Convert custom scripts to YAML runcmd format
                while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        echo "  - $line" >> "$CLOUD_INIT_FILE"
                    fi
                done <<< "$custom_scripts"
            fi
            
            # Set the cloud-init configuration
            qm set "$vmid" --cicustom "user=local:snippets/$(basename "$CLOUD_INIT_FILE")"
            
            # Copy the file to Proxmox snippets directory (if it exists)
            if [ -d "/var/lib/vz/snippets" ]; then
                cp "$CLOUD_INIT_FILE" "/var/lib/vz/snippets/$(basename "$CLOUD_INIT_FILE")"
            fi
            
            rm -f "$CLOUD_INIT_FILE"
        else
            # Just install QEMU guest agent
            CLOUD_INIT_FILE=$(mktemp)
            cat > "$CLOUD_INIT_FILE" << EOF
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
            
            # Add custom scripts if configured
            if [ -n "$custom_scripts" ]; then
                echo "  # Custom scripts" >> "$CLOUD_INIT_FILE"
                # Convert custom scripts to YAML runcmd format
                while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        echo "  - $line" >> "$CLOUD_INIT_FILE"
                    fi
                done <<< "$custom_scripts"
            fi
            qm set "$vmid" --cicustom "user=local:snippets/$(basename "$CLOUD_INIT_FILE")"
            
            if [ -d "/var/lib/vz/snippets" ]; then
                cp "$CLOUD_INIT_FILE" "/var/lib/vz/snippets/$(basename "$CLOUD_INIT_FILE")"
            fi
            
            rm -f "$CLOUD_INIT_FILE"
        fi
    fi

    # Add tags if provided
    if [ -n "$tags" ]; then
        qm set "$vmid" --tags "$tags"
    fi

    # Set VM description with creation info
    creation_info="Created: $(date '+%Y-%m-%d %H:%M:%S')\nDistribution: $distro $version\nCloud-Init: $use_cloudinit"
    qm set "$vmid" --description "$creation_info"

    # Convert to template
    log_info "Converting VM $vmid to template..."
    qm template "$vmid"

    log_info "Template $template_name ($vmid) created successfully."
    whiptail --title "Success" --msgbox "Template $template_name ($vmid) created successfully!" 10 60
    return 0
}

# Main menu function
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Proxmox Template Creator" --menu "Select an option:" 20 70 8 \
            "1" "Create new template" \
            "2" "List all templates" \
            "3" "Manage existing templates" \
            "4" "Validate template" \
            "5" "Test template" \
            "6" "Template configuration management" \
            "7" "Help and documentation" \
            "8" "Exit" 3>&1 1>&2 2>&3)
        
        case $choice in
            1)
                create_template
                ;;
            2)
                list_templates
                ;;
            3)
                manage_templates
                ;;
            4)
                validate_template
                ;;
            5)
                test_template
                ;;
            6)
                manage_template_config
                ;;
            7)
                show_help
                ;;
            8|"")
                log_info "Exiting template creator"
                exit 0
                ;;
        esac
    done
}

# Check if running in direct create mode or as CLI arguments
if [ "$1" = "--create" ] || [ -n "$CREATE_MODE" ]; then
    # Run pre-checks and go directly to template creation
    if [ -z "$TEST_MODE" ]; then
        check_dependencies
        check_proxmox
    fi
    create_template
    exit $?
elif [ $# -eq 0 ]; then
    # No arguments provided, show main menu
    if [ -z "$TEST_MODE" ]; then
        check_dependencies
        check_proxmox
    fi
    main_menu
else
    # Arguments were provided and handled at the beginning of the script
    # This handles --list-distros, --list-versions, --test, etc.
    log_info "CLI arguments were processed at script start"
fi
