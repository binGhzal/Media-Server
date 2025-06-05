# Variables specific to monitoring stack
variable "monitoring_vm_name" {
  description = "Name for the monitoring VM"
  type        = string
  default     = "monitoring"
}

variable "monitoring_template_id" {
  description = "Template ID to clone for monitoring VM"
  type        = string
}

variable "monitoring_cpu_cores" {
  description = "CPU cores for monitoring VM"
  type        = number
  default     = 4
}

variable "monitoring_memory_mb" {
  description = "Memory in MB for monitoring VM"
  type        = number
  default     = 8192
}

variable "monitoring_disk_size" {
  description = "Disk size for monitoring VM"
  type        = string
  default     = "100G"
}

variable "grafana_port" {
  description = "Port for Grafana"
  type        = number
  default     = 3000
}

variable "prometheus_port" {
  description = "Port for Prometheus"
  type        = number
  default     = 9090
}

variable "alertmanager_port" {
  description = "Port for Alertmanager"
  type        = number
  default     = 9093
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "enable_node_exporter" {
  description = "Enable Node Exporter for system metrics"
  type        = bool
  default     = true
}

variable "enable_cadvisor" {
  description = "Enable cAdvisor for container metrics"
  type        = bool
  default     = true
}

variable "enable_alertmanager" {
  description = "Enable Alertmanager for alerts"
  type        = bool
  default     = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "scrape_targets" {
  description = "Additional scrape targets for Prometheus"
  type        = list(string)
  default     = []
}

# Monitoring VM
resource "proxmox_vm_qemu" "monitoring_vm" {
  name        = var.monitoring_vm_name
  target_node = var.pm_target_node
  clone       = var.monitoring_template_id
  cores       = var.monitoring_cpu_cores
  memory      = var.monitoring_memory_mb
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  agent       = 1
  os_type     = "cloud-init"

  disk {
    size    = var.monitoring_disk_size
    type    = "scsi"
    storage = var.storage
  }

  network {
    bridge = var.network_bridge
    model  = "virtio"
  }

  ciuser  = var.cloud_user
  sshkeys = file(var.ssh_key_path)

  tags = "monitoring,prometheus,grafana"

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Install Docker and monitoring stack
resource "null_resource" "monitoring_setup" {
  depends_on = [proxmox_vm_qemu.monitoring_vm]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
  }

  # Install Docker
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo usermod -aG docker ${var.cloud_user}",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
  }

  # Create monitoring directories
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /home/${var.cloud_user}/monitoring/{prometheus,grafana,alertmanager}",
      "mkdir -p /home/${var.cloud_user}/monitoring/prometheus/{data,config}",
      "mkdir -p /home/${var.cloud_user}/monitoring/grafana/{data,dashboards,provisioning}",
      "mkdir -p /home/${var.cloud_user}/monitoring/grafana/provisioning/{dashboards,datasources}",
      "mkdir -p /home/${var.cloud_user}/monitoring/alertmanager/{data,config}"
    ]
  }

  triggers = {
    monitoring_ip = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
  }
}

# Configure Prometheus
resource "null_resource" "prometheus_config" {
  depends_on = [null_resource.monitoring_setup]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
  }

  # Create Prometheus configuration
  provisioner "remote-exec" {
    inline = [
      "cat > /home/${var.cloud_user}/monitoring/prometheus/config/prometheus.yml << 'EOF'",
      "global:",
      "  scrape_interval: 15s",
      "  evaluation_interval: 15s",
      "",
      "rule_files:",
      "  - '/etc/prometheus/rules/*.yml'",
      "",
      var.enable_alertmanager ? "alerting:" : "",
      var.enable_alertmanager ? "  alertmanagers:" : "",
      var.enable_alertmanager ? "    - static_configs:" : "",
      var.enable_alertmanager ? "        - targets:" : "",
      var.enable_alertmanager ? "          - alertmanager:9093" : "",
      "",
      "scrape_configs:",
      "  - job_name: 'prometheus'",
      "    static_configs:",
      "      - targets: ['localhost:9090']",
      "",
      var.enable_node_exporter ? "  - job_name: 'node-exporter'" : "",
      var.enable_node_exporter ? "    static_configs:" : "",
      var.enable_node_exporter ? "      - targets: ['node-exporter:9100']" : "",
      "",
      var.enable_cadvisor ? "  - job_name: 'cadvisor'" : "",
      var.enable_cadvisor ? "    static_configs:" : "",
      var.enable_cadvisor ? "      - targets: ['cadvisor:8080']" : "",
      length(var.scrape_targets) > 0 ? "" : "",
      length(var.scrape_targets) > 0 ? "  - job_name: 'additional-targets'" : "",
      length(var.scrape_targets) > 0 ? "    static_configs:" : "",
      length(var.scrape_targets) > 0 ? "      - targets:" : "",
      length(var.scrape_targets) > 0 ? join("\n", [for target in var.scrape_targets : "          - '${target}'"]) : "",
      "EOF"
    ]
  }

  triggers = {
    scrape_targets = join(",", var.scrape_targets)
    node_exporter  = var.enable_node_exporter
    cadvisor       = var.enable_cadvisor
    alertmanager   = var.enable_alertmanager
  }
}

# Configure Grafana
resource "null_resource" "grafana_config" {
  depends_on = [null_resource.monitoring_setup]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
  }

  # Create Grafana datasource configuration
  provisioner "remote-exec" {
    inline = [
      "cat > /home/${var.cloud_user}/monitoring/grafana/provisioning/datasources/prometheus.yml << 'EOF'",
      "apiVersion: 1",
      "",
      "datasources:",
      "  - name: Prometheus",
      "    type: prometheus",
      "    access: proxy",
      "    url: http://prometheus:9090",
      "    isDefault: true",
      "EOF"
    ]
  }

  # Create Grafana dashboard configuration
  provisioner "remote-exec" {
    inline = [
      "cat > /home/${var.cloud_user}/monitoring/grafana/provisioning/dashboards/dashboards.yml << 'EOF'",
      "apiVersion: 1",
      "",
      "providers:",
      "  - name: 'default'",
      "    orgId: 1",
      "    folder: ''",
      "    type: file",
      "    disableDeletion: false",
      "    updateIntervalSeconds: 10",
      "    allowUiUpdates: true",
      "    options:",
      "      path: /var/lib/grafana/dashboards",
      "EOF"
    ]
  }

  triggers = {
    grafana_password = var.grafana_admin_password
  }
}

# Configure Alertmanager
resource "null_resource" "alertmanager_config" {
  count      = var.enable_alertmanager ? 1 : 0
  depends_on = [null_resource.monitoring_setup]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
  }

  # Create Alertmanager configuration
  provisioner "remote-exec" {
    inline = [
      "cat > /home/${var.cloud_user}/monitoring/alertmanager/config/alertmanager.yml << 'EOF'",
      "global:",
      "  smtp_smarthost: 'localhost:587'",
      "  smtp_from: 'alertmanager@example.org'",
      "",
      "route:",
      "  group_by: ['alertname']",
      "  group_wait: 10s",
      "  group_interval: 10s",
      "  repeat_interval: 1h",
      "  receiver: 'web.hook'",
      "",
      "receivers:",
      "  - name: 'web.hook'",
      var.slack_webhook_url != "" ? "    slack_configs:" : "",
      var.slack_webhook_url != "" ? "      - api_url: '${var.slack_webhook_url}'" : "",
      var.slack_webhook_url != "" ? "        channel: '#alerts'" : "",
      var.slack_webhook_url != "" ? "        title: 'Alert: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'" : "",
      var.slack_webhook_url != "" ? "        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'" : "",
      "EOF"
    ]
  }

  triggers = {
    slack_webhook = var.slack_webhook_url
  }
}

# Deploy monitoring stack
resource "null_resource" "monitoring_deploy" {
  depends_on = [
    null_resource.prometheus_config,
    null_resource.grafana_config,
    null_resource.alertmanager_config
  ]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
  }

  # Create docker-compose file
  provisioner "remote-exec" {
    inline = [
      "cat > /home/${var.cloud_user}/monitoring/docker-compose.yml << 'EOF'",
      "version: '3.8'",
      "",
      "networks:",
      "  monitoring:",
      "    driver: bridge",
      "",
      "volumes:",
      "  prometheus_data:",
      "  grafana_data:",
      var.enable_alertmanager ? "  alertmanager_data:" : "",
      "",
      "services:",
      "  prometheus:",
      "    image: prom/prometheus:latest",
      "    container_name: prometheus",
      "    restart: unless-stopped",
      "    ports:",
      "      - '${var.prometheus_port}:9090'",
      "    command:",
      "      - '--config.file=/etc/prometheus/prometheus.yml'",
      "      - '--storage.tsdb.path=/prometheus'",
      "      - '--web.console.libraries=/etc/prometheus/console_libraries'",
      "      - '--web.console.templates=/etc/prometheus/consoles'",
      "      - '--storage.tsdb.retention.time=200h'",
      "      - '--web.enable-lifecycle'",
      "    volumes:",
      "      - ./prometheus/config:/etc/prometheus",
      "      - prometheus_data:/prometheus",
      "    networks:",
      "      - monitoring",
      "",
      "  grafana:",
      "    image: grafana/grafana:latest",
      "    container_name: grafana",
      "    restart: unless-stopped",
      "    ports:",
      "      - '${var.grafana_port}:3000'",
      "    environment:",
      "      - GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
      "      - GF_USERS_ALLOW_SIGN_UP=false",
      "    volumes:",
      "      - grafana_data:/var/lib/grafana",
      "      - ./grafana/provisioning:/etc/grafana/provisioning",
      "      - ./grafana/dashboards:/var/lib/grafana/dashboards",
      "    networks:",
      "      - monitoring",
      "",
      var.enable_node_exporter ? "  node-exporter:" : "",
      var.enable_node_exporter ? "    image: prom/node-exporter:latest" : "",
      var.enable_node_exporter ? "    container_name: node-exporter" : "",
      var.enable_node_exporter ? "    restart: unless-stopped" : "",
      var.enable_node_exporter ? "    ports:" : "",
      var.enable_node_exporter ? "      - '9100:9100'" : "",
      var.enable_node_exporter ? "    command:" : "",
      var.enable_node_exporter ? "      - '--path.procfs=/host/proc'" : "",
      var.enable_node_exporter ? "      - '--path.rootfs=/rootfs'" : "",
      var.enable_node_exporter ? "      - '--path.sysfs=/host/sys'" : "",
      var.enable_node_exporter ? "      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'" : "",
      var.enable_node_exporter ? "    volumes:" : "",
      var.enable_node_exporter ? "      - /proc:/host/proc:ro" : "",
      var.enable_node_exporter ? "      - /sys:/host/sys:ro" : "",
      var.enable_node_exporter ? "      - /:/rootfs:ro" : "",
      var.enable_node_exporter ? "    networks:" : "",
      var.enable_node_exporter ? "      - monitoring" : "",
      var.enable_node_exporter ? "" : "",
      var.enable_cadvisor ? "  cadvisor:" : "",
      var.enable_cadvisor ? "    image: gcr.io/cadvisor/cadvisor:latest" : "",
      var.enable_cadvisor ? "    container_name: cadvisor" : "",
      var.enable_cadvisor ? "    restart: unless-stopped" : "",
      var.enable_cadvisor ? "    ports:" : "",
      var.enable_cadvisor ? "      - '8080:8080'" : "",
      var.enable_cadvisor ? "    volumes:" : "",
      var.enable_cadvisor ? "      - /:/rootfs:ro" : "",
      var.enable_cadvisor ? "      - /var/run:/var/run:rw" : "",
      var.enable_cadvisor ? "      - /sys:/sys:ro" : "",
      var.enable_cadvisor ? "      - /var/lib/docker:/var/lib/docker:ro" : "",
      var.enable_cadvisor ? "    networks:" : "",
      var.enable_cadvisor ? "      - monitoring" : "",
      var.enable_cadvisor ? "" : "",
      var.enable_alertmanager ? "  alertmanager:" : "",
      var.enable_alertmanager ? "    image: prom/alertmanager:latest" : "",
      var.enable_alertmanager ? "    container_name: alertmanager" : "",
      var.enable_alertmanager ? "    restart: unless-stopped" : "",
      var.enable_alertmanager ? "    ports:" : "",
      var.enable_alertmanager ? "      - '${var.alertmanager_port}:9093'" : "",
      var.enable_alertmanager ? "    volumes:" : "",
      var.enable_alertmanager ? "      - ./alertmanager/config:/etc/alertmanager" : "",
      var.enable_alertmanager ? "      - alertmanager_data:/alertmanager" : "",
      var.enable_alertmanager ? "    networks:" : "",
      var.enable_alertmanager ? "      - monitoring" : "",
      "EOF"
    ]
  }

  # Start monitoring stack
  provisioner "remote-exec" {
    inline = [
      "cd /home/${var.cloud_user}/monitoring",
      "sudo docker compose up -d"
    ]
  }

  triggers = {
    prometheus_port   = var.prometheus_port
    grafana_port      = var.grafana_port
    alertmanager_port = var.alertmanager_port
    node_exporter     = var.enable_node_exporter
    cadvisor          = var.enable_cadvisor
    alertmanager      = var.enable_alertmanager
  }
}

# Outputs
output "monitoring_vm_ip" {
  description = "IP address of monitoring VM"
  value       = proxmox_vm_qemu.monitoring_vm.default_ipv4_address
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "http://${proxmox_vm_qemu.monitoring_vm.default_ipv4_address}:${var.grafana_port}"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${proxmox_vm_qemu.monitoring_vm.default_ipv4_address}:${var.prometheus_port}"
}

output "alertmanager_url" {
  description = "Alertmanager URL"
  value       = var.enable_alertmanager ? "http://${proxmox_vm_qemu.monitoring_vm.default_ipv4_address}:${var.alertmanager_port}" : "Alertmanager not enabled"
}

output "monitoring_vm_name" {
  description = "Name of monitoring VM"
  value       = proxmox_vm_qemu.monitoring_vm.name
}

output "monitoring_vm_id" {
  description = "VM ID of monitoring VM"
  value       = proxmox_vm_qemu.monitoring_vm.vmid
}
