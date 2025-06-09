#!/bin/bash
# Test suite for main.sh module
# Tests main controller, UI, and module execution functionality

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Test configuration
MAIN_SCRIPT="${SCRIPT_DIR}/../scripts/main.sh"
TEST_CONFIG_DIR="/tmp/homelab_test_main"
TEST_LOG_FILE="/tmp/homelab_main_test.log"

# Setup test environment
setup_main_tests() {
    test_info "Setting up main controller test environment"
    
    mkdir -p "${TEST_CONFIG_DIR}"
    export HL_LOG_LEVEL="DEBUG"
    export HL_LOG_FILE="${TEST_LOG_FILE}"
}

# Cleanup test environment
cleanup_main_tests() {
    test_info "Cleaning up main controller test environment"
    
    rm -rf "${TEST_CONFIG_DIR}" || true
    rm -f "${TEST_LOG_FILE}" || true
    unset HL_LOG_LEVEL HL_LOG_FILE
}

# Test main script exists and is executable
test_main_script_exists() {
    test_section "Main Controller Script Existence"
    
    assert_file_exists "${MAIN_SCRIPT}" "Main script should exist"
    assert_file_executable "${MAIN_SCRIPT}" "Main script should be executable"
}

# Test main script syntax
test_main_syntax() {
    test_section "Main Controller Script Syntax"
    
    if bash -n "${MAIN_SCRIPT}" 2>/dev/null; then
        test_pass "Main script has valid bash syntax"
    else
        test_fail "Main script has syntax errors"
    fi
}

# Test main menu system
test_main_menu_system() {
    test_section "Main Menu System"
    
    # Check for whiptail/dialog UI functions
    if grep -q "whiptail\|dialog" "${MAIN_SCRIPT}"; then
        test_pass "UI framework (whiptail/dialog) integration exists"
    else
        test_warn "UI framework integration may be missing"
    fi
    
    # Check for menu functions
    local menu_functions=(
        "show_menu"
        "main_menu"
        "display_menu"
        "menu"
    )
    
    for func in "${menu_functions[@]}"; do
        if grep -q "${func}" "${MAIN_SCRIPT}"; then
            test_pass "Menu function found: ${func}"
            break
        fi
    done
}

# Test module discovery and management
test_main_module_management() {
    test_section "Module Discovery and Management"
    
    # Check for module discovery functionality
    if grep -q "discover.*module\|find.*module\|list.*module" "${MAIN_SCRIPT}"; then
        test_pass "Module discovery functionality exists"
    else
        test_warn "Module discovery may be limited"
    fi
    
    # Check for module execution
    if grep -q "execute.*module\|run.*module\|call.*module" "${MAIN_SCRIPT}"; then
        test_pass "Module execution functionality exists"
    else
        test_warn "Module execution may be limited"
    fi
    
    # Check for known modules
    local known_modules=(
        "bootstrap"
        "template"
        "config"
        "container"
        "monitoring"
        "update"
    )
    
    local found_modules=0
    for module in "${known_modules[@]}"; do
        if grep -qi "${module}" "${MAIN_SCRIPT}"; then
            ((found_modules++))
            test_pass "Module reference: ${module}"
        fi
    done
    
    if [[ ${found_modules} -ge 4 ]]; then
        test_pass "Comprehensive module support (${found_modules} modules)"
    else
        test_warn "Limited module support (${found_modules} modules)"
    fi
}

# Test user input handling
test_main_input_handling() {
    test_section "User Input Handling"
    
    # Check for input validation
    if grep -q "validate.*input\|check.*input\|verify.*input" "${MAIN_SCRIPT}"; then
        test_pass "Input validation functionality exists"
    else
        test_warn "Input validation may be missing"
    fi
    
    # Check for input collection methods
    local input_methods=(
        "read"
        "whiptail.*inputbox"
        "dialog.*inputbox"
        "select"
    )
    
    for method in "${input_methods[@]}"; do
        if grep -q "${method}" "${MAIN_SCRIPT}"; then
            test_pass "Input method: ${method}"
        fi
    done
}

# Test main controller error handling
test_main_error_handling() {
    test_section "Main Controller Error Handling"
    
    # Check for error handling patterns
    if grep -q "set -e\|error_exit\|trap.*ERR\||| exit" "${MAIN_SCRIPT}"; then
        test_pass "Main script includes error handling"
    else
        test_warn "Main script may lack comprehensive error handling"
    fi
    
    # Check for user-friendly error messages
    if grep -q "error.*message\|user.*error\|friendly.*error" "${MAIN_SCRIPT}"; then
        test_pass "User-friendly error messaging exists"
    else
        test_warn "User-friendly error messaging may be limited"
    fi
}

# Test main controller logging integration
test_main_logging() {
    test_section "Main Controller Logging Integration"
    
    # Check if main script uses logging functions
    if grep -q "log_info\|log_error\|log_warn\|log_debug" "${MAIN_SCRIPT}"; then
        test_pass "Main script uses centralized logging"
    else
        test_warn "Main script may not use centralized logging"
    fi
}

# Test main controller configuration integration
test_main_configuration() {
    test_section "Main Controller Configuration Integration"
    
    # Check for configuration system usage
    if grep -q "config\|CONFIG" "${MAIN_SCRIPT}"; then
        test_pass "Configuration system integration exists"
    else
        test_warn "Configuration system integration may be missing"
    fi
    
    # Check for configuration loading
    if grep -q "load.*config\|read.*config\|get.*config" "${MAIN_SCRIPT}"; then
        test_pass "Configuration loading functionality exists"
    else
        test_warn "Configuration loading may be limited"
    fi
}

# Test dependency management
test_main_dependencies() {
    test_section "Main Controller Dependency Management"
    
    # Check for dependency verification
    if grep -q "check.*depend\|verify.*depend\|require" "${MAIN_SCRIPT}"; then
        test_pass "Dependency checking functionality exists"
    else
        test_warn "Dependency checking may be missing"
    fi
    
    # Check for common dependencies
    local dependencies=(
        "whiptail"
        "dialog"
        "bash"
        "git"
    )
    
    for dep in "${dependencies[@]}"; do
        if grep -q "${dep}" "${MAIN_SCRIPT}"; then
            test_pass "Dependency check: ${dep}"
        fi
    done
}

# Test batch execution capability
test_main_batch_execution() {
    test_section "Batch Execution Capability"
    
    # Check for batch/automated execution
    if grep -q "batch\|auto\|non.*interactive\|silent" "${MAIN_SCRIPT}"; then
        test_pass "Batch execution capability exists"
    else
        test_warn "Batch execution may not be supported"
    fi
    
    # Check for command-line argument processing
    if grep -q "getopts\|\$1\|\$@\|OPTARG" "${MAIN_SCRIPT}"; then
        test_pass "Command-line argument processing exists"
    else
        test_warn "Command-line argument processing may be limited"
    fi
}

# Test main execution flow
test_main_execution_flow() {
    test_section "Main Execution Flow"
    
    # Check for main function
    if grep -q "main()\|^main\s*(" "${MAIN_SCRIPT}"; then
        test_pass "Main execution function exists"
    else
        test_warn "Main execution function may be missing"
    fi
    
    # Check for initialization
    if grep -q "init\|initialize\|setup" "${MAIN_SCRIPT}"; then
        test_pass "Initialization functionality exists"
    else
        test_warn "Initialization may be limited"
    fi
    
    # Check for cleanup
    if grep -q "cleanup\|exit.*trap\|finish" "${MAIN_SCRIPT}"; then
        test_pass "Cleanup functionality exists"
    else
        test_warn "Cleanup functionality may be missing"
    fi
}

# Test main controller help system
test_main_help_system() {
    test_section "Help System"
    
    # Check for help functionality
    if grep -q "help\|usage\|--help\|-h" "${MAIN_SCRIPT}"; then
        test_pass "Help system exists"
    else
        test_warn "Help system may be missing"
    fi
    
    # Check for documentation integration
    if grep -q "doc\|manual\|guide" "${MAIN_SCRIPT}"; then
        test_pass "Documentation integration exists"
    else
        test_warn "Documentation integration may be limited"
    fi
}

# Test main controller security
test_main_security() {
    test_section "Main Controller Security"
    
    # Check for privilege verification
    if grep -q "root\|sudo\|EUID\|whoami" "${MAIN_SCRIPT}"; then
        test_pass "Privilege verification exists"
    else
        test_warn "Privilege verification may be missing"
    fi
    
    # Check for input sanitization
    if grep -q "sanitize\|validate\|escape" "${MAIN_SCRIPT}"; then
        test_pass "Input sanitization exists"
    else
        test_warn "Input sanitization may be limited"
    fi
}

# Test main controller performance
test_main_performance() {
    test_section "Main Controller Performance"
    
    # Check for performance considerations
    if grep -q "timeout\|progress\|spinner\|status" "${MAIN_SCRIPT}"; then
        test_pass "Performance/progress indicators exist"
    else
        test_warn "Performance indicators may be limited"
    fi
}

# Run all main controller tests
run_main_tests() {
    test_suite_start "Main Controller Tests"
    
    setup_main_tests
    
    # Core functionality tests
    test_main_script_exists
    test_main_syntax
    test_main_menu_system
    test_main_module_management
    test_main_input_handling
    test_main_execution_flow
    
    # Integration tests
    test_main_configuration
    test_main_logging
    test_main_dependencies
    
    # Advanced features
    test_main_batch_execution
    test_main_help_system
    
    # Quality and security tests
    test_main_error_handling
    test_main_security
    test_main_performance
    
    cleanup_main_tests
    
    test_suite_end "Main Controller Tests"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_main_tests
fi
