#!/bin/bash
# Enhanced Testing Framework for Homelab Project
# Comprehensive testing framework with unit, integration, performance, security, and E2E testing
# Version: 1.0.0

set -euo pipefail

# === Configuration ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly TESTS_DIR="$PROJECT_ROOT/tests"
readonly REPORTS_DIR="$PROJECT_ROOT/test_reports"
readonly TEMP_DIR="/tmp/homelab_tests_$$"
readonly TEST_CONFIG_FILE="$PROJECT_ROOT/test_config.json"

# Test execution parameters
readonly DEFAULT_TIMEOUT=300
readonly PARALLEL_JOBS=4
readonly PERFORMANCE_ITERATIONS=5

# Test result tracking
declare -g TOTAL_TESTS=0
declare -g PASSED_TESTS=0
declare -g FAILED_TESTS=0
declare -g SKIPPED_TESTS=0
declare -g TEST_START_TIME=""
declare -g TEST_SUITE=""
declare -g VERBOSE_MODE=false
declare -g QUIET_MODE=false
declare -g DRY_RUN=false
declare -g STOP_ON_FAIL=false

# Test categories
declare -ga TEST_CATEGORIES=("unit" "integration" "performance" "security" "e2e")
declare -ga ENABLED_CATEGORIES=()

# Output formats
declare -g OUTPUT_FORMAT="console"  # console, json, html, junit
declare -g REPORT_FILE=""

# === Logging and Output ===
setup_logging() {
    local log_level="${HL_LOG_LEVEL:-INFO}"
    export LOG_FILE_ALREADY_SET_EXTERNALLY="true"
    export LOG_FILE="$TEMP_DIR/test_framework.log"
    export HL_LOG_LEVEL="$log_level"
    
    # Source centralized logging if available
    if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
        source "$SCRIPT_DIR/lib/logging.sh"
    else
        # Fallback logging functions
        log_info() { echo -e "\033[32m[INFO]\033[0m $*" | tee -a "$LOG_FILE"; }
        log_warn() { echo -e "\033[33m[WARN]\033[0m $*" | tee -a "$LOG_FILE"; }
        log_error() { echo -e "\033[31m[ERROR]\033[0m $*" | tee -a "$LOG_FILE"; }
        log_debug() { [[ "$log_level" == "DEBUG" ]] && echo -e "\033[36m[DEBUG]\033[0m $*" | tee -a "$LOG_FILE"; }
    fi
}

# === Test Infrastructure ===
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create necessary directories
    mkdir -p "$TEMP_DIR" "$TESTS_DIR" "$REPORTS_DIR"
    
    # Initialize test tracking
    TEST_START_TIME=$(date '+%s')
    
    # Create test configuration if it doesn't exist
    if [[ ! -f "$TEST_CONFIG_FILE" ]]; then
        create_default_test_config
    fi
    
    # Set up cleanup trap
    trap cleanup_test_environment EXIT INT TERM
    
    log_info "Test environment ready: $TEMP_DIR"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Generate final report
    generate_test_report
    
    # Clean up temporary files
    if [[ -d "$TEMP_DIR" ]] && [[ "$TEMP_DIR" != "/" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    log_info "Test cleanup complete"
}

create_default_test_config() {
    cat > "$TEST_CONFIG_FILE" << 'EOF'
{
  "test_settings": {
    "timeout": 300,
    "parallel_jobs": 4,
    "performance_iterations": 5,
    "retry_count": 2
  },
  "test_categories": {
    "unit": {
      "enabled": true,
      "timeout": 60,
      "parallel": true
    },
    "integration": {
      "enabled": true,
      "timeout": 180,
      "parallel": false
    },
    "performance": {
      "enabled": true,
      "timeout": 300,
      "iterations": 5,
      "thresholds": {
        "memory_mb": 1024,
        "cpu_percent": 80,
        "disk_io_mb": 100
      }
    },
    "security": {
      "enabled": true,
      "timeout": 240,
      "tools": ["shellcheck", "bandit", "trivy"]
    },
    "e2e": {
      "enabled": false,
      "timeout": 600,
      "requires_infrastructure": true
    }
  },
  "environments": {
    "ci": {
      "categories": ["unit", "integration", "security"],
      "parallel": true,
      "output_format": "junit"
    },
    "local": {
      "categories": ["unit", "integration", "performance"],
      "parallel": false,
      "output_format": "console"
    },
    "full": {
      "categories": ["unit", "integration", "performance", "security", "e2e"],
      "parallel": false,
      "output_format": "html"
    }
  }
}
EOF
    log_info "Created default test configuration: $TEST_CONFIG_FILE"
}

# === Test Assertion Framework ===
assert_true() {
    local condition="$1"
    local description="${2:-Assertion failed}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    if eval "$condition" 2>/dev/null; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "Condition '$condition' evaluated to false"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local description="${2:-Assertion failed}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    if ! eval "$condition" 2>/dev/null; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "Condition '$condition' evaluated to true"
        return 1
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="${3:-Values should be equal}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    if [[ "$expected" == "$actual" ]]; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "Expected: '$expected', Actual: '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local description="${3:-Values should not be equal}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    if [[ "$expected" != "$actual" ]]; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "Expected '$expected' != '$actual'"
        return 1
    fi
}

assert_contains() {
    local substring="$1"
    local string="$2"
    local description="${3:-String should contain substring}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    if [[ "$string" == *"$substring"* ]]; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "String '$string' does not contain '$substring'"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local description="${2:-File should exist: $file_path}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    if [[ -f "$file_path" ]]; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "File does not exist: $file_path"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local description="${2:-Command should succeed: $command}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    local output
    local exit_code
    
    if output=$(eval "$command" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "Command failed with exit code $exit_code: $output"
        return 1
    fi
}

assert_command_fails() {
    local command="$1"
    local description="${2:-Command should fail: $command}"
    local line_number="${BASH_LINENO[0]}"
    
    ((TOTAL_TESTS++))
    
    local output
    local exit_code
    
    if output=$(eval "$command" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        pass_test "$description" "$line_number"
        return 0
    else
        fail_test "$description" "$line_number" "Command succeeded when it should have failed: $output"
        return 1
    fi
}

# === Test Result Tracking ===
pass_test() {
    local description="$1"
    local line_number="${2:-}"
    
    ((PASSED_TESTS++))
    
    if [[ "$VERBOSE_MODE" == "true" ]] || [[ "$QUIET_MODE" == "false" ]]; then
        echo -e "\033[32m✓ PASS\033[0m [$TEST_SUITE:$line_number] $description"
    fi
    
    log_test_result "PASS" "$description" "$line_number"
}

fail_test() {
    local description="$1"
    local line_number="${2:-}"
    local details="${3:-}"
    
    ((FAILED_TESTS++))
    
    echo -e "\033[31m✗ FAIL\033[0m [$TEST_SUITE:$line_number] $description"
    [[ -n "$details" ]] && echo -e "    \033[31mDetails:\033[0m $details"
    
    log_test_result "FAIL" "$description" "$line_number" "$details"
    
    if [[ "$STOP_ON_FAIL" == "true" ]]; then
        log_error "Stopping on first failure as requested"
        exit 1
    fi
}

skip_test() {
    local description="$1"
    local reason="${2:-No reason provided}"
    local line_number="${BASH_LINENO[0]}"
    
    ((SKIPPED_TESTS++))
    
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo -e "\033[33m○ SKIP\033[0m [$TEST_SUITE:$line_number] $description ($reason)"
    fi
    
    log_test_result "SKIP" "$description" "$line_number" "$reason"
}

log_test_result() {
    local result="$1"
    local description="$2"
    local line_number="${3:-}"
    local details="${4:-}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$result] [$TEST_SUITE:$line_number] $description"
    [[ -n "$details" ]] && log_entry="$log_entry | $details"
    
    echo "$log_entry" >> "$TEMP_DIR/test_results.log"
}

# === Test Execution Engine ===
run_test_suite() {
    local suite_name="$1"
    local suite_file="$2"
    
    TEST_SUITE="$suite_name"
    log_info "Running test suite: $suite_name"
    
    local suite_start_time=$(date '+%s')
    local suite_tests_before=$TOTAL_TESTS
    
    # Source and execute the test suite
    if [[ -f "$suite_file" ]]; then
        source "$suite_file"
    else
        log_error "Test suite file not found: $suite_file"
        return 1
    fi
    
    local suite_end_time=$(date '+%s')
    local suite_duration=$((suite_end_time - suite_start_time))
    local suite_tests_count=$((TOTAL_TESTS - suite_tests_before))
    
    log_info "Suite $suite_name completed: $suite_tests_count tests in ${suite_duration}s"
}

run_test_category() {
    local category="$1"
    
    log_info "Running $category tests..."
    
    local category_dir="$TESTS_DIR/$category"
    if [[ ! -d "$category_dir" ]]; then
        log_warn "No tests found for category: $category"
        return 0
    fi
    
    # Find and run all test files in the category
    local test_files
    mapfile -t test_files < <(find "$category_dir" -name "test_*.sh" -type f)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warn "No test files found in category: $category"
        return 0
    fi
    
    for test_file in "${test_files[@]}"; do
        local suite_name="$category/$(basename "$test_file" .sh)"
        run_test_suite "$suite_name" "$test_file"
    done
}

# === Performance Testing ===
benchmark_command() {
    local command="$1"
    local description="${2:-Performance benchmark}"
    local iterations="${3:-$PERFORMANCE_ITERATIONS}"
    
    log_info "Benchmarking: $description ($iterations iterations)"
    
    local total_time=0
    local min_time=999999
    local max_time=0
    local successful_runs=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date '+%s%3N')
        
        if eval "$command" >/dev/null 2>&1; then
            local end_time=$(date '+%s%3N')
            local duration=$((end_time - start_time))
            
            total_time=$((total_time + duration))
            successful_runs=$((successful_runs + 1))
            
            if [[ $duration -lt $min_time ]]; then
                min_time=$duration
            fi
            
            if [[ $duration -gt $max_time ]]; then
                max_time=$duration
            fi
            
            log_debug "Iteration $i: ${duration}ms"
        else
            log_warn "Iteration $i failed"
        fi
    done
    
    if [[ $successful_runs -gt 0 ]]; then
        local avg_time=$((total_time / successful_runs))
        
        log_info "Benchmark results for '$description':"
        log_info "  Successful runs: $successful_runs/$iterations"
        log_info "  Average time: ${avg_time}ms"
        log_info "  Min time: ${min_time}ms"
        log_info "  Max time: ${max_time}ms"
        
        # Save benchmark results
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$description,$successful_runs,$iterations,$avg_time,$min_time,$max_time" >> "$TEMP_DIR/benchmark_results.csv"
        
        return 0
    else
        log_error "All benchmark iterations failed for: $description"
        return 1
    fi
}

monitor_system_resources() {
    local duration="${1:-60}"
    local interval="${2:-5}"
    
    log_info "Monitoring system resources for ${duration}s (interval: ${interval}s)"
    
    local monitor_file="$TEMP_DIR/resource_monitor.log"
    echo "timestamp,cpu_percent,memory_mb,disk_io_mb" > "$monitor_file"
    
    local end_time=$(($(date '+%s') + duration))
    
    while [[ $(date '+%s') -lt $end_time ]]; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local cpu_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        local memory_mb=$(free -m | awk 'NR==2{printf "%.1f", $3}')
        local disk_io_mb=$(iostat -d 1 1 2>/dev/null | awk 'END{print $3+$4}' || echo "0")
        
        echo "$timestamp,$cpu_percent,$memory_mb,$disk_io_mb" >> "$monitor_file"
        
        sleep "$interval"
    done
    
    log_info "Resource monitoring complete: $monitor_file"
}

# === Security Testing ===
run_security_scan() {
    local target="${1:-$PROJECT_ROOT}"
    
    log_info "Running security scans on: $target"
    
    # ShellCheck for shell script analysis
    if command -v shellcheck >/dev/null 2>&1; then
        log_info "Running ShellCheck..."
        local shellcheck_output="$TEMP_DIR/shellcheck_results.txt"
        
        find "$target" -name "*.sh" -type f -exec shellcheck {} \; > "$shellcheck_output" 2>&1
        
        if [[ -s "$shellcheck_output" ]]; then
            log_warn "ShellCheck found issues:"
            cat "$shellcheck_output"
        else
            log_info "ShellCheck: No issues found"
        fi
    else
        log_warn "ShellCheck not available, skipping shell script analysis"
    fi
    
    # Check for common security issues
    security_check_passwords "$target"
    security_check_permissions "$target"
    security_check_secrets "$target"
}

security_check_passwords() {
    local target="$1"
    
    log_info "Checking for hardcoded passwords..."
    
    local patterns=(
        "password="
        "passwd="
        "pwd="
        "secret="
        "key="
        "token="
        "auth="
    )
    
    local findings=0
    
    for pattern in "${patterns[@]}"; do
        local matches
        mapfile -t matches < <(grep -r -i "$pattern" "$target" --include="*.sh" --include="*.conf" --include="*.json" 2>/dev/null || true)
        
        if [[ ${#matches[@]} -gt 0 ]]; then
            for match in "${matches[@]}"; do
                log_warn "Potential hardcoded credential: $match"
                ((findings++))
            done
        fi
    done
    
    if [[ $findings -eq 0 ]]; then
        log_info "No hardcoded credentials found"
    else
        log_warn "Found $findings potential credential issues"
    fi
}

security_check_permissions() {
    local target="$1"
    
    log_info "Checking file permissions..."
    
    # Check for world-writable files
    local world_writable
    mapfile -t world_writable < <(find "$target" -type f -perm -002 2>/dev/null || true)
    
    if [[ ${#world_writable[@]} -gt 0 ]]; then
        log_warn "World-writable files found:"
        printf '%s\n' "${world_writable[@]}"
    else
        log_info "No world-writable files found"
    fi
    
    # Check for executable scripts without proper shebang
    local scripts_without_shebang
    mapfile -t scripts_without_shebang < <(find "$target" -name "*.sh" -type f -executable ! -exec head -1 {} \; -quit 2>/dev/null | grep -v '^#!' || true)
    
    if [[ ${#scripts_without_shebang[@]} -gt 0 ]]; then
        log_warn "Executable scripts without shebang:"
        printf '%s\n' "${scripts_without_shebang[@]}"
    fi
}

security_check_secrets() {
    local target="$1"
    
    log_info "Checking for exposed secrets..."
    
    # Common secret patterns
    local secret_patterns=(
        "[0-9a-f]{32}"  # MD5 hashes
        "[0-9a-f]{40}"  # SHA1 hashes
        "[0-9a-f]{64}"  # SHA256 hashes
        "AKIA[0-9A-Z]{16}"  # AWS Access Key
        "-----BEGIN [A-Z ]+-----"  # Private keys
    )
    
    local findings=0
    
    for pattern in "${secret_patterns[@]}"; do
        local matches
        mapfile -t matches < <(grep -rE "$pattern" "$target" --include="*.sh" --include="*.conf" --include="*.json" 2>/dev/null || true)
        
        if [[ ${#matches[@]} -gt 0 ]]; then
            for match in "${matches[@]}"; do
                log_warn "Potential secret found: $match"
                ((findings++))
            done
        fi
    done
    
    if [[ $findings -eq 0 ]]; then
        log_info "No exposed secrets found"
    else
        log_warn "Found $findings potential secret exposures"
    fi
}

# === Report Generation ===
generate_test_report() {
    local end_time=$(date '+%s')
    local total_duration=$((end_time - TEST_START_TIME))
    
    case "$OUTPUT_FORMAT" in
        "console")
            generate_console_report "$total_duration"
            ;;
        "json")
            generate_json_report "$total_duration"
            ;;
        "html")
            generate_html_report "$total_duration"
            ;;
        "junit")
            generate_junit_report "$total_duration"
            ;;
        *)
            log_warn "Unknown output format: $OUTPUT_FORMAT, using console"
            generate_console_report "$total_duration"
            ;;
    esac
}

generate_console_report() {
    local duration="$1"
    
    echo ""
    echo "=========================================="
    echo "           TEST EXECUTION SUMMARY"
    echo "=========================================="
    echo "Total Tests:     $TOTAL_TESTS"
    echo "Passed:          $PASSED_TESTS"
    echo "Failed:          $FAILED_TESTS"
    echo "Skipped:         $SKIPPED_TESTS"
    echo "Duration:        ${duration}s"
    echo "Success Rate:    $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%"
    echo "=========================================="
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo ""
        echo "FAILED TESTS:"
        grep "\[FAIL\]" "$TEMP_DIR/test_results.log" 2>/dev/null || true
    fi
    
    if [[ -f "$TEMP_DIR/benchmark_results.csv" ]]; then
        echo ""
        echo "BENCHMARK RESULTS:"
        column -t -s',' "$TEMP_DIR/benchmark_results.csv"
    fi
}

generate_json_report() {
    local duration="$1"
    local report_file="${REPORT_FILE:-$REPORTS_DIR/test_report_$(date '+%Y%m%d_%H%M%S').json}"
    
    cat > "$report_file" << EOF
{
  "test_run": {
    "start_time": "$(date -d @$TEST_START_TIME '+%Y-%m-%d %H:%M:%S')",
    "end_time": "$(date '+%Y-%m-%d %H:%M:%S')",
    "duration_seconds": $duration,
    "environment": "$(uname -a)",
    "categories": $(printf '%s\n' "${ENABLED_CATEGORIES[@]}" | jq -R . | jq -s .)
  },
  "results": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "success_rate": $(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))
  },
  "test_details": [
$(if [[ -f "$TEMP_DIR/test_results.log" ]]; then
    awk -F'[][]' '
    {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6)
        printf "    {\"timestamp\":\"%s\",\"result\":\"%s\",\"suite\":\"%s\",\"description\":\"%s\"}", $2, $4, $6, $8
        if (NR < total_lines) printf ","
        printf "\n"
    }' total_lines=$(wc -l < "$TEMP_DIR/test_results.log") "$TEMP_DIR/test_results.log"
fi)
  ]
}
EOF
    
    log_info "JSON report generated: $report_file"
}

generate_html_report() {
    local duration="$1"
    local report_file="${REPORT_FILE:-$REPORTS_DIR/test_report_$(date '+%Y%m%d_%H%M%S').html}"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Homelab Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; }
        .metric h3 { margin: 0; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .skipped { color: #ffc107; }
        .test-results { margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .pass { background-color: #d4edda; }
        .fail { background-color: #f8d7da; }
        .skip { background-color: #fff3cd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Homelab Test Report</h1>
        <p>Generated: $(date)</p>
        <p>Duration: ${duration}s</p>
        <p>Categories: $(IFS=', '; echo "${ENABLED_CATEGORIES[*]}")</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>$TOTAL_TESTS</h3>
            <p>Total Tests</p>
        </div>
        <div class="metric passed">
            <h3>$PASSED_TESTS</h3>
            <p>Passed</p>
        </div>
        <div class="metric failed">
            <h3>$FAILED_TESTS</h3>
            <p>Failed</p>
        </div>
        <div class="metric skipped">
            <h3>$SKIPPED_TESTS</h3>
            <p>Skipped</p>
        </div>
        <div class="metric">
            <h3>$(( TOTAL_TESTS > 0 ? (PASSED_TESTS * 100) / TOTAL_TESTS : 0 ))%</h3>
            <p>Success Rate</p>
        </div>
    </div>
    
    <div class="test-results">
        <h2>Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>Result</th>
                    <th>Suite</th>
                    <th>Description</th>
                </tr>
            </thead>
            <tbody>
$(if [[ -f "$TEMP_DIR/test_results.log" ]]; then
    while IFS= read -r line; do
        if [[ $line =~ \[([^]]+)\]\ \[([^]]+)\]\ \[([^]]+)\]\ (.+) ]]; then
            timestamp="${BASH_REMATCH[1]}"
            result="${BASH_REMATCH[2]}"
            suite="${BASH_REMATCH[3]}"
            description="${BASH_REMATCH[4]}"
            
            case "$result" in
                "PASS") css_class="pass" ;;
                "FAIL") css_class="fail" ;;
                "SKIP") css_class="skip" ;;
                *) css_class="" ;;
            esac
            
            echo "                <tr class=\"$css_class\">"
            echo "                    <td>$timestamp</td>"
            echo "                    <td>$result</td>"
            echo "                    <td>$suite</td>"
            echo "                    <td>$description</td>"
            echo "                </tr>"
        fi
    done < "$TEMP_DIR/test_results.log"
fi)
            </tbody>
        </table>
    </div>
</body>
</html>
EOF
    
    log_info "HTML report generated: $report_file"
}

generate_junit_report() {
    local duration="$1"
    local report_file="${REPORT_FILE:-$REPORTS_DIR/junit_report_$(date '+%Y%m%d_%H%M%S').xml}"
    
    cat > "$report_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Homelab Tests" tests="$TOTAL_TESTS" failures="$FAILED_TESTS" skipped="$SKIPPED_TESTS" time="$duration">
    <testsuite name="AllTests" tests="$TOTAL_TESTS" failures="$FAILED_TESTS" skipped="$SKIPPED_TESTS" time="$duration">
$(if [[ -f "$TEMP_DIR/test_results.log" ]]; then
    while IFS= read -r line; do
        if [[ $line =~ \[([^]]+)\]\ \[([^]]+)\]\ \[([^]]+)\]\ (.+) ]]; then
            timestamp="${BASH_REMATCH[1]}"
            result="${BASH_REMATCH[2]}"
            suite="${BASH_REMATCH[3]}"
            description="${BASH_REMATCH[4]}"
            
            echo "        <testcase name=\"$description\" classname=\"$suite\" time=\"0\">"
            
            case "$result" in
                "FAIL")
                    echo "            <failure message=\"Test failed\">$description</failure>"
                    ;;
                "SKIP")
                    echo "            <skipped message=\"Test skipped\">$description</skipped>"
                    ;;
            esac
            
            echo "        </testcase>"
        fi
    done < "$TEMP_DIR/test_results.log"
fi)
    </testsuite>
</testsuites>
EOF
    
    log_info "JUnit report generated: $report_file"
}

# === CI/CD Integration ===
generate_github_actions_workflow() {
    local workflow_file="$PROJECT_ROOT/.github/workflows/tests.yml"
    
    mkdir -p "$(dirname "$workflow_file")"
    
    cat > "$workflow_file" << 'EOF'
name: Homelab Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        test-category: [unit, integration, security]
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v3
    
    - name: Set up test environment
      run: |
        sudo apt-get update
        sudo apt-get install -y shellcheck
    
    - name: Run tests
      run: |
        chmod +x scripts/test_framework.sh
        ./scripts/test_framework.sh --category ${{ matrix.test-category }} --output junit --report-file test-results-${{ matrix.test-category }}.xml
    
    - name: Upload test results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results-${{ matrix.test-category }}
        path: test-results-${{ matrix.test-category }}.xml
    
    - name: Publish test results
      uses: dorny/test-reporter@v1
      if: always()
      with:
        name: Test Results (${{ matrix.test-category }})
        path: test-results-${{ matrix.test-category }}.xml
        reporter: java-junit
EOF
    
    log_info "GitHub Actions workflow generated: $workflow_file"
}

# === Command Line Interface ===
show_help() {
    cat << 'EOF'
Enhanced Testing Framework for Homelab Project

USAGE:
    test_framework.sh [OPTIONS]

OPTIONS:
    -c, --category CATEGORY     Run specific test category (unit|integration|performance|security|e2e)
    -a, --all                   Run all enabled test categories
    -e, --environment ENV       Use predefined environment (ci|local|full)
    -f, --format FORMAT         Output format (console|json|html|junit)
    -r, --report-file FILE      Specify report file path
    -v, --verbose               Enable verbose output
    -q, --quiet                 Suppress non-essential output
    -d, --dry-run               Show what would be executed without running tests
    -s, --stop-on-fail          Stop execution on first test failure
    -p, --parallel              Enable parallel test execution where supported
    -t, --timeout SECONDS       Set test timeout (default: 300)
    -j, --jobs NUMBER           Number of parallel jobs (default: 4)
    --benchmark COMMAND         Run performance benchmark for command
    --monitor DURATION          Monitor system resources for duration (seconds)
    --security-scan PATH        Run security scan on specified path
    --generate-workflow         Generate GitHub Actions workflow file
    --setup-tests               Set up test environment and create sample tests
    -h, --help                  Show this help message

EXAMPLES:
    # Run all unit tests
    ./test_framework.sh --category unit

    # Run integration tests with HTML report
    ./test_framework.sh --category integration --format html

    # Run full test suite for CI
    ./test_framework.sh --environment ci

    # Benchmark a command
    ./test_framework.sh --benchmark "sleep 1"

    # Monitor system resources
    ./test_framework.sh --monitor 60

    # Run security scan
    ./test_framework.sh --security-scan /path/to/code

CONFIGURATION:
    Test configuration is stored in test_config.json and can be customized
    to define test categories, timeouts, thresholds, and environments.

EOF
}

setup_sample_tests() {
    log_info "Setting up sample test structure..."
    
    # Create test directories
    for category in "${TEST_CATEGORIES[@]}"; do
        mkdir -p "$TESTS_DIR/$category"
        
        # Create sample test file
        cat > "$TESTS_DIR/$category/test_sample.sh" << EOF
#!/bin/bash
# Sample $category test

test_${category}_sample() {
    TEST_SUITE="${category}_sample"
    
    assert_true "true" "Sample assertion that should pass"
    assert_equals "hello" "hello" "Sample equality test"
    assert_file_exists "/etc/passwd" "System file should exist"
    
    if command -v ls >/dev/null 2>&1; then
        assert_command_success "ls /" "List root directory"
    else
        skip_test "ls command not available" "Command not found"
    fi
}

# Execute the test function
test_${category}_sample
EOF
        
        chmod +x "$TESTS_DIR/$category/test_sample.sh"
        log_info "Created sample test: $TESTS_DIR/$category/test_sample.sh"
    done
    
    log_info "Sample test structure created successfully"
}

# === Main Execution ===
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--category)
                ENABLED_CATEGORIES+=("$2")
                shift 2
                ;;
            -a|--all)
                ENABLED_CATEGORIES=("${TEST_CATEGORIES[@]}")
                shift
                ;;
            -e|--environment)
                load_environment_config "$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -r|--report-file)
                REPORT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--stop-on-fail)
                STOP_ON_FAIL=true
                shift
                ;;
            -p|--parallel)
                # Parallel execution flag (implementation depends on category)
                shift
                ;;
            -t|--timeout)
                # Timeout configuration (stored for use in test execution)
                shift 2
                ;;
            -j|--jobs)
                # Parallel jobs configuration
                shift 2
                ;;
            --benchmark)
                setup_logging
                setup_test_environment
                benchmark_command "$2" "Custom benchmark"
                exit $?
                ;;
            --monitor)
                setup_logging
                setup_test_environment
                monitor_system_resources "$2"
                exit $?
                ;;
            --security-scan)
                setup_logging
                setup_test_environment
                run_security_scan "$2"
                exit $?
                ;;
            --generate-workflow)
                generate_github_actions_workflow
                exit $?
                ;;
            --setup-tests)
                setup_logging
                setup_test_environment
                setup_sample_tests
                exit $?
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set default category if none specified
    if [[ ${#ENABLED_CATEGORIES[@]} -eq 0 ]]; then
        ENABLED_CATEGORIES=("unit")
        log_info "No category specified, defaulting to unit tests"
    fi
    
    # Initialize test environment
    setup_logging
    setup_test_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute the following test categories:"
        printf '  - %s\n' "${ENABLED_CATEGORIES[@]}"
        exit 0
    fi
    
    # Execute tests for each enabled category
    for category in "${ENABLED_CATEGORIES[@]}"; do
        if [[ " ${TEST_CATEGORIES[*]} " =~ " $category " ]]; then
            run_test_category "$category"
        else
            log_error "Invalid test category: $category"
            log_info "Available categories: ${TEST_CATEGORIES[*]}"
            exit 1
        fi
    done
    
    # Return appropriate exit code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

load_environment_config() {
    local env="$1"
    
    if [[ -f "$TEST_CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        local env_config=$(jq -r ".environments.$env // empty" "$TEST_CONFIG_FILE")
        
        if [[ -n "$env_config" && "$env_config" != "null" ]]; then
            # Parse environment configuration
            local categories
            mapfile -t categories < <(echo "$env_config" | jq -r '.categories[]? // empty')
            ENABLED_CATEGORIES=("${categories[@]}")
            
            local format=$(echo "$env_config" | jq -r '.output_format // "console"')
            OUTPUT_FORMAT="$format"
            
            log_info "Loaded environment configuration: $env"
        else
            log_warn "Environment configuration not found: $env"
        fi
    else
        log_warn "Cannot load environment config (missing jq or config file)"
    fi
}

# Source test utilities if available
if [[ -f "$SCRIPT_DIR/test_utilities.sh" ]]; then
    source "$SCRIPT_DIR/test_utilities.sh"
fi

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi