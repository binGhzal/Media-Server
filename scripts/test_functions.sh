#!/bin/bash
# Proxmox Template Creator - Test Script
# Tests all functions and code in the project

set -e

TESTS_PASSED=0
TESTS_FAILED=0
LOG_FILE="/tmp/proxmox_template_creator_test.log"
true > "$LOG_FILE"

log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

assert_success() {
    if "$@"; then
        log "PASS" "$*"
        ((TESTS_PASSED++))
    else
        log "FAIL" "$*"
        ((TESTS_FAILED++))
    fi
}

assert_output() {
    local expected="$1"; shift
    local output
    output=$("$@" 2>&1)
    local status=$?
    if [[ "$output" == *"$expected"* ]]; then
        log "PASS" "$* => output contains '$expected'"
        ((TESTS_PASSED++))
    else
        log "FAIL" "$* => output: $output (expected: $expected)"
        ((TESTS_FAILED++))
    fi
    return $status
}

assert_exit_status() {
    local expected=$1; shift
    "$@" > /dev/null 2>&1
    local status=$?
    if [ "$status" -eq "$expected" ]; then
        log "PASS" "$* => exit status $status (expected: $expected)"
        ((TESTS_PASSED++))
    else
        log "FAIL" "$* => exit status $status (expected: $expected)"
        ((TESTS_FAILED++))
    fi
}

assert_file_exists() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        log "PASS" "File exists: $file_path"
        ((TESTS_PASSED++))
    else
        log "FAIL" "File does not exist: $file_path"
        ((TESTS_FAILED++))
    fi
}

assert_dir_exists() {
    local dir_path=$1
    if [ -d "$dir_path" ]; then
        log "PASS" "Directory exists: $dir_path"
        ((TESTS_PASSED++))
    else
        log "FAIL" "Directory does not exist: $dir_path"
        ((TESTS_FAILED++))
    fi
}

run_bootstrap_tests() {
    log_info "Testing bootstrap.sh functions..."
    source "$(dirname "$0")/bootstrap.sh"

    # Test core functions
    assert_success check_root
    assert_success check_os_compatibility
    assert_success check_dependencies
    assert_success check_proxmox

    # Test repository handling
    if [ -n "$TEST_SETUP_REPO" ]; then
        assert_success setup_repository
        assert_dir_exists "/opt/homelab"
        assert_dir_exists "/opt/homelab/.git"
    fi

    # Test config setup
    assert_success setup_config
    assert_dir_exists "/etc/homelab"
}

run_template_tests() {
    log_info "Testing template.sh (module functionality)..."
    
    # Test with --test flag to skip actual VM creation
    if bash "$(dirname "$0")/template.sh" --test 2>&1 | grep -q "Template Name"; then
        log "PASS" "template.sh launches and displays inputbox"
        ((TESTS_PASSED++))
    else
        log "FAIL" "template.sh did not display inputbox"
        ((TESTS_FAILED++))
    fi
    
    # Test distribution handling
    assert_output "Ubuntu Server" bash "$(dirname "$0")/template.sh" --list-distros
    
    # Test version selection
    assert_output "Jammy Jellyfish" bash "$(dirname "$0")/template.sh" --list-versions ubuntu
}

run_container_tests() {
    log_info "Testing containers.sh (module functionality)..."
    
    # Basic module test
    assert_output "Container Workloads" bash "$(dirname "$0")/containers.sh"
    
    # Test Docker integration if implemented
    if grep -q "docker_install" "$(dirname "$0")/containers.sh"; then
        assert_success bash "$(dirname "$0")/containers.sh" --check-docker
    fi
}

run_main_tests() {
    log_info "Testing main.sh (menu logic)..."
    if bash "$(dirname "$0")/main.sh" --test 2>&1 | grep -q "Welcome to the Proxmox Template Creator"; then
        log "PASS" "main.sh launches and displays welcome message"
        ((TESTS_PASSED++))
    else
        log "FAIL" "main.sh did not display welcome message"
        ((TESTS_FAILED++))
    fi
    
    # Verify module loading
    assert_exit_status 0 bash "$(dirname "$0")/main.sh" --list-modules
}

# --- Test skeleton modules ---
run_skeleton_tests() {
    log_info "Testing skeleton modules..."
    for mod in config.sh containers.sh monitoring.sh registry.sh terraform.sh update.sh; do
        assert_output "to be implemented" bash "$(dirname "$0")/$mod"
        assert_success bash "$(dirname "$0")/$mod"
    done
}

# Run all tests
run_bootstrap_tests
run_main_tests
run_template_tests
run_container_tests
run_skeleton_tests

# --- Summary ---
log_info "Testing complete. Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
if [ $TESTS_FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed. See $LOG_FILE for details."
    exit 1
fi
