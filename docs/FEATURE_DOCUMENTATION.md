# Proxmox Template Creator - Feature Documentation

This document provides detailed information about each feature of the Proxmox Template Creator script.

## Core Features

- Interactive Whiptail UI: Guided configuration for distributions, packages, networking, and more.
- 50+ Linux Distributions & BSD Support: Auto-discovery of cloud images and package managers.
- 150+ Pre-defined Packages: Organized in 16 categories with simple and complex install options.
- Custom ISO/Image Support: Prompt for URL or local path; supports qcow2, raw, iso.
- Network Configuration: DHCP, Static IP, VLAN tagging, custom bridge.
- Batch Queue: Add multiple template configurations and process in sequence.
- Configuration Export/Import: Save and load template settings via `.conf` files.
- Comprehensive Logging: Timestamped logs with rotation and cleanup.

## Automation Integrations

### Ansible

- Dynamic Playbook Discovery: Lists all `*.yml` in `ansible/playbooks/templates/`.
- UI Checklist & CLI Flags (`--ansible-playbook`): Select playbooks interactively or via `--ansible-playbook pb1,pb2`.
- Variable Support: Prompt for `key=value` pairs in UI or `--ansible-var key=val` flags.
- Execution on VMs Only: Runs playbooks against cloned VMs after template deployment.

### Terraform

- Module Discovery: Lists all `*.tf` files in the `terraform/` folder.
- UI Checklist & CLI Flags (`--terraform-module`): Select modules via UI or `--terraform-module mod1,mod2`.
- Variable Support: Prompt for `key=value` pairs or `--terraform-var key=val` flags.
- Deployment on Templates Only: Applies Terraform after converting VM to template to deploy VMs.

## Advanced Features

- Cloud-init Integration: Automatic user setup and SSH key injection.
- Hardware Templates: Pre-set CPU, memory, disk, BIOS/QEMU options.
- Error Recovery: Retry logic and cleanup on failure.
- Monitoring & Health Checks: Optional installation of monitoring agents and post-creation checks.

## Command-Line Usage Examples

```bash
# Interactive mode (default)
./create-template.sh

# CLI mode with Ansible and Terraform
echo "user=admin,env=dev" > vars.list
./create-template.sh \
  --distribution ubuntu-22.04 \
  --name "ubuntu-dev-template" \
  --vmid 9000 \
  --cores 2 --memory 4096 --disk-size 32G \
  --ansible --ansible-playbook install-docker.yml,system-hardening.yml \
  --ansible-var user=devops \
  --terraform --terraform-module main.tf,network.tf \
  --terraform-var vm_count=2
```
