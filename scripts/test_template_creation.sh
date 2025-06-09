#!/bin/bash
set -e

# Test script for template.sh custom ISO/image functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Source the centralized logging library
# Ensure LOG_FILE_ALREADY_SET_EXTERNALLY is set so logging.sh doesn't try to use its default log path
export LOG_FILE_ALREADY_SET_EXTERNALLY="true"
export LOG_FILE="/tmp/test_template_creation_main.log" # This test script's logs
export HL_LOG_LEVEL="INFO" # Log level for this test script
# Delete old log file
rm -f "$LOG_FILE"

source "$SCRIPT_DIR/lib/logging.sh"

# Global test counters
TEST_COUNT=0
FAIL_COUNT=0

pass_test() {
    local description="$1"
    log_info "✅ Test PASSED: $description"
}

fail_test() {
    local description="$1"
    log_error "❌ Test FAILED: $description"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

cleanup_vm() {
    local vmid="$1"
    log_info "TEST: (Cleanup) Would stop and destroy VM $vmid if it existed."
    # Actual qm commands for cleanup would go here in a real environment
    # Example:
    # if qm status "$vmid" &>/dev/null; then
    #     log_info "TEST: (Cleanup) Stopping VM $vmid..."
    #     qm stop "$vmid" --timeout 10 || qm stop "$vmid" --force || true
    #     log_info "TEST: (Cleanup) Destroying VM $vmid..."
    #     qm destroy "$vmid" --destroy-unreferenced-disks 1 --purge || true
    # else
    #     log_info "TEST: (Cleanup) VM $vmid not found or already cleaned up."
    # fi
}

main() {
    log_info "Starting Test Script for template.sh..."

    # Configuration Variables
    TEST_STORAGE="localteststorage"
    TEST_ISO_FILENAME="test-custom.iso"
    TEST_ISO_PATH_ON_STORAGE="template/iso/$TEST_ISO_FILENAME"
    # TEST_QCOW2_FILENAME="test-custom.qcow2" # For future tests
    # TEST_QCOW2_PATH_ON_STORAGE="template/iso/$TEST_QCOW2_FILENAME" # For future tests


    NEXT_VMID_BASE=7700
    local current_vmid_base=$NEXT_VMID_BASE

    # Informational Prerequisite Echo
    log_info "----------------------------------------"
    log_warn "This test script expects certain Proxmox resources to be pre-configured:"
    log_warn "1. Proxmox storage named '$TEST_STORAGE' (type: directory, content: ISO & Images)."
    log_warn "   Example: mkdir -p /mnt/pve/$TEST_STORAGE/template/iso /mnt/pve/$TEST_STORAGE/images"
    log_warn "   Example: pvesm add dir $TEST_STORAGE --path /mnt/pve/$TEST_STORAGE --content iso,images"
    log_warn "2. A test ISO at '$TEST_STORAGE:$TEST_ISO_PATH_ON_STORAGE'."
    log_warn "   Example: dd if=/dev/zero of=/mnt/pve/$TEST_STORAGE/$TEST_ISO_PATH_ON_STORAGE bs=1M count=1"
    log_warn "3. A test QCOW2 image (details for future tests - e.g. place in /mnt/pve/$TEST_STORAGE/images/)."
    log_info "----------------------------------------"

    if [[ $- == *i* ]]; then # Interactive shell
        read -r -p "Press [Enter] to continue if prerequisites are met, or Ctrl+C to abort..."
    else
        log_info "Non-interactive mode. Assuming prerequisites are met."
    fi

    # --- Placeholder Test Case ---
    ((TEST_COUNT++))
    log_info "Starting Test Case $TEST_COUNT: Placeholder for Custom ISO..."
    local vmid=$((current_vmid_base++))
    log_info "TEST: Simulating input for custom ISO for VM $vmid"

    # Actual call to template.sh and assertions will be added later.
    # Example input string (for future use):
    # local template_name="test-iso-$vmid"
    # local inputs="${template_name}\ncustom\n${TEST_STORAGE}\n${TEST_ISO_PATH_ON_STORAGE}\niso\nno\n1\n1024\n10\ntest,iso\nyes"
    # log_info "TEST: Input sequence would be:\n$inputs"
    # log_info "TEST: Would run: echo -e \"\$inputs\" | HL_TEMPLATE_CONFIG_DIR=\"/tmp/test_template_conf\" LOG_FILE_ALREADY_SET_EXTERNALLY=\"true\" LOG_FILE=\"/tmp/template_under_test.log\" \"\$SCRIPT_DIR/template.sh\" --create"

    pass_test "Placeholder Custom ISO test completed for VM $vmid."
    cleanup_vm "$vmid"


    # --- Test Summary ---
    log_info "----------------------------------------"
    log_info "Test Summary:"
    log_info "Total tests run: $TEST_COUNT"
    local passed_count=$((TEST_COUNT - FAIL_COUNT))
    log_info "Passed: $passed_count"
    log_info "Failed: $FAIL_COUNT"
    log_info "----------------------------------------"

    if [ $FAIL_COUNT -eq 0 ]; then
        log_info "All tests passed!"
        exit 0
    else
        log_error "$FAIL_COUNT test(s) failed."
        exit 1
    fi
}

# Call main function
main "$@"
