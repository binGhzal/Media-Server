#!/bin/bash
# Proxmox Template Creator - Template Module

set -e

# Logging function
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

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
        log "ERROR" "Missing dependencies: ${missing[*]}"
        whiptail --title "Error" --msgbox "Missing required tools: ${missing[*]}\n\nPlease install these dependencies and try again." 10 70
        exit 1
    fi
}

# Check for Proxmox environment
check_proxmox() {
    if ! command -v pvesh &> /dev/null; then
        log "ERROR" "This script must be run in a Proxmox VE environment."
        whiptail --title "Error" --msgbox "This script must be run in a Proxmox VE environment." 10 60
        exit 1
    fi
}

# Run pre-checks
if [ -z "$TEST_MODE" ]; then
    check_dependencies
    check_proxmox
fi

# --- Step 1: Template Name ---
template_name=$(whiptail --title "Template Name" --inputbox "Enter a name for the new VM template:" 10 60 "template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
template_result=$?
if [ $template_result -ne 0 ] || [ -z "$template_name" ]; then
    log "INFO" "User cancelled or empty template name."
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
    log "INFO" "User cancelled at distro selection."
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
    log "INFO" "User cancelled at version selection."
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
                log "INFO" "SSH key format validation passed"
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
                log "INFO" "Packages to install: $install_packages"
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
    log "ERROR" "Template configuration validation failed"
    exit 1
fi

# --- Step 9: Confirm and Create ---
summary="Template: $template_name\nDistro: $distro $version\nCPU: $cpu\nRAM: $ram MB\nDisk: $storage GB\nCloud-Init: $use_cloudinit\nTags: $tags"
if [ "$use_cloudinit" = "yes" ]; then
    summary+="\nUser: $ci_user\nSSH Key: ${ci_sshkey:0:30}...\nNetwork: $ci_network"
    if [ -n "$install_packages" ]; then
        summary+="\nPackages: $install_packages"
    fi
fi

if ! whiptail --title "Confirm Template Creation" --yesno "$summary\n\nProceed?" 20 70; then
    log "INFO" "User cancelled at confirmation."
    exit 0
fi

# Exit here if in test mode
if [ -n "$TEST_MODE" ]; then
    log "INFO" "Test mode - exiting before VM creation."
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
log "INFO" "Using VMID: $vmid"

# Download image
iso_dir="/var/lib/vz/template/iso"
iso_name="${distro}-${version}-$(date +%Y%m%d).qcow2"
iso_path="$iso_dir/$iso_name"

# Create ISO directory if it doesn't exist
mkdir -p "$iso_dir"

# Get URL template and replace version placeholder
url_template=$(get_distro_url_template "$distro")
if [ -z "$url_template" ]; then
    log "ERROR" "Failed to get download URL template for $distro"
    whiptail --title "Error" --msgbox "Failed to get download URL template for $distro." 10 60
    exit 1
fi

# Replace version placeholder in URL
download_url="${url_template//%version%/$version}"
log "INFO" "Download URL: $download_url"

if [ ! -f "$iso_path" ]; then
    log "INFO" "Downloading image for $distro $version..."
    whiptail --title "Downloading" --infobox "Downloading $distro $version image...\nThis may take a few minutes." 10 60
    
    # Download the image
    if ! curl -L -o "$iso_path" "$download_url"; then
        log "ERROR" "Failed to download image from $download_url"
        whiptail --title "Error" --msgbox "Failed to download image. Check network connection and try again." 10 60
        rm -f "$iso_path"  # Clean up partial download
        exit 1
    fi
fi

# Create VM
log "INFO" "Creating VM $vmid ($template_name)..."
whiptail --title "Creating VM" --infobox "Creating VM $vmid ($template_name)..." 10 60

if ! qm create "$vmid" --name "$template_name" --memory "$ram" --cores "$cpu" --net0 "virtio,bridge=vmbr0"; then
    log "ERROR" "Failed to create VM $vmid"
    whiptail --title "Error" --msgbox "Failed to create VM $vmid. Check logs for details." 10 60
    exit 1
fi

# Set additional VM parameters
qm set "$vmid" --scsihw virtio-scsi-pci
qm set "$vmid" --ostype l26

# Import disk (cloud image)
log "INFO" "Importing disk image..."
if ! qm importdisk "$vmid" "$iso_path" "$default_storage"; then
    log "ERROR" "Failed to import disk from $iso_path to $default_storage"
    whiptail --title "Error" --msgbox "Failed to import disk. Check storage configuration." 10 60
    exit 1
fi

# Attach disk
log "INFO" "Attaching disk to VM..."
qm set "$vmid" --scsi0 "$default_storage:vm-$vmid-disk-0"
qm set "$vmid" --boot order=scsi0

# Resize disk if needed (default size of cloud images is often small)
qm resize "$vmid" scsi0 "${storage}G"

# Add cloud-init drive if selected
if [ "$use_cloudinit" = "yes" ]; then
    log "INFO" "Configuring cloud-init..."
    qm set "$vmid" --ide2 "$default_storage:cloudinit"
    qm set "$vmid" --ciuser "$ci_user"
    
    # Only set SSH key if provided
    if [ -n "$ci_sshkey" ]; then
        # Fix for SSH key configuration - write to temporary file for proper handling
        SSH_KEY_FILE=$(mktemp)
        echo "$ci_sshkey" > "$SSH_KEY_FILE"
        qm set "$vmid" --sshkeys "$SSH_KEY_FILE"
        rm -f "$SSH_KEY_FILE"
        log "INFO" "SSH key configured for user $ci_user"
    fi
    
    # Set network configuration
    if [ "$ci_network" = "dhcp" ]; then
        qm set "$vmid" --ipconfig0 "ip=dhcp"
    else
        qm set "$vmid" --ipconfig0 "$ci_network"
    fi
    
    # Configure package installation via cloud-init
    if [ -n "$install_packages" ]; then
        log "INFO" "Configuring package installation: $install_packages"
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
log "INFO" "Converting VM $vmid to template..."
qm template "$vmid"

log "INFO" "Template $template_name ($vmid) created successfully."
whiptail --title "Success" --msgbox "Template $template_name ($vmid) created successfully!" 10 60
exit 0
