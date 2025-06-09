#!/bin/bash

# Test script for logging.sh library

# --- Test Setup ---
# IMPORTANT: Define LOG_FILE and LOG_FILE_ALREADY_SET_EXTERNALLY *before* sourcing logging.sh the first time.
export TEST_LOG_FILE=$(mktemp)
export LOG_FILE="$TEST_LOG_FILE"    # Override LOG_FILE for tests
export LOG_FILE_ALREADY_SET_EXTERNALLY=true # Prevent library's initial touch on /var/log

# Determine SCRIPT_DIR and source the logging library
SCRIPT_DIR_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LIB_PATH="$SCRIPT_DIR_TEST/lib/logging.sh"

if [ ! -f "$LIB_PATH" ]; then
    echo "FATAL: logging.sh library not found at $LIB_PATH"
    exit 1
fi
source "$LIB_PATH" # LOG_LEVEL will be initialized here based on HL_LOG_LEVEL or default

# Save original LOG_FILE that might have been set by sourcing (though we overrode it)
# This is more of a safeguard in case the library's LOG_FILE definition changes.
ORIGINAL_LOG_FILE_AFTER_SOURCE="$LOG_FILE"
LOG_FILE="$TEST_LOG_FILE" # Ensure it's still our test log file

# Counters for test results
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Cleanup function to remove temp log file
cleanup() {
    # Restore original LOG_FILE behavior if needed (though for tests, it's less critical)
    # unset LOG_FILE
    # unset LOG_FILE_ALREADY_SET_EXTERNALLY
    rm -f "$TEST_LOG_FILE"

    echo ""
    echo "--- Test Summary ---"
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo "--------------------"

    if [ "$FAILED_TESTS" -ne 0 ]; then
        exit 1
    fi
    exit 0
}
trap cleanup EXIT INT TERM

# --- Assert Functions ---
_increment_total() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

assert_success() {
    # _increment_total should be called by the assert_X wrapper
    local description="$1"
    echo -e "✅ PASS: $description"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

assert_fail() {
    # _increment_total should be called by the assert_X wrapper
    local description="$1"
    local extra_info="${2:-}"
    echo -e "❌ FAIL: $description"
    if [ -n "$extra_info" ]; then
        echo "    Info: $extra_info"
    fi
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

# Usage: assert_true "[ condition ]" "description"
assert_true() {
    local condition="$1" # Should be a valid bash conditional expression, e.g., [ "$VAR" == "VAL" ]
    local description="$2"
    _increment_total
    if eval "$condition"; then # Using eval to allow complex conditions like [ -n "$VAR" ] && [ "$VAR" == "VAL" ]
        assert_success "$description"
    else
        assert_fail "$description" "Condition '$condition' was false."
    fi
}

# Usage: assert_false "[ condition ]" "description"
assert_false() {
    local condition="$1" # Should be a valid bash conditional expression
    local description="$2"
    _increment_total
    if ! eval "$condition"; then
        assert_success "$description"
    else
        assert_fail "$description" "Condition '$condition' was true."
    fi
}

# Usage: assert_contains "string" "file" "description"
assert_contains() {
    local string="$1"
    local file="$2"
    local description="$3"
    _increment_total
    if grep -Fq "$string" "$file"; then
        assert_success "$description ('$string' found in $file)"
    else
        assert_fail "$description ('$string' NOT found in $file)" "Content of $file:\n$(cat "$file")"
    fi
}

# Usage: assert_not_contains "string" "file" "description"
assert_not_contains() {
    local string="$1"
    local file="$2"
    local description="$3"
    _increment_total
    if ! grep -Fq "$string" "$file"; then
        assert_success "$description ('$string' NOT found in $file)"
    else
        assert_fail "$description ('$string' found in $file)"
    fi
}

# Usage: assert_matches "regex" "string_to_check" "description"
assert_matches() {
    local regex="$1"
    local string_to_check="$2"
    local description="$3"
    _increment_total
    if [[ "$string_to_check" =~ $regex ]]; then
        assert_success "$description (Regex '$regex' matched '$string_to_check')"
    else
        assert_fail "$description (Regex '$regex' DID NOT match '$string_to_check')"
    fi
}

# Usage: assert_function_exists "func_name" "description"
assert_function_exists() {
    local func_name="$1"
    local description="Function $func_name exists" # Default description
    if [ -n "$2" ]; then # Allow custom description
        description="$2"
    fi
    _increment_total
    if declare -f "$func_name" > /dev/null; then
        assert_success "$description"
    else
        assert_fail "$description" # This will now correctly show "Function X exists" as failed
    fi
}


echo "--- Running Logging Tests ---"
echo "Using temporary log file: $LOG_FILE" # Use LOG_FILE as it's the overridden one
echo "Note: Console output from log functions will appear during tests."
echo ""

# --- Test Cases ---

# Test Case: Function Existence
echo "[TEST SUITE] Function Existence"
assert_function_exists "log_info"
assert_function_exists "log_warn"
assert_function_exists "log_error"
assert_function_exists "log_debug"
assert_function_exists "_log"
echo ""

# Test Case: Log File Creation
echo "[TEST SUITE] Log File Creation"
> "$LOG_FILE"
log_info "Test log file creation marker"
assert_true "[ -s \"$LOG_FILE\" ]" "Test log file exists and is not empty after a log_info call"
assert_contains "Test log file creation marker" "$LOG_FILE" "Log file contains initial marker"
echo ""

# Helper function to run a battery of log level tests
run_log_level_test_set() {
    local level_name_suffix="$1"
    local current_log_level_setting="$2"

    local debug_msg="Debug_$level_name_suffix"
    local info_msg="Info_$level_name_suffix"
    local warn_msg="Warn_$level_name_suffix"
    local error_msg="Error_$level_name_suffix"

    > "$LOG_FILE"

    local console_output
    # Capture combined output. The logging functions themselves direct to stdout/stderr.
    # The test script captures what's *visible* on the console.
    console_output=$({ log_debug "$debug_msg"; log_info "$info_msg"; log_warn "$warn_msg"; log_error "$error_msg"; } 2>&1)

    echo "Console output for $level_name_suffix (LOG_LEVEL=$current_log_level_setting) test:"
    # To make matching easier, strip ANSI color codes from console_output for assertions
    local plain_console_output=$(echo "$console_output" | sed 's/\x1b\[[0-9;]*m//g')
    echo "$plain_console_output" # Show the plain output for review
    echo "---"

    # Assertions for DEBUG messages
    if [[ "$current_log_level_setting" == "DEBUG" ]]; then
        assert_contains "$debug_msg" "$LOG_FILE"       "[File - $level_name_suffix] $debug_msg should be present"
        assert_true "echo \"$plain_console_output\" | grep -Fq \"$debug_msg\"" "[Console - $level_name_suffix] $debug_msg should be present"
    else
        assert_not_contains "$debug_msg" "$LOG_FILE"    "[File - $level_name_suffix] $debug_msg should NOT be present"
        assert_false "echo \"$plain_console_output\" | grep -Fq \"$debug_msg\"" "[Console - $level_name_suffix] $debug_msg should NOT be present"
    fi

    # Assertions for INFO messages
    if [[ "$current_log_level_setting" == "DEBUG" || "$current_log_level_setting" == "INFO" ]]; then
        assert_contains "$info_msg" "$LOG_FILE"        "[File - $level_name_suffix] $info_msg should be present"
        assert_true "echo \"$plain_console_output\" | grep -Fq \"$info_msg\""    "[Console - $level_name_suffix] $info_msg should be present"
    else
        assert_not_contains "$info_msg" "$LOG_FILE"     "[File - $level_name_suffix] $info_msg should NOT be present"
        assert_false "echo \"$plain_console_output\" | grep -Fq \"$info_msg\""  "[Console - $level_name_suffix] $info_msg should NOT be present"
    fi

    # Assertions for WARN messages
    if [[ "$current_log_level_setting" == "DEBUG" || "$current_log_level_setting" == "INFO" || "$current_log_level_setting" == "WARN" ]]; then
        assert_contains "$warn_msg" "$LOG_FILE"        "[File - $level_name_suffix] $warn_msg should be present"
        assert_true "echo \"$plain_console_output\" | grep -Fq \"$warn_msg\""    "[Console - $level_name_suffix] $warn_msg should be present"
    else
        assert_not_contains "$warn_msg" "$LOG_FILE"     "[File - $level_name_suffix] $warn_msg should NOT be present"
        assert_false "echo \"$plain_console_output\" | grep -Fq \"$warn_msg\""  "[Console - $level_name_suffix] $warn_msg should NOT be present"
    fi

    assert_contains "$error_msg" "$LOG_FILE"       "[File - $level_name_suffix] $error_msg should be present"
    assert_true "echo \"$plain_console_output\" | grep -Fq \"$error_msg\""   "[Console - $level_name_suffix] $error_msg should be present"
    echo ""
}

# Test Case: Default Log Level (should be INFO as per logging.sh)
echo "[TEST SUITE] Default Log Level (INFO)"
unset HL_LOG_LEVEL # Ensure it's not set from environment
# Re-source the library to apply the default LOG_LEVEL
# LOG_FILE_ALREADY_SET_EXTERNALLY is still true
source "$LIB_PATH"
LOG_FILE="$TEST_LOG_FILE" # Ensure LOG_FILE is our test file *after* sourcing
assert_true "[ \"$LOG_LEVEL\" == \"INFO\" ]" "Default LOG_LEVEL is INFO"
run_log_level_test_set "DefaultINFO" "INFO"
echo ""

# Test Case: DEBUG Log Level
echo "[TEST SUITE] DEBUG Log Level"
export HL_LOG_LEVEL="DEBUG"
source "$LIB_PATH"; LOG_FILE="$TEST_LOG_FILE"
assert_true "[ \"$LOG_LEVEL\" == \"DEBUG\" ]" "LOG_LEVEL is DEBUG"
run_log_level_test_set "DebugMode" "DEBUG"
echo ""

# Test Case: WARN Log Level
echo "[TEST SUITE] WARN Log Level"
export HL_LOG_LEVEL="WARN"
source "$LIB_PATH"; LOG_FILE="$TEST_LOG_FILE"
assert_true "[ \"$LOG_LEVEL\" == \"WARN\" ]" "LOG_LEVEL is WARN"
run_log_level_test_set "WarnMode" "WARN"
echo ""

# Test Case: ERROR Log Level
echo "[TEST SUITE] ERROR Log Level"
export HL_LOG_LEVEL="ERROR"
source "$LIB_PATH"; LOG_FILE="$TEST_LOG_FILE"
assert_true "[ \"$LOG_LEVEL\" == \"ERROR\" ]" "LOG_LEVEL is ERROR"
run_log_level_test_set "ErrorMode" "ERROR"
echo ""

# Test Case: Log Format (in file)
echo "[TEST SUITE] Log Format in File"
export HL_LOG_LEVEL="INFO"
source "$LIB_PATH"; LOG_FILE="$TEST_LOG_FILE"
> "$LOG_FILE"
log_info "Testing log format"
LOG_FORMAT_REGEX="^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[INFO\] Testing log format$"
LINE_TO_CHECK=$(grep "Testing log format" "$LOG_FILE")
assert_matches "$LOG_FORMAT_REGEX" "$LINE_TO_CHECK" "Log line in file matches expected format"
echo ""

# Test Case: Console Output Redirection and Content
echo "[TEST SUITE] Console Output Redirection and Content"
export HL_LOG_LEVEL="INFO"
source "$LIB_PATH"; LOG_FILE="$TEST_LOG_FILE"
> "$LOG_FILE"

INFO_MSG_CONSOLE="Console Info Test For STDOUT"
ERROR_MSG_CONSOLE="Console Error Test For STDERR"

# log_info writes to STDOUT.
info_stdout_content=$(log_info "$INFO_MSG_CONSOLE" 2>/dev/null) # Capture only STDOUT
info_stderr_content=$(log_info "$INFO_MSG_CONSOLE" 1>/dev/null) # Capture only STDERR

# Strip ANSI for matching, as colors are tested visually / implicitly by _log
plain_info_stdout_content=$(echo "$info_stdout_content" | sed 's/\x1b\[[0-9;]*m//g')
plain_info_stderr_content=$(echo "$info_stderr_content" | sed 's/\x1b\[[0-9;]*m//g')

assert_true "echo \"$plain_info_stdout_content\" | grep -Fq \"$INFO_MSG_CONSOLE\"" "log_info message appears on STDOUT"
assert_false "echo \"$plain_info_stderr_content\" | grep -Fq \"$INFO_MSG_CONSOLE\"" "log_info message does NOT appear on STDERR"

# log_error writes to STDERR.
error_stdout_content=$({ log_error "$ERROR_MSG_CONSOLE"; } 2>/dev/null) # Capture only STDOUT from the command group
error_stderr_content=$({ log_error "$ERROR_MSG_CONSOLE"; } 2>&1 1>/dev/null) # Capture only STDERR from the command group

plain_error_stdout_content=$(echo "$error_stdout_content" | sed 's/\x1b\[[0-9;]*m//g')
plain_error_stderr_content=$(echo "$error_stderr_content" | sed 's/\x1b\[[0-9;]*m//g')

assert_false "echo \"$plain_error_stdout_content\" | grep -Fq \"$ERROR_MSG_CONSOLE\"" "log_error message does NOT appear on STDOUT"
assert_true "[[ \"$plain_error_stderr_content\" == *\"$ERROR_MSG_CONSOLE\"* ]]" "log_error message appears on STDERR (glob check)"

assert_contains "$INFO_MSG_CONSOLE" "$LOG_FILE" "log_info message also in log file after console check"
assert_contains "$ERROR_MSG_CONSOLE" "$LOG_FILE" "log_error message also in log file after console check"
echo ""

echo "All test suites complete. Cleanup will summarize results."
