output "vm_names" {
  description = "Names of the created VMs"
  value       = proxmox_vm_qemu.vm[*].name
}

output "vm_ips" {
  description = "IP addresses of the created VMs"
  value       = proxmox_vm_qemu.vm[*].default_ipv4_address
}

output "vm_ids" {
  description = "VM IDs in Proxmox"
  value       = proxmox_vm_qemu.vm[*].vmid
}
