# Ansible Playbooks for Proxmox Template Creator

This directory contains example Ansible playbooks for use with the Proxmox Template Creator script's automation features.

## Example Playbooks

- `install-development-tools.yml`: Installs a suite of development tools
- `install-docker.yml`: Installs Docker and configures the system for container workloads
- `install-kubernetes-tools.yml`: Installs Kubernetes CLI tools (kubectl, helm, etc.)

## Usage

After template creation, you can run playbooks like:

```sh
ansible-playbook -i /opt/ansible/inventory/proxmox.yml playbooks/templates/install-development-tools.yml
```

See the [Proxmox Template Creator documentation](../proxmox/README-create-template.md) for full details and integration steps.
