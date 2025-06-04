# Proxmox Network Example
resource "proxmox_vm_qemu" "net_example" {
  name        = "net-example"
  target_node = var.pm_target_node
  clone       = var.template_id
  network {
    bridge = var.network_bridge
    model  = "virtio"
  }
}
