# Terraform Proxmox Example

This directory contains a minimal example for deploying VMs from a template using the Proxmox Terraform provider. See the main Proxmox Template Creator documentation for full details and advanced usage.

## Usage

```sh
cd terraform
terraform init
terraform plan
terraform apply
```

## Variables

- See `variables.tf` for all configurable options.

## Reference

- [Proxmox Template Creator Documentation](../proxmox/README-create-template.md)

# Terraform Modules for Proxmox Template Creator

This directory contains example Terraform modules and scripts for use with the Proxmox Template Creator automation workflow.

## Dynamic Module/Script Discovery

- The main script (`create-template.sh`) will automatically list all `.tf` files in this directory for user selection (UI and CLI).
- You can select one or more modules/scripts to apply after template creation.

## Passing Variables

- Variables can be passed to Terraform via the script:
  - UI: You will be prompted to enter key=value pairs.
  - CLI: Use `--terraform-var key=value` (repeatable).

## Example Modules/Scripts

- `main.tf`: Main VM provisioning logic.
- `firewall.tf`: Firewall rules and security groups.
- `network.tf`: Network and subnet configuration.
- `storage.tf`: Storage and disk resources.
- `user.tf`: User and SSH key management.
- `variables.tf`: Variable definitions.
- `outputs.tf`: Output values.
- `providers.tf`: Provider configuration.

See each module/script for details and variable usage.
