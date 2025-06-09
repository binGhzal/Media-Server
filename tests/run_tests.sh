#!/bin/bash
# Comprehensive test runner for the Proxmox Template Creator
# Executes all test suites and provides unified reporting

set -euo pipefail

# Test runner configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
REPORTS_DIR="${SCRIPT_DIR}/reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
GLOBAL_REPORT="${REPORTS_DIR}/test_report_${TIMESTAMP}.txt"

# Test suite definitions
declare -A TEST_SUITES=(
    ["logging"]="test_logging.sh"
    ["bootstrap"]="test_bootstrap.sh"
    ["template"]="test_template.sh"
    ["config"]="test_config.sh"
    ["main"]="test_main.sh"
    ["integration"]="test_integration.sh"
)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global test statistics
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_WARNINGS=0
TOTAL_SKIPPED=0

# Print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Print test runner header
print_header() {
    echo "============================================================================="
    print_color "${BLUE}" "    Proxmox Template Creator - Comprehensive Test Suite"
    echo "============================================================================="
    echo "Test run started: $(date)"
    echo "Project root: ${PROJECT_ROOT}"
    echo "Reports directory: ${REPORTS_DIR}"
    echo "============================================================================="
    echo
}

# Print test runner footer
print_footer() {
    echo
    echo "============================================================================="
    print_color "${BLUE}" "    Test Execution Summary"
    echo "============================================================================="
    echo "Total test suites executed: ${#TEST_SUITES[@]}"
    echo "Total tests run: ${TOTAL_TESTS}"
    print_color "${GREEN}" "Passed: ${TOTAL_PASSED}"
    print_color "${RED}" "Failed: ${TOTAL_FAILED}"
    print_color "${YELLOW}" "Warnings: ${TOTAL_WARNINGS}"
    print_color "${BLUE}" "Skipped: ${TOTAL_SKIPPED}"
    echo
    echo "Test run completed: $(date)"
    echo "Full report saved to: ${GLOBAL_REPORT}"
    echo "============================================================================="
}

# Setup test environment
setup_test_environment() {
    # Create reports directory
    mkdir -p "${REPORTS_DIR}"
    
    # Initialize global report
    cat > "${GLOBAL_REPORT}" << EOF
Proxmox Template Creator - Test Report
======================================
Generated: $(date)
Project: ${PROJECT_ROOT}

Test Execution Summary:
EOF
    
    # Ensure all test scripts are executable
    for suite in "${TEST_SUITES[@]}"; do
        local script_path="${SCRIPT_DIR}/${suite}"
        if [[ -f "${script_path}" ]]; then
            chmod +x "${script_path}"
        fi
    done
    
    # Source test framework for statistics collection
    if [[ -f "${SCRIPT_DIR}/test_framework.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/test_framework.sh"
    fi
}

# Parse test output and update statistics
parse_test_output() {
    local output="$1"
    local suite_name="$2"
    
    # Count different types of test results
    local passed
    local failed
    local warnings
    local skipped
    
    passed=$(echo "$output" | grep -c "✓.*PASS" || echo "0")
    failed=$(echo "$output" | grep -c "✗.*FAIL" || echo "0")
    warnings=$(echo "$output" | grep -c "⚠.*WARN" || echo "0")
    skipped=$(echo "$output" | grep -c "○.*SKIP" || echo "0")
    
    # Update global statistics
    TOTAL_TESTS=$((TOTAL_TESTS + passed + failed + warnings + skipped))
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + warnings))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))
    
    # Print suite summary
    echo
    print_color "${BLUE}" "Test Suite: ${suite_name}"
    echo "  Passed: ${passed}"
    echo "  Failed: ${failed}"
    echo "  Warnings: ${warnings}"
    echo "  Skipped: ${skipped}"
    echo
    
    # Append to global report
    cat >> "${GLOBAL_REPORT}" << EOF

Test Suite: ${suite_name}
  Passed: ${passed}
  Failed: ${failed}
  Warnings: ${warnings}
  Skipped: ${skipped}
EOF
}

# Run a single test suite
run_test_suite() {
    local suite_name="$1"
    local script_name="$2"
    local script_path="${SCRIPT_DIR}/${script_name}"
    
    print_color "${BLUE}" "Running ${suite_name} tests..."
    
    if [[ ! -f "${script_path}" ]]; then
        print_color "${RED}" "ERROR: Test script not found: ${script_path}"
        echo "ERROR: Test script not found: ${script_path}" >> "${GLOBAL_REPORT}"
        return 1
    fi
    
    if [[ ! -x "${script_path}" ]]; then
        print_color "${YELLOW}" "WARNING: Making test script executable: ${script_path}"
        chmod +x "${script_path}"
    fi
    
    # Create individual report file
    local suite_report="${REPORTS_DIR}/${suite_name}_${TIMESTAMP}.txt"
    
    # Execute test suite and capture output
    local output
    local exit_code=0
    
    if output=$(bash "${script_path}" 2>&1); then
        print_color "${GREEN}" "✓ ${suite_name} tests completed successfully"
    else
        exit_code=$?
        print_color "${YELLOW}" "⚠ ${suite_name} tests completed with warnings (exit code: ${exit_code})"
    fi
    
    # Save individual suite output
    echo "$output" > "${suite_report}"
    echo "Individual report saved: ${suite_report}"
    
    # Parse output and update statistics
    parse_test_output "$output" "${suite_name}"
    
    # Append detailed output to global report
    cat >> "${GLOBAL_REPORT}" << EOF

Detailed Output for ${suite_name}:
${output}

EOF
    
    return ${exit_code}
}

# Run specific test suite(s)
run_specific_suites() {
    local suites_to_run=("$@")
    
    for suite in "${suites_to_run[@]}"; do
        if [[ -n "${TEST_SUITES[$suite]:-}" ]]; then
            run_test_suite "${suite}" "${TEST_SUITES[$suite]}"
        else
            print_color "${RED}" "ERROR: Unknown test suite: ${suite}"
            echo "Available suites: ${!TEST_SUITES[*]}"
            return 1
        fi
    done
}

# Run all test suites
run_all_suites() {
    # Define execution order (dependencies first)
    local execution_order=(
        "logging"     # Foundation - no dependencies
        "config"      # Configuration system - depends on logging
        "bootstrap"   # Bootstrap system - depends on config and logging
        "template"    # Template system - depends on config and logging
        "main"        # Main controller - depends on all above
        "integration" # Integration tests - depends on all modules
    )
    
    for suite in "${execution_order[@]}"; do
        if [[ -n "${TEST_SUITES[$suite]:-}" ]]; then
            run_test_suite "${suite}" "${TEST_SUITES[$suite]}"
            echo # Add spacing between suites
        else
            print_color "${RED}" "ERROR: Suite ${suite} not found in TEST_SUITES"
        fi
    done
}

# Show help information
show_help() {
    cat << EOF
Proxmox Template Creator - Test Runner

Usage: $0 [OPTIONS] [SUITE_NAMES...]

OPTIONS:
    -h, --help          Show this help message
    -l, --list          List available test suites
    -a, --all           Run all test suites (default)
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress most output (errors only)
    --no-color          Disable colored output

SUITE_NAMES:
    logging             Test logging system
    bootstrap           Test bootstrap system
    template            Test template creation system
    config              Test configuration management
    main                Test main controller
    integration         Test integration workflows

Examples:
    $0                  # Run all test suites
    $0 -a               # Run all test suites
    $0 logging config   # Run only logging and config tests
    $0 --list           # Show available test suites

EOF
}

# List available test suites
list_suites() {
    echo "Available test suites:"
    echo
    for suite in "${!TEST_SUITES[@]}"; do
        local script="${TEST_SUITES[$suite]}"
        local status="✓"
        if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
            status="✗ (missing)"
        elif [[ ! -x "${SCRIPT_DIR}/${script}" ]]; then
            status="⚠ (not executable)"
        fi
        printf "  %-12s %-20s %s\n" "${suite}" "${script}" "${status}"
    done
    echo
}

# Check system requirements
check_requirements() {
    local requirements_met=true
    
    # Check for required commands
    local required_commands=("bash" "grep" "wc" "date")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            print_color "${RED}" "ERROR: Required command not found: ${cmd}"
            requirements_met=false
        fi
    done
    
    # Check for test framework
    if [[ ! -f "${SCRIPT_DIR}/test_framework.sh" ]]; then
        print_color "${RED}" "ERROR: Test framework not found: ${SCRIPT_DIR}/test_framework.sh"
        requirements_met=false
    fi
    
    if [[ "${requirements_met}" != "true" ]]; then
        print_color "${RED}" "ERROR: System requirements not met"
        return 1
    fi
    
    return 0
}

# Main execution function
main() {
    local run_all=true
    local verbose=false
    local quiet=false
    local use_color=true
    local specific_suites=()
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_suites
                exit 0
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            --no-color)
                use_color=false
                RED=""
                GREEN=""
                YELLOW=""
                BLUE=""
                NC=""
                shift
                ;;
            -*)
                print_color "${RED}" "ERROR: Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                run_all=false
                specific_suites+=("$1")
                shift
                ;;
        esac
    done
    
    # Check system requirements
    if ! check_requirements; then
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment
    
    # Print header unless quiet
    if [[ "${quiet}" != "true" ]]; then
        print_header
    fi
    
    # List available suites if verbose
    if [[ "${verbose}" == "true" ]]; then
        list_suites
    fi
    
    # Execute tests
    local exit_code=0
    
    if [[ "${run_all}" == "true" ]]; then
        run_all_suites || exit_code=$?
    else
        run_specific_suites "${specific_suites[@]}" || exit_code=$?
    fi
    
    # Print footer unless quiet
    if [[ "${quiet}" != "true" ]]; then
        print_footer
    fi
    
    # Final status
    if [[ ${TOTAL_FAILED} -eq 0 ]]; then
        print_color "${GREEN}" "All tests completed successfully!"
        exit_code=0
    else
        print_color "${YELLOW}" "Tests completed with ${TOTAL_FAILED} failures"
        exit_code=1
    fi
    
    exit ${exit_code}
}

# Execute main function with all arguments
main "$@"
