terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}

resource "proxmox_vm_qemu" "vm" {
  count       = var.vm_count
  name        = "${var.vm_name_prefix}-${count.index + 1}"
  target_node = var.target_node
  
  # Template settings
  clone    = var.template_name
  os_type  = "cloud-init"
  cores    = var.vm_cores
  memory   = var.vm_memory
  
  # Disk settings
  disk {
    size     = var.vm_disk_size
    type     = "scsi"
    storage  = var.vm_storage
  }
  
  # Network settings
  network {
    model  = "virtio"
    bridge = var.vm_bridge
    tag    = var.vm_vlan_tag != 0 ? var.vm_vlan_tag : null
  }
  
  # Cloud-init settings
  ciuser     = var.cloud_init_user
  cipassword = var.cloud_init_password
  sshkeys    = var.ssh_public_keys
  
  ipconfig0 = var.vm_ip_config
  
  # VM settings
  agent    = 1
  balloon  = 0
  bootdisk = "scsi0"
  
  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}
