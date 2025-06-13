#!/bin/bash
# Proxmox Template Creator - Monitoring Module
# Deploy and manage monitoring stack (Prometheus, Grafana, Node Exporter)

set -e

# Script version
VERSION="0.1.0"

# Directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR

# Logging function
log() {
    local level="$1"; shift
    local color=""
    local reset="\033[0m"
    case $level in
        INFO)
            color="\033[0;32m" # Green
            ;;
        WARN)
            color="\033[0;33m" # Yellow
            ;;
        ERROR)
            color="\033[0;31m" # Red
            ;;
        *)
            color=""
            ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*${reset}"
}

# Error handling function
handle_error() {
    local exit_code="$1"
    local line_no="$2"
    log "ERROR" "An error occurred on line $line_no with exit code $exit_code"
    if [ -t 0 ]; then  # If running interactively
        whiptail --title "Error" --msgbox "An error occurred. Check the logs for details." 10 60 3>&1 1>&2 2>&3
    fi
    exit "$exit_code"
}

# Set up error trap
trap 'handle_error $? $LINENO' ERR

# Parse command line arguments
TEST_MODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=1
            shift
            ;;
        --help|-h)
            cat << EOF
Proxmox Template Creator - Monitoring Module v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
  --test              Run in test mode (no actual deployments)
  --help, -h          Show this help message

EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Try '$(basename "$0") --help' for more information."
            exit 1
            ;;
    esac
done

# Configuration
MONITORING_DIR="/opt/monitoring"
PROMETHEUS_VERSION="2.45.0"
GRAFANA_VERSION="10.1.0"
NODE_EXPORTER_VERSION="1.6.1"

# Function to check if Docker is installed
check_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "INFO" "Docker is installed"
        return 0
    else
        log "INFO" "Docker is not installed"
        return 1
    fi
}

# Function to install Docker (if needed)
install_docker() {
    log "INFO" "Installing Docker..."

    # Update package index
    apt-get update

    # Install dependencies
    apt-get install -y ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Enable and start Docker
    systemctl enable --now docker

    log "INFO" "Docker installed successfully"
}

# Function to create monitoring directories
create_monitoring_dirs() {
    log "INFO" "Creating monitoring directories..."

    mkdir -p "$MONITORING_DIR"/{prometheus,grafana,alertmanager}
    mkdir -p "$MONITORING_DIR"/prometheus/{data,config}
    mkdir -p "$MONITORING_DIR"/grafana/{data,dashboards,provisioning}
    mkdir -p "$MONITORING_DIR"/grafana/provisioning/{dashboards,datasources}

    # Set proper permissions
    chown -R 472:472 "$MONITORING_DIR"/grafana
    chown -R 65534:65534 "$MONITORING_DIR"/prometheus

    log "INFO" "Monitoring directories created"
}

# Function to create Prometheus configuration
create_prometheus_config() {
    log "INFO" "Creating Prometheus configuration..."

    cat > "$MONITORING_DIR/prometheus/config/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert.rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['alertmanager:9093']

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    log "INFO" "Prometheus configuration created"
}

# Function to create Grafana datasource configuration
create_grafana_datasource() {
    log "INFO" "Creating Grafana datasource configuration..."

    cat > "$MONITORING_DIR/grafana/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    log "INFO" "Grafana datasource configuration created"
}

# Function to create Grafana dashboard provisioning
create_grafana_dashboards() {
    log "INFO" "Creating Grafana dashboard provisioning..."

    cat > "$MONITORING_DIR/grafana/provisioning/dashboards/default.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Download Node Exporter dashboard
    curl -s https://grafana.com/api/dashboards/1860/revisions/37/download | jq '.' > "$MONITORING_DIR/grafana/dashboards/node-exporter-dashboard.json"

    log "INFO" "Grafana dashboard provisioning created"
}

# Function to create Alertmanager configuration
create_alertmanager_config() {
    log "INFO" "Creating Alertmanager configuration..."

    # Create alertmanager directory
    mkdir -p "$MONITORING_DIR/alertmanager"

    # Create Alertmanager configuration
    cat > "$MONITORING_DIR/alertmanager/alertmanager.yml" << 'EOF'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@example.com'
  resolve_timeout: 5m

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
        send_resolved: true

  - name: 'email'
    email_configs:
      - to: 'admin@example.com'
        subject: 'Alert: {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Labels: {{ range .Labels.SortedPairs }} {{ .Name }}={{ .Value }} {{ end }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF

    # Create basic alert rules for Prometheus
    cat > "$MONITORING_DIR/prometheus/config/alert.rules.yml" << 'EOF'
groups:
  - name: system.rules
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is down"
          description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 1 minute."

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% for more than 5 minutes on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 90% for more than 5 minutes on {{ $labels.instance }}"

      - alert: DiskSpaceLow
        expr: (1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk usage is above 85% on {{ $labels.instance }} for filesystem {{ $labels.mountpoint }}"

      - alert: PrometheusConfigurationReloadFailure
        expr: prometheus_config_last_reload_successful != 1
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Prometheus configuration reload failure"
          description: "Prometheus configuration reload error"

  - name: container.rules
    rules:
      - alert: ContainerKilled
        expr: time() - container_last_seen > 60
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Container killed"
          description: "A container has disappeared"

      - alert: ContainerHighCpuUsage
        expr: (sum(rate(container_cpu_usage_seconds_total[3m])) BY (instance, name) * 100) > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Container high CPU usage"
          description: "Container CPU usage is above 80%"

      - alert: ContainerHighMemoryUsage
        expr: (sum(container_memory_working_set_bytes) BY (instance, name) / sum(container_spec_memory_limit_bytes > 0) BY (instance, name) * 100) > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Container high memory usage"
          description: "Container memory usage is above 80%"
EOF

    # Set proper permissions
    chown -R 65534:65534 "$MONITORING_DIR/alertmanager"

    log "INFO" "Alertmanager configuration created"
}

# Function to create Docker Compose file
create_docker_compose() {
    log "INFO" "Creating Docker Compose configuration..."

    cat > "$MONITORING_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v${PROMETHEUS_VERSION}
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/config:/etc/prometheus
      - ./prometheus/data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    restart: unless-stopped
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:v${NODE_EXPORTER_VERSION}
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    restart: unless-stopped
    networks:
      - monitoring

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    restart: unless-stopped
    networks:
      - monitoring

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager:/etc/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
      - '--web.external-url=http://localhost:9093'
      - '--cluster.advertise-address=0.0.0.0:9093'
    restart: unless-stopped
    networks:
      - monitoring

networks:
  monitoring:
    driver: bridge
EOF

    log "INFO" "Docker Compose configuration created"
}

# Function to deploy monitoring stack
deploy_monitoring_stack() {
    log "INFO" "Deploying monitoring stack..."

    cd "$MONITORING_DIR"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would deploy monitoring stack with docker-compose up -d"
    else
        docker compose up -d

        # Wait for services to be ready
        log "INFO" "Waiting for services to be ready..."
        sleep 30

        # Check service status
        log "INFO" "Checking service status..."
        docker compose ps

        log "INFO" "Monitoring stack deployed successfully!"
        log "INFO" "Access URLs:"
        log "INFO" "  Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
        log "INFO" "  Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/admin)"
        log "INFO" "  Node Exporter: http://$(hostname -I | awk '{print $1}'):9100"
        log "INFO" "  cAdvisor: http://$(hostname -I | awk '{print $1}'):8080"
        log "INFO" "  Alertmanager: http://$(hostname -I | awk '{print $1}'):9093"
    fi
}

# Function to check monitoring stack status
check_monitoring_status() {
    log "INFO" "Checking monitoring stack status..."

    if [ ! -f "$MONITORING_DIR/docker-compose.yml" ]; then
        log "INFO" "Monitoring stack not deployed"
        return 1
    fi

    cd "$MONITORING_DIR"

    local services_running=0
    local expected_services=5

    if docker compose ps --services --filter "status=running" | grep -q prometheus; then
        ((services_running++))
        log "INFO" "Prometheus: Running"
    else
        log "WARN" "Prometheus: Not running"
    fi

    if docker compose ps --services --filter "status=running" | grep -q grafana; then
        ((services_running++))
        log "INFO" "Grafana: Running"
    else
        log "WARN" "Grafana: Not running"
    fi

    if docker compose ps --services --filter "status=running" | grep -q node-exporter; then
        ((services_running++))
        log "INFO" "Node Exporter: Running"
    else
        log "WARN" "Node Exporter: Not running"
    fi

    if docker compose ps --services --filter "status=running" | grep -q cadvisor; then
        ((services_running++))
        log "INFO" "cAdvisor: Running"
    else
        log "WARN" "cAdvisor: Not running"
    fi

    if docker compose ps --services --filter "status=running" | grep -q alertmanager; then
        ((services_running++))
        log "INFO" "Alertmanager: Running"
    else
        log "WARN" "Alertmanager: Not running"
    fi

    if [ $services_running -eq $expected_services ]; then
        log "INFO" "All monitoring services are running"
        return 0
    else
        log "WARN" "Some monitoring services are not running ($services_running/$expected_services)"
        return 1
    fi
}

# Function to stop monitoring stack
stop_monitoring_stack() {
    log "INFO" "Stopping monitoring stack..."

    if [ ! -f "$MONITORING_DIR/docker-compose.yml" ]; then
        log "INFO" "Monitoring stack not deployed"
        return 1
    fi

    cd "$MONITORING_DIR"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would stop monitoring stack with docker-compose down"
    else
        docker compose down
        log "INFO" "Monitoring stack stopped"
    fi
}

# Function to remove monitoring stack
remove_monitoring_stack() {
    log "INFO" "Removing monitoring stack..."

    if [ ! -f "$MONITORING_DIR/docker-compose.yml" ]; then
        log "INFO" "Monitoring stack not deployed"
        return 1
    fi

    cd "$MONITORING_DIR"

    if [ -n "$TEST_MODE" ]; then
        log "INFO" "Test mode: Would remove monitoring stack and data"
    else
        # Stop and remove containers
        docker compose down -v

        # Ask for confirmation before removing data
        if whiptail --title "Remove Data" --yesno "Do you want to remove all monitoring data?\nThis action cannot be undone." 10 60; then
            rm -rf "$MONITORING_DIR"
            log "INFO" "Monitoring stack and data removed"
        else
            log "INFO" "Monitoring stack removed, data preserved"
        fi
    fi
}

# Main menu function
main_menu() {
    local option
    option=$(whiptail --title "Monitoring Stack" --menu "Choose an option:" 15 60 5 \
        "1" "Deploy monitoring stack" \
        "2" "Check monitoring status" \
        "3" "Stop monitoring stack" \
        "4" "Remove monitoring stack" \
        "5" "Help & Documentation" 3>&1 1>&2 2>&3)

    case $option in
        1)
            # Deploy monitoring stack
            if ! check_docker; then
                if whiptail --title "Docker Required" --yesno "Docker is required for the monitoring stack.\nInstall Docker now?" 10 60; then
                    if [ -n "$TEST_MODE" ]; then
                        log "INFO" "Test mode: Would install Docker"
                    else
                        install_docker
                    fi
                else
                    log "INFO" "Docker installation cancelled"
                    return 1
                fi
            fi

            create_monitoring_dirs
            create_prometheus_config
            create_grafana_datasource
            create_grafana_dashboards
            create_alertmanager_config
            create_docker_compose
            deploy_monitoring_stack
            ;;
        2)
            # Check status
            check_monitoring_status
            whiptail --title "Monitoring Status" --msgbox "Check the terminal output for detailed status information." 10 60
            ;;
        3)
            # Stop monitoring stack
            stop_monitoring_stack
            ;;
        4)
            # Remove monitoring stack
            if whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove the monitoring stack?" 10 60; then
                remove_monitoring_stack
            fi
            ;;
        5)
            whiptail --title "Monitoring Stack Help" --msgbox "Monitoring Stack Module v${VERSION}\n\nThis module helps you deploy a complete monitoring solution including:\n\n- Prometheus: Metrics collection and storage\n- Grafana: Visualization dashboards\n- Node Exporter: System metrics\n- cAdvisor: Container metrics\n- Alertmanager: Alert routing and notifications\n\nDefault access credentials:\n- Grafana: admin/admin\n\nAccess URLs (when deployed):\n- Prometheus: http://server-ip:9090\n- Grafana: http://server-ip:3000\n- Alertmanager: http://server-ip:9093\n\nFor more information, see the documentation at:\nhttps://github.com/binghzal/homelab/tree/main/docs" 20 80
            main_menu
            ;;
        *)
            log "INFO" "User exited monitoring menu."
            exit 0
            ;;
    esac
}

# Run the main menu if not in test mode
if [ -n "$TEST_MODE" ]; then
    log "INFO" "Monitoring Stack module (test mode)"
else
    main_menu
fi

exit 0
