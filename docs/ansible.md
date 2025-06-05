# Ansible Playbooks for Proxmox Template Creator

This section covers the Ansible automation integration with the Proxmox Template Creator, enabling automatic configuration management after template creation.

## Overview

The Proxmox Template Creator includes built-in Ansible integration that allows you to:

- Automatically run playbooks after template creation
- Dynamically discover and select playbooks
- Pass variables to playbooks via UI or CLI
- Manage inventory automatically

## Dynamic Playbook Discovery

- The main script (`create-template.sh`) automatically lists all playbooks in `ansible/playbooks/templates/` for user selection (UI and CLI)
- You can select one or more playbooks to run after template creation
- Playbooks are validated before execution

## Passing Variables

Variables can be passed to playbooks via the script:

- **UI Mode**: You will be prompted to enter key=value pairs during configuration
- **CLI Mode**: Use `--ansible-var key=value` (repeatable for multiple variables)

## Example Playbooks

The following example playbooks are included:

### Development Tools

- `install-development-tools.yml`: Installs common development tools (git, vim, curl, etc.)
- `install-docker.yml`: Installs Docker and Docker Compose
- `install-kubernetes-tools.yml`: Installs kubectl, helm, and other Kubernetes tools

### Infrastructure Tools

- `install-monitoring-tools.yml`: Installs monitoring agents (Prometheus node exporter, etc.)
- `configure-backups.yml`: Sets up automated backup routines
- `user-management.yml`: Manages users and SSH keys

### Security and Hardening

- `install-security-tools.yml`: Installs security tools and agents
- `system-hardening.yml`: Applies system hardening best practices
- `configure-firewall.yml`: Configures firewall rules

## Directory Structure

```
ansible/
├── README.md
├── playbooks/
│   ├── templates/
│   │   ├── install-development-tools.yml
│   │   ├── install-docker.yml
│   │   ├── install-kubernetes-tools.yml
│   │   ├── install-monitoring-tools.yml
│   │   ├── install-security-tools.yml
│   │   ├── user-management.yml
│   │   ├── configure-backups.yml
│   │   └── system-hardening.yml
│   └── roles/
│       ├── common/
│       ├── docker/
│       ├── kubernetes/
│       └── security/
├── inventory/
│   ├── group_vars/
│   ├── host_vars/
│   └── proxmox.yml
└── ansible.cfg
```

## Usage Examples

### Via UI

1. Run the template creator: `./create-template.sh`
2. Select your distribution and packages
3. In the automation menu, enable Ansible
4. Select playbooks from the discovered list
5. Enter any required variables when prompted

### Via CLI

```bash
# Create template with Ansible automation
./create-template.sh \
  --distro ubuntu-22.04 \
  --ansible-playbook install-development-tools.yml \
  --ansible-playbook install-docker.yml \
  --ansible-var docker_compose_version=2.21.0 \
  --ansible-var additional_user=devuser
```

### Manual Execution

After template creation, you can also run playbooks manually:

```bash
# Run a specific playbook
ansible-playbook -i /opt/ansible/inventory/proxmox.yml \
  playbooks/templates/install-development-tools.yml

# Run with extra variables
ansible-playbook -i /opt/ansible/inventory/proxmox.yml \
  playbooks/templates/install-docker.yml \
  -e "docker_compose_version=2.21.0"

# Run against specific hosts
ansible-playbook -i /opt/ansible/inventory/proxmox.yml \
  playbooks/templates/system-hardening.yml \
  --limit "ubuntu_servers"
```

## Configuration

### Ansible Configuration

The `ansible.cfg` file is automatically configured with optimal settings:

```ini
[defaults]
inventory = inventory/proxmox.yml
host_key_checking = False
stdout_callback = yaml
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_fact_cache
fact_caching_timeout = 86400

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
```

### Inventory Management

The script automatically generates Proxmox inventory with:

- Dynamic host discovery
- Group organization by template type
- Host variables for connection details

## Advanced Features

### Custom Playbook Development

Create your own playbooks in `ansible/playbooks/templates/`:

```yaml
---
- name: Custom Application Setup
  hosts: all
  become: yes
  vars:
    app_version: "{{ app_version | default('latest') }}"

  tasks:
    - name: Install custom application
      package:
        name: "myapp={{ app_version }}"
        state: present
```

### Integration with CI/CD

Playbooks can be integrated with CI/CD pipelines:

```yaml
# .github/workflows/ansible.yml
name: Ansible Playbook Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Test Ansible Playbooks
        run: |
          ansible-playbook --syntax-check ansible/playbooks/templates/*.yml
          ansible-lint ansible/playbooks/templates/
```

## Troubleshooting

### Common Issues

1. **Playbook not found**

   - Ensure playbooks are in `ansible/playbooks/templates/`
   - Check file permissions

2. **Connection failures**

   - Verify SSH connectivity to targets
   - Check inventory configuration

3. **Variable errors**
   - Validate variable syntax
   - Check required variables are defined

### Debug Mode

Enable debug output:

```bash
./create-template.sh --ansible-verbose
```

Or set environment variable:

```bash
export ANSIBLE_VERBOSITY=2
./create-template.sh
```

## See Also

- [Proxmox Template Creator Main Documentation](README.md)
- [Terraform Integration](terraform.md)
- [Contributing Guidelines](CONTRIBUTING.md)
