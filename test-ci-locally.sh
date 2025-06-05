#!/bin/bash
# test-ci-locally.sh - Script to run GitHub Actions workflows locally using act

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
  echo -e "${BLUE}   Testing GitHub Actions Workflows Locally${NC}"
  echo -e "${BLUE}================================================${NC}"
  echo ""
}

# Print usage information
print_usage() {
  echo -e "${CYAN}Usage:${NC}"
  echo -e "  ./test-ci-locally.sh [options]"
  echo ""
  echo -e "${CYAN}Options:${NC}"
  echo -e "  ${GREEN}-j, --job JOB_NAME${NC}      Run a specific job from the workflow"
  echo -e "  ${GREEN}-a, --all${NC}              Run all jobs in the workflow"
  echo -e "  ${GREEN}-w, --workflow FILE${NC}     Specify a workflow file to run (default: .github/workflows/ci.yml)"
  echo -e "  ${GREEN}-l, --list${NC}             List available jobs in the workflow"
  echo -e "  ${GREEN}-v, --verbose${NC}          Show verbose output"
  echo -e "  ${GREEN}-h, --help${NC}             Show this help message"
  echo ""
  echo -e "${CYAN}Examples:${NC}"
  echo -e "  ./test-ci-locally.sh --job shellcheck"
  echo -e "  ./test-ci-locally.sh --all"
  echo -e "  ./test-ci-locally.sh --list"
  echo ""
}

# List available jobs in the workflow file
list_jobs() {
  local workflow_file=$1
  echo -e "${CYAN}Available jobs in $workflow_file:${NC}"
  
  # Extract job names from the workflow file
  grep -A1 "^  [a-zA-Z0-9_-]*:" "$workflow_file" | grep "name:" | sed 's/    name: //' | while read -r job_name; do
    # Get the job ID (the key before the colon)
    local job_id=$(grep -B1 "name: $job_name" "$workflow_file" | head -n1 | sed 's/  //' | sed 's/:.*//')
    echo -e "  ${GREEN}$job_id${NC} - $job_name"
  done
  echo ""
}

# Run a specific job using act
run_job() {
  local job_name=$1
  local workflow_file=$2
  local verbose=$3
  
  echo -e "${YELLOW}Running job: $job_name from $workflow_file${NC}"
  
  # Build the act command
  local act_cmd="act -j $job_name -W $workflow_file --container-architecture linux/amd64"
  
  # Add verbose flag if requested
  if [ "$verbose" = true ]; then
    act_cmd="$act_cmd -v"
  fi
  
  # Run the command
  echo -e "${CYAN}Command:${NC} $act_cmd"
  echo -e "${CYAN}======= Job Output =======${NC}"
  
  # Execute act command
  if eval "$act_cmd"; then
    echo -e "${GREEN}✅ Job '$job_name' completed successfully!${NC}"
    return 0
  else
    local exit_code=$?
    echo -e "${RED}❌ Job '$job_name' failed with exit code $exit_code${NC}"
    return $exit_code
  fi
}

# Run all jobs in the workflow
run_all_jobs() {
  local workflow_file=$1
  local verbose=$2
  
  echo -e "${YELLOW}Running all jobs from $workflow_file${NC}"
  
  # Build the act command for all jobs
  local act_cmd="act -W $workflow_file --container-architecture linux/amd64"
  
  # Add verbose flag if requested
  if [ "$verbose" = true ]; then
    act_cmd="$act_cmd -v"
  fi
  
  # Run the command
  echo -e "${CYAN}Command:${NC} $act_cmd"
  echo -e "${CYAN}======= Workflow Output =======${NC}"
  
  # Execute act command
  if eval "$act_cmd"; then
    echo -e "${GREEN}✅ All jobs completed successfully!${NC}"
    return 0
  else
    local exit_code=$?
    echo -e "${RED}❌ Workflow failed with exit code $exit_code${NC}"
    return $exit_code
  fi
}

# Main function
main() {
  local job_name=""
  local run_all=false
  local show_list=false
  local workflow_file=".github/workflows/ci.yml"
  local verbose=false
  
  # Parse command-line arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -j|--job)
        job_name="$2"
        shift 2
        ;;
      -a|--all)
        run_all=true
        shift
        ;;
      -w|--workflow)
        workflow_file="$2"
        shift 2
        ;;
      -l|--list)
        show_list=true
        shift
        ;;
      -v|--verbose)
        verbose=true
        shift
        ;;
      -h|--help)
        print_header
        print_usage
        exit 0
        ;;
      *)
        echo -e "${RED}Error: Unknown option $1${NC}"
        print_usage
        exit 1
        ;;
    esac
  done
  
  # Check if workflow file exists
  if [ ! -f "$workflow_file" ]; then
    echo -e "${RED}Error: Workflow file '$workflow_file' not found!${NC}"
    exit 1
  fi
  
  # Print header
  print_header
  
  # List jobs if requested
  if [ "$show_list" = true ]; then
    list_jobs "$workflow_file"
    exit 0
  fi
  
  # Check if job name is provided or if running all jobs
  if [ -z "$job_name" ] && [ "$run_all" = false ]; then
    echo -e "${YELLOW}No job specified. Use -j/--job to specify a job or -a/--all to run all jobs.${NC}"
    echo ""
    list_jobs "$workflow_file"
    exit 1
  fi
  
  # Run act command
  if [ "$run_all" = true ]; then
    run_all_jobs "$workflow_file" "$verbose"
  else
    run_job "$job_name" "$workflow_file" "$verbose"
  fi
}

# Call the main function with all arguments
main "$@"
