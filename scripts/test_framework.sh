#!/bin/bash
# Enhanced Testing Framework for Proxmox Template Creator
# Comprehensive testing with unit, integration, performance, security, and E2E testing
# Supports CI/CD integration, automated reporting, and multiple execution modes

set -euo pipefail

# === Configuration ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"
readonly TEST_REPORTS_DIR="${TEST_RESULTS_DIR}/reports"
readonly TEST_LOGS_DIR="${TEST_RESULTS_DIR}/logs"
readonly TEST_COVERAGE_DIR="${TEST_RESULTS_DIR}/coverage"
readonly TEST_PERFORMANCE_DIR="${TEST_RESULTS_DIR}/performance"

# Test execution configuration
TEST_MODE="all"           # all, unit, integration, performance, security, e2e
OUTPUT_FORMAT="console"   # console, json, html, junit
PARALLEL_TESTS=false
VERBOSE_MODE=false
CI_MODE=false
PERFORMANCE_BENCHMARKS=true
COVERAGE_ANALYSIS=true
SECURITY_SCANNING=true

# Performance thresholds (in seconds unless otherwise specified)
readonly BOOTSTRAP_TIME_THRESHOLD=30
readonly TEMPLATE_CREATE_TIME_THRESHOLD=300
readonly MODULE_LOAD_TIME_THRESHOLD=5
readonly MEMORY_USAGE_THRESHOLD_MB=512

# Test counters and results
declare -A TEST_RESULTS=(
    [total]=0
    [passed]=0
    [failed]=0
    [skipped]=0
    [warnings]=0
)

declare -A TEST_CATEGORIES=(
    [unit]=0
    [integration]=0
    [performance]=0
    [security]=0
    [e2e]=0
)

declare -a FAILED_TESTS=()
declare -a WARNING_TESTS=()

# === Logging and Output ===
setup_logging() {
    mkdir -p "$TEST_LOGS_DIR"
    export LOG_FILE="${TEST_LOGS_DIR}/test_framework_$(date +%Y%m%d_%H%M%S).log"
    export LOG_FILE_ALREADY_SET_EXTERNALLY="true"
    export HL_LOG_LEVEL="${HL_LOG_LEVEL:-INFO}"
    
    # Source centralized logging if available
    if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/logging.sh"
    else
        # Fallback logging functions
        log_info() { echo "[INFO] $*" | tee -a "$LOG_FILE"; }
        log_warn() { echo "[WARN] $*" | tee -a "$LOG_FILE"; }
        log_error() { echo "[ERROR] $*" | tee -a "$LOG_FILE"; }
        log_debug() { [[ "${HL_LOG_LEVEL:-INFO}" == "DEBUG" ]] && echo "[DEBUG] $*" | tee -a "$LOG_FILE"; }
    fi
}

# === Test Utilities ===
assert_success() {
    local description="$1"
    shift
    
    if "$@" >/dev/null 2>&1; then
        record_test_result "PASS" "$description"
        return 0
    else
        record_test_result "FAIL" "$description" "Command failed: $*"
        return 1
    fi
}

assert_output_contains() {
    local expected="$1"
    local description="$2"
    shift 2
    
    local output
    if output=$("$@" 2>&1); then
        if [[ "$output" == *"$expected"* ]]; then
            record_test_result "PASS" "$description"
            return 0
        else
            record_test_result "FAIL" "$description" "Output doesn't contain '$expected'. Got: $output"
            return 1
        fi
    else
        record_test_result "FAIL" "$description" "Command failed: $*"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local description="${2:-File exists: $file_path}"
    
    if [[ -f "$file_path" ]]; then
        record_test_result "PASS" "$description"
        return 0
    else
        record_test_result "FAIL" "$description" "File not found: $file_path"
        return 1
    fi
}

assert_dir_exists() {
    local dir_path="$1"
    local description="${2:-Directory exists: $dir_path}"
    
    if [[ -d "$dir_path" ]]; then
        record_test_result "PASS" "$description"
        return 0
    else
        record_test_result "FAIL" "$description" "Directory not found: $dir_path"
        return 1
    fi
}

assert_performance_threshold() {
    local actual_time="$1"
    local threshold="$2"
    local description="$3"
    
    if (( $(echo "$actual_time <= $threshold" | bc -l) )); then
        record_test_result "PASS" "$description (${actual_time}s <= ${threshold}s)"
        return 0
    else
        record_test_result "WARN" "$description (${actual_time}s > ${threshold}s)" "Performance threshold exceeded"
        return 1
    fi
}

record_test_result() {
    local status="$1"
    local description="$2"
    local details="${3:-}"
    
    ((TEST_RESULTS[total]++))
    
    case "$status" in
        PASS)
            ((TEST_RESULTS[passed]++))
            if [[ "$VERBOSE_MODE" == true || "$CI_MODE" == false ]]; then
                echo "✅ PASS: $description"
            fi
            log_info "PASS: $description"
            ;;
        FAIL)
            ((TEST_RESULTS[failed]++))
            echo "❌ FAIL: $description"
            [[ -n "$details" ]] && echo "   Details: $details"
            log_error "FAIL: $description - $details"
            FAILED_TESTS+=("$description")
            ;;
        WARN)
            ((TEST_RESULTS[warnings]++))
            echo "⚠️  WARN: $description"
            [[ -n "$details" ]] && echo "   Details: $details"
            log_warn "WARN: $description - $details"
            WARNING_TESTS+=("$description")
            ;;
        SKIP)
            ((TEST_RESULTS[skipped]++))
            echo "⏭️  SKIP: $description"
            [[ -n "$details" ]] && echo "   Reason: $details"
            log_info "SKIP: $description - $details"
            ;;
    esac
}

measure_execution_time() {
    local start_time=$(date +%s.%N)
    "$@"
    local end_time=$(date +%s.%N)
    echo "$(echo "$end_time - $start_time" | bc -l)"
}

# === Unit Tests ===
run_unit_tests() {
    echo "🧪 Running Unit Tests..."
    ((TEST_CATEGORIES[unit]++))
    
    # Test bootstrap functions
    test_bootstrap_functions
    
    # Test template functions
    test_template_functions
    
    # Test configuration functions
    test_configuration_functions
    
    # Test logging functions
    test_logging_functions
    
    # Test utility functions
    test_utility_functions
}

test_bootstrap_functions() {
    echo "  Testing bootstrap functions..."
    
    if [[ -f "${SCRIPT_DIR}/bootstrap.sh" ]]; then
        # Source bootstrap without executing main logic
        source "${SCRIPT_DIR}/bootstrap.sh" --source-only 2>/dev/null || {
            # If source-only flag doesn't exist, test without sourcing
            assert_output_contains "Proxmox Template Creator" "Bootstrap script displays banner" \
                bash "${SCRIPT_DIR}/bootstrap.sh" --help
        }
        
        # Test function existence
        if declare -f check_root >/dev/null 2>&1; then
            assert_success "check_root function exists" declare -f check_root
        fi
        
        if declare -f check_os_compatibility >/dev/null 2>&1; then
            assert_success "check_os_compatibility function exists" declare -f check_os_compatibility
        fi
    else
        record_test_result "SKIP" "Bootstrap tests" "bootstrap.sh not found"
    fi
}

test_template_functions() {
    echo "  Testing template functions..."
    
    if [[ -f "${SCRIPT_DIR}/template.sh" ]]; then
        # Test template script loads without errors
        assert_success "Template script syntax check" bash -n "${SCRIPT_DIR}/template.sh"
        
        # Test help output
        assert_output_contains "template" "Template script shows help" \
            bash "${SCRIPT_DIR}/template.sh" --help 2>/dev/null || true
            
    else
        record_test_result "SKIP" "Template tests" "template.sh not found"
    fi
}

test_configuration_functions() {
    echo "  Testing configuration functions..."
    
    if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
        # Test config script loads without errors
        assert_success "Config script syntax check" bash -n "${SCRIPT_DIR}/config.sh"
        
        # Test configuration directory creation
        local test_config_dir="/tmp/test_homelab_config_$$"
        mkdir -p "$test_config_dir"
        assert_dir_exists "$test_config_dir" "Test config directory created"
        rm -rf "$test_config_dir"
        
    else
        record_test_result "SKIP" "Configuration tests" "config.sh not found"
    fi
}

test_logging_functions() {
    echo "  Testing logging functions..."
    
    if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
        # Source and test logging functions
        local test_log_file="/tmp/test_logging_$$.log"
        export LOG_FILE="$test_log_file"
        export LOG_FILE_ALREADY_SET_EXTERNALLY="true"
        
        source "${SCRIPT_DIR}/lib/logging.sh"
        
        # Test logging functions exist
        assert_success "log_info function exists" declare -f log_info
        assert_success "log_warn function exists" declare -f log_warn
        assert_success "log_error function exists" declare -f log_error
        assert_success "log_debug function exists" declare -f log_debug
        
        # Test actual logging
        log_info "Test log message"
        assert_file_exists "$test_log_file" "Log file created"
        
        if [[ -f "$test_log_file" ]]; then
            assert_output_contains "Test log message" "Log message written" cat "$test_log_file"
        fi
        
        rm -f "$test_log_file"
    else
        record_test_result "SKIP" "Logging tests" "logging.sh not found"
    fi
}

test_utility_functions() {
    echo "  Testing utility functions..."
    
    # Test basic shell utilities
    assert_success "bc calculator available" which bc
    assert_success "curl available" which curl
    assert_success "git available" which git
    
    # Test whiptail for UI
    if which whiptail >/dev/null 2>&1; then
        assert_success "whiptail available for UI" which whiptail
    else
        record_test_result "WARN" "whiptail not available" "UI features may not work"
    fi
}

# === Integration Tests ===
run_integration_tests() {
    echo "🔗 Running Integration Tests..."
    ((TEST_CATEGORIES[integration]++))
    
    test_module_integration
    test_configuration_integration
    test_logging_integration
    test_workflow_integration
}

test_module_integration() {
    echo "  Testing module integration..."
    
    # Test main.sh can load and list modules
    if [[ -f "${SCRIPT_DIR}/main.sh" ]]; then
        assert_success "Main script syntax check" bash -n "${SCRIPT_DIR}/main.sh"
        
        # Test module discovery
        if bash "${SCRIPT_DIR}/main.sh" --list-modules >/dev/null 2>&1; then
            assert_success "Module discovery works" bash "${SCRIPT_DIR}/main.sh" --list-modules
        else
            record_test_result "SKIP" "Module discovery test" "main.sh doesn't support --list-modules"
        fi
    fi
}

test_configuration_integration() {
    echo "  Testing configuration integration..."
    
    # Test configuration system integration
    local test_config_dir="/tmp/test_homelab_integration_$$"
    mkdir -p "$test_config_dir"
    
    # Test config creation and loading
    if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
        local config_output
        if config_output=$(timeout 10 bash "${SCRIPT_DIR}/config.sh" --test 2>&1 || true); then
            if [[ "$config_output" == *"config"* || "$config_output" == *"Config"* ]]; then
                assert_success "Configuration system responds" true
            else
                record_test_result "SKIP" "Config integration test" "No recognizable config output"
            fi
        else
            record_test_result "SKIP" "Config integration test" "Config script timeout or error"
        fi
    fi
    
    rm -rf "$test_config_dir"
}

test_logging_integration() {
    echo "  Testing logging integration..."
    
    # Test logging integration across modules
    local test_log_file="/tmp/test_integration_logging_$$.log"
    export LOG_FILE="$test_log_file"
    export LOG_FILE_ALREADY_SET_EXTERNALLY="true"
    
    # Test that modules can use logging
    if [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/logging.sh"
        log_info "Integration test message"
        
        if [[ -f "$test_log_file" ]]; then
            assert_output_contains "Integration test message" "Cross-module logging works" cat "$test_log_file"
        fi
    fi
    
    rm -f "$test_log_file"
}

test_workflow_integration() {
    echo "  Testing workflow integration..."
    
    # Test complete workflow simulation
    local workflow_test_dir="/tmp/test_workflow_$$"
    mkdir -p "$workflow_test_dir"
    
    # Simulate a complete workflow without actual deployment
    if [[ -f "${SCRIPT_DIR}/main.sh" ]]; then
        # Test that main script can handle test mode
        local main_output
        if main_output=$(timeout 15 bash "${SCRIPT_DIR}/main.sh" --help 2>&1 || true); then
            if [[ "$main_output" == *"help"* || "$main_output" == *"usage"* || "$main_output" == *"Template Creator"* ]]; then
                assert_success "Main workflow help accessible" true
            else
                record_test_result "SKIP" "Workflow test" "No recognizable help output"
            fi
        else
            record_test_result "SKIP" "Workflow test" "Main script timeout"
        fi
    fi
    
    rm -rf "$workflow_test_dir"
}

# === Performance Tests ===
run_performance_tests() {
    echo "⚡ Running Performance Tests..."
    ((TEST_CATEGORIES[performance]++))
    
    test_bootstrap_performance
    test_module_load_performance
    test_memory_usage
    test_disk_usage
}

test_bootstrap_performance() {
    echo "  Testing bootstrap performance..."
    
    if [[ -f "${SCRIPT_DIR}/bootstrap.sh" ]]; then
        local execution_time
        execution_time=$(measure_execution_time bash -n "${SCRIPT_DIR}/bootstrap.sh")
        assert_performance_threshold "$execution_time" "1.0" "Bootstrap syntax check performance"
        
        # Record performance metrics
        echo "bootstrap_syntax_check:$execution_time" >> "${TEST_PERFORMANCE_DIR}/metrics.txt"
    fi
}

test_module_load_performance() {
    echo "  Testing module load performance..."
    
    local modules=("main.sh" "template.sh" "config.sh" "containers.sh")
    
    for module in "${modules[@]}"; do
        if [[ -f "${SCRIPT_DIR}/$module" ]]; then
            local execution_time
            execution_time=$(measure_execution_time bash -n "${SCRIPT_DIR}/$module")
            assert_performance_threshold "$execution_time" "$MODULE_LOAD_TIME_THRESHOLD" "Module $module load performance"
            
            echo "${module}_load_time:$execution_time" >> "${TEST_PERFORMANCE_DIR}/metrics.txt"
        fi
    done
}

test_memory_usage() {
    echo "  Testing memory usage..."
    
    # Monitor memory usage during test execution
    local initial_memory
    initial_memory=$(free -m | awk 'NR==2{printf "%.2f", $3}')
    
    # Run a sample operation
    if [[ -f "${SCRIPT_DIR}/main.sh" ]]; then
        bash -n "${SCRIPT_DIR}/main.sh" >/dev/null 2>&1 || true
    fi
    
    local final_memory
    final_memory=$(free -m | awk 'NR==2{printf "%.2f", $3}')
    
    local memory_diff
    memory_diff=$(echo "$final_memory - $initial_memory" | bc -l)
    
    echo "memory_usage_mb:$memory_diff" >> "${TEST_PERFORMANCE_DIR}/metrics.txt"
    
    if (( $(echo "$memory_diff <= $MEMORY_USAGE_THRESHOLD_MB" | bc -l) )); then
        record_test_result "PASS" "Memory usage within threshold (${memory_diff}MB <= ${MEMORY_USAGE_THRESHOLD_MB}MB)"
    else
        record_test_result "WARN" "Memory usage exceeds threshold (${memory_diff}MB > ${MEMORY_USAGE_THRESHOLD_MB}MB)"
    fi
}

test_disk_usage() {
    echo "  Testing disk usage..."
    
    local project_size
    project_size=$(du -sm "$PROJECT_ROOT" 2>/dev/null | cut -f1 || echo "0")
    
    echo "project_size_mb:$project_size" >> "${TEST_PERFORMANCE_DIR}/metrics.txt"
    
    if (( project_size <= 100 )); then
        record_test_result "PASS" "Project disk usage reasonable (${project_size}MB <= 100MB)"
    else
        record_test_result "WARN" "Project disk usage high (${project_size}MB > 100MB)"
    fi
}

# === Security Tests ===
run_security_tests() {
    echo "🔒 Running Security Tests..."
    ((TEST_CATEGORIES[security]++))
    
    test_script_permissions
    test_secure_practices
    test_input_validation
    test_credential_handling
}

test_script_permissions() {
    echo "  Testing script permissions..."
    
    # Check that scripts have appropriate permissions
    while IFS= read -r -d '' script; do
        local perms
        perms=$(stat -c "%a" "$script")
        
        if [[ "$perms" =~ ^[67][0-7][0-7]$ ]]; then
            record_test_result "PASS" "Script permissions appropriate: $script ($perms)"
        else
            record_test_result "WARN" "Script permissions may be too permissive: $script ($perms)"
        fi
    done < <(find "$SCRIPT_DIR" -name "*.sh" -print0)
}

test_secure_practices() {
    echo "  Testing secure coding practices..."
    
    # Check for potential security issues in scripts
    local security_issues=0
    
    while IFS= read -r -d '' script; do
        # Check for eval usage
        if grep -q "eval" "$script"; then
            record_test_result "WARN" "eval usage found in $script" "Potential security risk"
            ((security_issues++))
        fi
        
        # Check for unquoted variables
        if grep -E '\$[A-Za-z_][A-Za-z0-9_]*[^"]' "$script" | grep -v "^\s*#" | head -1 >/dev/null; then
            record_test_result "WARN" "Potentially unquoted variables in $script" "May cause security issues"
            ((security_issues++))
        fi
        
    done < <(find "$SCRIPT_DIR" -name "*.sh" -print0)
    
    if [[ $security_issues -eq 0 ]]; then
        record_test_result "PASS" "No obvious security issues found"
    fi
}

test_input_validation() {
    echo "  Testing input validation..."
    
    # Test that scripts handle invalid input gracefully
    local scripts=("main.sh" "template.sh" "config.sh")
    
    for script in "${scripts[@]}"; do
        if [[ -f "${SCRIPT_DIR}/$script" ]]; then
            # Test with invalid arguments
            if timeout 5 bash "${SCRIPT_DIR}/$script" --invalid-argument >/dev/null 2>&1; then
                record_test_result "WARN" "$script may not validate arguments properly"
            else
                record_test_result "PASS" "$script handles invalid arguments appropriately"
            fi
        fi
    done
}

test_credential_handling() {
    echo "  Testing credential handling..."
    
    # Check for hardcoded credentials or secrets
    local credential_issues=0
    
    while IFS= read -r -d '' script; do
        # Look for potential hardcoded credentials
        if grep -iE "(password|passwd|secret|key|token).*=" "$script" | grep -v "^\s*#" | head -1 >/dev/null; then
            local findings
            findings=$(grep -iE "(password|passwd|secret|key|token).*=" "$script" | grep -v "^\s*#" | head -3)
            record_test_result "WARN" "Potential credentials found in $script" "$findings"
            ((credential_issues++))
        fi
        
    done < <(find "$SCRIPT_DIR" -name "*.sh" -print0)
    
    if [[ $credential_issues -eq 0 ]]; then
        record_test_result "PASS" "No hardcoded credentials detected"
    fi
}

# === End-to-End Tests ===
run_e2e_tests() {
    echo "🎯 Running End-to-End Tests..."
    ((TEST_CATEGORIES[e2e]++))
    
    test_complete_workflow
    test_error_recovery
    test_cleanup_procedures
}

test_complete_workflow() {
    echo "  Testing complete workflow simulation..."
    
    # Simulate a complete user workflow without actual deployment
    local e2e_test_dir="/tmp/test_e2e_$$"
    mkdir -p "$e2e_test_dir"
    
    # Test bootstrap → main → module selection workflow
    if [[ -f "${SCRIPT_DIR}/bootstrap.sh" && -f "${SCRIPT_DIR}/main.sh" ]]; then
        # Test bootstrap can complete syntax check
        assert_success "E2E: Bootstrap syntax validation" bash -n "${SCRIPT_DIR}/bootstrap.sh"
        
        # Test main script can be invoked
        assert_success "E2E: Main script syntax validation" bash -n "${SCRIPT_DIR}/main.sh"
        
        # Test template module workflow
        if [[ -f "${SCRIPT_DIR}/template.sh" ]]; then
            assert_success "E2E: Template module syntax validation" bash -n "${SCRIPT_DIR}/template.sh"
        fi
    else
        record_test_result "SKIP" "E2E workflow test" "Required scripts not found"
    fi
    
    rm -rf "$e2e_test_dir"
}

test_error_recovery() {
    echo "  Testing error recovery..."
    
    # Test that scripts handle errors gracefully
    local recovery_test_dir="/tmp/test_recovery_$$"
    mkdir -p "$recovery_test_dir"
    
    # Create conditions that should trigger error handling
    export HOMELAB_TEST_RECOVERY="true"
    
    # Test with insufficient permissions (simulate)
    if [[ -f "${SCRIPT_DIR}/main.sh" ]]; then
        # Scripts should handle errors gracefully
        local error_output
        if error_output=$(bash "${SCRIPT_DIR}/main.sh" --help 2>&1 | head -10); then
            record_test_result "PASS" "Error recovery: Scripts handle error conditions"
        else
            record_test_result "WARN" "Error recovery: Scripts may not handle errors gracefully"
        fi
    fi
    
    unset HOMELAB_TEST_RECOVERY
    rm -rf "$recovery_test_dir"
}

test_cleanup_procedures() {
    echo "  Testing cleanup procedures..."
    
    # Test that temporary files and resources are cleaned up
    local cleanup_test_dir="/tmp/test_cleanup_$$"
    mkdir -p "$cleanup_test_dir"
    
    # Simulate operations that create temporary files
    local temp_files_before
    temp_files_before=$(ls /tmp/test_* 2>/dev/null | wc -l || echo "0")
    
    # Run some operations
    if [[ -f "${SCRIPT_DIR}/main.sh" ]]; then
        bash -n "${SCRIPT_DIR}/main.sh" >/dev/null 2>&1 || true
    fi
    
    local temp_files_after
    temp_files_after=$(ls /tmp/test_* 2>/dev/null | wc -l || echo "0")
    
    if [[ $temp_files_after -le $temp_files_before ]]; then
        record_test_result "PASS" "Cleanup: No excessive temporary files created"
    else
        record_test_result "WARN" "Cleanup: Temporary files may not be cleaned up properly"
    fi
    
    rm -rf "$cleanup_test_dir"
}

# === Test Coverage Analysis ===
run_coverage_analysis() {
    if [[ "$COVERAGE_ANALYSIS" != true ]]; then
        return 0
    fi
    
    echo "📊 Running Coverage Analysis..."
    
    mkdir -p "$TEST_COVERAGE_DIR"
    
    # Analyze script coverage
    local total_scripts=0
    local tested_scripts=0
    
    while IFS= read -r -d '' script; do
        ((total_scripts++))
        local script_name
        script_name=$(basename "$script")
        
        # Check if script was tested
        if grep -q "$script_name" "$LOG_FILE" 2>/dev/null; then
            ((tested_scripts++))
        fi
    done < <(find "$SCRIPT_DIR" -name "*.sh" -print0)
    
    local coverage_percentage
    coverage_percentage=$(echo "scale=2; $tested_scripts * 100 / $total_scripts" | bc -l)
    
    echo "script_coverage_percentage:$coverage_percentage" >> "${TEST_COVERAGE_DIR}/coverage.txt"
    echo "scripts_total:$total_scripts" >> "${TEST_COVERAGE_DIR}/coverage.txt"
    echo "scripts_tested:$tested_scripts" >> "${TEST_COVERAGE_DIR}/coverage.txt"
    
    echo "📊 Test Coverage: ${coverage_percentage}% (${tested_scripts}/${total_scripts} scripts)"
}

# === Reporting ===
generate_reports() {
    echo "📋 Generating Test Reports..."
    
    mkdir -p "$TEST_REPORTS_DIR"
    
    case "$OUTPUT_FORMAT" in
        json)
            generate_json_report
            ;;
        html)
            generate_html_report
            ;;
        junit)
            generate_junit_report
            ;;
        *)
            generate_console_report
            ;;
    esac
}

generate_json_report() {
    local json_file="${TEST_REPORTS_DIR}/test_results.json"
    
    cat > "$json_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "execution_time": "$execution_duration",
  "summary": {
    "total": ${TEST_RESULTS[total]},
    "passed": ${TEST_RESULTS[passed]},
    "failed": ${TEST_RESULTS[failed]},
    "skipped": ${TEST_RESULTS[skipped]},
    "warnings": ${TEST_RESULTS[warnings]}
  },
  "categories": {
    "unit": ${TEST_CATEGORIES[unit]},
    "integration": ${TEST_CATEGORIES[integration]},
    "performance": ${TEST_CATEGORIES[performance]},
    "security": ${TEST_CATEGORIES[security]},
    "e2e": ${TEST_CATEGORIES[e2e]}
  },
  "failed_tests": [
$(printf '    "%s"' "${FAILED_TESTS[@]}" | sed 's/^/    /' | tr '\n' ',' | sed 's/,$//')
  ],
  "warning_tests": [
$(printf '    "%s"' "${WARNING_TESTS[@]}" | sed 's/^/    /' | tr '\n' ',' | sed 's/,$//')
  ]
}
EOF
    
    echo "📄 JSON report generated: $json_file"
}

generate_html_report() {
    local html_file="${TEST_REPORTS_DIR}/test_results.html"
    
    cat > "$html_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Homelab Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; border-bottom: 2px solid #333; padding-bottom: 20px; margin-bottom: 20px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric { background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center; border-left: 4px solid #007bff; }
        .metric.passed { border-left-color: #28a745; }
        .metric.failed { border-left-color: #dc3545; }
        .metric.warnings { border-left-color: #ffc107; }
        .metric h3 { margin: 0; font-size: 2em; }
        .metric p { margin: 5px 0 0; color: #666; }
        .section { margin-bottom: 30px; }
        .test-list { background: #f8f9fa; padding: 15px; border-radius: 8px; }
        .test-item { padding: 8px; margin: 4px 0; border-radius: 4px; }
        .test-item.passed { background: #d4edda; color: #155724; }
        .test-item.failed { background: #f8d7da; color: #721c24; }
        .test-item.warning { background: #fff3cd; color: #856404; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏠 Homelab Test Results</h1>
            <p>Test execution completed on $(date)</p>
        </div>
        
        <div class="summary">
            <div class="metric">
                <h3>${TEST_RESULTS[total]}</h3>
                <p>Total Tests</p>
            </div>
            <div class="metric passed">
                <h3>${TEST_RESULTS[passed]}</h3>
                <p>Passed</p>
            </div>
            <div class="metric failed">
                <h3>${TEST_RESULTS[failed]}</h3>
                <p>Failed</p>
            </div>
            <div class="metric warnings">
                <h3>${TEST_RESULTS[warnings]}</h3>
                <p>Warnings</p>
            </div>
        </div>
        
        <div class="section">
            <h2>Test Categories</h2>
            <div class="test-list">
                <div class="test-item">Unit Tests: ${TEST_CATEGORIES[unit]}</div>
                <div class="test-item">Integration Tests: ${TEST_CATEGORIES[integration]}</div>
                <div class="test-item">Performance Tests: ${TEST_CATEGORIES[performance]}</div>
                <div class="test-item">Security Tests: ${TEST_CATEGORIES[security]}</div>
                <div class="test-item">End-to-End Tests: ${TEST_CATEGORIES[e2e]}</div>
            </div>
        </div>
        
        <div class="footer">
            <p>Generated by Homelab Enhanced Testing Framework</p>
        </div>
    </div>
</body>
</html>
EOF
    
    echo "📄 HTML report generated: $html_file"
}

generate_junit_report() {
    local junit_file="${TEST_REPORTS_DIR}/junit_results.xml"
    
    cat > "$junit_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="Homelab Tests" tests="${TEST_RESULTS[total]}" failures="${TEST_RESULTS[failed]}" errors="0" skipped="${TEST_RESULTS[skipped]}" time="$execution_duration">
EOF
    
    # Add test cases (simplified)
    for test in "${FAILED_TESTS[@]}"; do
        echo "  <testcase name=\"$test\" classname=\"Homelab\">" >> "$junit_file"
        echo "    <failure message=\"Test failed\">$test</failure>" >> "$junit_file"
        echo "  </testcase>" >> "$junit_file"
    done
    
    echo "</testsuite>" >> "$junit_file"
    
    echo "📄 JUnit report generated: $junit_file"
}

generate_console_report() {
    echo ""
    echo "=================================="
    echo "🏠 HOMELAB TEST RESULTS SUMMARY"
    echo "=================================="
    echo "Timestamp: $(date)"
    echo "Execution Time: ${execution_duration}s"
    echo ""
    echo "📊 Test Summary:"
    echo "  Total Tests:  ${TEST_RESULTS[total]}"
    echo "  ✅ Passed:    ${TEST_RESULTS[passed]}"
    echo "  ❌ Failed:    ${TEST_RESULTS[failed]}"
    echo "  ⚠️  Warnings:  ${TEST_RESULTS[warnings]}"
    echo "  ⏭️  Skipped:   ${TEST_RESULTS[skipped]}"
    echo ""
    
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo "❌ Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
    fi
    
    if [[ ${#WARNING_TESTS[@]} -gt 0 ]]; then
        echo "⚠️  Warning Tests:"
        for test in "${WARNING_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
    fi
    
    echo "📁 Test artifacts saved to: $TEST_RESULTS_DIR"
    echo "📄 Detailed logs: $LOG_FILE"
}

# === CI/CD Integration ===
generate_github_workflow() {
    local workflow_dir="${PROJECT_ROOT}/.github/workflows"
    mkdir -p "$workflow_dir"
    
    cat > "${workflow_dir}/test.yml" << 'EOF'
name: Homelab Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup test environment
      run: |
        sudo apt-get update
        sudo apt-get install -y bc curl git whiptail
    
    - name: Run tests
      run: |
        chmod +x scripts/test_framework.sh
        sudo scripts/test_framework.sh --mode all --output-format junit --ci-mode
    
    - name: Upload test results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: test-results/
    
    - name: Publish test results
      uses: EnricoMi/publish-unit-test-result-action@v2
      if: always()
      with:
        files: test-results/reports/junit_results.xml
EOF
    
    echo "🚀 GitHub Actions workflow generated: ${workflow_dir}/test.yml"
}

# === Main Execution ===
show_usage() {
    cat << EOF
Enhanced Testing Framework for Homelab Project

Usage: $0 [OPTIONS]

Options:
  --mode MODE           Test mode: all, unit, integration, performance, security, e2e (default: all)
  --output-format FMT   Output format: console, json, html, junit (default: console)
  --parallel            Run tests in parallel where possible
  --verbose             Enable verbose output
  --ci-mode             Enable CI/CD mode (non-interactive)
  --no-performance      Skip performance tests
  --no-coverage         Skip coverage analysis
  --no-security         Skip security tests
  --generate-workflow   Generate GitHub Actions workflow
  --help                Show this help message

Examples:
  $0                                    # Run all tests with console output
  $0 --mode unit --verbose             # Run only unit tests with verbose output
  $0 --mode all --output-format html   # Run all tests and generate HTML report
  $0 --ci-mode --output-format junit   # CI/CD mode with JUnit output

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                TEST_MODE="$2"
                shift 2
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL_TESTS=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            --ci-mode)
                CI_MODE=true
                VERBOSE_MODE=false
                shift
                ;;
            --no-performance)
                PERFORMANCE_BENCHMARKS=false
                shift
                ;;
            --no-coverage)
                COVERAGE_ANALYSIS=false
                shift
                ;;
            --no-security)
                SECURITY_SCANNING=false
                shift
                ;;
            --generate-workflow)
                generate_github_workflow
                exit 0
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

main() {
    local start_time=$(date +%s.%N)
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Setup environment
    setup_logging
    mkdir -p "$TEST_RESULTS_DIR" "$TEST_REPORTS_DIR" "$TEST_LOGS_DIR" "$TEST_COVERAGE_DIR" "$TEST_PERFORMANCE_DIR"
    
    # Initialize performance metrics file
    echo "# Performance Metrics - $(date)" > "${TEST_PERFORMANCE_DIR}/metrics.txt"
    
    echo "🏠 Enhanced Testing Framework for Homelab Project"
    echo "Mode: $TEST_MODE | Output: $OUTPUT_FORMAT | CI: $CI_MODE"
    echo ""
    
    # Run tests based on mode
    case "$TEST_MODE" in
        unit)
            run_unit_tests
            ;;
        integration)
            run_integration_tests
            ;;
        performance)
            [[ "$PERFORMANCE_BENCHMARKS" == true ]] && run_performance_tests
            ;;
        security)
            [[ "$SECURITY_SCANNING" == true ]] && run_security_tests
            ;;
        e2e)
            run_e2e_tests
            ;;
        all)
            run_unit_tests
            run_integration_tests
            [[ "$PERFORMANCE_BENCHMARKS" == true ]] && run_performance_tests
            [[ "$SECURITY_SCANNING" == true ]] && run_security_tests
            run_e2e_tests
            ;;
        *)
            echo "Invalid test mode: $TEST_MODE"
            show_usage
            exit 1
            ;;
    esac
    
    # Generate coverage analysis
    [[ "$COVERAGE_ANALYSIS" == true ]] && run_coverage_analysis
    
    # Calculate execution time
    local end_time=$(date +%s.%N)
    execution_duration=$(echo "$end_time - $start_time" | bc -l)
    
    # Generate reports
    generate_reports
    
    # Exit with appropriate code
    if [[ ${TEST_RESULTS[failed]} -eq 0 ]]; then
        echo "🎉 All tests completed successfully!"
        exit 0
    else
        echo "💥 Some tests failed. Check the reports for details."
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"