# Proxmox Storage Example
resource "proxmox_vm_qemu" "storage_example" {
  name        = "storage-example"
  target_node = var.pm_target_node
  clone       = var.template_id
  disk {
    size    = "50G"
    type    = "scsi"
    storage = var.storage
  }
}
