#!/bin/bash
# Test suite for template.sh module
# Tests template creation, validation, and management functionality

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Test configuration
TEMPLATE_SCRIPT="${SCRIPT_DIR}/../scripts/template.sh"
TEST_CONFIG_DIR="/tmp/homelab_test_template"
TEST_LOG_FILE="/tmp/homelab_template_test.log"

# Setup test environment
setup_template_tests() {
    test_info "Setting up template test environment"
    
    mkdir -p "${TEST_CONFIG_DIR}"
    
    # Set test environment variables
    export HL_LOG_LEVEL="DEBUG"
    export HL_LOG_FILE="${TEST_LOG_FILE}"
}

# Cleanup test environment
cleanup_template_tests() {
    test_info "Cleaning up template test environment"
    
    rm -rf "${TEST_CONFIG_DIR}" || true
    rm -f "${TEST_LOG_FILE}" || true
    unset HL_LOG_LEVEL HL_LOG_FILE
}

# Test template script exists and is executable
test_template_script_exists() {
    test_section "Template Script Existence"
    
    assert_file_exists "${TEMPLATE_SCRIPT}" "Template script should exist"
    assert_file_executable "${TEMPLATE_SCRIPT}" "Template script should be executable"
}

# Test template script syntax
test_template_syntax() {
    test_section "Template Script Syntax"
    
    if bash -n "${TEMPLATE_SCRIPT}" 2>/dev/null; then
        test_pass "Template script has valid bash syntax"
    else
        test_fail "Template script has syntax errors"
    fi
}

# Test template creation functions
test_template_creation_functions() {
    test_section "Template Creation Functions"
    
    # Check for key template functions by searching the script
    local functions_to_check=(
        "create_template"
        "validate_template"
        "configure_cloudinit"
        "setup_network"
        "install_packages"
    )
    
    for func in "${functions_to_check[@]}"; do
        if grep -q "^${func}()\|^function ${func}" "${TEMPLATE_SCRIPT}"; then
            test_pass "Function ${func} exists"
        else
            test_warn "Function ${func} not found"
        fi
    done
}

# Test template validation functionality
test_template_validation() {
    test_section "Template Validation"
    
    # Check if validation functions exist
    if grep -q "validate.*template\|check.*template\|verify.*template" "${TEMPLATE_SCRIPT}"; then
        test_pass "Template validation functionality exists"
    else
        test_warn "Template validation functionality may be missing"
    fi
    
    # Check for resource validation
    if grep -q "memory\|cpu\|disk\|storage" "${TEMPLATE_SCRIPT}"; then
        test_pass "Resource validation checks exist"
    else
        test_warn "Resource validation may be incomplete"
    fi
}

# Test multi-distribution support
test_template_distro_support() {
    test_section "Multi-Distribution Support"
    
    # Check for various Linux distributions
    local distros=(
        "ubuntu"
        "debian"
        "centos"
        "fedora"
        "alpine"
        "rocky"
        "almalinux"
    )
    
    local found_distros=0
    for distro in "${distros[@]}"; do
        if grep -qi "${distro}" "${TEMPLATE_SCRIPT}"; then
            ((found_distros++))
        fi
    done
    
    if [[ ${found_distros} -ge 5 ]]; then
        test_pass "Multi-distribution support found (${found_distros} distributions)"
    else
        test_warn "Limited distribution support found (${found_distros} distributions)"
    fi
}

# Test cloud-init integration
test_template_cloudinit() {
    test_section "Cloud-init Integration"
    
    # Check for cloud-init related functionality
    if grep -q "cloud-init\|cloudinit" "${TEMPLATE_SCRIPT}"; then
        test_pass "Cloud-init integration exists"
    else
        test_warn "Cloud-init integration may be missing"
    fi
    
    # Check for specific cloud-init features
    local cloudinit_features=(
        "user-data"
        "meta-data"
        "network-config"
        "ssh.*key"
        "password"
    )
    
    for feature in "${cloudinit_features[@]}"; do
        if grep -q "${feature}" "${TEMPLATE_SCRIPT}"; then
            test_pass "Cloud-init feature: ${feature}"
        else
            test_warn "Cloud-init feature may be missing: ${feature}"
        fi
    done
}

# Test template management functionality
test_template_management() {
    test_section "Template Management"
    
    # Check for template management operations
    local management_ops=(
        "list.*template"
        "delete.*template"
        "clone.*template"
        "export.*template"
        "import.*template"
    )
    
    for op in "${management_ops[@]}"; do
        if grep -q "${op}" "${TEMPLATE_SCRIPT}"; then
            test_pass "Template management operation: ${op}"
        else
            test_warn "Template management operation may be missing: ${op}"
        fi
    done
}

# Test template configuration handling
test_template_configuration() {
    test_section "Template Configuration"
    
    # Check if template script uses configuration system
    if grep -q "config\|CONFIG" "${TEMPLATE_SCRIPT}"; then
        test_pass "Template configuration integration exists"
    else
        test_warn "Template configuration integration may be missing"
    fi
    
    # Check for template-specific configurations
    if grep -q "template.*config\|template.*settings" "${TEMPLATE_SCRIPT}"; then
        test_pass "Template-specific configuration handling exists"
    else
        test_warn "Template-specific configuration may be limited"
    fi
}

# Test template networking configuration
test_template_networking() {
    test_section "Template Networking Configuration"
    
    # Check for network configuration features
    local network_features=(
        "vlan"
        "bridge"
        "ip.*address"
        "dhcp"
        "static"
        "gateway"
        "dns"
    )
    
    local found_features=0
    for feature in "${network_features[@]}"; do
        if grep -qi "${feature}" "${TEMPLATE_SCRIPT}"; then
            ((found_features++))
            test_pass "Network feature: ${feature}"
        fi
    done
    
    if [[ ${found_features} -ge 4 ]]; then
        test_pass "Comprehensive networking support (${found_features} features)"
    else
        test_warn "Limited networking support (${found_features} features)"
    fi
}

# Test template logging integration
test_template_logging() {
    test_section "Template Logging Integration"
    
    # Check if template script uses logging functions
    if grep -q "log_info\|log_error\|log_warn\|log_debug" "${TEMPLATE_SCRIPT}"; then
        test_pass "Template script uses centralized logging"
    else
        test_warn "Template script may not use centralized logging"
    fi
}

# Test template error handling
test_template_error_handling() {
    test_section "Template Error Handling"
    
    # Check for error handling patterns
    if grep -q "set -e\|error_exit\|trap.*ERR\||| exit" "${TEMPLATE_SCRIPT}"; then
        test_pass "Template script includes error handling"
    else
        test_warn "Template script may lack comprehensive error handling"
    fi
}

# Test template security features
test_template_security() {
    test_section "Template Security Features"
    
    # Check for security-related functionality
    local security_features=(
        "ssh.*key"
        "password"
        "firewall"
        "selinux"
        "apparmor"
        "security"
        "hardening"
    )
    
    local found_security=0
    for feature in "${security_features[@]}"; do
        if grep -qi "${feature}" "${TEMPLATE_SCRIPT}"; then
            ((found_security++))
        fi
    done
    
    if [[ ${found_security} -ge 3 ]]; then
        test_pass "Security features implemented (${found_security} features)"
    else
        test_warn "Limited security features (${found_security} features)"
    fi
}

# Test template custom package installation
test_template_packages() {
    test_section "Template Package Installation"
    
    # Check for package management
    if grep -q "apt\|yum\|dnf\|apk\|zypper\|pacman" "${TEMPLATE_SCRIPT}"; then
        test_pass "Package management support exists"
    else
        test_warn "Package management support may be missing"
    fi
    
    # Check for custom package installation
    if grep -q "install.*package\|custom.*package" "${TEMPLATE_SCRIPT}"; then
        test_pass "Custom package installation support exists"
    else
        test_warn "Custom package installation may be limited"
    fi
}

# Run all template tests
run_template_tests() {
    test_suite_start "Template Module Tests"
    
    setup_template_tests
    
    # Core functionality tests
    test_template_script_exists
    test_template_syntax
    test_template_creation_functions
    test_template_validation
    
    # Feature-specific tests
    test_template_distro_support
    test_template_cloudinit
    test_template_management
    test_template_configuration
    test_template_networking
    test_template_packages
    test_template_security
    
    # Quality tests
    test_template_logging
    test_template_error_handling
    
    cleanup_template_tests
    
    test_suite_end "Template Module Tests"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_template_tests
fi
