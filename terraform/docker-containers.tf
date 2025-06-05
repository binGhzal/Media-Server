# Variables specific to Docker workloads
variable "docker_vm_count" {
  description = "Number of Docker VMs to create"
  type        = number
  default     = 1
}

variable "docker_vm_name_prefix" {
  description = "Prefix for Docker VM names"
  type        = string
  default     = "docker-"
}

variable "docker_template_id" {
  description = "Template ID to clone for Docker VMs"
  type        = string
}

variable "docker_cpu_cores" {
  description = "CPU cores for Docker VMs"
  type        = number
  default     = 4
}

variable "docker_memory_mb" {
  description = "Memory in MB for Docker VMs"
  type        = number
  default     = 4096
}

variable "docker_disk_size" {
  description = "Disk size for Docker VMs"
  type        = string
  default     = "50G"
}

variable "docker_containers" {
  description = "List of Docker containers to deploy"
  type = list(object({
    name        = string
    image       = string
    ports       = list(string)
    volumes     = list(string)
    environment = map(string)
    restart     = string
  }))
  default = [
    {
      name        = "nginx"
      image       = "nginx:latest"
      ports       = ["80:80", "443:443"]
      volumes     = ["/var/www:/usr/share/nginx/html:ro"]
      environment = {}
      restart     = "unless-stopped"
    }
  ]
}

variable "docker_network_name" {
  description = "Docker network name"
  type        = string
  default     = "homelab"
}

variable "docker_compose_file" {
  description = "Path to docker-compose.yml file (optional)"
  type        = string
  default     = ""
}

# Docker VM resources
resource "proxmox_vm_qemu" "docker_vm" {
  count       = var.docker_vm_count
  name        = "${var.docker_vm_name_prefix}${count.index + 1}"
  target_node = var.pm_target_node
  clone       = var.docker_template_id
  cores       = var.docker_cpu_cores
  memory      = var.docker_memory_mb
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  agent       = 1
  os_type     = "cloud-init"

  disk {
    size    = var.docker_disk_size
    type    = "scsi"
    storage = var.storage
  }

  network {
    bridge = var.network_bridge
    model  = "virtio"
  }

  ciuser  = var.cloud_user
  sshkeys = file(var.ssh_key_path)

  # Cloud-init configuration for Docker
  ciupgrade = true
  cicustom  = "user=local:snippets/docker-cloud-init.yml"

  tags = "docker,container"

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }

  # Connection for provisioning
  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = self.default_ipv4_address
  }

  # Install Docker and Docker Compose
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

  # Create Docker network
  provisioner "remote-exec" {
    inline = [
      "sudo docker network create ${var.docker_network_name} || true"
    ]
  }
}

# Deploy Docker containers
resource "null_resource" "docker_containers" {
  count = var.docker_vm_count

  depends_on = [proxmox_vm_qemu.docker_vm]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.docker_vm[count.index].default_ipv4_address
  }

  # Deploy containers using docker-compose if file provided
  provisioner "remote-exec" {
    inline = var.docker_compose_file != "" ? [
      "mkdir -p /home/${var.cloud_user}/docker",
      "cd /home/${var.cloud_user}/docker"
    ] : []
  }

  provisioner "file" {
    source      = var.docker_compose_file != "" ? var.docker_compose_file : "/dev/null"
    destination = var.docker_compose_file != "" ? "/home/${var.cloud_user}/docker/docker-compose.yml" : "/tmp/null"
    content     = var.docker_compose_file != "" ? null : ""
  }

  provisioner "remote-exec" {
    inline = var.docker_compose_file != "" ? [
      "cd /home/${var.cloud_user}/docker",
      "sudo docker compose up -d"
      ] : [
      # Deploy individual containers
      for container in var.docker_containers :
      "sudo docker run -d --name ${container.name} --network ${var.docker_network_name} --restart ${container.restart} ${join(" ", [for port in container.ports : "-p ${port}"])} ${join(" ", [for volume in container.volumes : "-v ${volume}"])} ${join(" ", [for key, value in container.environment : "-e ${key}=${value}"])} ${container.image}"
    ]
  }

  # Trigger redeployment when container configuration changes
  triggers = {
    container_config = jsonencode(var.docker_containers)
    compose_file     = var.docker_compose_file
  }
}

# Outputs
output "docker_vm_ips" {
  description = "IP addresses of Docker VMs"
  value       = proxmox_vm_qemu.docker_vm[*].default_ipv4_address
}

output "docker_vm_names" {
  description = "Names of Docker VMs"
  value       = proxmox_vm_qemu.docker_vm[*].name
}

output "docker_vm_ids" {
  description = "VM IDs of Docker VMs"
  value       = proxmox_vm_qemu.docker_vm[*].vmid
}
