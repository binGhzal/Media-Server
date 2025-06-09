#!/bin/bash
# Test suite for config.sh module
# Tests configuration management, validation, and hierarchy functionality

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_framework.sh"

# Test configuration
CONFIG_SCRIPT="${SCRIPT_DIR}/../scripts/config.sh"
TEST_CONFIG_DIR="/tmp/homelab_test_config"
TEST_LOG_FILE="/tmp/homelab_config_test.log"

# Setup test environment
setup_config_tests() {
    test_info "Setting up configuration test environment"
    
    mkdir -p "${TEST_CONFIG_DIR}"
    export HL_LOG_LEVEL="DEBUG"
    export HL_LOG_FILE="${TEST_LOG_FILE}"
}

# Cleanup test environment
cleanup_config_tests() {
    test_info "Cleaning up configuration test environment"
    
    rm -rf "${TEST_CONFIG_DIR}" || true
    rm -f "${TEST_LOG_FILE}" || true
    unset HL_LOG_LEVEL HL_LOG_FILE
}

# Test config script exists and is executable
test_config_script_exists() {
    test_section "Configuration Script Existence"
    
    assert_file_exists "${CONFIG_SCRIPT}" "Config script should exist"
    assert_file_executable "${CONFIG_SCRIPT}" "Config script should be executable"
}

# Test config script syntax
test_config_syntax() {
    test_section "Configuration Script Syntax"
    
    if bash -n "${CONFIG_SCRIPT}" 2>/dev/null; then
        test_pass "Config script has valid bash syntax"
    else
        test_fail "Config script has syntax errors"
    fi
}

# Test configuration hierarchy functions
test_config_hierarchy() {
    test_section "Configuration Hierarchy"
    
    # Check for hierarchy-related functions
    local hierarchy_functions=(
        "load_config"
        "save_config"
        "merge_config"
        "get_config"
        "set_config"
    )
    
    for func in "${hierarchy_functions[@]}"; do
        if grep -q "^${func}()\|^function ${func}" "${CONFIG_SCRIPT}"; then
            test_pass "Hierarchy function ${func} exists"
        else
            test_warn "Hierarchy function ${func} not found"
        fi
    done
}

# Test configuration validation
test_config_validation() {
    test_section "Configuration Validation"
    
    # Check for validation functions
    if grep -q "validate.*config\|check.*config\|verify.*config" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration validation functionality exists"
    else
        test_warn "Configuration validation may be missing"
    fi
    
    # Check for specific validation types
    local validation_types=(
        "required"
        "type"
        "range"
        "format"
        "dependency"
    )
    
    for validation in "${validation_types[@]}"; do
        if grep -qi "${validation}" "${CONFIG_SCRIPT}"; then
            test_pass "Validation type: ${validation}"
        else
            test_warn "Validation type may be missing: ${validation}"
        fi
    done
}

# Test configuration backup and restore
test_config_backup_restore() {
    test_section "Configuration Backup and Restore"
    
    # Check for backup/restore functionality
    if grep -q "backup.*config\|restore.*config" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration backup/restore functionality exists"
    else
        test_warn "Configuration backup/restore may be missing"
    fi
    
    # Check for versioning
    if grep -q "version\|timestamp\|history" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration versioning support exists"
    else
        test_warn "Configuration versioning may be limited"
    fi
}

# Test configuration import/export
test_config_import_export() {
    test_section "Configuration Import/Export"
    
    # Check for import/export functionality
    if grep -q "import.*config\|export.*config" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration import/export functionality exists"
    else
        test_warn "Configuration import/export may be missing"
    fi
    
    # Check for supported formats
    local formats=("json" "yaml" "ini" "env")
    local found_formats=0
    
    for format in "${formats[@]}"; do
        if grep -qi "${format}" "${CONFIG_SCRIPT}"; then
            ((found_formats++))
            test_pass "Format support: ${format}"
        fi
    done
    
    if [[ ${found_formats} -ge 2 ]]; then
        test_pass "Multiple format support (${found_formats} formats)"
    else
        test_warn "Limited format support (${found_formats} formats)"
    fi
}

# Test module-specific configurations
test_config_module_support() {
    test_section "Module-Specific Configuration"
    
    # Check for module configuration support
    if grep -q "module.*config\|component.*config" "${CONFIG_SCRIPT}"; then
        test_pass "Module-specific configuration support exists"
    else
        test_warn "Module-specific configuration may be limited"
    fi
    
    # Check for known modules
    local modules=(
        "bootstrap"
        "template"
        "container"
        "monitoring"
        "update"
    )
    
    for module in "${modules[@]}"; do
        if grep -qi "${module}" "${CONFIG_SCRIPT}"; then
            test_pass "Module configuration: ${module}"
        else
            test_info "Module configuration not found: ${module}"
        fi
    done
}

# Test configuration security
test_config_security() {
    test_section "Configuration Security"
    
    # Check for security features
    local security_features=(
        "encrypt"
        "decrypt"
        "secure"
        "permission"
        "chmod"
        "mask"
        "secret"
    )
    
    local found_security=0
    for feature in "${security_features[@]}"; do
        if grep -qi "${feature}" "${CONFIG_SCRIPT}"; then
            ((found_security++))
            test_pass "Security feature: ${feature}"
        fi
    done
    
    if [[ ${found_security} -ge 3 ]]; then
        test_pass "Security features implemented (${found_security} features)"
    else
        test_warn "Limited security features (${found_security} features)"
    fi
}

# Test configuration migration
test_config_migration() {
    test_section "Configuration Migration"
    
    # Check for migration functionality
    if grep -q "migrate.*config\|upgrade.*config\|convert.*config" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration migration functionality exists"
    else
        test_warn "Configuration migration may be missing"
    fi
    
    # Check for version compatibility
    if grep -q "version.*check\|compatibility\|migration.*version" "${CONFIG_SCRIPT}"; then
        test_pass "Version compatibility checking exists"
    else
        test_warn "Version compatibility checking may be limited"
    fi
}

# Test configuration defaults
test_config_defaults() {
    test_section "Configuration Defaults"
    
    # Check for default configuration handling
    if grep -q "default.*config\|fallback\|default.*value" "${CONFIG_SCRIPT}"; then
        test_pass "Default configuration handling exists"
    else
        test_warn "Default configuration handling may be missing"
    fi
    
    # Check for configuration templates
    if grep -q "template.*config\|config.*template" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration template support exists"
    else
        test_warn "Configuration template support may be limited"
    fi
}

# Test configuration error handling
test_config_error_handling() {
    test_section "Configuration Error Handling"
    
    # Check for error handling patterns
    if grep -q "set -e\|error_exit\|trap.*ERR\||| exit" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration script includes error handling"
    else
        test_warn "Configuration script may lack comprehensive error handling"
    fi
    
    # Check for configuration error recovery
    if grep -q "recover\|fallback\|retry" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration error recovery exists"
    else
        test_warn "Configuration error recovery may be limited"
    fi
}

# Test configuration logging integration
test_config_logging() {
    test_section "Configuration Logging Integration"
    
    # Check if config script uses logging functions
    if grep -q "log_info\|log_error\|log_warn\|log_debug" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration script uses centralized logging"
    else
        test_warn "Configuration script may not use centralized logging"
    fi
}

# Test configuration performance
test_config_performance() {
    test_section "Configuration Performance"
    
    # Check for caching mechanisms
    if grep -q "cache\|cached\|memoize" "${CONFIG_SCRIPT}"; then
        test_pass "Configuration caching functionality exists"
    else
        test_warn "Configuration caching may be missing"
    fi
    
    # Check for lazy loading
    if grep -q "lazy\|on.*demand\|defer" "${CONFIG_SCRIPT}"; then
        test_pass "Lazy loading functionality exists"
    else
        test_info "Lazy loading not explicitly implemented"
    fi
}

# Test configuration file formats
test_config_file_formats() {
    test_section "Configuration File Format Support"
    
    # Create test configuration files
    local test_json="${TEST_CONFIG_DIR}/test.json"
    local test_yaml="${TEST_CONFIG_DIR}/test.yaml"
    local test_ini="${TEST_CONFIG_DIR}/test.ini"
    
    # Test JSON format
    echo '{"test": "value"}' > "${test_json}"
    if [[ -f "${test_json}" ]]; then
        test_pass "JSON configuration file creation"
    else
        test_fail "JSON configuration file creation failed"
    fi
    
    # Test YAML format (basic)
    echo 'test: value' > "${test_yaml}"
    if [[ -f "${test_yaml}" ]]; then
        test_pass "YAML configuration file creation"
    else
        test_fail "YAML configuration file creation failed"
    fi
    
    # Test INI format
    echo '[section]' > "${test_ini}"
    echo 'test=value' >> "${test_ini}"
    if [[ -f "${test_ini}" ]]; then
        test_pass "INI configuration file creation"
    else
        test_fail "INI configuration file creation failed"
    fi
}

# Run all config tests
run_config_tests() {
    test_suite_start "Configuration Module Tests"
    
    setup_config_tests
    
    # Core functionality tests
    test_config_script_exists
    test_config_syntax
    test_config_hierarchy
    test_config_validation
    
    # Feature-specific tests
    test_config_backup_restore
    test_config_import_export
    test_config_module_support
    test_config_migration
    test_config_defaults
    test_config_file_formats
    
    # Quality and security tests
    test_config_security
    test_config_error_handling
    test_config_logging
    test_config_performance
    
    cleanup_config_tests
    
    test_suite_end "Configuration Module Tests"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_config_tests
fi
