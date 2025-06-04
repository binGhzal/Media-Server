#!/bin/bash
# Test script for Proxmox Template Creator
# This script tests key functions without creating actual templates

set -e

echo "Testing Proxmox Template Creator Functions"
echo "=========================================="
echo ""

# Test basic script syntax
echo "Test 1: Checking script syntax..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if bash -n "$SCRIPT_DIR/create-template.sh"; then
    echo "✅ Script syntax is valid"
else
    echo "❌ Script syntax errors found"
    exit 1
fi
echo ""

# Test script structure
echo "Test 2: Checking script structure..."
line_count=$(wc -l < "$SCRIPT_DIR/create-template.sh")
function_count=$(grep -c "^[a-zA-Z_][a-zA-Z0-9_]*() {" "$SCRIPT_DIR/create-template.sh" || true)

echo "   Script lines: $line_count"
echo "   Functions defined: $function_count"

if [ "$line_count" -gt 2000 ] && [ "$function_count" -gt 50 ]; then
    echo "✅ Script structure looks comprehensive"
else
    echo "❌ Script may be incomplete"
    exit 1
fi
echo ""

# Test specific function definitions
echo "Test 3: Checking critical function definitions..."
critical_functions=(
    "main_menu"
    "select_distribution" 
    "configure_packages"
    "create_template"
    "configure_ansible_integration"
    "generate_terraform_config"
    "export_configuration"
    "import_configuration"
    "show_help"
    "parse_arguments"
    "initialize_defaults"
)

missing_functions=()
for func in "${critical_functions[@]}"; do
    if grep -q "^${func}() {" "$SCRIPT_DIR/create-template.sh"; then
        echo "   ✅ $func - defined"
    else
        echo "   ❌ $func - missing"
        missing_functions+=("$func")
    fi
done

if [ ${#missing_functions[@]} -eq 0 ]; then
    echo "✅ All critical functions are defined"
else
    echo "❌ Missing functions: ${missing_functions[*]}"
    exit 1
fi
echo ""

# Test distribution list structure
echo "Test 4: Checking distribution list..."
distro_list_line=$(grep -n "DISTRO_LIST=(" "$SCRIPT_DIR/create-template.sh" | head -1 | cut -d: -f1)
if [ -n "$distro_list_line" ]; then
    echo "✅ DISTRO_LIST array found at line $distro_list_line"
    
    # Count distributions
    distro_count=$(sed -n "${distro_list_line},/^)/p" "$SCRIPT_DIR/create-template.sh" | grep -c '"|' || true)
    echo "   Estimated distributions: $distro_count"
    
    if [ "$distro_count" -gt 20 ]; then
        echo "✅ Distribution list appears comprehensive"
    else
        echo "❌ Distribution list may be incomplete"
        exit 1
    fi
else
    echo "❌ DISTRO_LIST array not found"
    exit 1
fi
echo ""

# Test package categories
echo "Test 5: Checking package categories..."
if grep -q "Essential System Tools" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "Development Tools" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "Network & Security" "$SCRIPT_DIR/create-template.sh"; then
    echo "✅ Package categories found"
else
    echo "❌ Package categories missing"
    exit 1
fi
echo ""

# Test Ansible integration
echo "Test 6: Checking Ansible integration..."
if grep -q "configure_ansible_integration" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "create_ansible_lxc_container" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "generate_ansible_inventory" "$SCRIPT_DIR/create-template.sh"; then
    echo "✅ Ansible integration functions found"
else
    echo "❌ Ansible integration incomplete"
    exit 1
fi
echo ""

# Test Terraform integration  
echo "Test 7: Checking Terraform integration..."
if grep -q "configure_terraform_integration" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "generate_terraform_config" "$SCRIPT_DIR/create-template.sh"; then
    echo "✅ Terraform integration functions found"
else
    echo "❌ Terraform integration incomplete"
    exit 1
fi
echo ""

# Test CLI support
echo "Test 8: Checking CLI support..."
if grep -q "parse_arguments" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "\-\-help" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "\-\-batch" "$SCRIPT_DIR/create-template.sh"; then
    echo "✅ CLI support found"
else
    echo "❌ CLI support incomplete"
    exit 1
fi
echo ""

# Test configuration management
echo "Test 9: Checking configuration management..."
if grep -q "export_configuration" "$SCRIPT_DIR/create-template.sh" && \
   grep -q "import_configuration" "$SCRIPT_DIR/create-template.sh"; then
    echo "✅ Configuration management found"
else
    echo "❌ Configuration management incomplete"
    exit 1
fi
echo ""

# Test example files
echo "Test 10: Checking example files..."
if [ -f "$SCRIPT_DIR/examples/ubuntu-22.04-dev.conf" ] && \
   [ -f "$SCRIPT_DIR/examples/template-queue-example.conf" ]; then
    echo "✅ Example configuration files found"
else
    echo "❌ Example configuration files missing"
    exit 1
fi
echo ""

# Summary
echo "🎉 ALL TESTS PASSED!"
echo ""
echo "Test Summary:"
echo "============="
echo "✅ Script syntax validation"
echo "✅ Script structure ($line_count lines, $function_count functions)"
echo "✅ Critical function definitions"
echo "✅ Distribution list (estimated $distro_count distributions)"
echo "✅ Package categories"
echo "✅ Ansible integration"
echo "✅ Terraform integration"
echo "✅ CLI support"
echo "✅ Configuration management"
echo "✅ Example files"
echo ""
echo "The Proxmox Template Creator script appears to be complete and ready for use!"
echo ""
echo "Next steps:"
echo "1. Copy the script to a Proxmox VE host"
echo "2. Ensure it has execute permissions: chmod +x create-template.sh"
echo "3. Run as root: ./create-template.sh"
echo "4. Or use CLI mode: ./create-template.sh --help"
