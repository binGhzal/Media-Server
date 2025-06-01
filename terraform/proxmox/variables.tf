terraform {
  required_version = ">= 0.13.0"

  required_providers {
    proxmox = {
      # LINK https://github.com/Telmate/terraform-provider-proxmox
      source  = "telmate/proxmox"
      version = "3.0.1-rc9"
    }
  }
}

variable "pm_api_url" {
  type = string
}

variable "pm_api_token_id" {
  type = string
}

variable "pm_api_token_secret" {
  type      = string
  sensitive = true
}

variable "node_name" {
  type    = string
  default = "your-proxmox-node"
}

variable "vm_count" {
  type    = number
  default = 1
}

variable "template_id" {
  type    = number
  default = 2000
}

variable "cpu_cores" {
  type    = number
  default = 1
}

variable "cpu_sockets" {
  type    = number
  default = 1
}

variable "memory_size" {
  type    = number
  default = 2048
}

variable "balloon_size" {
  type    = number
  default = 2048
}

variable "cloud_init_password" {
  type      = string
  sensitive = true
}
variable "public_ssh_key" {
  type      = string
  sensitive = true
}
variable "cloud_init_user" {
  type    = string
  default = "ubuntu"
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

provider "proxmox" {
  pm_api_url          = var.pm_api_url
  pm_api_token_id     = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_tls_insecure     = true
}
