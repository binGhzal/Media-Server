#!/bin/bash
# Proxmox Template Creator - Test Script
# Tests all functions and code in the project

set -e

TESTS_PASSED=0
TESTS_FAILED=0
LOG_FILE="/tmp/proxmox_template_creator_test.log"
> "$LOG_FILE"

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
    if [[ "$output" == *"$expected"* ]]; then
        log "PASS" "$* => output contains '$expected'"
        ((TESTS_PASSED++))
    else
        log "FAIL" "$* => output: $output (expected: $expected)"
        ((TESTS_FAILED++))
    fi
}

# --- Test bootstrap.sh functions ---
log "INFO" "Testing bootstrap.sh functions..."
source "$(dirname "$0")/bootstrap.sh"

assert_success check_root
assert_success check_os_compatibility
assert_success check_dependencies
assert_success check_proxmox

# --- Test main.sh (menu logic) ---
log "INFO" "Testing main.sh (menu logic)..."
if bash "$(dirname "$0")/main.sh" --test 2>&1 | grep -q "Welcome to the Proxmox Template Creator"; then
    log "PASS" "main.sh launches and displays welcome message"
    ((TESTS_PASSED++))
else
    log "FAIL" "main.sh did not display welcome message"
    ((TESTS_FAILED++))
fi

# --- Test skeleton modules ---
for mod in config.sh containers.sh monitoring.sh registry.sh terraform.sh update.sh; do
    log "INFO" "Testing $mod (skeleton)..."
    assert_output "to be implemented" bash "$(dirname "$0")/$mod"
    assert_success bash "$(dirname "$0")/$mod"
done

# --- Test template.sh (UI and logic) ---
log "INFO" "Testing template.sh (UI and logic)..."
if bash "$(dirname "$0")/template.sh" --test 2>&1 | grep -q "Template Name"; then
    log "PASS" "template.sh launches and displays inputbox"
    ((TESTS_PASSED++))
else
    log "FAIL" "template.sh did not display inputbox"
    ((TESTS_FAILED++))
fi

# --- Summary ---
log "INFO" "Testing complete. Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"
if [ $TESTS_FAILED -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed. See $LOG_FILE for details."
    exit 1
fi
