# Ubuntu Server 25-04"
# Packer Template to create an Ubuntu Server (25-04) on Proxmox

# Variable Definitions
variable "proxmox_api_url" {
    type = string
}

variable "proxmox_api_token_id" {
    type = string
}

variable "proxmox_api_token_secret" {
    type = string
    sensitive = true
}

variable "runner_ip_address" {
    type = string
}

# Resource Definiation for the VM Template
source "proxmox-iso" "ubuntu-server-25-04" {

    # Proxmox Connection Settings
    proxmox_url = "${var.proxmox_api_url}"
    username = "${var.proxmox_api_token_id}"
    token = "${var.proxmox_api_token_secret}"
    # (Optional) Skip TLS Verification
    insecure_skip_tls_verify = true

    # VM General Settings
    node = "pve"
    vm_id = "9000"
    vm_name = "ubuntu-server-25-04"
    template_description = "Ubuntu Server 25.04 Template for Proxmox"

    # VM OS Settings
    boot_iso {
        iso_file = "synology:iso/ubuntu-25.04-live-server-amd64.iso"
        iso_storage_pool = "bigdisk"
        unmount = true
        iso_checksum = "none"
    }
    os = "l26"

    # VM System Settings
    qemu_agent = true

    # VM Hard Disk Settings
    scsi_controller = "virtio-scsi-pci"

    disks {
        disk_size = "20G"
        format = "raw"
        storage_pool = "bigdisk"
        type = "virtio"
    }

    # VM CPU Settings
    cores = "2"

    # VM Memory Settings
    memory = "2048"

    # VM Network Settings
    network_adapters {
        model = "virtio"
        bridge = "vmbr0"
        firewall = "false"
    }

    # VM Cloud-Init Settings
    cloud_init = true
    cloud_init_storage_pool = "bigdisk"

    # PACKER Boot Commands
    boot_command = [
        "<esc><wait>",
        "e<wait>",
        "<down><down><down><end>",
        "<bs><bs><bs><bs><wait>",
        "autoinstall ds=nocloud-net\\;s=http://${var.runner_ip_address}:{{ .HTTPPort }}/ ---<wait>",
        "<f10><wait>"
    ]

    boot                    = "c"
    boot_wait               = "10s"
    communicator            = "ssh"

    # PACKER Autoinstall Settings
    http_directory          = "http"
    ssh_username            = "binghzal"
    ssh_password            = "PLAINTEXT_PASSWORD"

    # Raise the timeout, when installation takes longer
    ssh_timeout             = "30m"
    ssh_pty                 = true
}

# Build Definition to create the VM Template
build {

    name = "ubuntu-server-25-04"
    sources = ["source.proxmox-iso.ubuntu-server-25-04"]

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #1
    provisioner "shell" {
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
            "sudo rm /etc/ssh/ssh_host_*",
            "sudo truncate -s 0 /etc/machine-id",
            "sudo apt -y autoremove --purge",
            "sudo apt -y clean",
            "sudo apt -y autoclean",
            "sudo cloud-init clean",
            "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
            "sudo rm -f /etc/netplan/00-installer-config.yaml",
            "sudo sync"
        ]
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #2
    provisioner "file" {
        source = "./files/99-pve.cfg"
        destination = "/tmp/99-pve.cfg"
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #3
    provisioner "shell" {
        inline = [ "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg" ]
    }

    # Add additional provisioning scripts here
    # ...
}
