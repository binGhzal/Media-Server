#!/bin/bash
# Simple Container Module Test Suite
# Version: 1.0.0

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_MODULE="$SCRIPT_DIR/containers.sh"

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test function existence
test_function_exists() {
    local function_name="$1"
    local description="$2"
    
    ((TOTAL_TESTS++))
    
    if grep -q "${function_name}()" "$CONTAINERS_MODULE"; then
        echo "PASS: $description"
        ((PASSED_TESTS++))
        return 0
    else
        echo "FAIL: $description"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Main test execution
echo "========================================"
echo "Running Container Module Test Suite"
echo "========================================"

echo "Testing module: $CONTAINERS_MODULE"

# Core Function Tests
echo "--- Core Function Tests ---"
test_function_exists "main_menu" "Main menu function exists"
test_function_exists "docker_deployment" "Docker deployment function exists"
test_function_exists "kubernetes_deployment" "Kubernetes deployment function exists"
test_function_exists "k3s_deployment" "k3s deployment function exists"
test_function_exists "show_container_monitoring" "Container monitoring function exists"

# Check for container management functions
echo "--- Container Management Tests ---"
if grep -q "list_containers\|start_containers\|stop_containers" "$CONTAINERS_MODULE"; then
    echo "PASS: Container management functions exist"
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
else
    echo "FAIL: Container management functions missing"
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
fi

# Check for multi-VM deployment
if grep -q "multi_vm_deployment" "$CONTAINERS_MODULE"; then
    echo "PASS: Multi-VM deployment function exists"
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
else
    echo "FAIL: Multi-VM deployment function missing"
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
fi

# Results
echo "========================================"
echo "Test Results"
echo "========================================"
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
