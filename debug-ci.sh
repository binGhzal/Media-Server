#!/bin/bash
# debug-ci.sh - Script to help diagnose CI issues by comparing local and remote execution

# Exit on error
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print the header
print_header() {
  echo -e "${BLUE}================================================${NC}"
  echo -e "${BLUE}   CI Pipeline Debugging Assistant${NC}"
  echo -e "${BLUE}================================================${NC}"
  echo ""
}

# Check that all required utilities are installed
check_prerequisites() {
  local missing_tools=0
  
  echo -e "${CYAN}Checking prerequisites...${NC}"
  
  # Check for act
  if ! command -v act &>/dev/null; then
    echo -e "${RED}❌ act is not installed. Install with: brew install act${NC}"
    missing_tools=$((missing_tools + 1))
  else
    echo -e "${GREEN}✓ act is installed${NC}"
  fi
  
  # Check for jq
  if ! command -v jq &>/dev/null; then
    echo -e "${RED}❌ jq is not installed. Install with: brew install jq${NC}"
    missing_tools=$((missing_tools + 1))
  else
    echo -e "${GREEN}✓ jq is installed${NC}"
  fi
  
  # Check for git
  if ! command -v git &>/dev/null; then
    echo -e "${RED}❌ git is not installed${NC}"
    missing_tools=$((missing_tools + 1))
  else
    echo -e "${GREEN}✓ git is installed${NC}"
  fi
  
  if [ "$missing_tools" -gt 0 ]; then
    echo -e "${RED}Please install the missing tools and try again.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}✓ All prerequisites met${NC}"
  echo ""
}

# Create a debug workflow file
create_debug_workflow() {
  local job_name=$1
  local debug_workflow="debug-workflow.yml"
  
  echo -e "${CYAN}Creating debug workflow for job: $job_name${NC}"
  
  # Extract the job section from the main workflow
  awk -v job="$job_name:" '
    $0 ~ "^  "job {
      print "name: Debug Workflow"; 
      print "on: workflow_dispatch"; 
      print ""; 
      print "jobs:"; 
      print "  debug:"; 
      flag=1; 
      next
    }
    flag && /^  [a-zA-Z0-9_-]*:/ && $0 !~ "^  "job {
      exit
    }
    flag {
      print $0
    }
  ' .github/workflows/ci.yml > "$debug_workflow"
  
  echo -e "${GREEN}✓ Created debug workflow: $debug_workflow${NC}"
  
  # Return the filename
  echo "$debug_workflow"
}

# Run a job with extra debugging
debug_job() {
  local job_name=$1
  local workflow_file=".github/workflows/ci.yml"
  
  echo -e "${YELLOW}Debugging job: $job_name from $workflow_file${NC}"
  
  # Create a debug workflow for just this job
  local debug_workflow
  debug_workflow=$(create_debug_workflow "$job_name")
  
  # Run with verbose output and step debug level
  local act_cmd="act -j debug -W $debug_workflow -v --step-debug"
  
  echo -e "${CYAN}Running with debug options enabled...${NC}"
  echo -e "${CYAN}Command:${NC} $act_cmd"
  echo -e "${CYAN}======= Debug Output =======${NC}"
  
  # Execute act with debug options
  eval "$act_cmd" || {
    local exit_code=$?
    echo -e "${RED}❌ Debug run failed with exit code $exit_code${NC}"
    analyze_failure "$job_name" "$debug_workflow"
    return $exit_code
  }
  
  echo -e "${GREEN}✅ Debug run completed${NC}"
  
  # Clean up
  rm -f "$debug_workflow"
}

# Analyze a failed job
analyze_failure() {
  local job_name=$1
  local debug_workflow=$2
  
  echo -e "${YELLOW}Analyzing failure for job: $job_name${NC}"
  
  # Check for common issues
  echo -e "${CYAN}Checking for common issues:${NC}"
  
  # 1. Check for environment variables used in the job
  echo -e "1. ${CYAN}Environment variables check:${NC}"
  grep -E "env\.|environment:" "$debug_workflow" && {
    echo -e "${YELLOW}⚠️  Job uses environment variables. Make sure they're properly set in act.${NC}"
    echo -e "   Consider adding a .env file or using -e flags with act:"
    echo -e "   ${CYAN}act -j $job_name -W $workflow_file -e VAR=value${NC}"
  } || echo -e "${GREEN}✓ No explicit environment variables found${NC}"
  
  # 2. Check for Docker image requirements
  echo -e "2. ${CYAN}Docker image check:${NC}"
  grep -E "container:|image:" "$debug_workflow" && {
    echo -e "${YELLOW}⚠️  Job uses custom Docker images. Make sure they're available locally.${NC}"
    echo -e "   You might need to pull the image first:"
    echo -e "   ${CYAN}docker pull <image-name>${NC}"
  } || echo -e "${GREEN}✓ No custom Docker images specified${NC}"
  
  # 3. Check for secrets
  echo -e "3. ${CYAN}Secrets check:${NC}"
  grep -E "secrets\.|GITHUB_TOKEN" "$debug_workflow" && {
    echo -e "${YELLOW}⚠️  Job uses secrets. They need to be provided to act.${NC}"
    echo -e "   Consider creating a .secrets file or using --secret flags:"
    echo -e "   ${CYAN}act -j $job_name -W $workflow_file --secret KEY=value${NC}"
  } || echo -e "${GREEN}✓ No secrets usage detected${NC}"
  
  # 4. Check for external service dependencies
  echo -e "4. ${CYAN}External services check:${NC}"
  grep -E "service:|services:" "$debug_workflow" && {
    echo -e "${YELLOW}⚠️  Job uses service containers. Make sure they're configured correctly.${NC}"
    echo -e "   You might need to start services manually or modify configuration.${NC}"
  } || echo -e "${GREEN}✓ No service containers detected${NC}"
  
  echo -e "${YELLOW}See detailed act documentation: ${CYAN}https://github.com/nektos/act#readme${NC}"
  echo ""
}

# Compare local and CI environment
compare_environments() {
  echo -e "${CYAN}Comparing local and CI environments...${NC}"
  
  # Check local environment
  echo -e "${CYAN}Local environment:${NC}"
  echo -e "OS: $(uname -a)"
  echo -e "Shell: $SHELL"
  
  # Check for important tools and their versions
  for tool in bash docker git jq node npm python3; do
    if command -v "$tool" &>/dev/null; then
      version=$("$tool" --version 2>/dev/null || echo "version not available")
      echo -e "$tool: $version"
    else
      echo -e "$tool: ${RED}Not installed${NC}"
    fi
  done
  
  echo -e "${YELLOW}Note: GitHub Actions uses Ubuntu runners by default.${NC}"
  echo -e "${YELLOW}Environment differences might cause CI issues even when tests pass locally.${NC}"
  echo ""
}

# Find the most recent failing job in GitHub
find_recent_failures() {
  # Check if authenticated to GitHub
  if ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}Not authenticated to GitHub CLI. Cannot fetch recent failures.${NC}"
    echo -e "${YELLOW}To authenticate, run: ${CYAN}gh auth login${NC}"
    return
  fi
  
  echo -e "${CYAN}Checking recent workflow failures on GitHub...${NC}"
  
  # Get recent workflow runs with GitHub CLI if available
  if command -v gh &>/dev/null; then
    gh run list --limit 5 --json status,name,conclusion,databaseId,url | jq -r '.[] | "\(.status) \(.conclusion) \(.name) \(.databaseId) \(.url)"' | while read -r status conclusion name id url; do
      if [ "$conclusion" = "failure" ]; then
        echo -e "${RED}❌ Failure: $name${NC} (Run #$id)"
        echo -e "   URL: ${CYAN}$url${NC}"
        
        # Get job failures for this run
        gh run view "$id" --json jobs | jq -r '.jobs[] | select(.conclusion == "failure") | "\(.name)"' | while read -r job_name; do
          echo -e "   Failed job: ${RED}$job_name${NC}"
        done
      fi
    done
  else
    echo -e "${YELLOW}GitHub CLI (gh) not found. Install to see recent failures.${NC}"
    echo -e "${YELLOW}Installation: ${CYAN}brew install gh${NC}"
  fi
}

# Display help message
show_help() {
  echo -e "${CYAN}Debug CI Pipeline Helper${NC}"
  echo -e "Usage: ./debug-ci.sh [options]"
  echo ""
  echo -e "${CYAN}Options:${NC}"
  echo -e "  ${GREEN}-j, --job JOB_NAME${NC}    Debug a specific job with extra logging"
  echo -e "  ${GREEN}-c, --compare${NC}        Compare local and CI environments"
  echo -e "  ${GREEN}-f, --find-failures${NC}  Find recent failures on GitHub"
  echo -e "  ${GREEN}-h, --help${NC}           Show this help message"
  echo ""
  echo -e "${CYAN}Examples:${NC}"
  echo -e "  ./debug-ci.sh --job shellcheck"
  echo -e "  ./debug-ci.sh --compare"
  echo -e "  ./debug-ci.sh --find-failures"
  echo ""
}

# Main function
main() {
  local job_name=""
  local compare=false
  local find_failures=false
  
  # Parse command-line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -j|--job)
        job_name="$2"
        shift 2
        ;;
      -c|--compare)
        compare=true
        shift
        ;;
      -f|--find-failures)
        find_failures=true
        shift
        ;;
      -h|--help)
        print_header
        show_help
        exit 0
        ;;
      *)
        echo -e "${RED}Error: Unknown option $1${NC}"
        show_help
        exit 1
        ;;
    esac
  done
  
  # Print header
  print_header
  
  # Check prerequisites
  check_prerequisites
  
  # If no options provided, show help
  if [ -z "$job_name" ] && [ "$compare" = false ] && [ "$find_failures" = false ]; then
    show_help
    exit 0
  fi
  
  # Run requested actions
  if [ -n "$job_name" ]; then
    debug_job "$job_name"
  fi
  
  if [ "$compare" = true ]; then
    compare_environments
  fi
  
  if [ "$find_failures" = true ]; then
    find_recent_failures
  fi
  
  echo -e "${GREEN}Debug assistant completed!${NC}"
}

# Call the main function with all arguments
main "$@"
