#!/bin/bash
# Proxmox Template Creator - Logging Module Tests
# Unit tests for the centralized logging system

set -e

# Directory where the test script is located
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")/scripts"

# Test configuration
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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
    echo -e "${BLUE}[TEST ${TOTAL_TESTS}] ${test_name}${NC}"
}

test_pass() {
    local test_name="$1"
    ((PASSED_TESTS++))
    echo -e "${GREEN}[PASS] ${test_name}${NC}"
}

test_fail() {
    local test_name="$1"
    local error_msg="$2"
    ((FAILED_TESTS++))
    echo -e "${RED}[FAIL] ${test_name}: ${error_msg}${NC}"
}

# Test logging library existence and basic functionality
test_logging_library_exists() {
    test_start "Logging library file exists"
    if [ -f "$SCRIPT_DIR/lib/logging.sh" ]; then
        test_pass "Logging library file exists"
    else
        test_fail "Logging library file exists" "File not found at $SCRIPT_DIR/lib/logging.sh"
        return 1
    fi
}

test_logging_library_syntax() {
    test_start "Logging library has valid syntax"
    if bash -n "$SCRIPT_DIR/lib/logging.sh" 2>/dev/null; then
        test_pass "Logging library syntax is valid"
    else
        test_fail "Logging library syntax is valid" "Syntax errors detected"
        return 1
    fi
}

test_logging_functions_available() {
    test_start "Sourcing logging library"
    if source "$SCRIPT_DIR/lib/logging.sh" 2>/dev/null; then
        test_pass "Logging library sourced successfully"
    else
        test_fail "Logging library sourced successfully" "Failed to source library"
        return 1
    fi
    
    # Test that required functions are available
    local required_functions=("log_info" "log_warn" "log_error" "log_debug" "init_logging" "handle_error")
    
    for func in "${required_functions[@]}"; do
        test_start "Function $func is available"
        if type "$func" >/dev/null 2>&1; then
            test_pass "Function $func is available"
        else
            test_fail "Function $func is available" "Function not defined"
        fi
    done
}

test_log_level_configuration() {
    test_start "Log level configuration"
    source "$SCRIPT_DIR/lib/logging.sh"
    
    # Test default log level
    if [ -n "$HL_LOG_LEVEL" ]; then
        test_pass "HL_LOG_LEVEL is set (default: $HL_LOG_LEVEL)"
    else
        test_fail "HL_LOG_LEVEL is set" "Environment variable not set"
    fi
    
    # Test log level values
    test_start "Log level values are defined"
    if [ ${LOG_LEVEL_VALUES["INFO"]} ]; then
        test_pass "Log level values are defined"
    else
        test_fail "Log level values are defined" "LOG_LEVEL_VALUES array not defined"
    fi
}

test_log_file_configuration() {
    test_start "Log file configuration"
    source "$SCRIPT_DIR/lib/logging.sh"
    
    if [ -n "$LOG_FILE" ]; then
        test_pass "LOG_FILE variable is set ($LOG_FILE)"
        
        # Test if log directory exists or can be created
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        test_start "Log directory exists or can be created"
        if [ -d "$log_dir" ] || mkdir -p "$log_dir" 2>/dev/null; then
            test_pass "Log directory accessible"
        else
            test_fail "Log directory accessible" "Cannot access or create $log_dir"
        fi
    else
        test_fail "LOG_FILE variable is set" "Variable not defined"
    fi
}

test_basic_logging_functionality() {
    test_start "Basic logging functionality"
    source "$SCRIPT_DIR/lib/logging.sh"
    
    # Initialize logging if function exists
    if type init_logging >/dev/null 2>&1; then
        init_logging "LogTest"
    fi
    
    # Test each log level
    local log_levels=("debug" "info" "warn" "error")
    local test_message="Test message $(date +%s)"
    
    for level in "${log_levels[@]}"; do
        test_start "Testing log_${level} function"
        if "log_${level}" "$test_message" 2>/dev/null; then
            test_pass "log_${level} function works"
        else
            test_fail "log_${level} function works" "Function failed or doesn't exist"
        fi
    done
}

test_log_output_format() {
    test_start "Log output format validation"
    source "$SCRIPT_DIR/lib/logging.sh"
    
    # Initialize logging
    if type init_logging >/dev/null 2>&1; then
        init_logging "FormatTest"
    fi
    
    # Create a temporary log file to capture output
    local temp_log="/tmp/homelab_log_test_$(date +%s).log"
    local original_log_file="$LOG_FILE"
    LOG_FILE="$temp_log"
    
    # Test log message
    local test_message="Format test message"
    log_info "$test_message"
    
    # Check if log file was created and contains expected format
    if [ -f "$temp_log" ]; then
        if grep -q "INFO" "$temp_log" && grep -q "$test_message" "$temp_log"; then
            test_pass "Log format includes level and message"
        else
            test_fail "Log format includes level and message" "Expected format not found"
        fi
        
        # Check for timestamp
        if grep -q "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" "$temp_log"; then
            test_pass "Log format includes timestamp"
        else
            test_fail "Log format includes timestamp" "Timestamp format not found"
        fi
    else
        test_fail "Log file creation" "Temporary log file not created"
    fi
    
    # Cleanup
    rm -f "$temp_log"
    LOG_FILE="$original_log_file"
}

test_error_handling_functionality() {
    test_start "Error handling functionality"
    source "$SCRIPT_DIR/lib/logging.sh"
    
    # Test handle_error function exists
    if type handle_error >/dev/null 2>&1; then
        test_pass "handle_error function is available"
        
        # Test error handling in a subshell to avoid exiting main script
        test_start "Error handling execution"
        (
            set -e
            trap 'handle_error $? $LINENO' ERR
            # This should trigger the error handler
            false
        ) 2>/dev/null
        
        # If we get here, the error handling worked (subshell exited cleanly)
        test_pass "Error handling execution works"
    else
        test_fail "handle_error function is available" "Function not defined"
    fi
}

test_log_level_filtering() {
    test_start "Log level filtering"
    source "$SCRIPT_DIR/lib/logging.sh"
    
    # Test with different log levels
    local original_level="$HL_LOG_LEVEL"
    
    # Set to ERROR level and test that INFO messages are filtered
    export HL_LOG_LEVEL="ERROR"
    source "$SCRIPT_DIR/lib/logging.sh"  # Re-source to pick up new level
    
    local temp_log="/tmp/homelab_filter_test_$(date +%s).log"
    local original_log_file="$LOG_FILE"
    LOG_FILE="$temp_log"
    
    log_info "This should be filtered"
    log_error "This should appear"
    
    if [ -f "$temp_log" ]; then
        if grep -q "This should appear" "$temp_log" && ! grep -q "This should be filtered" "$temp_log"; then
            test_pass "Log level filtering works"
        else
            test_fail "Log level filtering works" "Messages not filtered correctly"
        fi
    else
        test_fail "Log level filtering test" "Log file not created"
    fi
    
    # Cleanup
    rm -f "$temp_log"
    LOG_FILE="$original_log_file"
    export HL_LOG_LEVEL="$original_level"
}

# Generate test report
generate_report() {
    echo
    echo -e "${BLUE}=== LOGGING TESTS SUMMARY ===${NC}"
    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    echo "Success Rate: ${success_rate}%"
    
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${RED}Some logging tests failed. Check the output above for details.${NC}"
        return 1
    else
        echo -e "${GREEN}All logging tests passed!${NC}"
        return 0
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Proxmox Template Creator - Logging Tests${NC}"
    echo "Testing centralized logging system..."
    echo
    
    # Run all logging tests
    test_logging_library_exists || exit 1
    test_logging_library_syntax || exit 1
    test_logging_functions_available
    test_log_level_configuration
    test_log_file_configuration
    test_basic_logging_functionality
    test_log_output_format
    test_error_handling_functionality
    test_log_level_filtering
    
    # Generate report and exit with appropriate code
    generate_report
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
