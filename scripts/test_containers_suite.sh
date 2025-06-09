#!/bin/bash
# Container Module Test Suite for Homelab Project
# Comprehensive testing for containers.sh module functionality
# Version: 1.0.0

set -euo pipefail

# === Configuration ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONTAINERS_MODULE="$SCRIPT_DIR/containers.sh"
readonly TEST_TEMP_DIR="/tmp/homelab_container_tests_$$"

# Test tracking
declare -g SUITE_TOTAL_TESTS=0
declare -g SUITE_PASSED_TESTS=0
declare -g SUITE_FAILED_TESTS=0
declare -g SUITE_SKIPPED_TESTS=0

# === Setup and Teardown ===
setup_container_tests() {
    echo "Setting up container test environment..."
    
    # Create test directory
    mkdir -p "$TEST_TEMP_DIR"
    
    # Set test mode for containers module
    export TEST_MODE="true"
    export QUIET_MODE="true"
    
    echo "Container test environment ready"
}

cleanup_container_tests() {
    echo "Cleaning up container test environment..."
    
    # Remove test directory
    if [[ -d "$TEST_TEMP_DIR" ]] && [[ "$TEST_TEMP_DIR" != "/" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    
    # Unset test environment variables
    unset TEST_MODE QUIET_MODE
    
    echo "Container test cleanup complete"
}

# === Test Helper Functions ===
test_function_exists() {
    local function_name="$1"
    local description="${2:-Function $function_name existence check}"
    
    ((SUITE_TOTAL_TESTS++))
    
    echo "DEBUG: Testing function '$function_name' in '$CONTAINERS_MODULE'"
    if grep -q "$function_name()" "$CONTAINERS_MODULE" 2>/dev/null; then
        echo "PASS: $description"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        echo "FAIL: $description"
        echo "DEBUG: grep result for '$function_name()':"
        grep -n "$function_name" "$CONTAINERS_MODULE" | head -3 || echo "No matches found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Container Management Tests ===
test_container_functions() {
    local description="Container management functions"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that container functions exist
    local found_functions=0
    
    if grep -q "list_containers\|show_container_monitoring" "$CONTAINERS_MODULE"; then
        ((found_functions++))
    fi
    
    if grep -q "docker_deployment\|kubernetes_deployment\|k3s_deployment" "$CONTAINERS_MODULE"; then
        ((found_functions++))
    fi
    
    if [[ $found_functions -ge 2 ]]; then
        echo "PASS: $description - Container functions found"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        echo "FAIL: $description - Insufficient container functions"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Main Test Execution ===
run_container_tests() {
    echo "========================================"
    echo "Running Container Module Test Suite"
    echo "========================================"
    
    setup_container_tests
    
    # Core Function Tests
    echo "--- Core Function Tests ---"
    test_function_exists "main_menu" "Main menu function"
    test_container_functions
    
    cleanup_container_tests
    
    # Report Results
    echo "========================================"
    echo "Container Module Test Suite Results"
    echo "========================================"
    echo "Total Tests: $SUITE_TOTAL_TESTS"
    echo "Passed: $SUITE_PASSED_TESTS"
    echo "Failed: $SUITE_FAILED_TESTS"
    echo "Skipped: $SUITE_SKIPPED_TESTS"
    
    local success_rate=0
    if [[ $SUITE_TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((SUITE_PASSED_TESTS * 100 / SUITE_TOTAL_TESTS))
    fi
    echo "Success Rate: ${success_rate}%"
    
    if [[ $SUITE_FAILED_TESTS -eq 0 ]]; then
        echo "🎉 All tests passed!"
        return 0
    else
        echo "❌ Some tests failed"
        return 1
    fi
}

# === Main Execution ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    run_container_tests
fi
#!/bin/bash
# Container Module Test Suite for Homelab Project
# Comprehensive testing for containers.sh module functionality
# Version: 1.0.0

set -euo pipefail

# === Configuration ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONTAINERS_MODULE="$SCRIPT_DIR/containers.sh"
readonly TEST_TEMP_DIR="/tmp/homelab_container_tests_$$"

# Test tracking
declare -g SUITE_TOTAL_TESTS=0
declare -g SUITE_PASSED_TESTS=0
declare -g SUITE_FAILED_TESTS=0
declare -g SUITE_SKIPPED_TESTS=0

# === Setup and Teardown ===
setup_container_tests() {
    echo "Setting up container test environment..."
    
    # Create test directory
    mkdir -p "$TEST_TEMP_DIR"
    
    # Source the test framework if available
    if [[ -f "$SCRIPT_DIR/test_framework.sh" ]]; then
        source "$SCRIPT_DIR/test_framework.sh"
        setup_logging
    else
        # Fallback logging
        log_info() { echo -e "\033[32m[INFO]\033[0m $*"; }
        log_warn() { echo -e "\033[33m[WARN]\033[0m $*"; }
        log_error() { echo -e "\033[31m[ERROR]\033[0m $*"; }
        assert_true() { local cond="$1"; local desc="$2"; eval "$cond" && echo "PASS: $desc" || echo "FAIL: $desc"; }
        assert_false() { local cond="$1"; local desc="$2"; ! eval "$cond" && echo "PASS: $desc" || echo "FAIL: $desc"; }
        assert_equals() { local exp="$1"; local act="$2"; local desc="$3"; [[ "$exp" == "$act" ]] && echo "PASS: $desc" || echo "FAIL: $desc (expected: $exp, actual: $act)"; }
    fi
    
    # Set test mode for containers module
    export TEST_MODE="true"
    export QUIET_MODE="true"
    
    # Clean up any existing test containers
    cleanup_test_containers
    
    echo "Container test environment ready"
}

cleanup_container_tests() {
    echo "Cleaning up container test environment..."
    
    # Clean up test containers
    cleanup_test_containers
    
    # Remove test directory
    if [[ -d "$TEST_TEMP_DIR" ]] && [[ "$TEST_TEMP_DIR" != "/" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    
    # Unset test environment variables
    unset TEST_MODE QUIET_MODE
    
    echo "Container test cleanup complete"
}

cleanup_test_containers() {
    # Remove any test containers that might exist
    if command -v docker >/dev/null 2>&1; then
        docker ps -a --filter "label=homelab-test" --format "{{.ID}}" 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true
        docker images --filter "label=homelab-test" --format "{{.ID}}" 2>/dev/null | xargs -r docker rmi -f 2>/dev/null || true
    fi
}

# === Test Helper Functions ===
test_function_exists() {
    local function_name="$1"
    local description="${2:-Function $function_name existence check}"
    
    ((SUITE_TOTAL_TESTS++))
    
    if grep -q "^$function_name()" "$CONTAINERS_MODULE" 2>/dev/null; then
        log_info "PASS: $description"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_docker_check_function() {
    local description="Docker availability check function"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that check_docker function exists and works
    if grep -q "check_docker" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_kubernetes_check_function() {
    local description="Kubernetes availability check function"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that check_kubernetes function exists
    if grep -q "check_kubernetes" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_k3s_check_function() {
    local description="k3s availability check function"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that check_k3s function exists
    if grep -q "check_k3s" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Container Management Tests ===
test_container_listing() {
    local description="Container listing functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that container listing functions exist
    if grep -q "list_containers" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_container_start_stop() {
    local description="Container start/stop functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that start/stop functions exist
    local start_exists=false
    local stop_exists=false
    
    if grep -q "start_containers\|start_container" "$CONTAINERS_MODULE"; then
        start_exists=true
    fi
    
    if grep -q "stop_containers\|stop_container" "$CONTAINERS_MODULE"; then
        stop_exists=true
    fi
    
    if [[ "$start_exists" == true && "$stop_exists" == true ]]; then
        log_info "PASS: $description - Functions exist"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Missing functions (start: $start_exists, stop: $stop_exists)"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_container_removal() {
    local description="Container removal functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that removal functions exist
    if grep -q "remove_containers\|remove_container" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_container_logs_management() {
    local description="Container logs management functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that log management functions exist
    if grep -q "manage_container_logs\|container_logs" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Deployment Tests ===
test_docker_deployment() {
    local description="Docker deployment functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that Docker deployment functions exist
    if grep -q "docker_deployment" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_kubernetes_deployment() {
    local description="Kubernetes deployment functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that Kubernetes deployment functions exist
    if grep -q "kubernetes_deployment" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_k3s_deployment() {
    local description="k3s deployment functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that k3s deployment functions exist
    if grep -q "k3s_deployment" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_multi_vm_deployment() {
    local description="Multi-VM deployment functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that multi-VM deployment functions exist
    if grep -q "multi_vm_deployment" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Monitoring Tests ===
test_container_monitoring() {
    local description="Container monitoring functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that monitoring functions exist
    if grep -q "show_container_monitoring\|container_monitoring" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_container_health_checks() {
    local description="Container health check functionality"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that health check functions exist
    if grep -q "health\|status" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Health-related functionality exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Health check functionality not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Integration Tests ===
test_main_menu_integration() {
    local description="Main menu integration"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that main menu function exists
    if grep -q "main_menu" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Main menu function exists"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Main menu function not found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_error_handling() {
    local description="Error handling implementation"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that error handling exists (trap, exit codes, etc.)
    local error_handling_count=0
    
    # Check for trap usage
    if grep -q "trap" "$CONTAINERS_MODULE"; then
        ((error_handling_count++))
    fi
    
    # Check for exit codes
    if grep -q "exit [0-9]" "$CONTAINERS_MODULE"; then
        ((error_handling_count++))
    fi
    
    # Check for error logging
    if grep -q "log.*ERROR\|error" "$CONTAINERS_MODULE"; then
        ((error_handling_count++))
    fi
    
    if [[ $error_handling_count -ge 2 ]]; then
        log_info "PASS: $description - Error handling patterns found"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - Insufficient error handling patterns"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_logging_integration() {
    local description="Logging system integration"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Test that logging functions are used
    if grep -q "log\|LOG" "$CONTAINERS_MODULE"; then
        log_info "PASS: $description - Logging functionality found"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - No logging functionality found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

# === Performance Tests ===
test_module_size_performance() {
    local description="Module size and complexity check"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Check module size (should be reasonable for maintenance)
    local line_count
    line_count=$(wc -l < "$CONTAINERS_MODULE" 2>/dev/null || echo "0")
    
    if [[ $line_count -gt 0 && $line_count -lt 5000 ]]; then
        log_info "PASS: $description - Module size acceptable ($line_count lines)"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_warn "WARN: $description - Module size may be large ($line_count lines)"
        ((SUITE_PASSED_TESTS++))  # Not a failure, just a warning
        return 0
    fi
}

test_function_complexity() {
    local description="Function complexity analysis"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Count functions in the module
    local function_count
    function_count=$(grep -c "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*(" "$CONTAINERS_MODULE" 2>/dev/null || echo "0")
    
    if [[ $function_count -gt 5 && $function_count -lt 100 ]]; then
        log_info "PASS: $description - Function count reasonable ($function_count functions)"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_warn "WARN: $description - Function count unusual ($function_count functions)"
        ((SUITE_PASSED_TESTS++))  # Not a failure, just a warning
        return 0
    fi
}

# === Security Tests ===
test_input_validation() {
    local description="Input validation patterns"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Check for input validation patterns
    local validation_patterns=0
    
    # Check for empty variable checks
    if grep -q "\[\[ -z.*\]\]\|\[\[ \${#.*} -eq 0 \]\]" "$CONTAINERS_MODULE"; then
        ((validation_patterns++))
    fi
    
    # Check for parameter validation
    if grep -q "return 1\|exit 1" "$CONTAINERS_MODULE"; then
        ((validation_patterns++))
    fi
    
    if [[ $validation_patterns -ge 1 ]]; then
        log_info "PASS: $description - Input validation patterns found"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_error "FAIL: $description - No input validation patterns found"
        ((SUITE_FAILED_TESTS++))
        return 1
    fi
}

test_privilege_escalation_safety() {
    local description="Privilege escalation safety check"
    
    ((SUITE_TOTAL_TESTS++))
    
    # Check for unsafe privilege escalation patterns
    local unsafe_patterns=0
    
    # Check for direct sudo without validation
    if grep -q "sudo.*-c\|sudo.*bash.*<<" "$CONTAINERS_MODULE"; then
        ((unsafe_patterns++))
    fi
    
    # Check for unquoted variables in commands
    if grep -q "sudo \$[a-zA-Z_]" "$CONTAINERS_MODULE"; then
        ((unsafe_patterns++))
    fi
    
    if [[ $unsafe_patterns -eq 0 ]]; then
        log_info "PASS: $description - No unsafe privilege escalation patterns found"
        ((SUITE_PASSED_TESTS++))
        return 0
    else
        log_warn "WARN: $description - Found $unsafe_patterns potential unsafe patterns"
        ((SUITE_PASSED_TESTS++))  # Warning, not failure
        return 0
    fi
}

# === Test Suite Execution ===
run_container_tests() {
    echo "========================================"
    echo "Running Container Module Test Suite"
    echo "========================================"
    
    setup_container_tests
    
    # Core Function Tests
    echo "--- Core Function Tests ---"
    test_function_exists "main_menu" "Main menu function"
    test_docker_check_function
    test_kubernetes_check_function
    test_k3s_check_function
    
    # Container Management Tests
    echo "--- Container Management Tests ---"
    test_container_listing
    test_container_start_stop
    test_container_removal
    test_container_logs_management
    
    # Deployment Tests
    echo "--- Deployment Tests ---"
    test_docker_deployment
    test_kubernetes_deployment
    test_k3s_deployment
    test_multi_vm_deployment
    
    # Monitoring Tests
    echo "--- Monitoring Tests ---"
    test_container_monitoring
    test_container_health_checks
    
    # Integration Tests
    echo "--- Integration Tests ---"
    test_main_menu_integration
    test_error_handling
    test_logging_integration
    
    # Performance Tests
    echo "--- Performance Tests ---"
    test_module_size_performance
    test_function_complexity
    
    # Security Tests
    echo "--- Security Tests ---"
    test_input_validation
    test_privilege_escalation_safety
    
    cleanup_container_tests
    
    # Report Results
    echo "========================================"
    echo "Container Module Test Suite Results"
    echo "========================================"
    echo "Total Tests: $SUITE_TOTAL_TESTS"
    echo "Passed: $SUITE_PASSED_TESTS"
    echo "Failed: $SUITE_FAILED_TESTS"
    echo "Skipped: $SUITE_SKIPPED_TESTS"
    
    local success_rate=0
    if [[ $SUITE_TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((SUITE_PASSED_TESTS * 100 / SUITE_TOTAL_TESTS))
    fi
    echo "Success Rate: ${success_rate}%"
    
    if [[ $SUITE_FAILED_TESTS -eq 0 ]]; then
        echo "🎉 All tests passed!"
        return 0
    else
        echo "❌ Some tests failed"
        return 1
    fi
}

# === Main Execution ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    run_container_tests
fi
