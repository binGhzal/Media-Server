# Variables specific to container registry
variable "registry_vm_name" {
  description = "Name for the container registry VM"
  type        = string
  default     = "container-registry"
}

variable "registry_template_id" {
  description = "Template ID to clone for registry VM"
  type        = string
}

variable "registry_cpu_cores" {
  description = "CPU cores for registry VM"
  type        = number
  default     = 2
}

variable "registry_memory_mb" {
  description = "Memory in MB for registry VM"
  type        = number
  default     = 2048
}

variable "registry_disk_size" {
  description = "Disk size for registry VM"
  type        = string
  default     = "100G"
}

variable "registry_port" {
  description = "Port for container registry"
  type        = number
  default     = 5000
}

variable "registry_ssl_enabled" {
  description = "Enable SSL for registry"
  type        = bool
  default     = true
}

variable "registry_auth_enabled" {
  description = "Enable authentication for registry"
  type        = bool
  default     = true
}

variable "registry_storage_path" {
  description = "Storage path for registry data"
  type        = string
  default     = "/opt/registry"
}

variable "registry_users" {
  description = "Registry users (username:password)"
  type        = list(string)
  default     = ["admin:admin123"]
}

# Container registry VM
resource "proxmox_vm_qemu" "registry_vm" {
  name        = var.registry_vm_name
  target_node = var.pm_target_node
  clone       = var.registry_template_id
  cores       = var.registry_cpu_cores
  memory      = var.registry_memory_mb
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  agent       = 1
  os_type     = "cloud-init"

  disk {
    size    = var.registry_disk_size
    type    = "scsi"
    storage = var.storage
  }

  network {
    bridge = var.network_bridge
    model  = "virtio"
  }

  ciuser  = var.cloud_user
  sshkeys = file(var.ssh_key_path)

  tags = "registry,container"

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Install and configure container registry
resource "null_resource" "registry_setup" {
  depends_on = [proxmox_vm_qemu.registry_vm]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.registry_vm.default_ipv4_address
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

  # Create registry directories
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p ${var.registry_storage_path}/data",
      "sudo mkdir -p ${var.registry_storage_path}/auth",
      "sudo mkdir -p ${var.registry_storage_path}/certs",
      "sudo chown -R ${var.cloud_user}:${var.cloud_user} ${var.registry_storage_path}"
    ]
  }

  # Generate SSL certificates if enabled
  provisioner "remote-exec" {
    inline = var.registry_ssl_enabled ? [
      "sudo apt-get install -y openssl",
      "openssl req -newkey rsa:4096 -nodes -sha256 -keyout ${var.registry_storage_path}/certs/domain.key -x509 -days 365 -out ${var.registry_storage_path}/certs/domain.crt -subj '/C=US/ST=State/L=City/O=Organization/CN=${proxmox_vm_qemu.registry_vm.default_ipv4_address}'"
    ] : []
  }

  # Create authentication if enabled
  provisioner "remote-exec" {
    inline = var.registry_auth_enabled ? [
      "sudo apt-get install -y apache2-utils",
      "rm -f ${var.registry_storage_path}/auth/htpasswd"
    ] : []
  }

  # Add registry users
  provisioner "remote-exec" {
    inline = var.registry_auth_enabled ? [
      for user in var.registry_users :
      "htpasswd -Bbn ${split(":", user)[0]} ${split(":", user)[1]} | sudo tee -a ${var.registry_storage_path}/auth/htpasswd"
    ] : []
  }

  triggers = {
    registry_ip = proxmox_vm_qemu.registry_vm.default_ipv4_address
  }
}

# Deploy registry container
resource "null_resource" "registry_deploy" {
  depends_on = [null_resource.registry_setup]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.registry_vm.default_ipv4_address
  }

  # Create docker-compose file
  provisioner "remote-exec" {
    inline = [
      "cat > ${var.registry_storage_path}/docker-compose.yml << 'EOF'",
      "version: '3.8'",
      "services:",
      "  registry:",
      "    image: registry:2",
      "    container_name: registry",
      "    restart: unless-stopped",
      "    ports:",
      "      - \"${var.registry_port}:5000\"",
      "    environment:",
      "      - REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/var/lib/registry",
      var.registry_auth_enabled ? "      - REGISTRY_AUTH=htpasswd" : "",
      var.registry_auth_enabled ? "      - REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" : "",
      var.registry_auth_enabled ? "      - REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" : "",
      var.registry_ssl_enabled ? "      - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt" : "",
      var.registry_ssl_enabled ? "      - REGISTRY_HTTP_TLS_KEY=/certs/domain.key" : "",
      "    volumes:",
      "      - ./data:/var/lib/registry",
      var.registry_auth_enabled ? "      - ./auth:/auth" : "",
      var.registry_ssl_enabled ? "      - ./certs:/certs" : "",
      "EOF"
    ]
  }

  # Start registry
  provisioner "remote-exec" {
    inline = [
      "cd ${var.registry_storage_path}",
      "sudo docker compose up -d"
    ]
  }

  # Configure Docker daemon to use insecure registry if SSL not enabled
  provisioner "remote-exec" {
    inline = var.registry_ssl_enabled ? [] : [
      "sudo mkdir -p /etc/docker",
      "echo '{\"insecure-registries\":[\"${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port}\"]}' | sudo tee /etc/docker/daemon.json",
      "sudo systemctl restart docker",
      "sleep 10",
      "cd ${var.registry_storage_path}",
      "sudo docker compose up -d"
    ]
  }

  triggers = {
    ssl_enabled  = var.registry_ssl_enabled
    auth_enabled = var.registry_auth_enabled
    users        = join(",", var.registry_users)
  }
}

# Test registry
resource "null_resource" "registry_test" {
  depends_on = [null_resource.registry_deploy]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.registry_vm.default_ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 30",
      "sudo docker pull hello-world",
      "sudo docker tag hello-world ${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port}/hello-world",
      var.registry_auth_enabled ? "echo '${split(":", var.registry_users[0])[1]}' | sudo docker login ${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port} -u ${split(":", var.registry_users[0])[0]} --password-stdin" : "",
      "sudo docker push ${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port}/hello-world",
      "sudo docker rmi ${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port}/hello-world",
      "sudo docker pull ${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port}/hello-world"
    ]
  }
}

# Outputs
output "registry_ip" {
  description = "IP address of container registry"
  value       = proxmox_vm_qemu.registry_vm.default_ipv4_address
}

output "registry_url" {
  description = "Container registry URL"
  value       = "${var.registry_ssl_enabled ? "https" : "http"}://${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port}"
}

output "registry_vm_name" {
  description = "Name of registry VM"
  value       = proxmox_vm_qemu.registry_vm.name
}

output "registry_vm_id" {
  description = "VM ID of registry VM"
  value       = proxmox_vm_qemu.registry_vm.vmid
}

output "registry_login_command" {
  description = "Command to login to registry"
  value       = var.registry_auth_enabled ? "docker login ${proxmox_vm_qemu.registry_vm.default_ipv4_address}:${var.registry_port} -u ${split(":", var.registry_users[0])[0]}" : "# No authentication required"
}
