#!/bin/bash
# Test Utilities for Homelab Project
# Specialized testing functions for different module types
# Supports Docker/Kubernetes, Terraform, Ansible, monitoring, security, and performance testing

set -euo pipefail

# === Configuration ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source logging if available
if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
    export LOG_FILE_ALREADY_SET_EXTERNALLY="${LOG_FILE_ALREADY_SET_EXTERNALLY:-false}"
    if [[ "$LOG_FILE_ALREADY_SET_EXTERNALLY" != "true" ]]; then
        export LOG_FILE="/tmp/test_utilities_$(date +%Y%m%d_%H%M%S).log"
    fi
    source "${SCRIPT_DIR}/lib/logging.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_debug() { [[ "${HL_LOG_LEVEL:-INFO}" == "DEBUG" ]] && echo "[DEBUG] $*"; }
fi

# === Docker and Container Testing Utilities ===

test_docker_functionality() {
    local test_name="$1"
    local container_script="${2:-${SCRIPT_DIR}/containers.sh}"
    
    log_info "Testing Docker functionality: $test_name"
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker not available, skipping Docker tests"
        return 2  # Skip
    fi
    
    # Test Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker daemon not running, skipping Docker tests"
        return 2  # Skip
    fi
    
    # Test container script functionality
    if [[ -f "$container_script" ]]; then
        # Test script syntax
        if bash -n "$container_script"; then
            log_info "✅ Container script syntax valid"
        else
            log_error "❌ Container script syntax error"
            return 1
        fi
        
        # Test container script help/info
        if timeout 10 bash "$container_script" --help >/dev/null 2>&1; then
            log_info "✅ Container script responds to help"
        else
            log_warn "⚠️ Container script may not have help functionality"
        fi
        
        return 0
    else
        log_warn "Container script not found: $container_script"
        return 2  # Skip
    fi
}

test_kubernetes_functionality() {
    local test_name="$1"
    local config_path="${2:-}"
    
    log_info "Testing Kubernetes functionality: $test_name"
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log_warn "kubectl not available, skipping Kubernetes tests"
        return 2  # Skip
    fi
    
    # Test cluster connectivity
    local kubectl_cmd="kubectl"
    if [[ -n "$config_path" ]]; then
        kubectl_cmd="kubectl --kubeconfig=$config_path"
    fi
    
    if timeout 10 $kubectl_cmd cluster-info >/dev/null 2>&1; then
        log_info "✅ Kubernetes cluster accessible"
        
        # Test basic operations
        if timeout 10 $kubectl_cmd get nodes >/dev/null 2>&1; then
            log_info "✅ Can list Kubernetes nodes"
        else
            log_warn "⚠️ Cannot list Kubernetes nodes"
        fi
        
        return 0
    else
        log_warn "Kubernetes cluster not accessible, skipping cluster tests"
        return 2  # Skip
    fi
}

test_container_workload() {
    local workload_name="$1"
    local image_name="$2"
    local timeout_seconds="${3:-30}"
    
    log_info "Testing container workload: $workload_name"
    
    # Test container can be pulled
    if timeout "$timeout_seconds" docker pull "$image_name" >/dev/null 2>&1; then
        log_info "✅ Container image pulled successfully: $image_name"
    else
        log_warn "⚠️ Could not pull container image: $image_name"
        return 1
    fi
    
    # Test container can be started
    local container_id
    if container_id=$(docker run -d --name "test_${workload_name}_$$" "$image_name" sleep 60 2>/dev/null); then
        log_info "✅ Container started successfully: $container_id"
        
        # Test container is running
        if docker ps --filter "id=$container_id" --filter "status=running" | grep -q "$container_id"; then
            log_info "✅ Container is running"
        else
            log_error "❌ Container not running"
        fi
        
        # Cleanup
        docker stop "$container_id" >/dev/null 2>&1 || true
        docker rm "$container_id" >/dev/null 2>&1 || true
        
        return 0
    else
        log_error "❌ Could not start container: $image_name"
        return 1
    fi
}

# === Terraform Testing Utilities ===

test_terraform_functionality() {
    local test_name="$1"
    local terraform_dir="${2:-}"
    
    log_info "Testing Terraform functionality: $test_name"
    
    # Check if Terraform is available
    if ! command -v terraform >/dev/null 2>&1; then
        log_warn "Terraform not available, skipping Terraform tests"
        return 2  # Skip
    fi
    
    # Test Terraform version
    local tf_version
    if tf_version=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4); then
        log_info "✅ Terraform version: $tf_version"
    else
        log_warn "⚠️ Could not determine Terraform version"
    fi
    
    # Test Terraform configuration if directory provided
    if [[ -n "$terraform_dir" && -d "$terraform_dir" ]]; then
        pushd "$terraform_dir" >/dev/null || return 1
        
        # Test configuration validation
        if terraform init -backend=false >/dev/null 2>&1; then
            log_info "✅ Terraform init successful"
            
            if terraform validate >/dev/null 2>&1; then
                log_info "✅ Terraform configuration valid"
            else
                log_error "❌ Terraform configuration invalid"
                popd >/dev/null
                return 1
            fi
        else
            log_error "❌ Terraform init failed"
            popd >/dev/null
            return 1
        fi
        
        # Test plan generation (dry run)
        if terraform plan -out=/tmp/test.tfplan >/dev/null 2>&1; then
            log_info "✅ Terraform plan generation successful"
            rm -f /tmp/test.tfplan
        else
            log_warn "⚠️ Terraform plan generation failed"
        fi
        
        popd >/dev/null
    fi
    
    return 0
}

test_terraform_module() {
    local module_path="$1"
    local module_name="${2:-$(basename "$module_path")}"
    
    log_info "Testing Terraform module: $module_name"
    
    if [[ ! -d "$module_path" ]]; then
        log_error "❌ Terraform module directory not found: $module_path"
        return 1
    fi
    
    # Check for required Terraform files
    local has_main=false
    local has_variables=false
    local has_outputs=false
    
    [[ -f "$module_path/main.tf" ]] && has_main=true
    [[ -f "$module_path/variables.tf" ]] && has_variables=true
    [[ -f "$module_path/outputs.tf" ]] && has_outputs=true
    
    if [[ "$has_main" == true ]]; then
        log_info "✅ main.tf found"
    else
        log_warn "⚠️ main.tf not found"
    fi
    
    if [[ "$has_variables" == true ]]; then
        log_info "✅ variables.tf found"
    else
        log_warn "⚠️ variables.tf not found"
    fi
    
    if [[ "$has_outputs" == true ]]; then
        log_info "✅ outputs.tf found"
    else
        log_warn "⚠️ outputs.tf not found"
    fi
    
    # Test module syntax
    pushd "$module_path" >/dev/null || return 1
    
    if terraform fmt -check >/dev/null 2>&1; then
        log_info "✅ Terraform formatting correct"
    else
        log_warn "⚠️ Terraform formatting issues found"
    fi
    
    popd >/dev/null
    return 0
}

# === Ansible Testing Utilities ===

test_ansible_functionality() {
    local test_name="$1"
    local playbook_path="${2:-}"
    
    log_info "Testing Ansible functionality: $test_name"
    
    # Check if Ansible is available
    if ! command -v ansible >/dev/null 2>&1; then
        log_warn "Ansible not available, skipping Ansible tests"
        return 2  # Skip
    fi
    
    # Test Ansible version
    local ansible_version
    if ansible_version=$(ansible --version | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+'); then
        log_info "✅ Ansible version: $ansible_version"
    else
        log_warn "⚠️ Could not determine Ansible version"
    fi
    
    # Test playbook syntax if provided
    if [[ -n "$playbook_path" && -f "$playbook_path" ]]; then
        if ansible-playbook --syntax-check "$playbook_path" >/dev/null 2>&1; then
            log_info "✅ Ansible playbook syntax valid: $playbook_path"
        else
            log_error "❌ Ansible playbook syntax invalid: $playbook_path"
            return 1
        fi
        
        # Test playbook dry run
        if ansible-playbook --check "$playbook_path" >/dev/null 2>&1; then
            log_info "✅ Ansible playbook dry run successful"
        else
            log_warn "⚠️ Ansible playbook dry run failed"
        fi
    fi
    
    return 0
}

test_ansible_inventory() {
    local inventory_path="$1"
    local inventory_name="${2:-$(basename "$inventory_path")}"
    
    log_info "Testing Ansible inventory: $inventory_name"
    
    if [[ ! -f "$inventory_path" ]]; then
        log_error "❌ Ansible inventory file not found: $inventory_path"
        return 1
    fi
    
    # Test inventory syntax
    if ansible-inventory -i "$inventory_path" --list >/dev/null 2>&1; then
        log_info "✅ Ansible inventory syntax valid"
        
        # Get host count
        local host_count
        if host_count=$(ansible-inventory -i "$inventory_path" --list | grep -c '"" :' 2>/dev/null || echo "0"); then
            log_info "✅ Inventory contains $host_count hosts"
        fi
    else
        log_error "❌ Ansible inventory syntax invalid"
        return 1
    fi
    
    return 0
}

# === Monitoring Testing Utilities ===

test_monitoring_stack() {
    local stack_name="$1"
    local prometheus_url="${2:-http://localhost:9090}"
    local grafana_url="${3:-http://localhost:3000}"
    
    log_info "Testing monitoring stack: $stack_name"
    
    # Test Prometheus connectivity
    if command -v curl >/dev/null 2>&1; then
        if curl -s -o /dev/null -w "%{http_code}" "$prometheus_url" | grep -q "200"; then
            log_info "✅ Prometheus accessible at $prometheus_url"
            
            # Test Prometheus targets
            if curl -s "$prometheus_url/api/v1/targets" | grep -q "targets"; then
                log_info "✅ Prometheus targets API responding"
            else
                log_warn "⚠️ Prometheus targets API not responding"
            fi
        else
            log_warn "⚠️ Prometheus not accessible at $prometheus_url"
        fi
        
        # Test Grafana connectivity
        if curl -s -o /dev/null -w "%{http_code}" "$grafana_url" | grep -q "200"; then
            log_info "✅ Grafana accessible at $grafana_url"
        else
            log_warn "⚠️ Grafana not accessible at $grafana_url"
        fi
    else
        log_warn "curl not available, skipping HTTP connectivity tests"
    fi
    
    return 0
}

test_metrics_collection() {
    local service_name="$1"
    local metrics_endpoint="${2:-http://localhost:9100/metrics}"
    
    log_info "Testing metrics collection for: $service_name"
    
    if command -v curl >/dev/null 2>&1; then
        local metrics_output
        if metrics_output=$(curl -s "$metrics_endpoint" 2>/dev/null); then
            # Check for common metrics
            local metric_count
            metric_count=$(echo "$metrics_output" | grep -c "^[a-zA-Z]" || echo "0")
            
            if [[ $metric_count -gt 0 ]]; then
                log_info "✅ Metrics endpoint responding with $metric_count metrics"
            else
                log_warn "⚠️ Metrics endpoint not returning valid metrics"
            fi
        else
            log_warn "⚠️ Could not connect to metrics endpoint: $metrics_endpoint"
        fi
    else
        log_warn "curl not available, skipping metrics tests"
    fi
    
    return 0
}

# === Security Testing Utilities ===

test_security_hardening() {
    local target_name="$1"
    local target_path="${2:-$SCRIPT_DIR}"
    
    log_info "Testing security hardening for: $target_name"
    
    # Test file permissions
    local permission_issues=0
    
    while IFS= read -r -d '' file; do
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
        
        # Check for overly permissive files
        if [[ "$perms" =~ ^[0-7][0-7][7-9]$ ]]; then
            log_warn "⚠️ Potentially insecure permissions: $file ($perms)"
            ((permission_issues++))
        fi
    done < <(find "$target_path" -type f -name "*.sh" -print0 2>/dev/null)
    
    if [[ $permission_issues -eq 0 ]]; then
        log_info "✅ No permission issues found"
    else
        log_warn "⚠️ Found $permission_issues permission issues"
    fi
    
    # Test for hardcoded secrets
    test_credential_security "$target_path"
    
    return 0
}

test_credential_security() {
    local search_path="$1"
    
    log_info "Testing credential security in: $search_path"
    
    local credential_patterns=(
        "password.*="
        "passwd.*="
        "secret.*="
        "api_key.*="
        "private_key.*="
        "token.*="
    )
    
    local issues_found=0
    
    for pattern in "${credential_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            if grep -iE "$pattern" "$file" | grep -v "^\s*#" >/dev/null 2>&1; then
                log_warn "⚠️ Potential credential found in $file (pattern: $pattern)"
                ((issues_found++))
            fi
        done < <(find "$search_path" -name "*.sh" -o -name "*.conf" -o -name "*.cfg" | head -20 | tr '\n' '\0')
    done
    
    if [[ $issues_found -eq 0 ]]; then
        log_info "✅ No hardcoded credentials detected"
    else
        log_warn "⚠️ Found $issues_found potential credential issues"
    fi
    
    return 0
}

test_network_security() {
    local service_name="$1"
    local host="${2:-localhost}"
    local port="${3:-22}"
    
    log_info "Testing network security for: $service_name"
    
    # Test port accessibility
    if command -v nc >/dev/null 2>&1; then
        if timeout 5 nc -z "$host" "$port" >/dev/null 2>&1; then
            log_info "✅ Port $port accessible on $host"
        else
            log_warn "⚠️ Port $port not accessible on $host"
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout 5 telnet "$host" "$port" </dev/null >/dev/null 2>&1; then
            log_info "✅ Port $port accessible on $host"
        else
            log_warn "⚠️ Port $port not accessible on $host"
        fi
    else
        log_warn "Neither nc nor telnet available for network testing"
    fi
    
    return 0
}

# === Performance Testing Utilities ===

test_performance_benchmark() {
    local test_name="$1"
    local command_to_test="$2"
    local max_time_seconds="${3:-10}"
    local iterations="${4:-1}"
    
    log_info "Running performance benchmark: $test_name"
    
    local total_time=0
    local successful_runs=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time
        start_time=$(date +%s.%N)
        
        if eval "$command_to_test" >/dev/null 2>&1; then
            local end_time
            end_time=$(date +%s.%N)
            local execution_time
            execution_time=$(echo "$end_time - $start_time" | bc -l)
            
            total_time=$(echo "$total_time + $execution_time" | bc -l)
            ((successful_runs++))
            
            log_debug "Iteration $i: ${execution_time}s"
        else
            log_warn "⚠️ Iteration $i failed"
        fi
    done
    
    if [[ $successful_runs -gt 0 ]]; then
        local average_time
        average_time=$(echo "scale=3; $total_time / $successful_runs" | bc -l)
        
        log_info "✅ Performance benchmark completed:"
        log_info "   Average time: ${average_time}s"
        log_info "   Successful runs: $successful_runs/$iterations"
        
        # Check against threshold
        if (( $(echo "$average_time <= $max_time_seconds" | bc -l) )); then
            log_info "✅ Performance within threshold (${average_time}s <= ${max_time_seconds}s)"
            return 0
        else
            log_warn "⚠️ Performance exceeds threshold (${average_time}s > ${max_time_seconds}s)"
            return 1
        fi
    else
        log_error "❌ All benchmark iterations failed"
        return 1
    fi
}

test_memory_usage() {
    local test_name="$1"
    local command_to_test="$2"
    local max_memory_mb="${3:-100}"
    
    log_info "Testing memory usage: $test_name"
    
    # Start monitoring memory usage
    local initial_memory
    initial_memory=$(free -m | awk 'NR==2{print $3}')
    
    # Execute command
    if eval "$command_to_test" >/dev/null 2>&1; then
        local final_memory
        final_memory=$(free -m | awk 'NR==2{print $3}')
        
        local memory_used
        memory_used=$((final_memory - initial_memory))
        
        log_info "✅ Memory usage test completed:"
        log_info "   Memory used: ${memory_used}MB"
        
        if [[ $memory_used -le $max_memory_mb ]]; then
            log_info "✅ Memory usage within threshold (${memory_used}MB <= ${max_memory_mb}MB)"
            return 0
        else
            log_warn "⚠️ Memory usage exceeds threshold (${memory_used}MB > ${max_memory_mb}MB)"
            return 1
        fi
    else
        log_error "❌ Command failed during memory test"
        return 1
    fi
}

test_disk_io_performance() {
    local test_name="$1"
    local test_dir="${2:-/tmp}"
    local file_size_mb="${3:-10}"
    
    log_info "Testing disk I/O performance: $test_name"
    
    local test_file="${test_dir}/test_io_$$"
    
    # Test write performance
    local write_start
    write_start=$(date +%s.%N)
    
    if dd if=/dev/zero of="$test_file" bs=1M count="$file_size_mb" >/dev/null 2>&1; then
        local write_end
        write_end=$(date +%s.%N)
        local write_time
        write_time=$(echo "$write_end - $write_start" | bc -l)
        
        log_info "✅ Write performance: ${write_time}s for ${file_size_mb}MB"
        
        # Test read performance
        local read_start
        read_start=$(date +%s.%N)
        
        if dd if="$test_file" of=/dev/null bs=1M >/dev/null 2>&1; then
            local read_end
            read_end=$(date +%s.%N)
            local read_time
            read_time=$(echo "$read_end - $read_start" | bc -l)
            
            log_info "✅ Read performance: ${read_time}s for ${file_size_mb}MB"
            
            # Cleanup
            rm -f "$test_file"
            return 0
        else
            log_error "❌ Read test failed"
            rm -f "$test_file"
            return 1
        fi
    else
        log_error "❌ Write test failed"
        return 1
    fi
}

# === Template Testing Utilities ===

test_template_functionality() {
    local template_name="$1"
    local template_script="${2:-${SCRIPT_DIR}/template.sh}"
    local test_mode="${3:-syntax}"
    
    log_info "Testing template functionality: $template_name"
    
    if [[ ! -f "$template_script" ]]; then
        log_error "❌ Template script not found: $template_script"
        return 1
    fi
    
    case "$test_mode" in
        syntax)
            if bash -n "$template_script"; then
                log_info "✅ Template script syntax valid"
                return 0
            else
                log_error "❌ Template script syntax invalid"
                return 1
            fi
            ;;
        functionality)
            # Test basic functionality without creating actual templates
            if timeout 10 bash "$template_script" --help >/dev/null 2>&1; then
                log_info "✅ Template script responds to help"
            else
                log_warn "⚠️ Template script may not have help functionality"
            fi
            
            # Test list functionality if available
            if timeout 10 bash "$template_script" --list >/dev/null 2>&1; then
                log_info "✅ Template script can list templates"
            else
                log_warn "⚠️ Template script may not have list functionality"
            fi
            
            return 0
            ;;
        *)
            log_error "❌ Unknown test mode: $test_mode"
            return 1
            ;;
    esac
}

test_vm_template_creation() {
    local template_name="$1"
    local distribution="${2:-ubuntu}"
    local test_mode="${3:-dry-run}"
    
    log_info "Testing VM template creation: $template_name ($distribution)"
    
    case "$test_mode" in
        dry-run)
            log_info "✅ Dry-run template creation test (simulation only)"
            # This would test the template creation logic without actually creating VMs
            return 0
            ;;
        validation)
            # Test template validation logic
            if [[ -n "$template_name" && -n "$distribution" ]]; then
                log_info "✅ Template parameters validation passed"
                return 0
            else
                log_error "❌ Template parameters validation failed"
                return 1
            fi
            ;;
        *)
            log_error "❌ Unknown test mode: $test_mode"
            return 1
            ;;
    esac
}

# === Network Testing Utilities ===

test_network_connectivity() {
    local target_name="$1"
    local target_host="$2"
    local target_port="${3:-80}"
    local timeout_seconds="${4:-5}"
    
    log_info "Testing network connectivity: $target_name"
    
    # Test basic connectivity
    if command -v ping >/dev/null 2>&1; then
        if timeout "$timeout_seconds" ping -c 1 "$target_host" >/dev/null 2>&1; then
            log_info "✅ Basic connectivity to $target_host"
        else
            log_warn "⚠️ No basic connectivity to $target_host"
        fi
    fi
    
    # Test port connectivity
    if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout_seconds" nc -z "$target_host" "$target_port" >/dev/null 2>&1; then
            log_info "✅ Port $target_port accessible on $target_host"
        else
            log_warn "⚠️ Port $target_port not accessible on $target_host"
        fi
    fi
    
    return 0
}

test_dns_resolution() {
    local hostname="$1"
    
    log_info "Testing DNS resolution for: $hostname"
    
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup "$hostname" >/dev/null 2>&1; then
            log_info "✅ DNS resolution successful for $hostname"
            return 0
        else
            log_error "❌ DNS resolution failed for $hostname"
            return 1
        fi
    elif command -v dig >/dev/null 2>&1; then
        if dig "$hostname" >/dev/null 2>&1; then
            log_info "✅ DNS resolution successful for $hostname"
            return 0
        else
            log_error "❌ DNS resolution failed for $hostname"
            return 1
        fi
    else
        log_warn "Neither nslookup nor dig available for DNS testing"
        return 2
    fi
}

# === Configuration Testing Utilities ===

test_configuration_validation() {
    local config_name="$1"
    local config_file="$2"
    local config_type="${3:-ini}"
    
    log_info "Testing configuration validation: $config_name"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "❌ Configuration file not found: $config_file"
        return 1
    fi
    
    case "$config_type" in
        ini)
            # Test INI file format
            if grep -E "^\[.*\]$" "$config_file" >/dev/null 2>&1; then
                log_info "✅ INI format sections found"
            else
                log_warn "⚠️ No INI format sections found"
            fi
            ;;
        json)
            # Test JSON format
            if command -v jq >/dev/null 2>&1; then
                if jq . "$config_file" >/dev/null 2>&1; then
                    log_info "✅ Valid JSON format"
                else
                    log_error "❌ Invalid JSON format"
                    return 1
                fi
            else
                log_warn "jq not available, skipping JSON validation"
            fi
            ;;
        yaml)
            # Test YAML format
            if command -v yq >/dev/null 2>&1; then
                if yq . "$config_file" >/dev/null 2>&1; then
                    log_info "✅ Valid YAML format"
                else
                    log_error "❌ Invalid YAML format"
                    return 1
                fi
            else
                log_warn "yq not available, skipping YAML validation"
            fi
            ;;
        *)
            log_info "✅ Basic configuration file existence validated"
            ;;
    esac
    
    return 0
}

# === Utility Functions ===

show_test_utilities_help() {
    cat << EOF
Test Utilities for Homelab Project

This module provides specialized testing functions for different component types:

Docker/Container Testing:
  test_docker_functionality <test_name> [container_script]
  test_kubernetes_functionality <test_name> [config_path]
  test_container_workload <workload_name> <image_name> [timeout]

Terraform Testing:
  test_terraform_functionality <test_name> [terraform_dir]
  test_terraform_module <module_path> [module_name]

Ansible Testing:
  test_ansible_functionality <test_name> [playbook_path]
  test_ansible_inventory <inventory_path> [inventory_name]

Monitoring Testing:
  test_monitoring_stack <stack_name> [prometheus_url] [grafana_url]
  test_metrics_collection <service_name> [metrics_endpoint]

Security Testing:
  test_security_hardening <target_name> [target_path]
  test_credential_security <search_path>
  test_network_security <service_name> [host] [port]

Performance Testing:
  test_performance_benchmark <test_name> <command> [max_time] [iterations]
  test_memory_usage <test_name> <command> [max_memory_mb]
  test_disk_io_performance <test_name> [test_dir] [file_size_mb]

Template Testing:
  test_template_functionality <template_name> [template_script] [test_mode]
  test_vm_template_creation <template_name> [distribution] [test_mode]

Network Testing:
  test_network_connectivity <target_name> <target_host> [port] [timeout]
  test_dns_resolution <hostname>

Configuration Testing:
  test_configuration_validation <config_name> <config_file> [config_type]

Example Usage:
  source test_utilities.sh
  test_docker_functionality "Docker Basic Test"
  test_terraform_functionality "Terraform Validation" "/path/to/terraform"
  test_performance_benchmark "Script Performance" "bash script.sh" 5 3

EOF
}

# Main execution (if script is run directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_test_utilities_help
fi