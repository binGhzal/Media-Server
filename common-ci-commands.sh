#!/bin/bash
# common-ci-commands.sh - Reference for common act/CI commands

# Example 1: Run a specific job with the most common options
run_job_with_options() {
  local job_name=$1
  
  # Basic job run
  act -j "$job_name"
  
  # With verbose output for debugging
  # act -j "$job_name" -v
  
  # Specify container architecture (needed for Apple Silicon)
  # act -j "$job_name" --container-architecture linux/amd64
  
  # With environment variables
  # act -j "$job_name" -e ENV_VAR=value
  
  # With secrets
  # act -j "$job_name" --secret SECRET_NAME=value
  
  # Specify event type (pull_request, push, etc.)
  # act -j "$job_name" -e pull_request
  
  # Use a specific workflow file
  # act -j "$job_name" -W .github/workflows/specific-workflow.yml
  
  # Run with a specific event JSON file
  # act -j "$job_name" -e pull_request --eventpath pr-event.json
}

# Example 2: Run all jobs for an event type
run_all_jobs_for_event() {
  local event_type=$1
  
  # Run all jobs for event type
  act "$event_type"
}

# Example 3: List all jobs or events
list_jobs_or_events() {
  # List jobs
  act -l
  
  # List jobs for a specific workflow
  # act -l -W .github/workflows/specific-workflow.yml
  
  # List workflows
  # find .github/workflows -name "*.yml" -o -name "*.yaml"
}

# Example 4: Run with dry-run mode to see what would happen
dry_run_job() {
  local job_name=$1
  
  # Dry run without execution
  act -j "$job_name" -n
}

# Example 5: Create and use artifact directories
use_artifacts() {
  local job_name=$1
  
  # Create artifact dir
  mkdir -p /tmp/artifacts
  
  # Run with artifact mapping
  act -j "$job_name" --artifact-server-path /tmp/artifacts
}

# Example 6: Use custom Docker image for a job runner
use_custom_image() {
  local job_name=$1
  local image_name=$2
  
  # Use custom image for a platform
  act -j "$job_name" -P ubuntu-latest=$image_name
}

# Example 7: Run with step debug enabled
run_with_step_debug() {
  local job_name=$1
  
  # Enable step debugging
  act -j "$job_name" --step-debug
}

# Example 8: Run with network shared with host
run_with_host_network() {
  local job_name=$1
  
  # Share host network
  act -j "$job_name" --bind
}

# Example 9: Cache Docker images to improve performance
use_cache() {
  local job_name=$1
  
  # Use Docker layer caching
  act -j "$job_name" --use-docker-cache
}

# Example 10: Run a job with specific Matrix values
run_matrix_job() {
  local job_name=$1
  
  # Run with matrix values
  act -j "$job_name" --matrix os=ubuntu-latest
}
