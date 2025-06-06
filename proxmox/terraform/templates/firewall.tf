# Proxmox Firewall Example
resource "proxmox_firewall_vm" "fw_example" {
  vmid   = proxmox_vm_qemu.template_clone[0].id
  enable = true
  rules {
    type   = "in"
    action = "accept"
    macro  = "ssh"
  }
}
