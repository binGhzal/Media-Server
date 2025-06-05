#!/bin/bash
set -e
SCRIPT_DIR="."
test_script=$(mktemp)
cat > "$test_script" << 'EOFTEST'
#!/bin/bash
# Minimal test for CLI parsing
source /dev/stdin

# Test parse_arguments function exists
if declare -f parse_arguments >/dev/null 2>&1; then
    echo "parse_arguments function found"
else
    echo "parse_arguments function not found"
    exit 1
fi
EOFTEST

echo "About to run test..."
# Extract just the function definitions to test
awk '/^parse_arguments\(\) {/,/^}$/' "$SCRIPT_DIR/create-template.sh" | bash "$test_script"
result=$?
echo "Test result: $result"
rm -f "$test_script"
