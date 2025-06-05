# Ansible Playbooks for Proxmox Template Creator

This document describes the Ansible playbooks provided for use with the Proxmox Template Creator automation workflow.

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

After template creation, you can run playbooks using the integration in the template creator script, or manually:

```bash
# Using template creator script
./create-template.sh --ansible-playbook install-docker.yml --ansible-var docker_version=latest

# Manually
ansible-playbook -i inventory/proxmox.yml playbooks/install-docker.yml -e "docker_version=latest"
```

## Creating Custom Playbooks

You can create custom playbooks to extend the functionality:

1. Create a new YAML file in the `ansible/playbooks/templates/` directory
2. Follow Ansible best practices for playbook structure
3. Document any required variables at the top of the playbook
4. The script will automatically discover and make your playbook available for selection

## Integration with Template Creator

The Proxmox Template Creator seamlessly integrates with these Ansible playbooks to:

1. Automatically create an inventory of newly created VMs/templates
2. Present a menu of available playbooks for selection
3. Prompt for any required variables
4. Apply selected playbooks to newly created templates

Refer to the [Proxmox Template Creator Guide](ProxmoxTemplateCreatorGuide.md) for detailed information on the integration process.
