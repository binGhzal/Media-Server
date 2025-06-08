#!/bin/bash
# Proxmox Template Creator - Template Module

set -e

# Logging function
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

# --- Configurable distro list (extendable) ---
DISTRO_LIST=(
    "ubuntu|Ubuntu Server"
    "debian|Debian"
    "centos|CentOS"
    "rocky|Rocky Linux"
    "alpine|Alpine Linux"
    # Add more distros here
)

# --- Step 1: Template Name ---
template_name=$(whiptail --title "Template Name" --inputbox "Enter a name for the new VM template:" 10 60 "template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$template_name" ]; then
    log "INFO" "User cancelled or empty template name."
    exit 0
fi

# --- Step 2: Distribution Selection ---
distro_menu=()
for entry in "${DISTRO_LIST[@]}"; do
    IFS='|' read -r val desc <<< "$entry"
    distro_menu+=("$val" "$desc")
done
distro=$(whiptail --title "Select Distribution" --menu "Choose a Linux distribution:" 20 60 10 "${distro_menu[@]}" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$distro" ]; then
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
            "3.18" "Alpine 3.18" 3>&1 1>&2 2>&3)
        ;;
    *)
        version="latest"
        ;;
esac
if [ $? -ne 0 ] || [ -z "$version" ]; then
    log "INFO" "User cancelled at version selection."
    exit 0
fi

# --- Step 4: Hardware Specification ---
cpu=$(whiptail --title "CPU Cores" --inputbox "Enter number of CPU cores:" 10 60 "2" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$cpu" ]; then exit 0; fi
ram=$(whiptail --title "RAM (MB)" --inputbox "Enter RAM in MB:" 10 60 "2048" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$ram" ]; then exit 0; fi
storage=$(whiptail --title "Disk Size (GB)" --inputbox "Enter disk size in GB:" 10 60 "16" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$storage" ]; then exit 0; fi

# --- Step 5: Cloud-Init User/SSH Config ---
use_cloudinit=$(whiptail --title "Cloud-Init" --yesno "Enable cloud-init for this template?" 10 60 3>&1 1>&2 2>&3 && echo yes || echo no)
if [ "$use_cloudinit" = "yes" ]; then
    ci_user=$(whiptail --title "Cloud-Init User" --inputbox "Enter default username:" 10 60 "clouduser" 3>&1 1>&2 2>&3)
    ci_sshkey=$(whiptail --title "SSH Public Key" --inputbox "Paste SSH public key for user $ci_user:" 10 60 "" 3>&1 1>&2 2>&3)
    ci_network=$(whiptail --title "Network Config" --inputbox "Enter network config (e.g. dhcp/static):" 10 60 "dhcp" 3>&1 1>&2 2>&3)
fi

# --- Step 6: Tagging/Categorization ---
tags=$(whiptail --title "Tags" --inputbox "Enter tags (comma-separated):" 10 60 "" 3>&1 1>&2 2>&3)

# --- Step 7: Confirm and Create ---
summary="Template: $template_name\nDistro: $distro $version\nCPU: $cpu\nRAM: $ram MB\nDisk: $storage GB\nCloud-Init: $use_cloudinit\nTags: $tags"
if [ "$use_cloudinit" = "yes" ]; then
    summary+="\nUser: $ci_user\nSSH Key: ${ci_sshkey:0:30}...\nNetwork: $ci_network"
fi
whiptail --title "Confirm Template Creation" --yesno "$summary\n\nProceed?" 20 70
if [ $? -ne 0 ]; then
    log "INFO" "User cancelled at confirmation."
    exit 0
fi

# --- Step 8: Proxmox Automation (basic) ---
# Find next available VMID
default_storage="local-lvm"
vmid=$(pvesh get /cluster/nextid)

# Download ISO if not present (placeholder, extend for all distros)
iso_dir="/var/lib/vz/template/iso"
iso_name="${distro}-${version}.iso"
iso_path="$iso_dir/$iso_name"
if [ ! -f "$iso_path" ]; then
    log "INFO" "Downloading ISO for $distro $version..."
    # Placeholder: actual download URLs should be mapped per distro/version
    iso_url="https://cloud-images.ubuntu.com/releases/$version/release/ubuntu-$version-server-cloudimg-amd64.img"
    mkdir -p "$iso_dir"
    curl -L "$iso_url" -o "$iso_path" || { log "ERROR" "Failed to download ISO."; exit 1; }
fi

# Create VM
echo "Creating VM $vmid..."
qm create $vmid --name "$template_name" --memory $ram --cores $cpu --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci --ostype l26 --tags "$tags"

# Import disk (cloud image)
qm importdisk $vmid "$iso_path" "$default_storage"

# Attach disk
qm set $vmid --scsi0 "$default_storage:vm-$vmid-disk-0" --boot order=scsi0

# Enable cloud-init if selected
if [ "$use_cloudinit" = "yes" ]; then
    qm set $vmid --ide2 "$default_storage:cloudinit"
    qm set $vmid --ciuser "$ci_user" --sshkey "$ci_sshkey"
    if [ "$ci_network" = "dhcp" ]; then
        qm set $vmid --ipconfig0 "ip=dhcp"
    else
        qm set $vmid --ipconfig0 "$ci_network"
    fi
fi

# Convert to template
qm template $vmid

log "INFO" "Template $template_name ($vmid) created successfully."
whiptail --title "Success" --msgbox "Template $template_name ($vmid) created successfully!" 10 60
exit 0
