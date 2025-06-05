# Terraform Proxmox Example

This document describes the Terraform examples provided for deploying VMs from templates created with the Proxmox Template Creator.

## Usage

```sh
cd terraform
terraform init
terraform plan
terraform apply
```

## Variables

- See `variables.tf` for all configurable options.

## Dynamic Module/Script Discovery

- The main script (`create-template.sh`) will automatically list all `.tf` files in the terraform directory for user selection (UI and CLI).
- You can select one or more modules/scripts to apply after template creation.

## Passing Variables

- Variables can be passed to Terraform via the script:
  - UI: You will be prompted to enter key=value pairs.
  - CLI: Use `--terraform-var key=value` (repeatable).

## Example Infrastructure

The provided Terraform examples demonstrate:

1. VM deployment from templates
2. Network configuration
3. Resource allocation
4. Cloud-init customization

## Configuration Reference

The Terraform examples use the following variables:

| Variable             | Description                   | Default                          |
| -------------------- | ----------------------------- | -------------------------------- |
| `proxmox_url`        | Proxmox API endpoint URL      | https://localhost:8006/api2/json |
| `proxmox_node`       | Target Proxmox node           | pve                              |
| `template_name`      | Source template name to clone | template-ubuntu-2204             |
| `vm_name`            | Name for the new VM           | terraform-vm                     |
| `vm_cpu_cores`       | Number of CPU cores           | 2                                |
| `vm_memory_mb`       | Memory allocation in MB       | 2048                             |
| `vm_disk_gb`         | Disk size in GB               | 32                               |
| `vm_network_bridge`  | Network bridge to use         | vmbr0                            |
| `vm_ip_address`      | Static IP address (if used)   | dhcp                             |
| `vm_gateway`         | Network gateway               | none                             |
| `vm_ssh_public_keys` | SSH public keys to add        | none                             |

## Integration with Template Creator

The Proxmox Template Creator can:

1. Generate Terraform files based on your template configuration
2. Provide a selection interface for existing Terraform modules
3. Apply Terraform configurations after template creation

Refer to the [Proxmox Template Creator Guide](ProxmoxTemplateCreatorGuide.md) for detailed information on the integration process.
