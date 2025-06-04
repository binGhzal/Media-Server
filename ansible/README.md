# Ansible Playbooks for Proxmox Template Creator

This directory contains example Ansible playbooks for use with the Proxmox Template Creator automation workflow.

## Dynamic Playbook Discovery

- The main script (`create-template.sh`) will automatically list all playbooks in `ansible/playbooks/templates/` for user selection (UI and CLI).
- You can select one or more playbooks to run after template creation.

## Passing Variables

- Variables can be passed to playbooks via the script:
  - UI: You will be prompted to enter key=value pairs.
  - CLI: Use `--ansible-var key=value` (repeatable).

## Example Playbooks

- `install-development-tools.yml`: Installs common development tools.
- `install-docker.yml`: Installs Docker and dependencies.
- `install-kubernetes-tools.yml`: Installs Kubernetes tools.
- `install-monitoring-tools.yml`: Installs monitoring agents.
- `install-security-tools.yml`: Applies security hardening.
- `user-management.yml`: Manages users and SSH keys.
- `configure-backups.yml`: Sets up backup routines.
- `system-hardening.yml`: Applies system hardening best practices.

See each playbook for details and variable usage.

## Usage

After template creation, you can run playbooks like:

```sh
ansible-playbook -i /opt/ansible/inventory/proxmox.yml playbooks/templates/install-development-tools.yml
```

See the [Proxmox Template Creator documentation](../proxmox/README-create-template.md) for full details and integration steps.
