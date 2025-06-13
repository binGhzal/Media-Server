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
# shellcheck disable=SC2317  # False positive - this function is used in trap
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

# Function to create advanced Prometheus configuration with additional scrape configs
create_prometheus_config() {
    local enable_advanced_monitoring=${1:-false}
    local enable_thanos=${2:-false}
    local thanos_sidecar_enabled="false"
    
    if [ "$enable_advanced_monitoring" = true ]; then
        log "INFO" "Enabling advanced monitoring features in Prometheus configuration..."
        thanos_sidecar_enabled="true"
    fi
    
    if [ "$enable_thanos" = true ]; then
        log "INFO" "Enabling Thanos sidecar in Prometheus configuration..."
        thanos_sidecar_enabled="true"
    fi
    
    log "INFO" "Creating Prometheus configuration..."
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

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115  # Blackbox exporter

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
    metrics_path: /metrics/cadvisor

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['alertmanager:9093']

  - job_name: 'blackbox-http'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - 'http://prometheus:9090'  # Example target
        - 'http://alertmanager:9093'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115

  - job_name: 'blackbox-icmp'
    metrics_path: /probe
    params:
      module: [icmp]
    static_configs:
      - targets:
        - 'prometheus'
        - 'alertmanager'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox-exporter:9115
      - source_labels: [__param_target]
        target_label: instance
      - target_label: job
        replacement: blackbox-icmp

  - job_name: 'blackbox-tcp'
    metrics_path: /probe
    params:
      module: [tcp_connect]
    static_configs:
      - targets:
        - 'prometheus:9090'
        - 'alertmanager:9093'
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox-exporter:9115
      - source_labels: [__param_target]
        target_label: instance
      - target_label: job
        replacement: blackbox-tcp

  - job_name: 'kube-state-metrics'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: kube-system;kube-state-metrics;http-metrics

  - job_name: 'kubernetes-apiservers'
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https

  - job_name: 'kubernetes-nodes'
    kubernetes_sd_configs:
      - role: node
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/\${1}/proxy/metrics

  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: \$1:\$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name

  - job_name: 'kubernetes-cadvisor'
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __metrics_path__
        replacement: /api/v1/nodes/\${1}/proxy/metrics/cadvisor
        source_labels: [__meta_kubernetes_node_name]
        regex: (.+)

  - job_name: 'kubernetes-service-endpoints'
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: \$1:\$2
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: kubernetes_name

  - job_name: 'kubernetes-services'
    kubernetes_sd_configs:
      - role: service
    metrics_path: /probe
    params:
      module: [http_2xx]
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_probe]
        action: keep
        regex: true
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox-exporter:9115
      - source_labels: [__param_target]
        target_label: instance
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_service_name]
        target_label: kubernetes_service_name

  - job_name: 'kubernetes-ingresses'
    kubernetes_sd_configs:
      - role: ingress
    relabel_configs:
      - source_labels: [__meta_kubernetes_ingress_annotation_prometheus_io_probe]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_ingress_scheme,__address__,__meta_kubernetes_ingress_path]
        regex: (.+);(.+);(.+)
        replacement: \${1}://\${2}\${3}
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox-exporter:9115
      - source_labels: [__param_target]
        target_label: instance
      - action: labelmap
        regex: __meta_kubernetes_ingress_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_ingress_name]
        target_label: ingress_name

  - job_name: 'kubernetes-pods-slow'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape_slow]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: \$1:\$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name
    scrape_interval: 5m
    scrape_timeout: 30s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - 'alertmanager:9093'
    - timeout: 10s
      scheme: http
      path_prefix: /
      api_version: v2
      relabel_configs:
        - source_labels: [__meta_kubernetes_service_annotation_alertmanager]
          regex: true
          action: keep
        - source_labels: [__meta_kubernetes_service_annotation_scheme]
          target_label: __scheme__
          regex: (https?)
        - source_labels: [__meta_kubernetes_service_annotation_path]
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_service_annotation_port]
          action: replace
          target_label: __address__
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: \$1:\$2
        - source_labels: [__meta_kubernetes_namespace]
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_service_name]
          target_label: kubernetes_service_name
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

# Function to create Blackbox Exporter configuration
create_blackbox_config() {
    log "INFO" "Creating Blackbox Exporter configuration..."
    
    mkdir -p "$MONITORING_DIR/blackbox/config"
    
    cat > "$MONITORING_DIR/blackbox/config/config.yml" << 'EOF'
modules:
  http_2xx:
    prober: http
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 301, 302, 303, 307, 308]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      headers:
        Accept-Language: en-US
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_post_2xx:
    prober: http
    http:
      method: POST
      headers:
        Content-Type: application/json
      body: '{}'
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 204]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_ssl_expiry:
    prober: http
    http:
      fail_if_not_ssl: true
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: false
    timeout: 10s
    verify: true

  tcp_connect:
    prober: tcp
    tcp:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls: false
      tls_config:
        insecure_skip_verify: true

  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: true

  dns_tcp:
    prober: dns
    dns:
      transport_protocol: "tcp"
      preferred_ip_protocol: "ip4"
      query_name: "example.com"
      query_type: "A"
      valid_rdata:
        match_regexp:
          - ".*"

  dns_udp:
    prober: dns
    dns:
      transport_protocol: "udp"
      preferred_ip_protocol: "ip4"
      query_name: "example.com"
      query_type: "A"
      valid_rdata:
        match_regexp:
          - ".*"

  grpc_plaintext:
    prober: grpc
    grpc:
      tls: false
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      service: ""

  grpc_tls:
    prober: grpc
    grpc:
      tls: true
      tls_config:
        insecure_skip_verify: true
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      service: ""

  ssh_banner:
    prober: tcp
    tcp:
      query_response:
        - expect: "^SSH-2.0-"
      tls: false
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false

  http_2xx_with_body:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      headers:
        Accept: '*/*'
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      fail_if_body_not_matches_regexp:
        - "<title>.*</title>"

  http_2xx_with_redirect:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 301, 302, 303, 307, 308]
      no_follow_redirects: false
      fail_if_not_redirect: true
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_basic_auth:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      basic_auth:
        username: "user"
        password: "password"
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_headers:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      headers:
        X-Custom-Header: "custom-value"
        Accept: "application/json"
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_body_match:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      fail_if_body_not_matches_regexp:
        - "<title>.*</title>"
        - "<meta.*charset=[\"']?[uU][tT][fF]-?8"

  http_2xx_with_cert_check:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: true
      method: GET
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: false
        cert_file: "/path/to/cert.pem"
        key_file: "/path/to/key.pem"
        ca_file: "/path/to/ca.pem"
        server_name: "example.com"

  http_2xx_with_proxy:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      proxy_url: "http://proxy.example.com:8080"
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_compression:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      headers:
        Accept-Encoding: "gzip, deflate, br"
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_cookies:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      headers:
        Cookie: "sessionid=abc123"
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_oauth2:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: true
      method: GET
      oauth2:
        client_id: "client-id"
        client_secret: "client-secret"
        token_url: "https://auth.example.com/oauth2/token"
        scopes: ["read"]
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_ntlm:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      method: GET
      basic_auth:
        username: "domain\\user"
        password: "password"
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_aws_sigv4:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: true
      method: GET
      aws_sigv4:
        region: "us-east-1"
        access_key: "AKIA..."
        secret_key: "..."
        service: "execute-api"
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true

  http_2xx_with_http2:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/2.0"]
      valid_status_codes: [200]
      method: GET
      headers:
        User-Agent: "Blackbox Exporter"

  http_2xx_with_http11_required:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/1.1"]
      valid_status_codes: [200]
      method: GET
      headers:
        User-Agent: "Blackbox Exporter"

  http_2xx_with_ipv6:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip6"
      ip_protocol_fallback: true
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      method: GET

  http_2xx_with_http10:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/1.0"]
      valid_status_codes: [200, 301, 302, 303, 307, 308]
      method: GET

  http_2xx_with_http09:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/0.9", "HTTP/1.0"]
      valid_status_codes: [200, 301, 302, 303, 307, 308]
      method: GET

  http_2xx_with_http3:
    prober: http
    timeout: 10s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/3.0"]
      valid_status_codes: [200]
      method: GET
      enable_http2: true
      preferred_ip_protocol: "udp"

  http_2xx_with_http2_prior_knowledge:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/2.0"]
      valid_status_codes: [200]
      method: GET
      enable_http2: true
      http2_prior_knowledge: true

  http_2xx_with_http2_prior_knowledge_and_tls:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/2.0"]
      valid_status_codes: [200]
      method: GET
      enable_http2: true
      http2_prior_knowledge: true
      tls: true

  http_2xx_with_http2_prior_knowledge_and_tls_and_alpn:
    prober: http
    timeout: 5s
    http:
      preferred_ip_protocol: "ip4"
      ip_protocol_fallback: false
      tls_config:
        insecure_skip_verify: true
      valid_http_versions: ["HTTP/2.0"]
      valid_status_codes: [200]
      method: GET
      enable_http2: true
      http2_prior_knowledge: true
      tls: true
      tls_config:
        insecure_skip_verify: true
        server_name: "example.com"
        min_version: "TLS12"
        max_version: "TLS13"
        next_protos: ["h2", "http/1.1"]
        cipher_suites:
          - "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
          - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
          - "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
          - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
          - "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
          - "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305"
          - "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA"
          - "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA"
          - "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA"
          - "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA"
          - "TLS_RSA_WITH_AES_128_GCM_SHA256"
          - "TLS_RSA_WITH_AES_256_GCM_SHA384"
          - "TLS_RSA_WITH_AES_128_CBC_SHA"
          - "TLS_RSA_WITH_AES_256_CBC_SHA"
          - "TLS_RSA_WITH_3DES_EDE_CBC_SHA"
        curve_preferences:
          - "CurveP521"
          - "CurveP384"
          - "CurveP256"
        prefer_server_cipher_suites: false
        session_tickets: true
        session_ticket_key: ""
        client_auth_type: ""
        client_ca_file: ""
        client_cert_file: ""
        client_key_file: ""
        insecure_skip_verify: true
        server_name: "example.com"
EOF

    log "INFO" "Blackbox Exporter configuration created"
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

    # Create comprehensive alert rules for Prometheus
    cat > "$MONITORING_DIR/prometheus/config/alert.rules.yml" << 'EOF'
groups:
  # System and infrastructure alerts
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
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 90% for more than 5 minutes on {{ $labels.instance }}"

      - alert: CriticalCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Critical CPU usage on {{ $labels.instance }}"
          description: "CPU usage is critically high (above 95%) on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 90% for more than 5 minutes on {{ $labels.instance }}"

      - alert: CriticalMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 95
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Critical memory usage on {{ $labels.instance }}"
          description: "Memory usage is critically high (above 95%) on {{ $labels.instance }}"

      - alert: DiskSpaceLow
        expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs"})) * 100 > 85
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has only {{ $value | humanizePercentage }} free space"

      - alert: DiskSpaceCritical
        expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs"})) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Critical disk space on {{ $labels.instance }}"
          description: "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has only {{ $value | humanizePercentage }} free space"

      - alert: DiskWillFillIn4Hours
        expr: predict_linear(node_filesystem_avail_bytes[6h], 4 * 3600) <= 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Disk predicted to fill in 4 hours on {{ $labels.instance }}"
          description: "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} will be full within 4 hours if current growth rate continues"

      - alert: HighLoadAverage
        expr: (sum by(instance) (rate(node_cpu_seconds_total{mode="system"}[5m])) / count by(instance) (count by(instance, cpu) (node_cpu_seconds_total{mode="system"}))) * 100 > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High load average on {{ $labels.instance }}"
          description: "Load average is high on {{ $labels.instance }}"

      - alert: HighNetworkTraffic
        expr: sum by(instance) (rate(node_network_receive_bytes_total[5m])) / 1024 / 1024 > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High network traffic on {{ $labels.instance }}"
          description: "Network traffic is above 100MB/s on {{ $labels.instance }}"

      - alert: HighNetworkErrorRate
        expr: (sum(rate(node_network_receive_errs_total[5m])) by(instance) / sum(rate(node_network_receive_packets_total[5m])) by(instance)) * 100 > 5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High network error rate on {{ $labels.instance }}"
          description: "Network error rate is above 5% on {{ $labels.instance }}"

      - alert: HighTCPConnectionCount
        expr: node_netstat_Tcp_CurrEstab > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of TCP connections on {{ $labels.instance }}"
          description: "Number of TCP connections is high on {{ $labels.instance }}"

  # Blackbox exporter alerts
  - name: blackbox.rules
    rules:
      - alert: BlackboxProbeFailed
        expr: probe_success == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Blackbox probe failed (instance {{ $labels.instance }})"
          description: "Blackbox probe failed for {{ $labels.instance }} ({{ $labels.job }})"

      - alert: BlackboxProbeHttpFailure
        expr: probe_http_status_code <= 199 OR probe_http_status_code >= 400
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Blackbox HTTP probe failed (instance {{ $labels.instance }})"
          description: "HTTP status code is {{ $value }} for {{ $labels.instance }}"

      - alert: BlackboxSlowResponse
        expr: probe_duration_seconds > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Blackbox slow response (instance {{ $labels.instance }})"
          description: "Blackbox probe took {{ $value }} seconds for {{ $labels.instance }}"

      - alert: BlackboxSSLCertExpiringSoon
        expr: probe_ssl_earliest_cert_expiry - time() < 86400 * 30  # 30 days
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon (instance {{ $labels.instance }})"
          description: "SSL certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}"

  # Kubernetes cluster alerts
  - name: kubernetes.rules
    rules:
      - alert: KubeNodeNotReady
        expr: kube_node_status_condition{condition="Ready",status!="true"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Node {{ $labels.node }} is not ready"
          description: "Node {{ $labels.node }} has been in a non-ready state for more than 5 minutes"

      - alert: KubeNodeUnreachable
        expr: kube_node_spec_unschedulable == 1
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Node {{ $labels.node }} is unreachable"
          description: "Node {{ $labels.node }} has been unreachable for more than 15 minutes"

      - alert: KubeletDown
        expr: absent(up{job="kubelet"} == 1)
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kubelet is down on {{ $labels.instance }}"
          description: "Kubelet has disappeared from Prometheus target discovery"

      - alert: KubeAPIDown
        expr: absent(up{job="apiserver"} == 1)
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kubernetes API server is down"
          description: "Kubernetes API server has disappeared from Prometheus target discovery"

      - alert: KubeSchedulerDown
        expr: absent(up{job="kube-scheduler"} == 1)
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kubernetes scheduler is down"
          description: "Kubernetes scheduler has disappeared from Prometheus target discovery"

      - alert: KubeControllerManagerDown
        expr: absent(up{job="kube-controller-manager"} == 1)
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Kubernetes controller manager is down"
          description: "Kubernetes controller manager has disappeared from Prometheus target discovery"

  # Container alerts
  - name: container.rules
    rules:
      - alert: ContainerKilled
        expr: time() - container_last_seen > 60
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Container killed (instance {{ $labels.instance }})"
          description: "Container {{ $labels.name }} has disappeared from cAdvisor"

      - alert: ContainerHighCpuUsage
        expr: (sum(rate(container_cpu_usage_seconds_total[3m])) BY (instance, name) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container high CPU usage (instance {{ $labels.instance }})"
          description: "Container {{ $labels.name }} CPU usage is {{ $value }}%"

      - alert: ContainerHighMemoryUsage
        expr: (sum(container_memory_working_set_bytes) BY (instance, name) / sum(container_spec_memory_limit_bytes > 0) BY (instance, name) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container high memory usage (instance {{ $labels.instance }})"
          description: "Container {{ $labels.name }} memory usage is {{ $value }}%"

      - alert: ContainerRestartingFrequently
        expr: increase(kube_pod_container_status_restarts_total[1h]) > 3
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Container restarting frequently (instance {{ $labels.instance }})"
          description: "Container {{ $labels.container }} in pod {{ $labels.pod }} is restarting frequently ({{ $value }} times in the last hour)"

      - alert: ContainerOOMKilled
        expr: increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}[30m]) > 0
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Container OOMKilled (instance {{ $labels.instance }})"
          description: "Container {{ $labels.container }} in pod {{ $labels.pod }} was OOMKilled"

  # Application performance alerts
  - name: application.rules
    rules:
      - alert: HighRequestLatency
        expr: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High request latency (instance {{ $labels.instance }})"
          description: "99th percentile request latency is {{ $value }}s"

      - alert: HighErrorRate
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (job) / sum(rate(http_requests_total[5m])) by (job) > 0.01
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate (instance {{ $labels.instance }})"
          description: "Error rate is {{ $value }}%"

      - alert: HighRequestRate
        expr: sum(rate(http_requests_total[5m])) by (job) > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High request rate (instance {{ $labels.instance }})"
          description: "Request rate is {{ $value }} requests/second"

  # Security alerts
  - name: security.rules
    rules:
      - alert: UnauthorizedAccessAttempts
        expr: increase(auth_failed_attempts_total[5m]) > 5
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Multiple failed login attempts (instance {{ $labels.instance }})"
          description: "There were {{ $value }} failed login attempts in the last 5 minutes"

      - alert: HighPrivilegeContainer
        expr: container_security_ctx_privileged == 1 or container_security_ctx_allow_privilege_escalation == 1
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "High privilege container detected (instance {{ $labels.instance }})"
          description: "Container {{ $labels.container }} is running with elevated privileges"

  # Business metrics alerts
  - name: business.rules
    rules:
      - alert: HighOrderFailureRate
        expr: sum(rate(orders_failed_total[5m])) by (service) / sum(rate(orders_total[5m])) by (service) > 0.05
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "High order failure rate (service {{ $labels.service }})"
          description: "Order failure rate is {{ $value | humanizePercentage }}"

      - alert: LowInventory
        expr: inventory_items < 10
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Low inventory level ({{ $labels.product }})"
          description: "Inventory level for {{ $labels.product }} is critically low ({{ $value }} items)"

      - alert: HighCheckoutAbandonment
        expr: (1 - (checkout_completed_total / checkout_started_total)) > 0.7
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "High checkout abandonment rate"
          description: "Checkout abandonment rate is {{ $value | humanizePercentage }}"

  # Recording rules for frequently used queries
  - name: recording.rules
    rules:
      - record: job:http_inprogress_requests:sum
        expr: sum by(job) (http_requests_in_progress)
      - record: job:http_request_duration_seconds:avg_rate5m
        expr: avg by(job) (rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m]))
      - record: instance:node_cpu_utilisation:rate5m
        expr: 1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
      - record: instance:node_memory_utilisation:ratio
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes
      - record: instance:node_filesystem_usage:ratio
        expr: 1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs"})
      - record: instance:node_network_receive_bytes:rate5m
        expr: rate(node_network_receive_bytes_total[5m])
      - record: instance:node_network_transmit_bytes:rate5m
        expr: rate(node_network_transmit_bytes_total[5m])
      - record: instance:node_disk_reads_completed:rate5m
        expr: rate(node_disk_reads_completed_total[5m])
      - record: instance:node_disk_writes_completed:rate5m
        expr: rate(node_disk_writes_completed_total[5m])
      - record: container_memory_working_set_bytes:sum
        expr: sum by(container, pod, namespace) (container_memory_working_set_bytes{container!="",pod!=""})
      - record: container_cpu_usage_seconds_total:rate5m
        expr: sum by(container, pod, namespace) (rate(container_cpu_usage_seconds_total[5m]))
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
