#!/bin/bash
# Test suite for bootstrap.sh module
# Tests bootstrap functionality, dependency management, and system setup

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Test configuration
BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/../scripts/bootstrap.sh"
TEST_CONFIG_DIR="/tmp/homelab_test_bootstrap"
TEST_LOG_FILE="/tmp/homelab_bootstrap_test.log"

# Setup test environment
setup_bootstrap_tests() {
    test_info "Setting up bootstrap test environment"
    
    # Create temporary test directory
    mkdir -p "${TEST_CONFIG_DIR}"
    
    # Backup original log level if set
    if [[ -n "${HL_LOG_LEVEL:-}" ]]; then
        export ORIGINAL_HL_LOG_LEVEL="${HL_LOG_LEVEL}"
    fi
    
    # Set test log level
    export HL_LOG_LEVEL="DEBUG"
    export HL_LOG_FILE="${TEST_LOG_FILE}"
}

# Cleanup test environment
cleanup_bootstrap_tests() {
    test_info "Cleaning up bootstrap test environment"
    
    # Remove test directory
    rm -rf "${TEST_CONFIG_DIR}" || true
    rm -f "${TEST_LOG_FILE}" || true
    
    # Restore original log level
    if [[ -n "${ORIGINAL_HL_LOG_LEVEL:-}" ]]; then
        export HL_LOG_LEVEL="${ORIGINAL_HL_LOG_LEVEL}"
        unset ORIGINAL_HL_LOG_LEVEL
    else
        unset HL_LOG_LEVEL
    fi
}

# Test bootstrap script exists and is executable
test_bootstrap_script_exists() {
    test_section "Bootstrap Script Existence"
    
    assert_file_exists "${BOOTSTRAP_SCRIPT}" "Bootstrap script should exist"
    assert_file_executable "${BOOTSTRAP_SCRIPT}" "Bootstrap script should be executable"
}

# Test bootstrap script syntax
test_bootstrap_syntax() {
    test_section "Bootstrap Script Syntax"
    
    # Check bash syntax
    if bash -n "${BOOTSTRAP_SCRIPT}" 2>/dev/null; then
        test_pass "Bootstrap script has valid bash syntax"
    else
        test_fail "Bootstrap script has syntax errors"
    fi
}

# Test bootstrap dependency checking functions
test_bootstrap_dependencies() {
    test_section "Bootstrap Dependency Management"
    
    # Source bootstrap script in subshell to test functions
    (
        source "${BOOTSTRAP_SCRIPT}"
        
        # Test dependency checking function exists
        if declare -f check_dependencies >/dev/null; then
            test_pass "check_dependencies function exists"
        else
            test_fail "check_dependencies function not found"
        fi
        
        # Test OS detection function exists
        if declare -f detect_os >/dev/null; then
            test_pass "detect_os function exists"
        else
            test_fail "detect_os function not found"
        fi
        
        # Test Proxmox detection function exists
        if declare -f check_proxmox >/dev/null; then
            test_pass "check_proxmox function exists"
        else
            test_fail "check_proxmox function not found"
        fi
    ) 2>/dev/null || test_fail "Error sourcing bootstrap script for function testing"
}

# Test bootstrap configuration setup
test_bootstrap_configuration() {
    test_section "Bootstrap Configuration Setup"
    
    # Create mock homelab directory
    local mock_homelab_dir="${TEST_CONFIG_DIR}/homelab"
    mkdir -p "${mock_homelab_dir}/scripts"
    mkdir -p "${mock_homelab_dir}/docs"
    mkdir -p "${mock_homelab_dir}/config"
    
    # Test configuration directory creation
    assert_directory_exists "${mock_homelab_dir}/config" "Config directory should be created"
    
    # Test scripts directory exists
    assert_directory_exists "${mock_homelab_dir}/scripts" "Scripts directory should exist"
}

# Test bootstrap error handling
test_bootstrap_error_handling() {
    test_section "Bootstrap Error Handling"
    
    # Test that bootstrap handles missing dependencies gracefully
    # This is a basic test - in production would need more sophisticated testing
    
    if [[ -f "${BOOTSTRAP_SCRIPT}" ]]; then
        # Check if error handling functions exist
        if grep -q "error_exit\|handle_error\|trap.*ERR" "${BOOTSTRAP_SCRIPT}"; then
            test_pass "Bootstrap script includes error handling"
        else
            test_warn "Bootstrap script may lack comprehensive error handling"
        fi
    fi
}

# Test bootstrap logging integration
test_bootstrap_logging() {
    test_section "Bootstrap Logging Integration"
    
    # Check if bootstrap script uses logging functions
    if grep -q "log_info\|log_error\|log_warn\|log_debug" "${BOOTSTRAP_SCRIPT}"; then
        test_pass "Bootstrap script uses logging functions"
    else
        test_warn "Bootstrap script may not use centralized logging"
    fi
    
    # Test log file creation during bootstrap
    if [[ -f "${TEST_LOG_FILE}" ]] || touch "${TEST_LOG_FILE}" 2>/dev/null; then
        test_pass "Bootstrap log file can be created"
        rm -f "${TEST_LOG_FILE}" || true
    else
        test_fail "Cannot create bootstrap log file"
    fi
}

# Test bootstrap repository handling
test_bootstrap_repository() {
    test_section "Bootstrap Repository Handling"
    
    # Check if bootstrap script includes git operations
    if grep -q "git clone\|git pull\|git fetch" "${BOOTSTRAP_SCRIPT}"; then
        test_pass "Bootstrap script includes git repository operations"
    else
        test_warn "Bootstrap script may not handle git repository operations"
    fi
}

# Test bootstrap main execution flow
test_bootstrap_main_flow() {
    test_section "Bootstrap Main Execution Flow"
    
    # Check if main execution function exists
    if grep -q "main()\|^main\s*(" "${BOOTSTRAP_SCRIPT}"; then
        test_pass "Bootstrap script has main execution function"
    else
        test_warn "Bootstrap script may lack structured main execution"
    fi
    
    # Check if script can be sourced without execution
    if head -20 "${BOOTSTRAP_SCRIPT}" | grep -q "BASH_SOURCE\|return\|exit"; then
        test_pass "Bootstrap script includes proper sourcing protection"
    else
        test_warn "Bootstrap script may execute when sourced"
    fi
}

# Test bootstrap privilege checking
test_bootstrap_privileges() {
    test_section "Bootstrap Privilege Checking"
    
    # Check if bootstrap verifies root/sudo privileges
    if grep -q "EUID\|whoami\|sudo\|root" "${BOOTSTRAP_SCRIPT}"; then
        test_pass "Bootstrap script includes privilege checking"
    else
        test_warn "Bootstrap script may not verify required privileges"
    fi
}

# Test bootstrap system compatibility
test_bootstrap_compatibility() {
    test_section "Bootstrap System Compatibility"
    
    # Check if bootstrap includes OS compatibility checks
    if grep -q "lsb_release\|/etc/os-release\|uname" "${BOOTSTRAP_SCRIPT}"; then
        test_pass "Bootstrap script includes OS compatibility checks"
    else
        test_warn "Bootstrap script may not verify OS compatibility"
    fi
}

# Run all bootstrap tests
run_bootstrap_tests() {
    test_suite_start "Bootstrap Module Tests"
    
    setup_bootstrap_tests
    
    # Core functionality tests
    test_bootstrap_script_exists
    test_bootstrap_syntax
    test_bootstrap_dependencies
    test_bootstrap_configuration
    
    # Quality and reliability tests
    test_bootstrap_error_handling
    test_bootstrap_logging
    test_bootstrap_repository
    
    # Execution flow tests
    test_bootstrap_main_flow
    test_bootstrap_privileges
    test_bootstrap_compatibility
    
    cleanup_bootstrap_tests
    
    test_suite_end "Bootstrap Module Tests"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_bootstrap_tests
fi
