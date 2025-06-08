# Proxmox VM Terraform Module

This module creates one or more VMs in Proxmox using a template.

## Usage

```hcl
module "proxmox_vms" {
  source = "./terraform/proxmox-vm"

  # Proxmox connection
  proxmox_api_url      = "https://proxmox.example.com:8006/api2/json"
  proxmox_user         = "root@pam"
  proxmox_password     = "your_password"
  proxmox_tls_insecure = true

  # VM configuration
  target_node    = "proxmox-node1"
  template_name  = "ubuntu-20-04-template"
  vm_count       = 3
  vm_name_prefix = "webserver"

  # VM resources
  vm_cores      = 2
  vm_memory     = 4096
  vm_disk_size  = "30G"
  vm_storage    = "local-lvm"

  # Network configuration
  vm_bridge    = "vmbr0"
  vm_vlan_tag  = 100
  vm_ip_config = "ip=dhcp"

  # Cloud-init configuration
  cloud_init_user     = "ubuntu"
  cloud_init_password = "secure_password"
  ssh_public_keys     = file("~/.ssh/id_rsa.pub")
}
```

## Requirements

- Terraform >= 1.0
- Proxmox provider >= 2.9
- Proxmox VE cluster with API access
- VM template with cloud-init support

## Inputs

| Name                | Description             | Type     | Default       | Required |
| ------------------- | ----------------------- | -------- | ------------- | :------: |
| proxmox_api_url     | Proxmox API URL         | `string` | n/a           |   yes    |
| proxmox_user        | Proxmox username        | `string` | `"root@pam"`  |    no    |
| proxmox_password    | Proxmox password        | `string` | n/a           |   yes    |
| target_node         | Proxmox node name       | `string` | n/a           |   yes    |
| template_name       | VM template to clone    | `string` | n/a           |   yes    |
| vm_count            | Number of VMs to create | `number` | `1`           |    no    |
| vm_name_prefix      | Prefix for VM names     | `string` | `"vm"`        |    no    |
| vm_cores            | CPU cores per VM        | `number` | `2`           |    no    |
| vm_memory           | Memory in MB per VM     | `number` | `2048`        |    no    |
| vm_disk_size        | Disk size per VM        | `string` | `"20G"`       |    no    |
| vm_storage          | Storage pool name       | `string` | `"local-lvm"` |    no    |
| vm_bridge           | Network bridge          | `string` | `"vmbr0"`     |    no    |
| vm_vlan_tag         | VLAN tag (0 for none)   | `number` | `0`           |    no    |
| cloud_init_user     | Cloud-init username     | `string` | `"ubuntu"`    |    no    |
| cloud_init_password | Cloud-init password     | `string` | `""`          |    no    |
| ssh_public_keys     | SSH public keys         | `string` | `""`          |    no    |
| vm_ip_config        | IP configuration        | `string` | `"ip=dhcp"`   |    no    |

## Outputs

| Name     | Description          |
| -------- | -------------------- |
| vm_names | Names of created VMs |
| vm_ips   | IP addresses of VMs  |
| vm_ids   | Proxmox VM IDs       |
