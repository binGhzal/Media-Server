variable "pm_api_url" {}
variable "pm_user" {}
variable "pm_password" {}
variable "pm_target_node" {}
variable "template_id" {}
variable "vm_count" { default = 1 }
variable "vm_name_prefix" { default = "template-" }
variable "cpu_cores" { default = 2 }
variable "memory_mb" { default = 2048 }
variable "disk_size" { default = "20G" }
variable "storage" { default = "local-lvm" }
variable "network_bridge" { default = "vmbr0" }
variable "cloud_user" { default = "ubuntu" }
variable "ssh_key_path" { default = "~/.ssh/id_rsa.pub" }
