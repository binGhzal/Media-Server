#!/bin/bash
# Performance Testing Module for Homelab Project
# Comprehensive performance benchmarking and analysis
# Version: 1.0.0

set -euo pipefail

# === Configuration ===
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly PERFORMANCE_REPORTS_DIR="$PROJECT_ROOT/performance_reports"
readonly TEMP_DIR="/tmp/homelab_performance_$$"

# Performance test parameters
readonly DEFAULT_DURATION=60
readonly DEFAULT_ITERATIONS=5
readonly WARMUP_DURATION=10

# Resource thresholds (configurable)
readonly CPU_THRESHOLD_PERCENT=80
readonly MEMORY_THRESHOLD_MB=1024
readonly DISK_IO_THRESHOLD_MB=100
readonly NETWORK_THRESHOLD_MBPS=10

# Test tracking
declare -g PERFORMANCE_TESTS=0
declare -g PERFORMANCE_PASSED=0
declare -g PERFORMANCE_FAILED=0
declare -g PERFORMANCE_WARNINGS=0

# === Logging Setup ===
setup_performance_logging() {
    if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
        source "$SCRIPT_DIR/lib/logging.sh"
    else
        log_info() { echo -e "\033[32m[PERF-INFO]\033[0m $*"; }
        log_warn() { echo -e "\033[33m[PERF-WARN]\033[0m $*"; }
        log_error() { echo -e "\033[31m[PERF-ERROR]\033[0m $*"; }
        log_debug() { echo -e "\033[36m[PERF-DEBUG]\033[0m $*"; }
    fi
    
    mkdir -p "$TEMP_DIR" "$PERFORMANCE_REPORTS_DIR"
    
    # Set up cleanup
    trap cleanup_performance_environment EXIT INT TERM
}

cleanup_performance_environment() {
    log_info "Cleaning up performance test environment..."
    
    # Kill any background monitoring processes
    local monitor_pids
    mapfile -t monitor_pids < <(pgrep -f "homelab_performance_monitor" 2>/dev/null || true)
    for pid in "${monitor_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    
    # Clean up temporary files
    if [[ -d "$TEMP_DIR" && "$TEMP_DIR" != "/" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# === Performance Test Framework ===
run_performance_test() {
    local test_name="$1"
    local test_function="$2"
    local description="${3:-Performance test: $test_name}"
    
    ((PERFORMANCE_TESTS++))
    
    log_info "Starting performance test: $test_name"
    
    local start_time=$(date '+%s')
    local test_result=""
    local test_details=""
    
    # Start system monitoring
    start_system_monitoring "$test_name" &
    local monitor_pid=$!
    
    # Run the test function
    if eval "$test_function"; then
        test_result="PASS"
        ((PERFORMANCE_PASSED++))
        echo -e "\033[32m✓ PERF-PASS\033[0m [$test_name] $description"
    else
        test_result="FAIL"
        ((PERFORMANCE_FAILED++))
        echo -e "\033[31m✗ PERF-FAIL\033[0m [$test_name] $description"
    fi
    
    # Stop monitoring
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
    
    local end_time=$(date '+%s')
    local duration=$((end_time - start_time))
    
    # Save test results
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$test_name,$test_result,$duration,$description" >> "$TEMP_DIR/performance_results.csv"
    
    log_info "Performance test '$test_name' completed in ${duration}s: $test_result"
}

start_system_monitoring() {
    local test_name="$1"
    local monitor_file="$TEMP_DIR/monitor_${test_name}.log"
    
    echo "timestamp,cpu_percent,memory_mb,disk_read_mb,disk_write_mb,network_rx_mb,network_tx_mb" > "$monitor_file"
    
    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # CPU usage
        local cpu_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr -d ' ')
        
        # Memory usage
        local memory_mb=$(free -m | awk 'NR==2{printf "%.1f", $3}')
        
        # Disk I/O
        local disk_stats=(0 0)
        if command -v iostat >/dev/null 2>&1; then
            mapfile -t disk_stats < <(iostat -d 1 1 2>/dev/null | awk 'END{print $3; print $4}' || echo -e "0\n0")
        fi
        
        # Network I/O
        local network_stats=(0 0)
        if [[ -f "/proc/net/dev" ]]; then
            mapfile -t network_stats < <(awk '/eth0:|ens|enp/{rx+=$2; tx+=$10} END{printf "%.2f\n%.2f\n", rx/1024/1024, tx/1024/1024}' /proc/net/dev)
        fi
        
        echo "$timestamp,${cpu_percent:-0},${memory_mb:-0},${disk_stats[0]:-0},${disk_stats[1]:-0},${network_stats[0]:-0},${network_stats[1]:-0}" >> "$monitor_file"
        
        sleep 2
    done
}

# === CPU Performance Tests ===
test_cpu_performance() {
    log_info "Running CPU performance tests..."
    
    # Single-core CPU test
    run_performance_test "cpu_single_core" "benchmark_cpu_single_core" "Single-core CPU benchmark"
    
    # Multi-core CPU test
    run_performance_test "cpu_multi_core" "benchmark_cpu_multi_core" "Multi-core CPU benchmark"
    
    # CPU stress test
    run_performance_test "cpu_stress" "stress_test_cpu" "CPU stress test"
}

benchmark_cpu_single_core() {
    log_info "Benchmarking single-core CPU performance..."
    
    local iterations=1000000
    local start_time=$(date '+%s%3N')
    
    # CPU-intensive calculation
    local result=0
    for ((i=1; i<=iterations; i++)); do
        result=$((result + i))
    done
    
    local end_time=$(date '+%s%3N')
    local duration=$((end_time - start_time))
    
    log_info "Single-core CPU benchmark: $iterations iterations in ${duration}ms"
    
    # Check if performance is within acceptable range (< 10 seconds for 1M iterations)
    if [[ $duration -lt 10000 ]]; then
        return 0
    else
        log_warn "Single-core CPU performance below expected threshold: ${duration}ms"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

benchmark_cpu_multi_core() {
    log_info "Benchmarking multi-core CPU performance..."
    
    local cores=$(nproc)
    local iterations_per_core=500000
    local pids=()
    
    local start_time=$(date '+%s%3N')
    
    # Start worker processes for each core
    for ((i=1; i<=cores; i++)); do
        (
            local result=0
            for ((j=1; j<=iterations_per_core; j++)); do
                result=$((result + j))
            done
            echo "$result" > "$TEMP_DIR/cpu_worker_$i.result"
        ) &
        pids+=($!)
    done
    
    # Wait for all workers to complete
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    local end_time=$(date '+%s%3N')
    local duration=$((end_time - start_time))
    
    log_info "Multi-core CPU benchmark: $cores cores, $iterations_per_core iterations each in ${duration}ms"
    
    # Check if multi-core performance scales reasonably
    local expected_max_duration=$((10000 / cores + 2000))  # Expected scaling + overhead
    
    if [[ $duration -lt $expected_max_duration ]]; then
        return 0
    else
        log_warn "Multi-core CPU performance below expected threshold: ${duration}ms (expected < ${expected_max_duration}ms)"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

stress_test_cpu() {
    log_info "Running CPU stress test..."
    
    local duration=30
    local max_cpu_percent=95
    
    # Start CPU stress test
    if command -v stress >/dev/null 2>&1; then
        timeout "$duration" stress --cpu "$(nproc)" >/dev/null 2>&1 &
        local stress_pid=$!
    else
        # Fallback stress test using yes command
        for ((i=1; i<=$(nproc); i++)); do
            timeout "$duration" yes >/dev/null 2>&1 &
        done
        local stress_pid=$!
    fi
    
    sleep 5  # Let stress test ramp up
    
    # Monitor CPU usage during stress test
    local peak_cpu=0
    for ((i=1; i<=10; i++)); do
        local current_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr -d ' ')
        current_cpu=${current_cpu%.*}  # Remove decimal part
        
        if [[ ${current_cpu:-0} -gt $peak_cpu ]]; then
            peak_cpu=$current_cpu
        fi
        
        sleep 2
    done
    
    # Clean up stress processes
    pkill -f "stress\|yes" 2>/dev/null || true
    
    log_info "CPU stress test peak usage: ${peak_cpu}%"
    
    # Check if CPU can reach high utilization
    if [[ $peak_cpu -ge 80 ]]; then
        return 0
    else
        log_warn "CPU stress test did not reach expected utilization: ${peak_cpu}% (expected >= 80%)"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

# === Memory Performance Tests ===
test_memory_performance() {
    log_info "Running memory performance tests..."
    
    # Memory allocation test
    run_performance_test "memory_allocation" "benchmark_memory_allocation" "Memory allocation benchmark"
    
    # Memory bandwidth test
    run_performance_test "memory_bandwidth" "benchmark_memory_bandwidth" "Memory bandwidth benchmark"
    
    # Memory stress test
    run_performance_test "memory_stress" "stress_test_memory" "Memory stress test"
}

benchmark_memory_allocation() {
    log_info "Benchmarking memory allocation performance..."
    
    local allocations=10000
    local allocation_size_mb=1
    local temp_files=()
    
    local start_time=$(date '+%s%3N')
    
    # Allocate memory blocks
    for ((i=1; i<=allocations; i++)); do
        local temp_file="$TEMP_DIR/mem_alloc_$i"
        dd if=/dev/zero of="$temp_file" bs=1M count="$allocation_size_mb" >/dev/null 2>&1
        temp_files+=("$temp_file")
        
        # Check every 1000 allocations to avoid overwhelming the system
        if ((i % 1000 == 0)); then
            if [[ $(df "$TEMP_DIR" | awk 'NR==2 {print $4}') -lt 1000000 ]]; then
                log_warn "Disk space running low, stopping memory allocation test early"
                break
            fi
        fi
    done
    
    local end_time=$(date '+%s%3N')
    local duration=$((end_time - start_time))
    
    # Clean up allocated files
    rm -f "${temp_files[@]}"
    
    log_info "Memory allocation benchmark: ${#temp_files[@]} allocations of ${allocation_size_mb}MB in ${duration}ms"
    
    # Check allocation speed (should be reasonable for disk-based simulation)
    local allocations_per_second=$(( ${#temp_files[@]} * 1000 / duration ))
    
    if [[ $allocations_per_second -ge 100 ]]; then
        return 0
    else
        log_warn "Memory allocation performance below expected threshold: ${allocations_per_second} allocs/sec"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

benchmark_memory_bandwidth() {
    log_info "Benchmarking memory bandwidth..."
    
    local test_size_mb=100
    local test_file="$TEMP_DIR/memory_bandwidth_test"
    
    # Write test
    local start_time=$(date '+%s%3N')
    dd if=/dev/zero of="$test_file" bs=1M count="$test_size_mb" >/dev/null 2>&1
    local write_end_time=$(date '+%s%3N')
    
    # Read test
    dd if="$test_file" of=/dev/null bs=1M >/dev/null 2>&1
    local read_end_time=$(date '+%s%3N')
    
    local write_duration=$((write_end_time - start_time))
    local read_duration=$((read_end_time - write_end_time))
    
    local write_mbps=$(( test_size_mb * 1000 / write_duration ))
    local read_mbps=$(( test_size_mb * 1000 / read_duration ))
    
    rm -f "$test_file"
    
    log_info "Memory bandwidth: Write ${write_mbps}MB/s, Read ${read_mbps}MB/s"
    
    # Check minimum bandwidth requirements
    if [[ $write_mbps -ge 50 && $read_mbps -ge 50 ]]; then
        return 0
    else
        log_warn "Memory bandwidth below expected threshold: Write ${write_mbps}MB/s, Read ${read_mbps}MB/s"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

stress_test_memory() {
    log_info "Running memory stress test..."
    
    local duration=30
    local available_memory_mb=$(free -m | awk 'NR==2{print $7}')
    local stress_memory_mb=$((available_memory_mb * 70 / 100))  # Use 70% of available memory
    
    if [[ $stress_memory_mb -lt 100 ]]; then
        log_warn "Insufficient memory for stress test: ${available_memory_mb}MB available"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
    
    log_info "Stress testing with ${stress_memory_mb}MB of ${available_memory_mb}MB available"
    
    # Start memory stress test
    if command -v stress >/dev/null 2>&1; then
        timeout "$duration" stress --vm 1 --vm-bytes "${stress_memory_mb}m" >/dev/null 2>&1 &
        local stress_pid=$!
    else
        # Fallback: allocate memory using dd
        local stress_file="$TEMP_DIR/memory_stress_test"
        timeout "$duration" dd if=/dev/zero of="$stress_file" bs=1M count="$stress_memory_mb" >/dev/null 2>&1 &
        local stress_pid=$!
    fi
    
    sleep 5  # Let stress test ramp up
    
    # Monitor memory usage
    local peak_memory_usage=0
    for ((i=1; i<=10; i++)); do
        local current_memory=$(free -m | awk 'NR==2{print $3}')
        
        if [[ $current_memory -gt $peak_memory_usage ]]; then
            peak_memory_usage=$current_memory
        fi
        
        sleep 2
    done
    
    # Clean up stress processes
    pkill -f "stress" 2>/dev/null || true
    rm -f "$TEMP_DIR/memory_stress_test" 2>/dev/null || true
    
    log_info "Memory stress test peak usage: ${peak_memory_usage}MB"
    
    # Check if memory usage increased significantly
    local memory_increase=$((peak_memory_usage - (available_memory_mb - stress_memory_mb)))
    
    if [[ $memory_increase -ge $((stress_memory_mb / 2)) ]]; then
        return 0
    else
        log_warn "Memory stress test did not achieve expected memory usage increase"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

# === Disk I/O Performance Tests ===
test_disk_performance() {
    log_info "Running disk I/O performance tests..."
    
    # Disk read performance
    run_performance_test "disk_read" "benchmark_disk_read" "Disk read performance"
    
    # Disk write performance
    run_performance_test "disk_write" "benchmark_disk_write" "Disk write performance"
    
    # Random I/O performance
    run_performance_test "disk_random_io" "benchmark_disk_random_io" "Random disk I/O performance"
}

benchmark_disk_read() {
    log_info "Benchmarking disk read performance..."
    
    local test_size_mb=500
    local test_file="$TEMP_DIR/disk_read_test"
    
    # Create test file
    dd if=/dev/zero of="$test_file" bs=1M count="$test_size_mb" >/dev/null 2>&1
    
    # Clear cache
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    # Read test
    local start_time=$(date '+%s%3N')
    dd if="$test_file" of=/dev/null bs=1M >/dev/null 2>&1
    local end_time=$(date '+%s%3N')
    
    local duration=$((end_time - start_time))
    local read_mbps=$(( test_size_mb * 1000 / duration ))
    
    rm -f "$test_file"
    
    log_info "Disk read performance: ${read_mbps}MB/s"
    
    # Check minimum read performance
    if [[ $read_mbps -ge 20 ]]; then
        return 0
    else
        log_warn "Disk read performance below expected threshold: ${read_mbps}MB/s"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

benchmark_disk_write() {
    log_info "Benchmarking disk write performance..."
    
    local test_size_mb=500
    local test_file="$TEMP_DIR/disk_write_test"
    
    # Write test
    local start_time=$(date '+%s%3N')
    dd if=/dev/zero of="$test_file" bs=1M count="$test_size_mb" oflag=direct >/dev/null 2>&1
    local end_time=$(date '+%s%3N')
    
    local duration=$((end_time - start_time))
    local write_mbps=$(( test_size_mb * 1000 / duration ))
    
    rm -f "$test_file"
    
    log_info "Disk write performance: ${write_mbps}MB/s"
    
    # Check minimum write performance
    if [[ $write_mbps -ge 15 ]]; then
        return 0
    else
        log_warn "Disk write performance below expected threshold: ${write_mbps}MB/s"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

benchmark_disk_random_io() {
    log_info "Benchmarking random disk I/O performance..."
    
    local test_file="$TEMP_DIR/disk_random_test"
    local test_size_mb=100
    local operations=1000
    
    # Create test file
    dd if=/dev/zero of="$test_file" bs=1M count="$test_size_mb" >/dev/null 2>&1
    
    local start_time=$(date '+%s%3N')
    
    # Perform random I/O operations
    for ((i=1; i<=operations; i++)); do
        local offset=$(( RANDOM % test_size_mb ))
        dd if="$test_file" of=/dev/null bs=1M count=1 skip="$offset" >/dev/null 2>&1
    done
    
    local end_time=$(date '+%s%3N')
    local duration=$((end_time - start_time))
    local iops=$(( operations * 1000 / duration ))
    
    rm -f "$test_file"
    
    log_info "Random I/O performance: ${iops} IOPS"
    
    # Check minimum random I/O performance
    if [[ $iops -ge 50 ]]; then
        return 0
    else
        log_warn "Random I/O performance below expected threshold: ${iops} IOPS"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

# === Network Performance Tests ===
test_network_performance() {
    log_info "Running network performance tests..."
    
    # Network connectivity performance
    run_performance_test "network_connectivity" "benchmark_network_connectivity" "Network connectivity performance"
    
    # DNS resolution performance
    run_performance_test "dns_resolution" "benchmark_dns_resolution" "DNS resolution performance"
    
    # Local network throughput
    run_performance_test "local_throughput" "benchmark_local_throughput" "Local network throughput"
}

benchmark_network_connectivity() {
    log_info "Benchmarking network connectivity performance..."
    
    local targets=("8.8.8.8" "1.1.1.1" "google.com")
    local total_tests=0
    local successful_tests=0
    local total_latency=0
    
    for target in "${targets[@]}"; do
        for ((i=1; i<=5; i++)); do
            ((total_tests++))
            
            local ping_result
            if ping_result=$(ping -c 1 -W 5 "$target" 2>/dev/null); then
                ((successful_tests++))
                
                local latency
                latency=$(echo "$ping_result" | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' | tr -d 'ms')
                
                if [[ -n "$latency" ]]; then
                    total_latency=$(awk "BEGIN {print $total_latency + $latency}")
                fi
            fi
        done
    done
    
    local success_rate=$(( successful_tests * 100 / total_tests ))
    local avg_latency=0
    
    if [[ $successful_tests -gt 0 ]]; then
        avg_latency=$(awk "BEGIN {printf \"%.2f\", $total_latency / $successful_tests}")
    fi
    
    log_info "Network connectivity: ${success_rate}% success rate, ${avg_latency}ms average latency"
    
    # Check network performance thresholds
    if [[ $success_rate -ge 80 ]] && (( $(awk "BEGIN {print ($avg_latency <= 100)}") )); then
        return 0
    else
        log_warn "Network connectivity below expected threshold: ${success_rate}% success, ${avg_latency}ms latency"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

benchmark_dns_resolution() {
    log_info "Benchmarking DNS resolution performance..."
    
    local domains=("google.com" "github.com" "stackoverflow.com" "ubuntu.com" "docker.com")
    local total_resolutions=0
    local successful_resolutions=0
    local total_time=0
    
    for domain in "${domains[@]}"; do
        for ((i=1; i<=3; i++)); do
            ((total_resolutions++))
            
            local start_time=$(date '+%s%3N')
            
            if nslookup "$domain" >/dev/null 2>&1; then
                local end_time=$(date '+%s%3N')
                local resolution_time=$((end_time - start_time))
                
                ((successful_resolutions++))
                total_time=$((total_time + resolution_time))
            fi
        done
    done
    
    local success_rate=$(( successful_resolutions * 100 / total_resolutions ))
    local avg_resolution_time=0
    
    if [[ $successful_resolutions -gt 0 ]]; then
        avg_resolution_time=$(( total_time / successful_resolutions ))
    fi
    
    log_info "DNS resolution: ${success_rate}% success rate, ${avg_resolution_time}ms average time"
    
    # Check DNS performance thresholds
    if [[ $success_rate -ge 90 && $avg_resolution_time -le 1000 ]]; then
        return 0
    else
        log_warn "DNS resolution below expected threshold: ${success_rate}% success, ${avg_resolution_time}ms average"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

benchmark_local_throughput() {
    log_info "Benchmarking local network throughput..."
    
    # Test localhost throughput using nc (netcat)
    if ! command -v nc >/dev/null 2>&1; then
        log_warn "netcat not available, skipping local throughput test"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
    
    local port=12345
    local test_duration=10
    local test_data_mb=50
    
    # Start server
    nc -l "$port" > "$TEMP_DIR/network_throughput_received" &
    local server_pid=$!
    
    sleep 1  # Give server time to start
    
    # Generate test data and send it
    local start_time=$(date '+%s')
    dd if=/dev/zero bs=1M count="$test_data_mb" 2>/dev/null | nc localhost "$port" &
    local client_pid=$!
    
    # Wait for completion or timeout
    local timeout=15
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]] && kill -0 "$client_pid" 2>/dev/null; do
        sleep 1
        ((elapsed++))
    done
    
    local end_time=$(date '+%s')
    local duration=$((end_time - start_time))
    
    # Clean up
    kill "$server_pid" "$client_pid" 2>/dev/null || true
    wait "$server_pid" "$client_pid" 2>/dev/null || true
    
    # Calculate throughput
    local bytes_received
    if [[ -f "$TEMP_DIR/network_throughput_received" ]]; then
        bytes_received=$(wc -c < "$TEMP_DIR/network_throughput_received")
        rm -f "$TEMP_DIR/network_throughput_received"
    else
        bytes_received=0
    fi
    
    local mbps=0
    if [[ $duration -gt 0 && $bytes_received -gt 0 ]]; then
        mbps=$(( bytes_received / duration / 1024 / 1024 ))
    fi
    
    log_info "Local network throughput: ${mbps}MB/s"
    
    # Check minimum throughput
    if [[ $mbps -ge 10 ]]; then
        return 0
    else
        log_warn "Local network throughput below expected threshold: ${mbps}MB/s"
        ((PERFORMANCE_WARNINGS++))
        return 1
    fi
}

# === Module Performance Tests ===
test_module_performance() {
    log_info "Running module performance tests..."
    
    # Test main modules
    local modules=("bootstrap.sh" "template.sh" "containers.sh" "config.sh")
    
    for module in "${modules[@]}"; do
        if [[ -f "$SCRIPT_DIR/$module" ]]; then
            run_performance_test "module_${module%.*}" "benchmark_module_startup \"$module\"" "Module startup performance: $module"
        fi
    done
}

benchmark_module_startup() {
    local module="$1"
    local module_path="$SCRIPT_DIR/$module"
    
    if [[ ! -f "$module_path" ]]; then
        log_warn "Module not found: $module_path"
        return 1
    fi
    
    log_info "Benchmarking startup time for module: $module"
    
    local iterations=5
    local total_time=0
    local successful_runs=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date '+%s%3N')
        
        # Run module with --help or similar safe option
        if timeout 30 bash "$module_path" --help >/dev/null 2>&1; then
            local end_time=$(date '+%s%3N')
            local duration=$((end_time - start_time))
            
            total_time=$((total_time + duration))
            ((successful_runs++))
        fi
    done
    
    if [[ $successful_runs -gt 0 ]]; then
        local avg_startup_time=$(( total_time / successful_runs ))
        
        log_info "Module $module average startup time: ${avg_startup_time}ms"
        
        # Check startup time threshold (should be < 5 seconds)
        if [[ $avg_startup_time -lt 5000 ]]; then
            return 0
        else
            log_warn "Module startup time above threshold: ${avg_startup_time}ms"
            ((PERFORMANCE_WARNINGS++))
            return 1
        fi
    else
        log_warn "All module startup attempts failed for: $module"
        return 1
    fi
}

# === Report Generation ===
generate_performance_report() {
    local report_file="$PERFORMANCE_REPORTS_DIR/performance_report_$(date '+%Y%m%d_%H%M%S').html"
    
    log_info "Generating performance report: $report_file"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Homelab Performance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
        .metric h3 { margin: 0; }
        .pass { color: #28a745; }
        .fail { color: #dc3545; }
        .warn { color: #ffc107; }
        .chart-container { margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .test-pass { background-color: #d4edda; }
        .test-fail { background-color: #f8d7da; }
        .test-warn { background-color: #fff3cd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Homelab Performance Report</h1>
        <p>Generated: $(date)</p>
        <p>System: $(uname -a)</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>$PERFORMANCE_TESTS</h3>
            <p>Total Tests</p>
        </div>
        <div class="metric pass">
            <h3>$PERFORMANCE_PASSED</h3>
            <p>Passed</p>
        </div>
        <div class="metric fail">
            <h3>$PERFORMANCE_FAILED</h3>
            <p>Failed</p>
        </div>
        <div class="metric warn">
            <h3>$PERFORMANCE_WARNINGS</h3>
            <p>Warnings</p>
        </div>
    </div>
    
    <h2>Test Results</h2>
    <table>
        <thead>
            <tr>
                <th>Timestamp</th>
                <th>Test Name</th>
                <th>Result</th>
                <th>Duration (s)</th>
                <th>Description</th>
            </tr>
        </thead>
        <tbody>
$(if [[ -f "$TEMP_DIR/performance_results.csv" ]]; then
    while IFS=',' read -r timestamp test_name result duration description; do
        local css_class=""
        case "$result" in
            "PASS") css_class="test-pass" ;;
            "FAIL") css_class="test-fail" ;;
            *) css_class="test-warn" ;;
        esac
        
        echo "            <tr class=\"$css_class\">"
        echo "                <td>$timestamp</td>"
        echo "                <td>$test_name</td>"
        echo "                <td>$result</td>"
        echo "                <td>$duration</td>"
        echo "                <td>$description</td>"
        echo "            </tr>"
    done < "$TEMP_DIR/performance_results.csv"
fi)
        </tbody>
    </table>
    
    <h2>System Monitoring Data</h2>
    <p>Monitoring data collected during tests is available in the temporary directory for further analysis.</p>
    
</body>
</html>
EOF
    
    log_info "Performance report generated: $report_file"
}

# === Main Execution ===
show_performance_help() {
    cat << 'EOF'
Performance Testing Module for Homelab Project

USAGE:
    test_performance.sh [OPTIONS]

OPTIONS:
    -c, --category CATEGORY     Run specific performance category (cpu|memory|disk|network|modules)
    -a, --all                   Run all performance tests
    -d, --duration SECONDS      Set test duration (default: 60)
    -i, --iterations NUMBER     Set number of iterations (default: 5)
    -r, --report-file FILE      Specify HTML report file path
    -v, --verbose               Enable verbose output
    -q, --quiet                 Suppress non-essential output
    --thresholds FILE           Load custom performance thresholds
    --baseline                  Run baseline performance tests
    --stress                    Run stress tests
    -h, --help                  Show this help message

EXAMPLES:
    # Run all performance tests
    ./test_performance.sh --all

    # Run CPU performance tests only
    ./test_performance.sh --category cpu

    # Run stress tests with custom duration
    ./test_performance.sh --stress --duration 120

    # Generate performance report
    ./test_performance.sh --all --report-file performance.html

CATEGORIES:
    cpu         - CPU performance and stress tests
    memory      - Memory allocation and bandwidth tests
    disk        - Disk I/O and throughput tests
    network     - Network connectivity and throughput tests
    modules     - Module startup and performance tests

EOF
}

main() {
    local categories=()
    local run_all=false
    local run_stress=false
    local run_baseline=false
    local verbose=false
    local quiet=false
    local custom_report=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--category)
                categories+=("$2")
                shift 2
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -d|--duration)
                # Store duration for use in tests
                shift 2
                ;;
            -i|--iterations)
                # Store iterations for use in tests
                shift 2
                ;;
            -r|--report-file)
                custom_report="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            --thresholds)
                # Load custom thresholds
                shift 2
                ;;
            --baseline)
                run_baseline=true
                shift
                ;;
            --stress)
                run_stress=true
                shift
                ;;
            -h|--help)
                show_performance_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_performance_help
                exit 1
                ;;
        esac
    done
    
    # Set default categories if none specified
    if [[ $run_all == "true" ]]; then
        categories=("cpu" "memory" "disk" "network" "modules")
    elif [[ ${#categories[@]} -eq 0 ]]; then
        categories=("cpu")
    fi
    
    # Initialize performance testing environment
    setup_performance_logging
    
    log_info "Starting performance testing..."
    log_info "Categories: ${categories[*]}"
    
    # Run performance tests for each category
    for category in "${categories[@]}"; do
        case "$category" in
            cpu)
                test_cpu_performance
                ;;
            memory)
                test_memory_performance
                ;;
            disk)
                test_disk_performance
                ;;
            network)
                test_network_performance
                ;;
            modules)
                test_module_performance
                ;;
            *)
                log_error "Unknown performance category: $category"
                log_info "Available categories: cpu, memory, disk, network, modules"
                exit 1
                ;;
        esac
    done
    
    # Generate performance report
    generate_performance_report
    
    # Print summary
    echo ""
    echo "=========================================="
    echo "       PERFORMANCE TEST SUMMARY"
    echo "=========================================="
    echo "Total Tests:     $PERFORMANCE_TESTS"
    echo "Passed:          $PERFORMANCE_PASSED"
    echo "Failed:          $PERFORMANCE_FAILED"
    echo "Warnings:        $PERFORMANCE_WARNINGS"
    echo "Success Rate:    $(( PERFORMANCE_TESTS > 0 ? (PERFORMANCE_PASSED * 100) / PERFORMANCE_TESTS : 0 ))%"
    echo "=========================================="
    
    # Return appropriate exit code
    if [[ $PERFORMANCE_FAILED -gt 0 ]]; then
        exit 1
    elif [[ $PERFORMANCE_WARNINGS -gt 0 ]]; then
        log_warn "Performance tests completed with warnings"
        exit 2
    else
        exit 0
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi