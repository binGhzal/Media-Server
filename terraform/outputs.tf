output "vm_ids" {
  value = [for vm in proxmox_vm_qemu.template_clone : vm.id]
}
