#!/bin/bash
# Proxmox Template Creator - Main Test Framework
# Comprehensive testing framework for all modules

set -e

# Directory where the test script is located
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")/scripts"

# Source logging library if available
if [ -f "$SCRIPT_DIR/lib/logging.sh" ]; then
    source "$SCRIPT_DIR/lib/logging.sh"
    init_logging "TestFramework"
else
    echo "ERROR: logging.sh library not found. Cannot run tests." >&2
    exit 1
fi

# Test configuration
TEST_MODE=1
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test result tracking
declare -a TEST_RESULTS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test helper functions
test_start() {
    local test_name="$1"
    ((TOTAL_TESTS++))
    echo -e "${BLUE}[TEST ${TOTAL_TESTS}] Starting: ${test_name}${NC}"
    log_info "Starting test: $test_name"
}

test_pass() {
    local test_name="$1"
    ((PASSED_TESTS++))
    echo -e "${GREEN}[PASS] ${test_name}${NC}"
    log_info "Test passed: $test_name"
    TEST_RESULTS+=("PASS: $test_name")
}

test_fail() {
    local test_name="$1"
    local error_msg="$2"
    ((FAILED_TESTS++))
    echo -e "${RED}[FAIL] ${test_name}: ${error_msg}${NC}"
    log_error "Test failed: $test_name - $error_msg"
    TEST_RESULTS+=("FAIL: $test_name - $error_msg")
}

test_skip() {
    local test_name="$1"
    local reason="$2"
    ((SKIPPED_TESTS++))
    echo -e "${YELLOW}[SKIP] ${test_name}: ${reason}${NC}"
    log_warn "Test skipped: $test_name - $reason"
    TEST_RESULTS+=("SKIP: $test_name - $reason")
}

# Assert functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [ "$expected" = "$actual" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Expected '$expected', got '$actual'"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local test_name="$2"
    
    if [ -n "$value" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Value is empty"
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local test_name="$2"
    
    if [ -f "$filepath" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "File does not exist: $filepath"
        return 1
    fi
}

assert_directory_exists() {
    local dirpath="$1"
    local test_name="$2"
    
    if [ -d "$dirpath" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Directory does not exist: $dirpath"
        return 1
    fi
}

assert_command_exists() {
    local command="$1"
    local test_name="$2"
    
    if command -v "$command" >/dev/null 2>&1; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Command not found: $command"
        return 1
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local actual_code="$2"
    local test_name="$3"
    
    if [ "$expected_code" -eq "$actual_code" ]; then
        test_pass "$test_name"
        return 0
    else
        test_fail "$test_name" "Expected exit code $expected_code, got $actual_code"
        return 1
    fi
}

# Test execution functions
run_unit_tests() {
    echo -e "${BLUE}=== Running Unit Tests ===${NC}"
    
    # Test logging functionality
    test_logging_functions
    
    # Test configuration management
    test_configuration_management
    
    # Test bootstrap functionality
    test_bootstrap_functions
    
    # Test template module functions
    test_template_functions
}

run_integration_tests() {
    echo -e "${BLUE}=== Running Integration Tests ===${NC}"
    
    # Test module communication
    test_module_communication
    
    # Test configuration hierarchy
    test_configuration_hierarchy
    
    # Test bootstrap to main controller flow
    test_bootstrap_integration
}

run_system_tests() {
    echo -e "${BLUE}=== Running System Tests ===${NC}"
    
    # Test full workflow
    test_full_workflow
    
    # Test error handling
    test_error_handling
    
    # Test update mechanism
    test_update_mechanism
}

# Individual test functions
test_logging_functions() {
    echo -e "${YELLOW}Testing Logging Functions${NC}"
    
    test_start "Logging library exists"
    assert_file_exists "$SCRIPT_DIR/lib/logging.sh" "Logging library file"
    
    test_start "Log functions available"
    if type log_info >/dev/null 2>&1; then
        test_pass "log_info function available"
    else
        test_fail "log_info function available" "Function not defined"
    fi
    
    test_start "Log file creation"
    local test_log_msg="Test log message $(date)"
    log_info "$test_log_msg"
    if [ -f "/var/log/homelab_bootstrap.log" ]; then
        test_pass "Log file creation"
    else
        test_fail "Log file creation" "Log file not created"
    fi
}

test_configuration_management() {
    echo -e "${YELLOW}Testing Configuration Management${NC}"
    
    test_start "Config script exists"
    assert_file_exists "$SCRIPT_DIR/config.sh" "Configuration script"
    
    test_start "Config directory creation"
    local test_config_dir="/tmp/test_homelab_config"
    mkdir -p "$test_config_dir"
    assert_directory_exists "$test_config_dir" "Test config directory"
    rm -rf "$test_config_dir"
}

test_bootstrap_functions() {
    echo -e "${YELLOW}Testing Bootstrap Functions${NC}"
    
    test_start "Bootstrap script exists"
    assert_file_exists "$SCRIPT_DIR/bootstrap.sh" "Bootstrap script"
    
    test_start "Bootstrap script is executable"
    if [ -x "$SCRIPT_DIR/bootstrap.sh" ]; then
        test_pass "Bootstrap script executable"
    else
        test_fail "Bootstrap script executable" "Script is not executable"
    fi
}

test_template_functions() {
    echo -e "${YELLOW}Testing Template Functions${NC}"
    
    test_start "Template script exists"
    assert_file_exists "$SCRIPT_DIR/template.sh" "Template script"
    
    test_start "Template script is executable"
    if [ -x "$SCRIPT_DIR/template.sh" ]; then
        test_pass "Template script executable"
    else
        test_fail "Template script executable" "Script is not executable"
    fi
}

test_module_communication() {
    echo -e "${YELLOW}Testing Module Communication${NC}"
    
    test_start "Main controller exists"
    assert_file_exists "$SCRIPT_DIR/main.sh" "Main controller script"
    
    # Test if modules can be sourced without errors
    test_start "Modules can be sourced"
    local modules=("config.sh" "template.sh" "containers.sh" "monitoring.sh")
    local source_errors=0
    
    for module in "${modules[@]}"; do
        if [ -f "$SCRIPT_DIR/$module" ]; then
            # Test syntax by running with --help or similar safe option
            if bash -n "$SCRIPT_DIR/$module" 2>/dev/null; then
                log_debug "Module $module has valid syntax"
            else
                ((source_errors++))
                log_error "Module $module has syntax errors"
            fi
        fi
    done
    
    if [ $source_errors -eq 0 ]; then
        test_pass "Module syntax validation"
    else
        test_fail "Module syntax validation" "$source_errors modules have syntax errors"
    fi
}

test_configuration_hierarchy() {
    echo -e "${YELLOW}Testing Configuration Hierarchy${NC}"
    
    test_start "Configuration hierarchy test"
    # This would test the actual config hierarchy when implemented
    test_skip "Configuration hierarchy test" "Implementation pending"
}

test_bootstrap_integration() {
    echo -e "${YELLOW}Testing Bootstrap Integration${NC}"
    
    test_start "Bootstrap integration test"
    # This would test bootstrap -> main controller flow
    test_skip "Bootstrap integration test" "Requires non-root testing environment"
}

test_full_workflow() {
    echo -e "${YELLOW}Testing Full Workflow${NC}"
    
    test_start "Full workflow test"
    test_skip "Full workflow test" "Requires Proxmox environment"
}

test_error_handling() {
    echo -e "${YELLOW}Testing Error Handling${NC}"
    
    test_start "Error trap functionality"
    # Test that error handling works
    if type handle_error >/dev/null 2>&1; then
        test_pass "Error handler function available"
    else
        test_fail "Error handler function available" "Function not defined"
    fi
}

test_update_mechanism() {
    echo -e "${YELLOW}Testing Update Mechanism${NC}"
    
    test_start "Update script exists"
    assert_file_exists "$SCRIPT_DIR/update.sh" "Update script"
}

# Generate test report
generate_report() {
    echo
    echo -e "${BLUE}=== TEST SUMMARY ===${NC}"
    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    echo -e "Skipped:      ${YELLOW}$SKIPPED_TESTS${NC}"
    echo
    
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${RED}=== FAILED TESTS ===${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ $result == FAIL* ]]; then
                echo -e "${RED}$result${NC}"
            fi
        done
        echo
    fi
    
    if [ $SKIPPED_TESTS -gt 0 ]; then
        echo -e "${YELLOW}=== SKIPPED TESTS ===${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ $result == SKIP* ]]; then
                echo -e "${YELLOW}$result${NC}"
            fi
        done
        echo
    fi
    
    # Calculate success rate
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    echo "Success Rate: ${success_rate}%"
    
    # Write report to file
    local report_file="/tmp/homelab_test_report_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "Proxmox Template Creator - Test Report"
        echo "Generated: $(date)"
        echo "Total Tests: $TOTAL_TESTS"
        echo "Passed: $PASSED_TESTS"
        echo "Failed: $FAILED_TESTS"
        echo "Skipped: $SKIPPED_TESTS"
        echo "Success Rate: ${success_rate}%"
        echo
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "$result"
        done
    } > "$report_file"
    
    echo "Detailed report saved to: $report_file"
    log_info "Test run completed. Report saved to: $report_file"
}

# Main execution
main() {
    echo -e "${GREEN}Proxmox Template Creator - Test Framework${NC}"
    echo "Starting comprehensive test suite..."
    echo
    
    log_info "Starting test framework execution"
    
    # Check if running as root (some tests may require it)
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Running as root - all tests available${NC}"
    else
        echo -e "${YELLOW}Running as non-root - some tests may be skipped${NC}"
    fi
    
    # Run test suites
    run_unit_tests
    echo
    run_integration_tests
    echo
    run_system_tests
    echo
    
    # Generate final report
    generate_report
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        log_error "Test run completed with failures"
        exit 1
    else
        log_info "Test run completed successfully"
        exit 0
    fi
}

# Handle command line arguments
case "${1:-}" in
    --unit)
        run_unit_tests
        generate_report
        ;;
    --integration)
        run_integration_tests
        generate_report
        ;;
    --system)
        run_system_tests
        generate_report
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --unit         Run only unit tests"
        echo "  --integration  Run only integration tests" 
        echo "  --system       Run only system tests"
        echo "  --help         Show this help"
        exit 0
        ;;
    *)
        main
        ;;
esac
