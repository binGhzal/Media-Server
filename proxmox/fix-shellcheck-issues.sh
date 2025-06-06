#!/bin/bash
#
# This script fixes shellcheck issues in create-template.sh
#

# Make a backup of the original script
cp create-template.sh create-template.sh.bak
echo "Created backup at create-template.sh.bak"

# Fix SC2002: Useless cat
echo "Fixing useless cat (SC2002)..."
sed -i.tmp 's/cat "$template_host_path" | pct exec "$TEMP_LXC_ID" -- tee "$template_lxc_path" > \/dev\/null/pct exec "$TEMP_LXC_ID" -- tee "$template_lxc_path" < "$template_host_path" > \/dev\/null/g' create-template.sh

# Fix SC2181: Check exit code directly
echo "Fixing exit code checks (SC2181)..."
# This is a manual process that requires careful editing
echo "The following lines need manual fixes for SC2181 (checking \$? directly):"
grep -n "\$?" create-template.sh

echo "
To fix SC2181 issues, replace patterns like:

command
if [ \$? -ne 0 ]; then
    # error handling
fi

With:

if ! command; then
    # error handling
fi

And replace:

command
[[ \$? -ne 0 ]] && return 1

With:

command || return 1
"

# Fix SC2317: Unreachable code
echo "
For SC2317 (unreachable code) issues:
1. Check that all functions are defined before they're called
2. Ensure there are no early exits that prevent code execution
3. Verify that all functions are actually called somewhere
"

# Fix SC2034: Unused variables
echo "
For SC2034 (unused variables) issues:
1. Check if these variables are actually used:
   - DISTRIBUTION
   - TEMPLATE_NAME
   - DOCKER_TEMPLATE
   - K8S_TEMPLATE
2. Either use them in the script or remove them
3. If they're used by external scripts, add a comment explaining this or export them
"

echo "Basic fixes applied. Please review the changes and manually address the remaining issues."
