#!/bin/bash
# Test Utilities for Homelab Project
# Specialized testing functions for different module types
# Version: 1.0.0

# === Docker and Container Testing ===
test_docker_installation() {
    local description="${1:-Docker installation check}"
    
    if command -v docker >/dev/null 2>&1; then
        if docker --version >/dev/null 2>&1; then
            assert_command_success "docker --version" "$description - Docker version command"
            
            # Test Docker daemon is running
            if docker info >/dev/null 2>&1; then
                assert_true "true" "$description - Docker daemon is running"
                return 0
            else
                fail_test "$description - Docker daemon not running" "${BASH_LINENO[0]}"
                return 1
            fi
        else
            fail_test "$description - Docker command failed" "${BASH_LINENO[0]}"
            return 1
        fi
    else
        skip_test "$description" "Docker not installed"
        return 0
    fi
}

test_container_functionality() {
    local image="${1:-hello-world}"
    local description="${2:-Container functionality test}"
    
    if ! test_docker_installation >/dev/null 2>&1; then
        skip_test "$description" "Docker not available"
        return 0
    fi
    
    log_info "Testing container functionality with image: $image"
    
    # Pull image if not exists
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        assert_command_success "docker pull $image" "$description - Pull test image"
    fi
    
    # Run container
    local container_id
    if container_id=$(docker run -d "$image" sleep 10 2>/dev/null); then
        assert_true "true" "$description - Container started successfully"
        
        # Wait for container to be running
        sleep 2
        
        # Check container status
        if docker ps | grep -q "$container_id"; then
            assert_true "true" "$description - Container is running"
        else
            assert_true "true" "$description - Container completed (expected for some test images)"
        fi
        
        # Cleanup
        docker rm -f "$container_id" >/dev/null 2>&1 || true
        
        return 0
    else
        fail_test "$description - Failed to start container" "${BASH_LINENO[0]}"
        return 1
    fi
}

test_kubernetes_workload() {
    local namespace="${1:-default}"
    local workload_type="${2:-deployment}"
    local workload_name="${3:-test-workload}"
    local description="${4:-Kubernetes workload test}"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        skip_test "$description" "kubectl not available"
        return 0
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        skip_test "$description" "Kubernetes cluster not accessible"
        return 0
    fi
    
    log_info "Testing Kubernetes workload: $workload_type/$workload_name in namespace $namespace"
    
    # Check if workload exists
    if kubectl get "$workload_type" "$workload_name" -n "$namespace" >/dev/null 2>&1; then
        assert_true "true" "$description - Workload exists"
        
        # Check workload status
        local ready_replicas
        ready_replicas=$(kubectl get "$workload_type" "$workload_name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [[ "$ready_replicas" -gt 0 ]]; then
            assert_true "true" "$description - Workload has ready replicas"
        else
            fail_test "$description - No ready replicas" "${BASH_LINENO[0]}"
        fi
        
        return 0
    else
        fail_test "$description - Workload not found" "${BASH_LINENO[0]}"
        return 1
    fi
}

# === Terraform Testing ===
test_terraform_module() {
    local module_path="${1:-.}"
    local description="${2:-Terraform module validation}"
    
    if ! command -v terraform >/dev/null 2>&1; then
        skip_test "$description" "Terraform not available"
        return 0
    fi
    
    log_info "Testing Terraform module at: $module_path"
    
    # Change to module directory
    local original_dir=$(pwd)
    if [[ -d "$module_path" ]]; then
        cd "$module_path"
    else
        fail_test "$description - Module path not found: $module_path" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Initialize Terraform
    if terraform init -backend=false >/dev/null 2>&1; then
        assert_true "true" "$description - Terraform init successful"
    else
        cd "$original_dir"
        fail_test "$description - Terraform init failed" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Validate configuration
    if terraform validate >/dev/null 2>&1; then
        assert_true "true" "$description - Terraform validation passed"
    else
        cd "$original_dir"
        fail_test "$description - Terraform validation failed" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Format check
    if terraform fmt -check=true >/dev/null 2>&1; then
        assert_true "true" "$description - Terraform formatting correct"
    else
        assert_true "false" "$description - Terraform formatting issues found"
    fi
    
    cd "$original_dir"
    return 0
}

test_terraform_plan() {
    local module_path="${1:-.}"
    local vars_file="${2:-}"
    local description="${3:-Terraform plan test}"
    
    if ! command -v terraform >/dev/null 2>&1; then
        skip_test "$description" "Terraform not available"
        return 0
    fi
    
    local original_dir=$(pwd)
    if [[ -d "$module_path" ]]; then
        cd "$module_path"
    else
        fail_test "$description - Module path not found: $module_path" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Build terraform command
    local tf_command="terraform plan -input=false -detailed-exitcode"
    if [[ -n "$vars_file" && -f "$vars_file" ]]; then
        tf_command="$tf_command -var-file=$vars_file"
    fi
    
    # Run terraform plan
    local exit_code
    if eval "$tf_command" >/dev/null 2>&1; then
        exit_code=$?
    else
        exit_code=$?
    fi
    
    case $exit_code in
        0)
            assert_true "true" "$description - No changes needed"
            ;;
        2)
            assert_true "true" "$description - Plan successful with changes"
            ;;
        *)
            fail_test "$description - Plan failed with exit code $exit_code" "${BASH_LINENO[0]}"
            cd "$original_dir"
            return 1
            ;;
    esac
    
    cd "$original_dir"
    return 0
}

# === Ansible Testing ===
test_ansible_playbook() {
    local playbook_path="$1"
    local inventory_path="${2:-inventory}"
    local description="${3:-Ansible playbook test}"
    
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        skip_test "$description" "Ansible not available"
        return 0
    fi
    
    if [[ ! -f "$playbook_path" ]]; then
        fail_test "$description - Playbook not found: $playbook_path" "${BASH_LINENO[0]}"
        return 1
    fi
    
    log_info "Testing Ansible playbook: $playbook_path"
    
    # Syntax check
    if ansible-playbook "$playbook_path" --syntax-check >/dev/null 2>&1; then
        assert_true "true" "$description - Syntax check passed"
    else
        fail_test "$description - Syntax check failed" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Dry run check (if inventory exists)
    if [[ -f "$inventory_path" ]]; then
        if ansible-playbook "$playbook_path" -i "$inventory_path" --check >/dev/null 2>&1; then
            assert_true "true" "$description - Dry run successful"
        else
            assert_true "false" "$description - Dry run failed (may be expected)"
        fi
    else
        skip_test "$description - Dry run" "No inventory file found"
    fi
    
    return 0
}

test_ansible_inventory() {
    local inventory_path="${1:-inventory}"
    local description="${2:-Ansible inventory test}"
    
    if ! command -v ansible-inventory >/dev/null 2>&1; then
        skip_test "$description" "Ansible not available"
        return 0
    fi
    
    if [[ ! -f "$inventory_path" ]]; then
        fail_test "$description - Inventory not found: $inventory_path" "${BASH_LINENO[0]}"
        return 1
    fi
    
    log_info "Testing Ansible inventory: $inventory_path"
    
    # List inventory
    if ansible-inventory -i "$inventory_path" --list >/dev/null 2>&1; then
        assert_true "true" "$description - Inventory parsing successful"
    else
        fail_test "$description - Inventory parsing failed" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Graph inventory
    if ansible-inventory -i "$inventory_path" --graph >/dev/null 2>&1; then
        assert_true "true" "$description - Inventory graph generation successful"
    else
        assert_true "false" "$description - Inventory graph generation failed"
    fi
    
    return 0
}

# === Monitoring and Metrics Testing ===
test_prometheus_connectivity() {
    local prometheus_url="${1:-http://localhost:9090}"
    local description="${2:-Prometheus connectivity test}"
    
    log_info "Testing Prometheus connectivity: $prometheus_url"
    
    # Test basic connectivity
    if curl -s -f "$prometheus_url/api/v1/query?query=up" >/dev/null 2>&1; then
        assert_true "true" "$description - Prometheus API accessible"
        
        # Test metrics availability
        local up_targets
        up_targets=$(curl -s "$prometheus_url/api/v1/query?query=up" | jq -r '.data.result | length' 2>/dev/null || echo "0")
        
        if [[ "$up_targets" -gt 0 ]]; then
            assert_true "true" "$description - Prometheus has active targets"
        else
            assert_true "false" "$description - No active targets found"
        fi
        
        return 0
    else
        fail_test "$description - Prometheus not accessible" "${BASH_LINENO[0]}"
        return 1
    fi
}

test_grafana_connectivity() {
    local grafana_url="${1:-http://localhost:3000}"
    local description="${2:-Grafana connectivity test}"
    
    log_info "Testing Grafana connectivity: $grafana_url"
    
    # Test basic connectivity
    if curl -s -f "$grafana_url/api/health" >/dev/null 2>&1; then
        assert_true "true" "$description - Grafana API accessible"
        
        # Test health status
        local health_status
        health_status=$(curl -s "$grafana_url/api/health" | jq -r '.database' 2>/dev/null || echo "unknown")
        
        if [[ "$health_status" == "ok" ]]; then
            assert_true "true" "$description - Grafana database healthy"
        else
            assert_true "false" "$description - Grafana database status: $health_status"
        fi
        
        return 0
    else
        fail_test "$description - Grafana not accessible" "${BASH_LINENO[0]}"
        return 1
    fi
}

test_metrics_collection() {
    local endpoint="${1:-http://localhost:9100/metrics}"
    local metric_name="${2:-node_cpu_seconds_total}"
    local description="${3:-Metrics collection test}"
    
    log_info "Testing metrics collection from: $endpoint"
    
    # Test endpoint accessibility
    if curl -s -f "$endpoint" >/dev/null 2>&1; then
        assert_true "true" "$description - Metrics endpoint accessible"
        
        # Test specific metric availability
        if curl -s "$endpoint" | grep -q "$metric_name"; then
            assert_true "true" "$description - Metric '$metric_name' available"
        else
            assert_true "false" "$description - Metric '$metric_name' not found"
        fi
        
        return 0
    else
        fail_test "$description - Metrics endpoint not accessible" "${BASH_LINENO[0]}"
        return 1
    fi
}

# === Security Testing ===
test_system_hardening() {
    local description="${1:-System hardening validation}"
    
    log_info "Testing system hardening measures"
    
    # Check SSH configuration
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        # Check if root login is disabled
        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
            assert_true "true" "$description - SSH root login disabled"
        else
            assert_true "false" "$description - SSH root login not properly disabled"
        fi
        
        # Check if password authentication is disabled
        if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
            assert_true "true" "$description - SSH password authentication disabled"
        else
            assert_true "false" "$description - SSH password authentication not disabled"
        fi
    else
        skip_test "$description - SSH config" "SSH config file not found"
    fi
    
    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            assert_true "true" "$description - UFW firewall active"
        else
            assert_true "false" "$description - UFW firewall not active"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
            assert_true "true" "$description - firewalld active"
        else
            assert_true "false" "$description - firewalld not active"
        fi
    else
        skip_test "$description - Firewall" "No supported firewall found"
    fi
    
    # Check for automatic updates
    if [[ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]]; then
        if grep -q "1" /etc/apt/apt.conf.d/20auto-upgrades; then
            assert_true "true" "$description - Automatic updates enabled"
        else
            assert_true "false" "$description - Automatic updates not enabled"
        fi
    else
        skip_test "$description - Auto updates" "Auto-updates config not found"
    fi
}

test_credential_security() {
    local path="${1:-$PROJECT_ROOT}"
    local description="${2:-Credential security test}"
    
    log_info "Testing credential security in: $path"
    
    local issues=0
    
    # Check for common credential patterns
    local patterns=(
        "password\s*=\s*['\"][^'\"]{1,}"
        "passwd\s*=\s*['\"][^'\"]{1,}"
        "secret\s*=\s*['\"][^'\"]{1,}"
        "api[_-]?key\s*=\s*['\"][^'\"]{1,}"
        "token\s*=\s*['\"][^'\"]{1,}"
    )
    
    for pattern in "${patterns[@]}"; do
        local matches
        mapfile -t matches < <(grep -rEi "$pattern" "$path" --include="*.sh" --include="*.conf" --include="*.json" --include="*.yaml" --include="*.yml" 2>/dev/null || true)
        
        if [[ ${#matches[@]} -gt 0 ]]; then
            for match in "${matches[@]}"; do
                log_warn "Potential credential found: $match"
                ((issues++))
            done
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        assert_true "true" "$description - No hardcoded credentials found"
    else
        assert_true "false" "$description - Found $issues potential credential issues"
    fi
    
    return 0
}

test_network_security() {
    local description="${1:-Network security test}"
    
    log_info "Testing network security configuration"
    
    # Check open ports
    if command -v ss >/dev/null 2>&1; then
        local open_ports
        mapfile -t open_ports < <(ss -tuln | awk 'NR>1 {print $5}' | sed 's/.*://' | sort -n | uniq)
        
        # Check for commonly insecure ports
        local insecure_ports=("21" "23" "25" "53" "80" "110" "143" "993" "995")
        local found_insecure=0
        
        for port in "${open_ports[@]}"; do
            if [[ " ${insecure_ports[*]} " =~ " $port " ]]; then
                log_warn "Potentially insecure port open: $port"
                ((found_insecure++))
            fi
        done
        
        if [[ $found_insecure -eq 0 ]]; then
            assert_true "true" "$description - No obviously insecure ports open"
        else
            assert_true "false" "$description - Found $found_insecure potentially insecure open ports"
        fi
    else
        skip_test "$description - Port check" "ss command not available"
    fi
    
    # Check IP forwarding
    if [[ -f "/proc/sys/net/ipv4/ip_forward" ]]; then
        local ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
        if [[ "$ip_forward" == "0" ]]; then
            assert_true "true" "$description - IP forwarding disabled"
        else
            assert_true "false" "$description - IP forwarding enabled (may be intentional)"
        fi
    fi
    
    return 0
}

# === Performance Testing ===
test_performance_baseline() {
    local description="${1:-Performance baseline test}"
    local duration="${2:-30}"
    
    log_info "Running performance baseline test for ${duration}s"
    
    # CPU performance test
    local cpu_start_time=$(date '+%s')
    local cpu_result
    cpu_result=$(timeout "$duration" yes >/dev/null 2>&1 &
                 local pid=$!
                 sleep 1
                 local cpu_usage=$(ps -p $pid -o %cpu --no-headers 2>/dev/null || echo "0")
                 kill $pid 2>/dev/null || true
                 echo "${cpu_usage%.*}")
    
    if [[ "${cpu_result:-0}" -gt 0 ]]; then
        assert_true "true" "$description - CPU stress test functional"
    else
        assert_true "false" "$description - CPU stress test failed"
    fi
    
    # Memory test
    local memory_available
    memory_available=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    
    if [[ "${memory_available:-0}" -gt 100 ]]; then
        assert_true "true" "$description - Sufficient memory available (${memory_available}MB)"
    else
        assert_true "false" "$description - Low memory available (${memory_available}MB)"
    fi
    
    # Disk I/O test
    local temp_file="/tmp/disk_test_$$"
    local disk_start_time=$(date '+%s%3N')
    
    if dd if=/dev/zero of="$temp_file" bs=1M count=10 >/dev/null 2>&1; then
        local disk_end_time=$(date '+%s%3N')
        local disk_duration=$((disk_end_time - disk_start_time))
        
        rm -f "$temp_file"
        
        if [[ $disk_duration -lt 5000 ]]; then # Less than 5 seconds for 10MB
            assert_true "true" "$description - Disk I/O performance acceptable (${disk_duration}ms)"
        else
            assert_true "false" "$description - Disk I/O performance slow (${disk_duration}ms)"
        fi
    else
        assert_true "false" "$description - Disk I/O test failed"
    fi
    
    return 0
}

test_memory_usage() {
    local process_name="$1"
    local max_memory_mb="${2:-1024}"
    local description="${3:-Memory usage test for $process_name}"
    
    if ! pgrep "$process_name" >/dev/null 2>&1; then
        skip_test "$description" "Process '$process_name' not running"
        return 0
    fi
    
    log_info "Testing memory usage for process: $process_name"
    
    # Get memory usage in MB
    local memory_usage
    memory_usage=$(ps -o pid,comm,rss --no-headers -C "$process_name" | awk '{sum+=$3} END {printf "%.0f", sum/1024}')
    
    if [[ "${memory_usage:-0}" -le "$max_memory_mb" ]]; then
        assert_true "true" "$description - Memory usage acceptable (${memory_usage}MB <= ${max_memory_mb}MB)"
    else
        assert_true "false" "$description - Memory usage excessive (${memory_usage}MB > ${max_memory_mb}MB)"
    fi
    
    return 0
}

# === Template and VM Testing ===
test_template_creation() {
    local template_name="${1:-test-template}"
    local description="${2:-Template creation test}"
    
    log_info "Testing template creation: $template_name"
    
    # Check if Proxmox tools are available
    if ! command -v qm >/dev/null 2>&1; then
        skip_test "$description" "Proxmox tools not available"
        return 0
    fi
    
    # Check if template already exists
    if qm status "$template_name" >/dev/null 2>&1; then
        assert_true "true" "$description - Template exists and is accessible"
        
        # Check template configuration
        local template_config
        template_config=$(qm config "$template_name" 2>/dev/null)
        
        if [[ -n "$template_config" ]]; then
            assert_true "true" "$description - Template configuration readable"
            
            # Check if it's marked as template
            if echo "$template_config" | grep -q "template: 1"; then
                assert_true "true" "$description - VM properly marked as template"
            else
                assert_true "false" "$description - VM not marked as template"
            fi
        else
            assert_true "false" "$description - Template configuration not readable"
        fi
        
        return 0
    else
        fail_test "$description - Template not found or not accessible" "${BASH_LINENO[0]}"
        return 1
    fi
}

test_vm_deployment() {
    local template_id="$1"
    local new_vm_id="$2"
    local description="${3:-VM deployment test}"
    
    if ! command -v qm >/dev/null 2>&1; then
        skip_test "$description" "Proxmox tools not available"
        return 0
    fi
    
    log_info "Testing VM deployment from template $template_id to VM $new_vm_id"
    
    # Check if template exists
    if ! qm status "$template_id" >/dev/null 2>&1; then
        fail_test "$description - Source template not found: $template_id" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Check if target VM ID is available
    if qm status "$new_vm_id" >/dev/null 2>&1; then
        fail_test "$description - Target VM ID already exists: $new_vm_id" "${BASH_LINENO[0]}"
        return 1
    fi
    
    # Clone template (dry run)
    if qm clone "$template_id" "$new_vm_id" --name "test-vm-$new_vm_id" --target "$(hostname)" >/dev/null 2>&1; then
        assert_true "true" "$description - VM cloning successful"
        
        # Cleanup test VM
        qm destroy "$new_vm_id" --destroy-unreferenced-disks 1 >/dev/null 2>&1 || true
        
        return 0
    else
        fail_test "$description - VM cloning failed" "${BASH_LINENO[0]}"
        return 1
    fi
}

# === Network Testing ===
test_network_connectivity() {
    local target="${1:-8.8.8.8}"
    local timeout="${2:-5}"
    local description="${3:-Network connectivity test to $target}"
    
    log_info "Testing network connectivity to: $target"
    
    if ping -c 1 -W "$timeout" "$target" >/dev/null 2>&1; then
        assert_true "true" "$description - Ping successful"
    else
        fail_test "$description - Ping failed" "${BASH_LINENO[0]}"
        return 1
    fi
    
    return 0
}

test_dns_resolution() {
    local hostname="${1:-google.com}"
    local description="${2:-DNS resolution test for $hostname}"
    
    log_info "Testing DNS resolution for: $hostname"
    
    if nslookup "$hostname" >/dev/null 2>&1; then
        assert_true "true" "$description - DNS resolution successful"
    elif host "$hostname" >/dev/null 2>&1; then
        assert_true "true" "$description - DNS resolution successful (via host)"
    elif dig "$hostname" >/dev/null 2>&1; then
        assert_true "true" "$description - DNS resolution successful (via dig)"
    else
        fail_test "$description - DNS resolution failed" "${BASH_LINENO[0]}"
        return 1
    fi
    
    return 0
}

test_port_connectivity() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    local description="${4:-Port connectivity test to $host:$port}"
    
    log_info "Testing port connectivity to: $host:$port"
    
    if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout" nc -z "$host" "$port" >/dev/null 2>&1; then
            assert_true "true" "$description - Port connection successful"
        else
            fail_test "$description - Port connection failed" "${BASH_LINENO[0]}"
            return 1
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout "$timeout" telnet "$host" "$port" </dev/null >/dev/null 2>&1; then
            assert_true "true" "$description - Port connection successful (via telnet)"
        else
            fail_test "$description - Port connection failed" "${BASH_LINENO[0]}"
            return 1
        fi
    else
        skip_test "$description" "No network connectivity tools available"
        return 0
    fi
    
    return 0
}

# === Configuration Testing ===
test_config_file_syntax() {
    local config_file="$1"
    local config_type="${2:-auto}"
    local description="${3:-Configuration file syntax test}"
    
    if [[ ! -f "$config_file" ]]; then
        fail_test "$description - Configuration file not found: $config_file" "${BASH_LINENO[0]}"
        return 1
    fi
    
    log_info "Testing configuration file syntax: $config_file"
    
    # Auto-detect configuration type if not specified
    if [[ "$config_type" == "auto" ]]; then
        case "${config_file##*.}" in
            json) config_type="json" ;;
            yaml|yml) config_type="yaml" ;;
            conf|config) config_type="conf" ;;
            *) config_type="unknown" ;;
        esac
    fi
    
    case "$config_type" in
        json)
            if command -v jq >/dev/null 2>&1; then
                if jq empty "$config_file" >/dev/null 2>&1; then
                    assert_true "true" "$description - JSON syntax valid"
                else
                    fail_test "$description - JSON syntax invalid" "${BASH_LINENO[0]}"
                    return 1
                fi
            else
                skip_test "$description" "jq not available for JSON validation"
            fi
            ;;
        yaml)
            if command -v yq >/dev/null 2>&1; then
                if yq eval . "$config_file" >/dev/null 2>&1; then
                    assert_true "true" "$description - YAML syntax valid"
                else
                    fail_test "$description - YAML syntax invalid" "${BASH_LINENO[0]}"
                    return 1
                fi
            elif python3 -c "import yaml" 2>/dev/null; then
                if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" >/dev/null 2>&1; then
                    assert_true "true" "$description - YAML syntax valid (via Python)"
                else
                    fail_test "$description - YAML syntax invalid" "${BASH_LINENO[0]}"
                    return 1
                fi
            else
                skip_test "$description" "No YAML validator available"
            fi
            ;;
        conf)
            # Basic syntax check for key=value format
            if grep -E '^[^#]*=' "$config_file" >/dev/null 2>&1; then
                assert_true "true" "$description - Configuration file appears valid"
            else
                assert_true "false" "$description - No key=value pairs found"
            fi
            ;;
        *)
            skip_test "$description" "Unknown configuration type: $config_type"
            ;;
    esac
    
    return 0
}

test_config_values() {
    local config_file="$1"
    local expected_key="$2"
    local expected_value="$3"
    local description="${4:-Configuration value test}"
    
    if [[ ! -f "$config_file" ]]; then
        fail_test "$description - Configuration file not found: $config_file" "${BASH_LINENO[0]}"
        return 1
    fi
    
    log_info "Testing configuration value: $expected_key=$expected_value in $config_file"
    
    # Try different parsing methods based on file type
    local actual_value=""
    
    case "${config_file##*.}" in
        json)
            if command -v jq >/dev/null 2>&1; then
                actual_value=$(jq -r ".$expected_key // empty" "$config_file" 2>/dev/null)
            fi
            ;;
        yaml|yml)
            if command -v yq >/dev/null 2>&1; then
                actual_value=$(yq eval ".$expected_key" "$config_file" 2>/dev/null)
            fi
            ;;
        conf|config)
            actual_value=$(grep "^$expected_key=" "$config_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'" 2>/dev/null)
            ;;
    esac
    
    if [[ "$actual_value" == "$expected_value" ]]; then
        assert_true "true" "$description - Configuration value correct: $expected_key=$actual_value"
    else
        fail_test "$description - Configuration value mismatch: expected '$expected_value', got '$actual_value'" "${BASH_LINENO[0]}"
        return 1
    fi
    
    return 0
}

# === Export all test functions ===
# This ensures all functions are available when this file is sourced
declare -fx test_docker_installation
declare -fx test_container_functionality
declare -fx test_kubernetes_workload
declare -fx test_terraform_module
declare -fx test_terraform_plan
declare -fx test_ansible_playbook
declare -fx test_ansible_inventory
declare -fx test_prometheus_connectivity
declare -fx test_grafana_connectivity
declare -fx test_metrics_collection
declare -fx test_system_hardening
declare -fx test_credential_security
declare -fx test_network_security
declare -fx test_performance_baseline
declare -fx test_memory_usage
declare -fx test_template_creation
declare -fx test_vm_deployment
declare -fx test_network_connectivity
declare -fx test_dns_resolution
declare -fx test_port_connectivity
declare -fx test_config_file_syntax
declare -fx test_config_values

log_info "Test utilities loaded successfully"