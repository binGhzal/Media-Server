#!/bin/bash
#
# This script fixes the most common shellcheck issues in create-template.sh
#

# Make sure we have a backup
if [[ ! -f create-template.sh.bak ]]; then
  cp create-template.sh create-template.sh.bak
  echo "Created backup at create-template.sh.bak"
fi

# Fix SC2002: Useless cat
echo "Fixing useless cat (SC2002)..."
sed -i.tmp 's/cat "$template_host_path" | pct exec "$TEMP_LXC_ID" -- tee "$template_lxc_path" > \/dev\/null/pct exec "$TEMP_LXC_ID" -- tee "$template_lxc_path" < "$template_host_path" > \/dev\/null/g' create-template.sh

# Fix SC2181: Common patterns for exit code checks
echo "Fixing common exit code check patterns (SC2181)..."

# Pattern: command\n[[ $? -ne 0 ]] && return 1
# Find all occurrences and create a temporary file with line numbers
grep -n "\[\[ \$? -ne 0 \]\] && return 1" create-template.sh > /tmp/sc2181_fixes.txt

# Process each occurrence
while IFS=: read -r line_num line_content; do
  # Get the previous line (the command)
  prev_line_num=$((line_num - 1))
  prev_line=$(sed -n "${prev_line_num}p" create-template.sh)
  
  # Skip if previous line is not a simple command (contains if, for, while, etc.)
  if [[ "$prev_line" =~ if|for|while|case|function|return|exit|else|elif|fi|done|esac ]]; then
    continue
  fi
  
  # Create the replacement pattern
  # Remove leading whitespace from prev_line for the sed pattern
  indent=$(echo "$line_content" | sed -E 's/^([[:space:]]*).*$/\1/')
  clean_prev_line=$(echo "$prev_line" | sed -E 's/^[[:space:]]*//')
  
  # Create sed command to replace both lines with the new pattern
  sed -i.tmp "${prev_line_num},${line_num}s/${clean_prev_line}\n${indent}\[\[ \$? -ne 0 \]\] && return 1/${clean_prev_line} || return 1/" create-template.sh
done < /tmp/sc2181_fixes.txt

# Clean up temporary files
rm -f create-template.sh.tmp /tmp/sc2181_fixes.txt

echo "Basic fixes applied. Please review the changes and manually address the remaining issues."
