# Proxmox Terraform Example
# This is a minimal example. See the script's README for full details.

provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_user         = var.pm_user
  pm_password     = var.pm_password
  pm_tls_insecure = true
}

resource "proxmox_vm_qemu" "template_clone" {
  count       = var.vm_count
  name        = "${var.vm_name_prefix}${count.index + 1}"
  target_node = var.pm_target_node
  clone       = var.template_id
  cores       = var.cpu_cores
  memory      = var.memory_mb
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  agent       = 1
  os_type     = "cloud-init"
  disk {
    size    = var.disk_size
    type    = "scsi"
    storage = var.storage
  }
  network {
    bridge = var.network_bridge
    model  = "virtio"
  }
  ciuser     = var.cloud_user
  sshkeys    = file(var.ssh_key_path)
}
