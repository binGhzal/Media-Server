#!/usr/bin/env bash
parse_arguments() {
set -e
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                ;;
            --batch)
                BATCH_MODE=true
                ;;
            --dry-run)
                DRY_RUN=true
                log_info "Dry run mode enabled - no actual changes will be made"
                ;;
            --docker-template)
                shift
                DOCKER_INTEGRATION=true
                SELECTED_DOCKER_TEMPLATES=("$1")
                ;;
            --k8s-template)
                shift
                K8S_INTEGRATION=true
                SELECTED_K8S_TEMPLATES=("$1")
                ;;
            --config)
                shift
                CONFIG_FILE="$1"
                ;;
            --vmid)
                shift
                VMID_DEFAULT="$1"
                ;;
            --distro)
                shift
                SELECTED_DISTRIBUTION="$1"
                ;;
            --vm-name)
                shift
                VM_NAME="$1"
                ;;
            --cores)
                shift
                VM_CORES="$1"
                ;;
            --memory)
                shift
                VM_MEMORY="$1"
                ;;
            --disk-size)
                shift
                VM_DISK_SIZE="$1"
                ;;
            --storage)
                shift
                VM_STORAGE="$1"
                ;;
            --network-bridge)
                shift
                NETWORK_BRIDGE="$1"
                ;;
            --static-ip)
                shift
                STATIC_IP="$1"
                ;;
            --gateway)
                shift
                STATIC_GATEWAY="$1"
                ;;
            --dns)
                shift
                STATIC_DNS="$1"
                ;;
            --enable-ansible)
                ANSIBLE_ENABLED=true
                ;;
            --enable-terraform)
                TERRAFORM_ENABLED=true
                ;;
            --enable-docker)
                DOCKER_INTEGRATION=true
                ;;
            --enable-k8s)
                K8S_INTEGRATION=true
                ;;
            --log-level)
                shift
                LOG_LEVEL="$1"
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
