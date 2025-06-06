#!/bin/bash
#==============================================================================
# test-template-creator.sh
#
# Description: Efficient, modular test script for Proxmox Template Creator
# Performs comprehensive validation and error detection on create-template.sh
# without creating actual templates. Designed for CI and local use.
#
# Author: Improved by GitHub Copilot
# License: Same as create-template.sh
# Version: 4.0
#==============================================================================

set -euo pipefail

# Terminal colors
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
BOLD="\033[1m"

# Script under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/create-template.sh"

# Test result counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_WARNED=0
TESTS_FAILED=0

# Print colored message
print_msg() {
    local type="$1"; shift
    case "$type" in
        pass) echo -e "  ${GREEN}✅ $*${RESET}"; ((TESTS_PASSED++)); ;;
        warn) echo -e "  ${YELLOW}⚠️ $*${RESET}"; ((TESTS_WARNED++)); ;;
        fail) echo -e "  ${RED}❌ $*${RESET}"; ((TESTS_FAILED++)); ;;
        info) echo -e "  ${CYAN}ℹ️ $*${RESET}" ;;
        header) echo -e "\n${BOLD}${BLUE}$*${RESET}" ;;
        *) echo -e "  $*" ;;
    esac
}

# Test definitions: each test is a function, description, and optional skip flag
# Add new tests by appending to this array
TESTS=(
    "test_syntax:Check script syntax"
    "test_structure:Check script structure"
    "test_critical_functions:Check critical function definitions"
    "test_sudo_removal:Check sudo removal and root execution"
    "test_logging:Check logging system"
    "test_cli_flags:Check CLI argument flags"
    "test_docker_k8s_templates:Check Docker/K8s template integration"
    "test_config_files:Check example config files"
    "test_error_handling:Check error handling and recovery"
    "test_directory_structure:Check required directory structure"
    "test_dependency_checks:Check dependency validation"
    "test_validation_functions:Check input validation"
    "test_cleanup_functions:Check cleanup procedures"
)

# Test implementations

test_syntax() {
    if bash -n "$TARGET_SCRIPT"; then
        print_msg pass "Script syntax is valid"
        return 0
    else
        print_msg fail "Script syntax errors found"
        return 1
    fi
}

test_structure() {
    local lines functions
    lines=$(wc -l < "$TARGET_SCRIPT")
    functions=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$TARGET_SCRIPT" || true)
    print_msg info "Script lines: $lines, functions: $functions"
    (( lines > 2000 && functions > 50 )) && print_msg pass "Script structure looks comprehensive" || { print_msg warn "Script may be incomplete"; }
}

test_critical_functions() {
    local critical=(show_main_menu select_distribution select_packages create_single_template configure_ansible_automation configure_terraform_automation export_configuration import_configuration load_configuration_file initialize_script main get_next_available_vmid download_distribution_image create_vm_from_image configure_cloud_init install_packages_virt_customize convert_to_template configure_vm_defaults configure_network_settings configure_storage_settings configure_automation_settings configure_security_settings reset_to_defaults view_current_settings)
    local missing=()
    for f in "${critical[@]}"; do
        grep -q "^${f}() {" "$TARGET_SCRIPT" || missing+=("$f")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "All critical functions are defined"
    else
        print_msg fail "Missing functions: ${missing[*]}"; return 1
    fi
}

test_sudo_removal() {
    local sudo_count
    # Exclude comments and variable names containing "sudo"
    sudo_count=$(grep "sudo " "$TARGET_SCRIPT" | grep -v "# " | grep -v "SUDO" | wc -l)
    if (( sudo_count == 0 )); then
        print_msg pass "No sudo commands found - script designed for root execution"
    elif (( sudo_count < 5 )); then
        print_msg warn "Only $sudo_count sudo commands found - mostly cleaned up"
    else
        print_msg fail "$sudo_count sudo commands still found - needs cleanup"; return 1
    fi
}

test_logging() {
    local logs=(log_info log_error log_warn log_success log_debug)
    for l in "${logs[@]}"; do
        grep -q "$l" "$TARGET_SCRIPT" || { print_msg fail "Logging function $l missing"; return 1; }
    done
    print_msg pass "Comprehensive logging system found"
}

test_cli_flags() {
    local flags=(--help --batch --docker-template --k8s-template --config --dry-run --distribution --template-name)
    local missing=()
    for f in "${flags[@]}"; do
        grep -q "[[:space:]]$f" "$TARGET_SCRIPT" || missing+=("$f")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "All key CLI flags found"
    else
        print_msg fail "Missing CLI flags: ${missing[*]}"; return 1
    fi
}

test_docker_k8s_templates() {
    local funcs=(list_docker_templates list_k8s_templates select_docker_template_ui select_k8s_template_ui)
    for f in "${funcs[@]}"; do
        grep -q "$f" "$TARGET_SCRIPT" || { print_msg fail "Function $f missing"; return 1; }
    done
    print_msg pass "Docker/K8s template functions found"
}

test_config_files() {
    local files=("$SCRIPT_DIR/examples/ubuntu-22.04-dev.conf" "$SCRIPT_DIR/examples/template-queue-example.conf")
    local missing=()
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || missing+=("$f")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "Example configuration files found"
    else
        print_msg fail "Missing example config files: ${missing[*]}"; return 1
    fi
}

test_error_handling() {
    local error_handlers=(cleanup_on_exit cleanup_on_interrupt handle_error)
    local missing=()
    for h in "${error_handlers[@]}"; do
        grep -q "$h" "$TARGET_SCRIPT" || missing+=("$h")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "Error handling functions found"
    else
        print_msg fail "Missing error handlers: ${missing[*]}"; return 1
    fi
}

test_directory_structure() {
    local dirs=(logs configs temp terraform/templates ansible/inventory ansible/playbooks docker/templates kubernetes/templates)
    local missing=()
    for d in "${dirs[@]}"; do
        [[ -d "$SCRIPT_DIR/$d" ]] || missing+=("$d")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "Required directory structure exists"
    else
        print_msg warn "Missing directories: ${missing[*]}"
    fi
}

test_dependency_checks() {
    local deps=(whiptail pvesm qm pct curl wget jq virt-customize guestfs-tools)
    local missing=()
    for d in "${deps[@]}"; do
        grep -q "$d" "$TARGET_SCRIPT" || missing+=("$d")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "Dependency checks implemented"
    else
        print_msg fail "Missing dependency checks: ${missing[*]}"; return 1
    fi
}

test_validation_functions() {
    local validators=(validate_vm_settings validate_network_settings validate_storage_settings validate_automation_settings)
    local missing=()
    for v in "${validators[@]}"; do
        grep -q "$v" "$TARGET_SCRIPT" || missing+=("$v")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "Input validation functions found"
    else
        print_msg fail "Missing validators: ${missing[*]}"; return 1
    fi
}

test_cleanup_functions() {
    local cleanup=(cleanup_on_exit cleanup_on_interrupt cleanup_temp_resources)
    local missing=()
    for c in "${cleanup[@]}"; do
        grep -q "$c" "$TARGET_SCRIPT" || missing+=("$c")
    done
    if (( ${#missing[@]} == 0 )); then
        print_msg pass "Cleanup functions found"
    else
        print_msg fail "Missing cleanup functions: ${missing[*]}"; return 1
    fi
}

# Main test runner
main() {
    print_msg header "Proxmox Template Creator Test Suite"
    print_msg info "Testing $TARGET_SCRIPT"
    for entry in "${TESTS[@]}"; do
        IFS=":" read -r func desc <<< "$entry"
        ((TESTS_TOTAL++))
        print_msg header "$desc"
        if "$func"; then :; else :; fi
    done
    print_summary
}

# Print summary and exit with appropriate code
print_summary() {
    echo
    print_msg header "Test Summary"
    echo -e "${GREEN}Passed: $TESTS_PASSED${RESET}  ${YELLOW}Warnings: $TESTS_WARNED${RESET}  ${RED}Failed: $TESTS_FAILED${RESET}  ${BLUE}Total: $TESTS_TOTAL${RESET}"
    if (( TESTS_FAILED > 0 )); then
        print_msg fail "Test suite failed with $TESTS_FAILED errors."
        exit 1
    elif (( TESTS_WARNED > 0 )); then
        print_msg warn "Test suite passed with $TESTS_WARNED warnings."
        exit 0
    else
        print_msg pass "All tests passed successfully!"
        exit 0
    fi
}

main "$@"
