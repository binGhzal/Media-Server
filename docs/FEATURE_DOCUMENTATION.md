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

## Planned Features

- Auto-build Docker container templates under `docker/`
- Auto-generate Kubernetes VM templates under `kubernetes/`
- SSH bastion setup for template enrollment
- Template publishing to private registry

## Docker & Kubernetes Templates

- Docker Template Discovery: Lists all files in `docker/templates/` folder with `list_docker_templates()`.
- UI Radiolist & CLI Flags (`--docker-template`): Select a Docker template interactively or via `--docker-template name1,name2`.
- Kubernetes Template Discovery: Lists all files in `kubernetes/templates/` folder with `list_k8s_templates()`.
- UI Radiolist & CLI Flags (`--k8s-template`): Select a Kubernetes template interactively or via `--k8s-template name1,name2`.

## Quick Start

1. **Download the Repository:**

   ```bash
   wget https://github.com/binghzal/homelab/archive/main.zip
   unzip main.zip
   cd homelab-main/proxmox
   ```

2. **Run the Script (as root):**

   ```bash
   chmod +x create-template.sh
   ./create-template.sh
   ```
