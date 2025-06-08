# Homelab Infrastructure - homelab Creator

Access the wiki by clicking this button:
[![GitBook](https://img.shields.io/badge/GitBook-%23000000.svg?style=for-the-badge&logo=gitbook&logoColor=white)](https://bizarreindustries.gitbook.io/homelab)

## Introduction

This repository contains the configuration files and scripts for setting up a comprehensive homelab environment. The infrastructure supports various applications and services including virtualization, container orchestration, monitoring, automation, and development tools.

## System Design & Architecture

The homelab Creator is a modular system designed to streamline the creation and management of VM templates in Proxmox environments. Each feature is implemented as a separate script for maximum flexibility and maintainability.

### System Overview

```ascii
                           ┌─────────────────────┐
                           │                     │
                           │   Main Controller   │
                           │     (main.sh)       │
                           │                     │
                           └─────────┬───────────┘
                                     │
         ┌─────────────┬─────────────┼─────────────┬─────────────┐
         │             │             │             │             │
┌────────▼─────────┐ ┌─▼───────────┐ ┌▼────────────┐ ┌──────────▼─────────┐
│                  │ │             │ │             │ │                     │
│ Template Creator │ │Docker/K8s   │ │ Terraform   │ │ Configuration       │
│ (template.sh)    │ │(containers.sh)│(terraform.sh)│ │ (config.sh)        │
│                  │ │             │ │             │ │                     │
└─────────┬────────┘ └──────┬──────┘ └───────┬─────┘ └─────────┬───────────┘
          │                 │                │                 │
          │                 │                │                 │
┌─────────▼────────────────▼────────────────▼─────────────────▼───────────┐
│                                                                         │
│                               Proxmox API                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Implementation Strategy

The system follows a modular architecture with each script focusing on a specific responsibility:

1. **Main Controller (`main.sh`)**:

   - Entry point for all operations
   - Orchestrates the workflow between modules
   - Provides unified CLI interface
   - Handles logging and error management

2. **Template Creator (`template.sh`)**:

   - Handles core VM template creation for 50+ Linux distributions
   - Manages hardware specifications and cloud-init integration
   - Implements tagging and categorization
   - Controls lifecycle of template creation

3. **Container Workloads (`containers.sh`)**:

   - Manages Docker and Kubernetes installations
   - Configures container runtimes and dependencies
   - Sets up container networking
   - Implements monitoring for containerized workloads

4. **Terraform Integration (`terraform.sh`)**:

   - Discovers and selects Terraform modules
   - Collects and validates variables
   - Generates configuration with modular architecture
   - Manages state and workspace outputs

5. **Configuration Manager (`config.sh`)**:

   - Handles settings persistence and retrieval
   - Manages import/export of configurations
   - Implements batch processing for multiple templates
   - Controls queue processing for template pipelines

6. **Monitoring Stack (`monitoring.sh`)**:

   - Sets up Prometheus, Grafana, Node Exporter
   - Configures alerts and dashboards
   - Implements metrics collection for all components
   - Provides visualization of system status

7. **Registry Manager (`registry.sh`)**:
   - Configures private container registry
   - Manages authentication and access control
   - Sets up SSL/TLS for secure communication
   - Implements storage backends

## Implementation Plan

### Phase 1: Core Infrastructure

1. **Develop Bootstrap Script**

   - Create lightweight bootstrap.sh for single-command installation
   - Implement dependency checking and installation
   - Build auto-update mechanism
   - Develop whiptail UI framework for all interfaces
   - Create root user verification and security checks

2. **Setup Core Template Creation**

   - Implement basic VM template creation functionality
   - Support for major Linux distributions
   - Basic hardware specification options
   - Simple cloud-init integration

3. **Build Configuration Framework**

   - Create settings system for storing configurations
   - Implement basic import/export functionality
   - Develop simple CLI interface
   - Set up configuration persistence mechanism

4. **Develop Testing Framework**
   - Create basic test script for core functions
   - Implement CI pipeline for automated testing
   - Build test cases for bootstrap process

### Phase 2: Container Workloads

1. **Docker Integration**

   - Implement Docker installation automation
   - Support for docker-compose workflows
   - Basic container deployment functionality

2. **Kubernetes Support**

   - Develop multi-node cluster deployment
   - Implement CNI plugins integration
   - Setup basic add-ons (cert-manager, ingress)

3. **Registry Implementation**
   - Create private registry functionality
   - Implement authentication and access control
   - Setup storage backends

### Phase 3: Infrastructure as Code

1. **Terraform Module Development**

   - Create basic framework for module selection
   - Develop container workload modules
   - Implement variable collection and validation

2. **Ansible Integration**
   - Implement playbook discovery
   - Create template configuration with Ansible
   - Develop inventory generation

### Phase 4: Advanced Features

1. **Batch Processing**

   - Implement queue processing for batch operations
   - Develop template queue functionality
   - Create batch automation tools

2. **Monitoring and Alerting**

   - Setup comprehensive monitoring stack
   - Develop alerts and notifications
   - Create visualization dashboards

3. **Documentation and Refinement**
   - Complete GitBook documentation
   - Optimize performance and error handling
   - Enhance security features

## Data Flow

### Bootstrap Process

```ascii
┌────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                │     │                 │     │                 │
│  Single curl   ├────►│  Bootstrap.sh   ├────►│  Dependencies   │
│    Command     │     │                 │     │  Installation   │
│                │     │                 │     │                 │
└────────────────┘     └────────┬────────┘     └────────┬────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐     ┌─────────────────┐
                       │                 │     │                 │
                       │  Clone/Update   │     │   Launch Main   │
                       │  Repository     │     │     Script      │
                       │                 │     │                 │
                       └─────────────────┘     └─────────────────┘
```

### Main Execution Flow

```ascii
┌────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                │     │                 │     │                 │
│  User Input    ├────►│ Main Controller ├────►│ Feature Module  │
│  (Whiptail UI) │     │   (main.sh)     │     │  (module.sh)    │
│                │     │                 │     │                 │
└────────────────┘     └────────┬────────┘     └────────┬────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐     ┌─────────────────┐
                       │                 │     │                 │
                       │  Configuration  │     │   Proxmox API   │
                       │   (config.sh)   │     │   Operations    │
                       │                 │     │                 │
                       └─────────────────┘     └─────────────────┘
```

## Feature Implementation Status

See the [Progress Tracker](docs/PROGRESS_TRACKER.md) for detailed implementation status of all features.

## Getting Started

The Proxmox Template Creator is designed to be extremely easy to use. Simply copy and paste the following command to get started:

```bash
curl -sSL https://raw.githubusercontent.com/binghzal/homelab/main/scripts/bootstrap.sh | sudo bash
```

This single command will:

1. Download the bootstrap script
2. Check for and install all required dependencies
3. Clone the repository to the appropriate location
4. Set up automatic updates
5. Launch the whiptail-based UI for easy navigation

### System Requirements

- Proxmox Virtual Environment 7.0 or higher (primary target)
- Any Linux distribution with bash shell (for development/testing)
- Root privileges (required for VM/container operations)
- Internet connection (for downloading distributions and updates)

### Dependencies

All dependencies are automatically installed by the bootstrap script, including:

- curl, wget
- whiptail
- qemu-guest-agent
- cloud-init
- docker (optional, for container features)
- terraform (optional, for infrastructure as code)

For detailed usage instructions, see the Documentation section below.

---

## Documentation

The project documentation is organized as follows:

1. **Getting Started Guide**

   - Basic setup and configuration
   - Quick start templates
   - Common workflows

2. **Feature Documentation**

   - Detailed usage for each module
   - Advanced configuration options
   - Integration examples

3. **API Reference**

   - Script interfaces and parameters
   - Configuration file formats
   - Return codes and error handling

4. **Troubleshooting**
   - Common issues and solutions
   - Diagnostic procedures
   - Support resources

## Development

### Directory Structure

```bash
/
├── scripts/               # Core scripts
│   ├── bootstrap.sh       # Bootstrap entry point (single curl command target)
│   ├── main.sh            # Main controller script
│   ├── template.sh        # Template creation module
│   ├── containers.sh      # Docker/K8s module
│   ├── terraform.sh       # Terraform integration
│   ├── config.sh          # Configuration manager
│   ├── monitoring.sh      # Monitoring stack setup
│   ├── update.sh          # Auto-update functionality
│   └── registry.sh        # Container registry management
│
├── modules/               # Feature modules
│   ├── template/          # Template creation resources
│   ├── containers/        # Container workload resources
│   ├── terraform/         # Terraform module resources
│   └── monitoring/        # Monitoring stack resources
│
├── config/                # Configuration files
│   ├── defaults.conf      # Default settings
│   ├── templates/         # Template configurations
│   └── examples/          # Example configurations
│
├── tests/                 # Test scripts and resources
│   ├── unit/              # Unit tests
│   ├── integration/       # Integration tests
│   └── fixtures/          # Test fixtures
│
└── docs/                  # Documentation
    ├── getting-started.md # Getting started guide
    ├── features/          # Feature documentation
    └── api/               # API documentation
```

### Development Workflow

1. **Branch Management**

   - `main`: Production-ready code
   - `develop`: Development branch
   - Feature branches: `feature/name-of-feature`
   - Fix branches: `fix/issue-description`

2. **Testing**

   - Run unit tests: `./tests/run_tests.sh unit`
   - Run integration tests: `./tests/run_tests.sh integration`
   - Run all tests: `./tests/run_tests.sh all`

3. **Contributing**
   - See [CONTRIBUTING.md](CONTRIBUTING.md) for details
   - Follow coding style guidelines
   - Submit pull requests against the `develop` branch

## Next Steps

1. **Bootstrap and Core Scripts Implementation**

   - Develop the bootstrap script for single-command installation
   - Implement the auto-update mechanism
   - Create the whiptail UI framework
   - Build the main controller script
   - Implement the basic template creation module
   - Develop the configuration manager

2. **Module Development**

   - Build container workload modules
   - Implement Terraform integration
   - Develop monitoring stack setup
   - Create the registry manager

3. **Testing and Documentation**
   - Create unit and integration tests
   - Complete documentation for all features
   - Develop usage examples and tutorials
   - Create troubleshooting guides for common issues

---

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Security

For security-related issues, please review our [Security Policy](SECURITY.md).

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Resources & References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Cloud-Init Documentation](https://cloud-init.readthedocs.io/)
- [Virt-customize Manual](https://libguestfs.org/virt-customize.1.html)
- [Christian Lempa's Boilerplates](https://github.com/christianlempa/boilerplates)

---

## Support

If you encounter issues or have questions:

1. Check the Troubleshooting section in the documentation
2. Review existing [GitHub Issues](../../issues)
3. Create a new issue with detailed information

### Enjoy your homelab journey! 🚀
