#!/bin/bash
# Integration test suite for the Proxmox Template Creator
# Tests end-to-end workflows and module interactions

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Test configuration
PROJECT_ROOT="${SCRIPT_DIR}/.."
TEST_CONFIG_DIR="/tmp/homelab_integration_test"
TEST_LOG_FILE="/tmp/homelab_integration_test.log"

# Setup integration test environment
setup_integration_tests() {
    test_info "Setting up integration test environment"
    
    mkdir -p "${TEST_CONFIG_DIR}"
    export HL_LOG_LEVEL="DEBUG"
    export HL_LOG_FILE="${TEST_LOG_FILE}"
    
    # Create mock Proxmox environment variables for testing
    export PROXMOX_NODE="test-node"
    export PROXMOX_STORAGE="local"
    export TEST_MODE="true"
}

# Cleanup integration test environment
cleanup_integration_tests() {
    test_info "Cleaning up integration test environment"
    
    rm -rf "${TEST_CONFIG_DIR}" || true
    rm -f "${TEST_LOG_FILE}" || true
    unset HL_LOG_LEVEL HL_LOG_FILE PROXMOX_NODE PROXMOX_STORAGE TEST_MODE
}

# Test complete project structure
test_project_structure() {
    test_section "Project Structure Validation"
    
    # Check essential directories
    local required_dirs=(
        "scripts"
        "docs"
        "tests"
        "config"
        "ansible"
        "terraform"
    )
    
    for dir in "${required_dirs[@]}"; do
        local dir_path="${PROJECT_ROOT}/${dir}"
        if [[ -d "${dir_path}" ]]; then
            test_pass "Required directory exists: ${dir}"
        else
            test_fail "Missing required directory: ${dir}"
        fi
    done
    
    # Check essential files
    local required_files=(
        "README.md"
        "scripts/main.sh"
        "scripts/bootstrap.sh"
        "scripts/template.sh"
        "scripts/config.sh"
        "scripts/lib/logging.sh"
    )
    
    for file in "${required_files[@]}"; do
        local file_path="${PROJECT_ROOT}/${file}"
        if [[ -f "${file_path}" ]]; then
            test_pass "Required file exists: ${file}"
        else
            test_fail "Missing required file: ${file}"
        fi
    done
}

# Test bootstrap to main controller workflow
test_bootstrap_to_main_workflow() {
    test_section "Bootstrap to Main Controller Workflow"
    
    # Check if bootstrap script can source main components
    local bootstrap_script="${PROJECT_ROOT}/scripts/bootstrap.sh"
    local main_script="${PROJECT_ROOT}/scripts/main.sh"
    
    if [[ -f "${bootstrap_script}" && -f "${main_script}" ]]; then
        # Test syntax of both scripts
        if bash -n "${bootstrap_script}" && bash -n "${main_script}"; then
            test_pass "Bootstrap and main scripts have valid syntax"
        else
            test_fail "Syntax errors in bootstrap or main scripts"
        fi
        
        # Check for integration points
        if grep -q "main.sh\|main_script" "${bootstrap_script}"; then
            test_pass "Bootstrap script references main controller"
        else
            test_warn "Bootstrap may not integrate with main controller"
        fi
    else
        test_fail "Bootstrap or main script missing"
    fi
}

# Test configuration system integration
test_configuration_integration() {
    test_section "Configuration System Integration"
    
    local config_script="${PROJECT_ROOT}/scripts/config.sh"
    local logging_script="${PROJECT_ROOT}/scripts/lib/logging.sh"
    
    # Test that config system can be sourced
    if [[ -f "${config_script}" ]]; then
        if bash -n "${config_script}"; then
            test_pass "Configuration script has valid syntax"
        else
            test_fail "Configuration script has syntax errors"
        fi
        
        # Check for logging integration
        if [[ -f "${logging_script}" ]] && grep -q "logging\|log_" "${config_script}"; then
            test_pass "Configuration system integrates with logging"
        else
            test_warn "Configuration system may not use centralized logging"
        fi
    else
        test_fail "Configuration script missing"
    fi
}

# Test template creation workflow
test_template_creation_workflow() {
    test_section "Template Creation Workflow"
    
    local template_script="${PROJECT_ROOT}/scripts/template.sh"
    local config_script="${PROJECT_ROOT}/scripts/config.sh"
    
    if [[ -f "${template_script}" ]]; then
        # Test template script syntax
        if bash -n "${template_script}"; then
            test_pass "Template script has valid syntax"
        else
            test_fail "Template script has syntax errors"
        fi
        
        # Check for configuration integration
        if grep -q "config\|CONFIG" "${template_script}"; then
            test_pass "Template system integrates with configuration"
        else
            test_warn "Template system may not use configuration system"
        fi
        
        # Check for cloud-init workflow
        if grep -q "cloud-init\|cloudinit" "${template_script}"; then
            test_pass "Template system includes cloud-init workflow"
        else
            test_warn "Template system may lack cloud-init integration"
        fi
    else
        test_fail "Template script missing"
    fi
}

# Test logging system integration
test_logging_integration() {
    test_section "Logging System Integration"
    
    local logging_script="${PROJECT_ROOT}/scripts/lib/logging.sh"
    
    if [[ -f "${logging_script}" ]]; then
        # Test logging script syntax
        if bash -n "${logging_script}"; then
            test_pass "Logging script has valid syntax"
        else
            test_fail "Logging script has syntax errors"
        fi
        
        # Check how many scripts use logging
        local scripts_with_logging=0
        local total_scripts=0
        
        for script in "${PROJECT_ROOT}/scripts"/*.sh; do
            if [[ -f "${script}" ]]; then
                ((total_scripts++))
                if grep -q "log_info\|log_error\|log_warn\|log_debug\|logging.sh" "${script}"; then
                    ((scripts_with_logging++))
                fi
            fi
        done
        
        if [[ ${scripts_with_logging} -gt 0 ]]; then
            test_pass "Logging integration found in ${scripts_with_logging}/${total_scripts} scripts"
        else
            test_warn "No scripts appear to use centralized logging"
        fi
    else
        test_fail "Logging script missing"
    fi
}

# Test module interdependencies
test_module_interdependencies() {
    test_section "Module Interdependencies"
    
    # Check for cross-module references
    local modules=(
        "bootstrap.sh"
        "main.sh"
        "template.sh"
        "config.sh"
        "containers.sh"
        "monitoring.sh"
        "update.sh"
    )
    
    local dependency_count=0
    
    for module in "${modules[@]}"; do
        local module_path="${PROJECT_ROOT}/scripts/${module}"
        if [[ -f "${module_path}" ]]; then
            # Check if module references other modules
            for other_module in "${modules[@]}"; do
                if [[ "${module}" != "${other_module}" ]]; then
                    local other_name="${other_module%.sh}"
                    if grep -q "${other_name}\|${other_module}" "${module_path}"; then
                        ((dependency_count++))
                        test_pass "Dependency: ${module} → ${other_module}"
                    fi
                fi
            done
        fi
    done
    
    if [[ ${dependency_count} -ge 3 ]]; then
        test_pass "Good module interdependency (${dependency_count} dependencies)"
    else
        test_warn "Limited module interdependency (${dependency_count} dependencies)"
    fi
}

# Test documentation consistency
test_documentation_consistency() {
    test_section "Documentation Consistency"
    
    local docs_dir="${PROJECT_ROOT}/docs"
    local readme_file="${PROJECT_ROOT}/README.md"
    
    # Check documentation structure
    if [[ -d "${docs_dir}" ]]; then
        local doc_files=(
            "SYSTEM_DESIGN.md"
            "PROGRESS_TRACKER.md"
            "IMPLEMENTATION_PLAN.md"
        )
        
        for doc in "${doc_files[@]}"; do
            local doc_path="${docs_dir}/${doc}"
            if [[ -f "${doc_path}" ]]; then
                test_pass "Documentation file exists: ${doc}"
            else
                test_warn "Documentation file missing: ${doc}"
            fi
        done
    else
        test_fail "Documentation directory missing"
    fi
    
    # Check README exists and has content
    if [[ -f "${readme_file}" ]]; then
        local readme_size
        readme_size=$(wc -l < "${readme_file}")
        if [[ ${readme_size} -gt 10 ]]; then
            test_pass "README.md exists and has content (${readme_size} lines)"
        else
            test_warn "README.md may lack sufficient content"
        fi
    else
        test_fail "README.md missing"
    fi
}

# Test ansible integration
test_ansible_integration() {
    test_section "Ansible Integration"
    
    local ansible_dir="${PROJECT_ROOT}/ansible"
    local ansible_script="${PROJECT_ROOT}/scripts/ansible.sh"
    
    if [[ -d "${ansible_dir}" ]]; then
        test_pass "Ansible directory exists"
        
        # Check for playbook files
        if find "${ansible_dir}" -name "*.yml" -o -name "*.yaml" | head -1 | read -r; then
            test_pass "Ansible playbooks found"
        else
            test_warn "No Ansible playbooks found"
        fi
    else
        test_warn "Ansible directory missing"
    fi
    
    if [[ -f "${ansible_script}" ]]; then
        if bash -n "${ansible_script}"; then
            test_pass "Ansible script has valid syntax"
        else
            test_fail "Ansible script has syntax errors"
        fi
    else
        test_warn "Ansible script missing"
    fi
}

# Test terraform integration
test_terraform_integration() {
    test_section "Terraform Integration"
    
    local terraform_dir="${PROJECT_ROOT}/terraform"
    local terraform_script="${PROJECT_ROOT}/scripts/terraform.sh"
    
    if [[ -d "${terraform_dir}" ]]; then
        test_pass "Terraform directory exists"
        
        # Check for terraform files
        if find "${terraform_dir}" -name "*.tf" | head -1 | read -r; then
            test_pass "Terraform configuration files found"
        else
            test_warn "No Terraform configuration files found"
        fi
    else
        test_warn "Terraform directory missing"
    fi
    
    if [[ -f "${terraform_script}" ]]; then
        if bash -n "${terraform_script}"; then
            test_pass "Terraform script has valid syntax"
        else
            test_fail "Terraform script has syntax errors"
        fi
    else
        test_warn "Terraform script missing"
    fi
}

# Test container workloads integration
test_container_integration() {
    test_section "Container Workloads Integration"
    
    local containers_script="${PROJECT_ROOT}/scripts/containers.sh"
    local kubernetes_dir="${PROJECT_ROOT}/kubernetes"
    
    if [[ -f "${containers_script}" ]]; then
        if bash -n "${containers_script}"; then
            test_pass "Containers script has valid syntax"
        else
            test_fail "Containers script has syntax errors"
        fi
        
        # Check for Docker integration
        if grep -q "docker\|Docker" "${containers_script}"; then
            test_pass "Docker integration found in containers script"
        else
            test_warn "Docker integration may be missing"
        fi
        
        # Check for Kubernetes integration
        if grep -q "kubectl\|kubernetes\|k8s" "${containers_script}"; then
            test_pass "Kubernetes integration found in containers script"
        else
            test_warn "Kubernetes integration may be missing"
        fi
    else
        test_warn "Containers script missing"
    fi
    
    if [[ -d "${kubernetes_dir}" ]]; then
        test_pass "Kubernetes directory exists"
    else
        test_warn "Kubernetes directory missing"
    fi
}

# Test monitoring integration
test_monitoring_integration() {
    test_section "Monitoring Integration"
    
    local monitoring_script="${PROJECT_ROOT}/scripts/monitoring.sh"
    
    if [[ -f "${monitoring_script}" ]]; then
        if bash -n "${monitoring_script}"; then
            test_pass "Monitoring script has valid syntax"
        else
            test_fail "Monitoring script has syntax errors"
        fi
        
        # Check for monitoring tools integration
        local monitoring_tools=(
            "prometheus"
            "grafana"
            "alertmanager"
            "node_exporter"
        )
        
        for tool in "${monitoring_tools[@]}"; do
            if grep -qi "${tool}" "${monitoring_script}"; then
                test_pass "Monitoring tool integration: ${tool}"
            fi
        done
    else
        test_warn "Monitoring script missing"
    fi
}

# Test update system integration
test_update_integration() {
    test_section "Update System Integration"
    
    local update_script="${PROJECT_ROOT}/scripts/update.sh"
    
    if [[ -f "${update_script}" ]]; then
        if bash -n "${update_script}"; then
            test_pass "Update script has valid syntax"
        else
            test_fail "Update script has syntax errors"
        fi
        
        # Check for git integration
        if grep -q "git pull\|git fetch\|git merge" "${update_script}"; then
            test_pass "Git integration found in update script"
        else
            test_warn "Git integration may be missing from update script"
        fi
        
        # Check for backup functionality
        if grep -q "backup\|rollback" "${update_script}"; then
            test_pass "Backup/rollback functionality found"
        else
            test_warn "Backup/rollback functionality may be missing"
        fi
    else
        test_warn "Update script missing"
    fi
}

# Test overall system consistency
test_system_consistency() {
    test_section "Overall System Consistency"
    
    # Count total lines of implementation
    local total_lines=0
    local script_count=0
    
    for script in "${PROJECT_ROOT}/scripts"/*.sh; do
        if [[ -f "${script}" ]]; then
            local lines
            lines=$(wc -l < "${script}")
            total_lines=$((total_lines + lines))
            ((script_count++))
        fi
    done
    
    # Include lib scripts
    for script in "${PROJECT_ROOT}/scripts/lib"/*.sh; do
        if [[ -f "${script}" ]]; then
            local lines
            lines=$(wc -l < "${script}")
            total_lines=$((total_lines + lines))
            ((script_count++))
        fi
    done
    
    test_pass "Total implementation: ${total_lines} lines across ${script_count} scripts"
    
    if [[ ${total_lines} -gt 10000 ]]; then
        test_pass "Substantial implementation (${total_lines} lines)"
    elif [[ ${total_lines} -gt 5000 ]]; then
        test_pass "Good implementation size (${total_lines} lines)"
    else
        test_warn "Limited implementation size (${total_lines} lines)"
    fi
}

# Run all integration tests
run_integration_tests() {
    test_suite_start "Integration Tests"
    
    setup_integration_tests
    
    # Structural tests
    test_project_structure
    test_documentation_consistency
    test_system_consistency
    
    # Core workflow tests
    test_bootstrap_to_main_workflow
    test_configuration_integration
    test_template_creation_workflow
    test_logging_integration
    test_module_interdependencies
    
    # Component integration tests
    test_ansible_integration
    test_terraform_integration
    test_container_integration
    test_monitoring_integration
    test_update_integration
    
    cleanup_integration_tests
    
    test_suite_end "Integration Tests"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests
fi
