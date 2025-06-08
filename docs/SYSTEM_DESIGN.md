# Proxmox Template Creator - System Design

## Table of Contents

- [System Overview](#system-overview)
- [Architecture](#architecture)
- [Bootstrap Process](#bootstrap-process)
- [Module Communication](#module-communication)
- [Configuration Management](#configuration-management)
- [Security Considerations](#security-considerations)
- [Error Handling](#error-handling)
- [User Interface](#user-interface)
- [Upgrade Paths](#upgrade-paths)
- [Performance Considerations](#performance-considerations)

## System Overview

The Proxmox Template Creator is a modular system designed for streamlined creation and management of VM templates in Proxmox environments. The system follows a single-command installation philosophy where users can get started with just one curl command, and the system handles everything else automatically.

### Core Design Principles

1. **Simplicity First**: Users should be able to get started with a single command
2. **Modularity**: Each feature is implemented as a separate script
3. **Self-Contained**: The system manages its own dependencies and updates
4. **User-Friendly**: Whiptail UI provides intuitive navigation for all operations
5. **Secure By Default**: Root user verification, secure defaults, and proper permission handling
6. **Resilient**: Comprehensive error handling and state management

## Architecture

### Component Overview

The system consists of the following key components:

```ascii
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                           Bootstrap Script                              │
│                         (Single curl target)                            │
│                                                                         │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                             Main Controller                             │
│                                                                         │
└───┬─────────────┬─────────────┬─────────────┬─────────────┬─────────────┘
    │             │             │             │             │
    ▼             ▼             ▼             ▼             ▼
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│         │   │         │   │         │   │         │   │         │
│Template │   │Container│   │Terraform│   │  Config │   │Monitoring│
│ Module  │   │ Module  │   │ Module  │   │ Module  │   │ Module   │
│         │   │         │   │         │   │         │   │         │
└────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘
     │             │             │             │             │
     ▼             ▼             ▼             ▼             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│                             Proxmox API                                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Core Components

1. **Bootstrap Script (`bootstrap.sh`)**

   - Entry point invoked by single curl command
   - Handles dependency management
   - Performs repository setup and configuration
   - Launches the main controller

2. **Main Controller (`main.sh`)**

   - Central coordination point
   - Handles module loading and lifecycle
   - Provides unified UI framework
   - Manages error handling and logging

3. **Feature Modules**
   - `template.sh`: VM template creation
   - `containers.sh`: Docker/K8s container workloads
   - `terraform.sh`: Infrastructure as Code integration
   - `config.sh`: Configuration management
   - `monitoring.sh`: Monitoring stack setup
   - `registry.sh`: Container registry management
   - `update.sh`: Auto-update functionality

## Bootstrap Process

The bootstrap process is designed to provide a seamless initial experience for users from a single curl command.

### Bootstrap Flow

```ascii
┌────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                │     │                 │     │                 │
│  Single curl   ├────►│  Root user and  ├────►│  Dependency     │
│    Command     │     │  OS verification│     │  Check & Install│
│                │     │                 │     │                 │
└────────────────┘     └────────┬────────┘     └────────┬────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐     ┌─────────────────┐
                       │                 │     │                 │
                       │  Repository     │     │   Config        │
                       │  Clone/Update   │     │   Setup         │
                       │                 │     │                 │
                       └────────┬────────┘     └────────┬────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐     ┌─────────────────┐
                       │                 │     │                 │
                       │  Proxmox        │     │   Launch        │
                       │  Detection      │     │   Main Script   │
                       │                 │     │                 │
                       └─────────────────┘     └─────────────────┘
```

### Implementation Details

1. **Initial Verification**

   - Check for root privileges using `id -u`
   - Verify operating system compatibility
   - Set up logging with timestamps and levels

2. **Dependency Management**

   - Check for essential dependencies: curl, git, whiptail, jq
   - Detect package manager (apt, yum, dnf, zypper)
   - Install missing dependencies automatically
   - Verify successful installation

3. **Repository Management**

   - Clone repository if not present
   - Update existing repository if already cloned
   - Set proper permissions on script files

4. **Configuration Setup**

   - Create configuration directories
   - Copy default configurations
   - Set secure permissions

5. **Proxmox Detection**

   - Check for Proxmox environment
   - Detect Proxmox version
   - Warn if not running in Proxmox

6. **Main Script Launch**
   - Make scripts executable
   - Launch main controller
   - Handle exit codes and errors

### Code Example: Root Privilege Check

```bash
# Check root privileges
check_root() {
    if [ $(id -u) -ne 0 ]; then
        echo "Error: This script must be run as root or with sudo."
        echo "Please run: sudo $0"
        exit 1
    fi

    log "INFO" "Running as root: OK"
}
```

## Module Communication

The modules communicate with each other through a well-defined API, ensuring loose coupling and easy extensibility.

### Communication Patterns

1. **Event-Driven Architecture**

   - Modules emit events on state changes
   - Main controller subscribes to module events
   - Events include detailed context data

2. **Standardized Return Values**

   - Consistent return code conventions across modules
   - Structured output formatting (JSON)
   - Error codes with descriptive messages

3. **Shared Configuration**
   - Modules access centralized configuration
   - Changes to configuration trigger notifications
   - Configuration locked during critical operations

### Module API Example

```bash
# Standard module execution function
module_execute() {
    local action=$1
    local params=$2
    local result_file=$(mktemp)

    # Execute requested action
    ${action}_handler "$params" > "$result_file"

    # Check result status
    local status=$(jq -r '.status' "$result_file")

    if [[ "$status" == "success" ]]; then
        # Return successful result
        cat "$result_file"
        rm "$result_file"
        return 0
    else
        # Log error and return failure
        local error_msg=$(jq -r '.error' "$result_file")
        log "ERROR" "Module execution failed: $error_msg"
        cat "$result_file"
        rm "$result_file"
        return 1
    fi
}
```

## Configuration Management

The configuration management system ensures that user settings are maintained across sessions and updates.

### Configuration Components

1. **Configuration Files**

   - System defaults: `/etc/homelab/defaults.conf`
   - User configuration: `/etc/homelab/user.conf`
   - Template definitions: `/etc/homelab/templates/*.conf`

2. **Configuration Format**

   - Simple key-value pairs for basic settings
   - JSON for complex structured data
   - Includes validation rules and schema

3. **Configuration Operations**
   - Load/save individual settings
   - Import/export complete configurations
   - Reset to defaults
   - Configuration validation

### Implementation Example

```bash
# Save a configuration value
save_config() {
    local key=$1
    local value=$2
    local config_file=$USER_CONFIG

    # Create config file if it doesn't exist
    if [ ! -f "$config_file" ]; then
        mkdir -p $(dirname "$config_file")
        touch "$config_file"
        # Set secure permissions
        chmod 640 "$config_file"
    fi

    # Check if key exists
    if grep -q "^$key=" "$config_file"; then
        # Update existing key
        sed -i "s|^$key=.*|$key=$value|" "$config_file"
    else
        # Add new key
        echo "$key=$value" >> "$config_file"
    fi
}
```

## Security Considerations

The system implements comprehensive security measures to ensure safe operation.

### Security Measures

1. **Authentication and Authorization**

   - Root privilege verification
   - Secure credential storage
   - Least privilege principle

2. **File Security**

   - Proper file permissions (640 for configs, 750 for scripts)
   - Secure temporary file handling
   - Validation of file content

3. **Network Security**

   - HTTPS for all external communications
   - Verification of downloaded content
   - Certificate validation

4. **Input Validation**
   - Sanitization of all user inputs
   - Parameter validation before execution
   - Protection against command injection

### Security Implementation Example

```bash
# Securely download a file with verification
secure_download() {
    local url=$1
    local output_file=$2
    local expected_hash=$3
    local hash_type=${4:-"sha256"}

    # Download file
    if ! curl -sSL --proto '=https' "$url" -o "$output_file"; then
        log "ERROR" "Failed to download $url"
        return 1
    fi

    # Verify file hash if provided
    if [ -n "$expected_hash" ]; then
        local file_hash

        case "$hash_type" in
            sha256)
                file_hash=$(sha256sum "$output_file" | cut -d ' ' -f 1)
                ;;
            sha512)
                file_hash=$(sha512sum "$output_file" | cut -d ' ' -f 1)
                ;;
            md5)
                file_hash=$(md5sum "$output_file" | cut -d ' ' -f 1)
                ;;
            *)
                log "ERROR" "Unsupported hash type: $hash_type"
                return 1
                ;;
        esac

        if [ "$file_hash" != "$expected_hash" ]; then
            log "ERROR" "Hash verification failed for $output_file"
            log "ERROR" "Expected: $expected_hash"
            log "ERROR" "Got: $file_hash"
            rm -f "$output_file"
            return 1
        fi

        log "INFO" "Hash verification passed for $output_file"
    fi

    return 0
}
```

## Error Handling

The system implements comprehensive error handling to ensure resilience and reliability.

### Error Handling Approach

1. **Graceful Failure**

   - Each operation checks for success
   - Clear error messages provided to users
   - Recovery attempts where possible

2. **Detailed Logging**

   - Structured log format with timestamps
   - Multiple log levels (INFO, WARN, ERROR, DEBUG)
   - Log rotation and management

3. **State Management**
   - Checkpoints during complex operations
   - Ability to resume from failure points
   - Rollback capabilities for critical operations

### Error Handling Example

```bash
# Execute a command with proper error handling
execute_with_retry() {
    local cmd=$1
    local description=$2
    local max_attempts=${3:-3}
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log "INFO" "Executing: $description (Attempt $attempt/$max_attempts)"

        # Execute command and capture output and exit code
        output=$(eval $cmd 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            log "INFO" "$description: Success"
            echo "$output"
            return 0
        else
            log "WARN" "$description: Failed (Exit code: $exit_code)"
            log "WARN" "Output: $output"

            # Increase attempt counter
            attempt=$((attempt + 1))

            if [ $attempt -le $max_attempts ]; then
                # Wait before retrying
                sleep 2
            fi
        fi
    done

    log "ERROR" "$description: All attempts failed"
    return 1
}
```

## User Interface

The user interface is built on whiptail to provide a consistent and user-friendly experience.

### UI Components

1. **Menu System**

   - Hierarchical menu structure
   - Consistent navigation patterns
   - Keyboard shortcuts

2. **Forms and Input**

   - Validated input fields
   - Default values with sensible presets
   - Error highlighting for invalid inputs

3. **Progress Indication**
   - Progress bars for long-running operations
   - Spinners for indeterminate operations
   - Elapsed time display

### UI Implementation Example

```bash
# Display a form for template creation
display_template_form() {
    # Get template name
    TEMPLATE_NAME=$(whiptail --title "Template Creation" --inputbox "Enter template name:" 8 78 "template-$(date +%Y%m%d)" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Validate template name
    if ! [[ "$TEMPLATE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        whiptail --title "Error" --msgbox "Invalid template name. Use only letters, numbers, underscores and hyphens." 8 78
        return 1
    fi

    # Get template parameters
    DISTRO=$(whiptail --title "Template Creation" --radiolist "Select distribution:" 16 78 8 \
        "ubuntu" "Ubuntu Server" ON \
        "debian" "Debian" OFF \
        "centos" "CentOS" OFF \
        "rocky" "Rocky Linux" OFF \
        "fedora" "Fedora" OFF \
        "alpine" "Alpine Linux" OFF 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Dynamic version selection based on distro
    case "$DISTRO" in
        ubuntu)
            VERSION=$(whiptail --title "Ubuntu Version" --radiolist "Select version:" 16 78 8 \
                "22.04" "Jammy Jellyfish (LTS)" ON \
                "20.04" "Focal Fossa (LTS)" OFF \
                "18.04" "Bionic Beaver (LTS)" OFF 3>&1 1>&2 2>&3)
            ;;
        debian)
            VERSION=$(whiptail --title "Debian Version" --radiolist "Select version:" 16 78 8 \
                "12" "Bookworm" ON \
                "11" "Bullseye" OFF \
                "10" "Buster" OFF 3>&1 1>&2 2>&3)
            ;;
        # Other distros...
    esac
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Return collected data as JSON
    echo "{\"template_name\": \"$TEMPLATE_NAME\", \"distro\": \"$DISTRO\", \"version\": \"$VERSION\"}"
    return 0
}
```

## Upgrade Paths

The system provides robust upgrade paths to ensure smooth updates and version transitions.

### Upgrade Components

1. **Version Management**

   - Semantic versioning for all components
   - Version compatibility checking
   - Gradual rollout of major changes

2. **Update Process**

   - Automatic update checking
   - Safe application of updates
   - Rollback capability if update fails

3. **Configuration Migration**
   - Schema versioning for configurations
   - Automatic migration of old formats
   - Preservation of user settings during upgrades

### Upgrade Implementation Example

```bash
# Check for available updates
check_updates() {
    log "INFO" "Checking for updates..."

    # Store current directory
    local current_dir=$(pwd)
    cd "$INSTALL_DIR"

    # Get current version
    local current_version=$(git describe --tags --always)

    # Fetch latest changes without applying them
    git fetch origin main --quiet

    # Get latest version
    local latest_version=$(git describe --tags --always origin/main)

    # Compare versions
    if [ "$current_version" != "$latest_version" ]; then
        log "INFO" "Update available: $current_version -> $latest_version"

        # Restore directory
        cd "$current_dir"

        # Return update available
        echo "{\"update_available\": true, \"current_version\": \"$current_version\", \"latest_version\": \"$latest_version\"}"
        return 0
    else
        log "INFO" "System is up to date: $current_version"

        # Restore directory
        cd "$current_dir"

        # Return no update
        echo "{\"update_available\": false, \"current_version\": \"$current_version\"}"
        return 0
    fi
}
```

## Performance Considerations

The system is designed with performance in mind to ensure efficient operation.

### Performance Optimizations

1. **Resource Management**

   - Efficient memory usage
   - Minimal CPU utilization
   - Optimized disk I/O

2. **Caching Mechanisms**

   - Cache downloaded ISO files
   - Cache package lists
   - Cache template configurations

3. **Asynchronous Operations**
   - Background processing for long operations
   - Progress reporting for async tasks
   - Job management and queuing

### Performance Implementation Example

```bash
# Download with caching
cached_download() {
    local url=$1
    local cache_dir=${2:-"/var/cache/homelab/downloads"}

    # Create URL hash for cache filename
    local url_hash=$(echo "$url" | md5sum | cut -d ' ' -f 1)
    local cache_file="$cache_dir/$url_hash"
    local meta_file="$cache_file.meta"

    # Create cache directory if it doesn't exist
    mkdir -p "$cache_dir"

    # Check if file is in cache and not too old
    if [ -f "$cache_file" ] && [ -f "$meta_file" ]; then
        local cache_date=$(cat "$meta_file" | jq -r '.timestamp')
        local current_date=$(date +%s)
        local max_age=$((86400 * 7))  # 7 days

        if [ $((current_date - cache_date)) -lt $max_age ]; then
            log "INFO" "Using cached file for $url"
            echo "$cache_file"
            return 0
        else
            log "INFO" "Cache expired for $url"
        fi
    fi

    # Download file
    log "INFO" "Downloading $url to cache"
    if curl -sSL --proto '=https' "$url" -o "$cache_file.tmp"; then
        mv "$cache_file.tmp" "$cache_file"
        echo "{\"url\": \"$url\", \"timestamp\": $(date +%s)}" > "$meta_file"
        echo "$cache_file"
        return 0
    else
        log "ERROR" "Failed to download $url"
        rm -f "$cache_file.tmp"
        return 1
    fi
}
```

---

## Implementation Update (2025-06-08)

- Main controller script (`main.sh`) and all module skeletons (`template.sh`, `containers.sh`, `terraform.sh`, `config.sh`, `monitoring.sh`, `registry.sh`, `update.sh`) have been created in the `scripts/` directory.
- The main controller launches a whiptail menu for module selection and will coordinate module execution.
- Next steps: Implement core logic for template creation and expand module functionality.

This document will be continuously updated as the system evolves and new features are implemented.

Last updated: June 8, 2025
