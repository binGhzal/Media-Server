variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmox username (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "target_node" {
  description = "Proxmox node name where VMs will be created"
  type        = string
}

variable "template_name" {
  description = "Name of the VM template to clone"
  type        = string
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
}

variable "vm_name_prefix" {
  description = "Prefix for VM names"
  type        = string
  default     = "vm"
}

variable "vm_cores" {
  description = "Number of CPU cores for each VM"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Amount of memory (MB) for each VM"
  type        = number
  default     = 2048
}

variable "vm_disk_size" {
  description = "Disk size for each VM (e.g., '20G')"
  type        = string
  default     = "20G"
}

variable "vm_storage" {
  description = "Storage pool name"
  type        = string
  default     = "local-lvm"
}

variable "vm_bridge" {
  description = "Network bridge name"
  type        = string
  default     = "vmbr0"
}

variable "vm_vlan_tag" {
  description = "VLAN tag (0 for no VLAN)"
  type        = number
  default     = 0
}

variable "cloud_init_user" {
  description = "Cloud-init username"
  type        = string
  default     = "ubuntu"
}

variable "cloud_init_password" {
  description = "Cloud-init password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_public_keys" {
  description = "SSH public keys for cloud-init"
  type        = string
  default     = ""
}

variable "vm_ip_config" {
  description = "IP configuration (e.g., 'ip=192.168.1.100/24,gw=192.168.1.1' or 'ip=dhcp')"
  type        = string
  default     = "ip=dhcp"
}
