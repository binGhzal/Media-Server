# CLI Guide

The Proxmox Template Creator provides comprehensive command-line interface support for automation and scripting.

## Usage Syntax

```bash
./create-template.sh [OPTIONS]
```

## Basic Options

### Template Creation

- `--distribution DISTRO` - Specify distribution to use
- `--template-name NAME` - Set template name
- `--vmid ID` - Set VM ID (default: auto-assign)
- `--packages PACKAGES` - Comma-separated package list

### Container Templates

- `--docker-template TEMPLATE` - Use Docker template
- `--k8s-template TEMPLATE` - Use Kubernetes template

### Operation Modes

- `--dry-run` - Preview operations without executing
- `--batch` - Run in non-interactive batch mode
- `--help` - Show help message

### Configuration

- `--config FILE` - Load configuration from file
- `--export-config FILE` - Export current config to file

## Examples

### Basic Template Creation

```bash
# Create Ubuntu 22.04 template with development tools
./create-template.sh \
  --distribution ubuntu-22.04 \
  --template-name ubuntu-dev \
  --packages "development,docker,kubernetes"

# Create minimal Alpine template
./create-template.sh \
  --distribution alpine-3.18 \
  --template-name alpine-minimal \
  --packages "essential"
```

### Docker Integration

```bash
# Create template with Docker web server stack
./create-template.sh \
  --docker-template web-server \
  --template-name docker-web

# Create template with monitoring stack
./create-template.sh \
  --docker-template monitoring \
  --template-name docker-monitoring
```

### Kubernetes Integration

```bash
# Create Kubernetes worker node template
./create-template.sh \
  --k8s-template worker-node \
  --template-name k8s-worker

# Create Kubernetes control plane template
./create-template.sh \
  --k8s-template control-plane \
  --template-name k8s-control
```

### Batch Processing

```bash
# Use configuration file for batch processing
./create-template.sh \
  --batch \
  --config /path/to/config.conf

# Dry run to preview operations
./create-template.sh \
  --batch \
  --config /path/to/config.conf \
  --dry-run
```

## Advanced CLI Usage

### Environment Variables

Set these environment variables to override defaults:

```bash
export PROXMOX_STORAGE="local-lvm"
export PROXMOX_BRIDGE="vmbr0"
export TEMPLATE_DEFAULT_CORES="2"
export TEMPLATE_DEFAULT_MEMORY="2048"
```

### Scripting Integration

```bash
#!/bin/bash
# Example automation script

# Create multiple templates
for distro in ubuntu-22.04 debian-12 rocky-9; do
  ./create-template.sh \
    --distribution "$distro" \
    --template-name "${distro}-base" \
    --packages "essential,development" \
    --batch
done
```

### Output Parsing

The CLI provides structured output for automation:

```bash
# JSON output mode (if implemented)
./create-template.sh --output json --dry-run

# Filter specific information
./create-template.sh --list-templates | grep ubuntu
```

## Error Handling

### Exit Codes

- `0` - Success
- `1` - General error
- `2` - Invalid parameters
- `3` - Missing dependencies
- `4` - Insufficient permissions

### Error Messages

All error messages are written to stderr, while normal output goes to stdout.

```bash
# Redirect errors to log file
./create-template.sh --batch 2>error.log

# Capture both output and errors
./create-template.sh --batch >output.log 2>&1
```

## Integration Examples

### CI/CD Pipeline

```yaml
# GitHub Actions example
- name: Create VM Template
  run: |
    ./create-template.sh \
      --distribution ubuntu-22.04 \
      --template-name ci-runner \
      --packages "development,docker" \
      --batch
```

### Ansible Playbook

```yaml
- name: Create Proxmox Templates
  command: >
    ./create-template.sh
    --distribution {{ item.distro }}
    --template-name {{ item.name }}
    --packages {{ item.packages }}
    --batch
  loop:
    - { distro: "ubuntu-22.04", name: "ubuntu-web", packages: "web-server" }
    - { distro: "debian-12", name: "debian-db", packages: "database" }
```

For more detailed parameter descriptions, see [CLI Parameters](cli-parameters.md).
