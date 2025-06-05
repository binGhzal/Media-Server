#!/bin/bash
# fix-ci-pipeline.sh - Fix CI pipeline issues by testing locally

# Exit on error
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print header
print_header() {
  echo -e "${BLUE}================================================${NC}"
  echo -e "${BLUE}   CI Pipeline Fixer${NC}"
  echo -e "${BLUE}================================================${NC}"
  echo ""
}

# Verify installation of act
check_act() {
  if ! command -v act &>/dev/null; then
    echo -e "${RED}Error: 'act' is not installed.${NC}"
    echo -e "Install act using: ${CYAN}brew install act${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ 'act' is installed: $(act --version)${NC}"
}

# Execute all jobs in sequence to identify failing ones
run_jobs_in_sequence() {
  local workflow_file=".github/workflows/ci.yml"
  local failed_jobs=()
  local passing_jobs=()
  
  echo -e "${CYAN}Running all jobs in sequence to identify failures...${NC}"
  echo ""
  
  # Extract job IDs from the workflow file
  local jobs
  jobs=$(grep -A1 "^  [a-zA-Z0-9_-]*:" "$workflow_file" | grep "name:" | sed 's/    name: //' | 
         grep -B1 "name:" "$workflow_file" | grep ":" | sed 's/:.*//' | sed 's/  //')
  
  echo -e "${YELLOW}Found the following jobs:${NC}"
  for job in $jobs; do
    echo "  - $job"
  done
  echo ""
  
  # Run each job and track results
  for job in $jobs; do
    echo -e "${BLUE}===============================${NC}"
    echo -e "${YELLOW}Testing job: ${CYAN}$job${NC}"
    echo -e "${BLUE}===============================${NC}"
    
    # Run the job and capture the result
    if act -j "$job" --container-architecture linux/amd64; then
      echo -e "${GREEN}✓ Job '$job' passed!${NC}"
      passing_jobs+=("$job")
    else
      echo -e "${RED}✗ Job '$job' failed!${NC}"
      failed_jobs+=("$job")
    fi
    
    echo ""
  done
  
  # Print summary
  echo -e "${BLUE}===============================${NC}"
  echo -e "${CYAN}Test Results Summary${NC}"
  echo -e "${BLUE}===============================${NC}"
  echo -e "${GREEN}Passing Jobs (${#passing_jobs[@]}):${NC}"
  for job in "${passing_jobs[@]}"; do
    echo -e "  ✓ $job"
  done
  
  echo -e "${RED}Failing Jobs (${#failed_jobs[@]}):${NC}"
  for job in "${failed_jobs[@]}"; do
    echo -e "  ✗ $job"
  done
  
  # Return failed jobs as a comma-separated list
  echo "${failed_jobs[@]}"
}

# Fix common CI issues
fix_common_issues() {
  local fixed=0
  
  echo -e "${CYAN}Checking for and fixing common CI issues...${NC}"
  
  # Fix 1: Ensure scripts are executable
  echo -e "1. ${YELLOW}Making shell scripts executable...${NC}"
  find ./proxmox -name "*.sh" -exec chmod +x {} \;
  echo -e "   ${GREEN}All shell scripts made executable${NC}"
  fixed=$((fixed + 1))
  
  # Fix 2: Remove trailing whitespace
  echo -e "2. ${YELLOW}Removing trailing whitespace in shell scripts...${NC}"
  # Use portable sed command for both Linux and macOS
  if [[ $(uname) == "Darwin" ]]; then
    # macOS requires an argument after -i
    find ./proxmox -name "*.sh" -exec sed -i '' 's/[[:space:]]*$//' {} \;
  else
    # Linux works without an argument
    find ./proxmox -name "*.sh" -exec sed -i 's/[[:space:]]*$//' {} \;
  fi
  echo -e "   ${GREEN}Trailing whitespace removed${NC}"
  fixed=$((fixed + 1))
  
  # Fix 3: Ensure consistent line endings (LF, not CRLF)
  echo -e "3. ${YELLOW}Converting line endings to LF...${NC}"
  find ./proxmox -name "*.sh" -exec perl -pi -e 's/\r\n/\n/g' {} \;
  echo -e "   ${GREEN}Line endings converted to LF${NC}"
  fixed=$((fixed + 1))
  
  # Fix 4: Ensure syntax in shell scripts
  echo -e "4. ${YELLOW}Checking shell script syntax...${NC}"
  find ./proxmox -name "*.sh" -exec bash -n {} \; 2>/dev/null || {
    echo -e "   ${RED}Syntax errors found in some scripts${NC}"
  }
  echo -e "   ${GREEN}Shell script syntax checked${NC}"
  
  # Fix 5: Check for common shell script issues
  echo -e "5. ${YELLOW}Checking for improper variable usage...${NC}"
  # This grep finds variable references without quotes
  # For more thorough analysis, we'd need shellcheck
  if grep -l '\$[A-Za-z0-9_]*' ./proxmox/*.sh | xargs grep -l '[[:space:]]\$[A-Za-z0-9_]*[[:space:]]'; then
    echo -e "   ${RED}Possible unquoted variables found${NC}"
  else
    echo -e "   ${GREEN}No obvious unquoted variables found${NC}"
  fi
  
  # Fix 6: Ensure proper error handling in scripts
  echo -e "6. ${YELLOW}Adding proper error handling to scripts...${NC}"
  for script in ./proxmox/*.sh; do
    if ! grep -q "set -e" "$script"; then
      # Add set -e to the top of the script after the shebang
      if [[ $(uname) == "Darwin" ]]; then
        # macOS sed requires an argument after -i
        sed -i '' '2i\
set -e
' "$script"
      else
        # Linux sed works without an argument
        sed -i '2i\
set -e
' "$script"
      fi
      fixed=$((fixed + 1))
    fi
  done
  echo -e "   ${GREEN}Error handling added where needed${NC}"
  
  # Summary
  echo -e "${CYAN}Fixed $fixed common issues${NC}"
}

# Test job with additional context
detailed_job_test() {
  local job_name=$1
  
  echo -e "${CYAN}Running detailed test for job: $job_name${NC}"
  
  # Get job commands from workflow file
  local commands
  commands=$(awk -v job="$job_name:" '
    $0 ~ "^  "job {
      flag=1; 
      next
    }
    flag && /^  [a-zA-Z0-9_-]*:/ && $0 !~ "^  "job {
      exit
    }
    flag && /run:/ {
      capture=1; 
      next
    }
    capture && /^ *$/ {
      capture=0
    }
    capture {
      print $0
    }
  ' .github/workflows/ci.yml | sed 's/^          //')
  
  # Print the commands for reference
  echo -e "${YELLOW}This job runs the following commands:${NC}"
  echo "$commands"
  echo ""
  
  # Create a temporary script to run locally for testing
  local temp_script
  temp_script=$(mktemp)
  
  cat <<EOF > "$temp_script"
#!/bin/bash
# Temporary script to test job: $job_name
set -e
set -x

# Commands from job
$commands

EOF
  
  chmod +x "$temp_script"
  
  echo -e "${CYAN}Running job commands locally to test:${NC}"
  if "$temp_script"; then
    echo -e "${GREEN}✓ Local execution succeeded!${NC}"
    echo -e "${YELLOW}This suggests the issue might be specific to the GitHub Actions environment.${NC}"
  else
    echo -e "${RED}✗ Local execution failed!${NC}"
    echo -e "${YELLOW}The issue can be reproduced locally, which makes it easier to fix.${NC}"
  fi
  
  # Clean up
  rm -f "$temp_script"
}

# Create a patch for CI issues
create_ci_patch() {
  echo -e "${CYAN}Creating patch for CI issues...${NC}"
  
  # Store original versions of files
  mkdir -p .ci-fixes/originals
  find ./proxmox -name "*.sh" -exec cp {} .ci-fixes/originals/ \;
  
  # Apply fixes
  fix_common_issues
  
  # Create a patch
  mkdir -p .ci-fixes
  echo -e "${YELLOW}Creating diff patch...${NC}"
  git diff -- ./proxmox > .ci-fixes/ci-fixes.patch
  
  echo -e "${GREEN}Patch created at .ci-fixes/ci-fixes.patch${NC}"
  echo -e "${YELLOW}Review the patch and apply with: ${CYAN}git apply .ci-fixes/ci-fixes.patch${NC}"
}

# Main function
main() {
  print_header
  check_act
  
  # Menu options
  while true; do
    echo -e "${CYAN}Select an option:${NC}"
    echo -e "1) ${GREEN}Test all jobs in sequence${NC}"
    echo -e "2) ${GREEN}Fix common CI issues${NC}"
    echo -e "3) ${GREEN}Create a patch for CI fixes${NC}"
    echo -e "4) ${GREEN}Run a specific job with details${NC}"
    echo -e "5) ${GREEN}Exit${NC}"
    
    read -r -p "Enter your choice (1-5): " choice
    
    case $choice in
      1)
        failed_jobs=$(run_jobs_in_sequence)
        ;;
      2)
        fix_common_issues
        ;;
      3)
        create_ci_patch
        ;;
      4)
        echo -e "${CYAN}Available jobs:${NC}"
        grep -A1 "^  [a-zA-Z0-9_-]*:" .github/workflows/ci.yml | grep "name:" | sed 's/    name: //'
        read -r -p "Enter job name to test: " job_name
        detailed_job_test "$job_name"
        ;;
      5)
        echo -e "${GREEN}Exiting...${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option.${NC}"
        ;;
    esac
  done
}

# Run the main function
main
