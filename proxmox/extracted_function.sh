#!/usr/bin/env bash
parse_arguments() {
set -e
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                ;;
            --batch)
                export BATCH_MODE=true
                ;;
            --dry-run)
                export DRY_RUN=true
                log_info "Dry run mode enabled - no actual changes will be made"
                ;;
            --docker-template)
                shift
                export DOCKER_INTEGRATION=true
                export SELECTED_DOCKER_TEMPLATES=("$1")
                ;;
            --k8s-template)
                shift
                export K8S_INTEGRATION=true
                export SELECTED_K8S_TEMPLATES=("$1")
                ;;
            --config)
                shift
                export CONFIG_FILE="$1"
                ;;
            --vmid)
                shift
                export VMID_DEFAULT="$1"
                ;;
            --distro)
                shift
                export SELECTED_DISTRIBUTION="$1"
                ;;
            --vm-name)
                shift
                export VM_NAME="$1"
                ;;
            --cores)
                shift
                export VM_CORES="$1"
                ;;
            --memory)
                shift
                export VM_MEMORY="$1"
                ;;
            --disk-size)
                shift
                export VM_DISK_SIZE="$1"
                ;;
            --storage)
                shift
                export VM_STORAGE="$1"
                ;;
            --network-bridge)
                shift
                export NETWORK_BRIDGE="$1"
                ;;
            --static-ip)
                shift
                export STATIC_IP="$1"
                ;;
            --gateway)
                shift
                export STATIC_GATEWAY="$1"
                ;;
            --dns)
                shift
                export STATIC_DNS="$1"
                ;;
            --enable-ansible)
                export ANSIBLE_ENABLED=true
                ;;
            --enable-terraform)
                export TERRAFORM_ENABLED=true
                ;;
            --enable-docker)
                export DOCKER_INTEGRATION=true
                ;;
            --enable-k8s)
                export K8S_INTEGRATION=true
                ;;
            --log-level)
                shift
                export LOG_LEVEL="$1"
                ;;
            --version)
                echo "Proxmox Template Creator v$SCRIPT_VERSION"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_warn "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                # Positional argument
                POSITIONAL_ARGS+=("$1")
                ;;
        esac
        shift
    done
}
