# Variables specific to Kubernetes workloads
variable "k8s_master_count" {
  description = "Number of Kubernetes master nodes"
  type        = number
  default     = 1
}

variable "k8s_worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 2
}

variable "k8s_vm_name_prefix" {
  description = "Prefix for Kubernetes VM names"
  type        = string
  default     = "k8s-"
}

variable "k8s_template_id" {
  description = "Template ID to clone for Kubernetes VMs"
  type        = string
}

variable "k8s_master_cpu_cores" {
  description = "CPU cores for Kubernetes master nodes"
  type        = number
  default     = 4
}

variable "k8s_master_memory_mb" {
  description = "Memory in MB for Kubernetes master nodes"
  type        = number
  default     = 4096
}

variable "k8s_worker_cpu_cores" {
  description = "CPU cores for Kubernetes worker nodes"
  type        = number
  default     = 2
}

variable "k8s_worker_memory_mb" {
  description = "Memory in MB for Kubernetes worker nodes"
  type        = number
  default     = 2048
}

variable "k8s_disk_size" {
  description = "Disk size for Kubernetes VMs"
  type        = string
  default     = "40G"
}

variable "k8s_pod_subnet" {
  description = "Pod subnet CIDR for Kubernetes"
  type        = string
  default     = "10.244.0.0/16"
}

variable "k8s_service_subnet" {
  description = "Service subnet CIDR for Kubernetes"
  type        = string
  default     = "10.96.0.0/12"
}

variable "k8s_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.28.2"
}

variable "k8s_cni" {
  description = "CNI plugin to use (flannel, calico, weave)"
  type        = string
  default     = "flannel"
}

variable "k8s_ingress_controller" {
  description = "Ingress controller to install (nginx, traefik, none)"
  type        = string
  default     = "nginx"
}

variable "k8s_cert_manager" {
  description = "Install cert-manager for SSL certificates"
  type        = bool
  default     = true
}

variable "k8s_monitoring" {
  description = "Install monitoring stack (prometheus, grafana)"
  type        = bool
  default     = false
}

# Kubernetes master nodes
resource "proxmox_vm_qemu" "k8s_master" {
  count       = var.k8s_master_count
  name        = "${var.k8s_vm_name_prefix}master-${count.index + 1}"
  target_node = var.pm_target_node
  clone       = var.k8s_template_id
  cores       = var.k8s_master_cpu_cores
  memory      = var.k8s_master_memory_mb
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  agent       = 1
  os_type     = "cloud-init"

  disk {
    size    = var.k8s_disk_size
    type    = "scsi"
    storage = var.storage
  }

  network {
    bridge = var.network_bridge
    model  = "virtio"
  }

  ciuser  = var.cloud_user
  sshkeys = file(var.ssh_key_path)

  # Cloud-init configuration for Kubernetes
  ciupgrade = true
  cicustom  = "user=local:snippets/k8s-cloud-init.yml"

  tags = "kubernetes,master"

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Kubernetes worker nodes
resource "proxmox_vm_qemu" "k8s_worker" {
  count       = var.k8s_worker_count
  name        = "${var.k8s_vm_name_prefix}worker-${count.index + 1}"
  target_node = var.pm_target_node
  clone       = var.k8s_template_id
  cores       = var.k8s_worker_cpu_cores
  memory      = var.k8s_worker_memory_mb
  sockets     = 1
  scsihw      = "virtio-scsi-pci"
  boot        = "order=scsi0"
  agent       = 1
  os_type     = "cloud-init"

  disk {
    size    = var.k8s_disk_size
    type    = "scsi"
    storage = var.storage
  }

  network {
    bridge = var.network_bridge
    model  = "virtio"
  }

  ciuser  = var.cloud_user
  sshkeys = file(var.ssh_key_path)

  # Cloud-init configuration for Kubernetes
  ciupgrade = true
  cicustom  = "user=local:snippets/k8s-cloud-init.yml"

  tags = "kubernetes,worker"

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Install Kubernetes on master nodes
resource "null_resource" "k8s_master_setup" {
  count = var.k8s_master_count

  depends_on = [proxmox_vm_qemu.k8s_master]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.k8s_master[count.index].default_ipv4_address
  }

  # Install container runtime and Kubernetes
  provisioner "remote-exec" {
    inline = [
      # Update system
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl",

      # Install containerd
      "sudo apt-get install -y containerd",
      "sudo mkdir -p /etc/containerd",
      "containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml",
      "sudo systemctl restart containerd",
      "sudo systemctl enable containerd",

      # Configure system for Kubernetes
      "echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee -a /etc/sysctl.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables = 1' | sudo tee -a /etc/sysctl.conf",
      "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl --system",
      "sudo modprobe br_netfilter",

      # Install kubeadm, kubelet, kubectl
      "curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      "sudo apt-get update",
      "sudo apt-get install -y kubelet=${var.k8s_version}-00 kubeadm=${var.k8s_version}-00 kubectl=${var.k8s_version}-00",
      "sudo apt-mark hold kubelet kubeadm kubectl"
    ]
  }

  # Initialize Kubernetes cluster (only on first master)
  provisioner "remote-exec" {
    inline = count.index == 0 ? [
      "sudo kubeadm init --pod-network-cidr=${var.k8s_pod_subnet} --service-cidr=${var.k8s_service_subnet}",
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config"
    ] : []
  }

  # Install CNI plugin (only on first master)
  provisioner "remote-exec" {
    inline = count.index == 0 ? (
      var.k8s_cni == "flannel" ? [
        "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
        ] : var.k8s_cni == "calico" ? [
        "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
        ] : var.k8s_cni == "weave" ? [
        "kubectl apply -f https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\\n')"
      ] : []
    ) : []
  }

  triggers = {
    master_ip = proxmox_vm_qemu.k8s_master[count.index].default_ipv4_address
  }
}

# Get join token for worker nodes
resource "null_resource" "k8s_join_token" {
  depends_on = [null_resource.k8s_master_setup]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.k8s_master[0].default_ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "kubeadm token create --print-join-command > /tmp/join-command.sh"
    ]
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ${replace(var.ssh_key_path, ".pub", "")} ${var.cloud_user}@${proxmox_vm_qemu.k8s_master[0].default_ipv4_address}:/tmp/join-command.sh /tmp/k8s-join-command.sh"
  }
}

# Join worker nodes to cluster
resource "null_resource" "k8s_worker_join" {
  count = var.k8s_worker_count

  depends_on = [proxmox_vm_qemu.k8s_worker, null_resource.k8s_join_token]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.k8s_worker[count.index].default_ipv4_address
  }

  # Install container runtime and Kubernetes
  provisioner "remote-exec" {
    inline = [
      # Update system
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl",

      # Install containerd
      "sudo apt-get install -y containerd",
      "sudo mkdir -p /etc/containerd",
      "containerd config default | sudo tee /etc/containerd/config.toml",
      "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml",
      "sudo systemctl restart containerd",
      "sudo systemctl enable containerd",

      # Configure system for Kubernetes
      "echo 'net.bridge.bridge-nf-call-iptables = 1' | sudo tee -a /etc/sysctl.conf",
      "echo 'net.bridge.bridge-nf-call-ip6tables = 1' | sudo tee -a /etc/sysctl.conf",
      "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl --system",
      "sudo modprobe br_netfilter",

      # Install kubeadm, kubelet, kubectl
      "curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      "sudo apt-get update",
      "sudo apt-get install -y kubelet=${var.k8s_version}-00 kubeadm=${var.k8s_version}-00 kubectl=${var.k8s_version}-00",
      "sudo apt-mark hold kubelet kubeadm kubectl"
    ]
  }

  # Join cluster
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ${replace(var.ssh_key_path, ".pub", "")} /tmp/k8s-join-command.sh ${var.cloud_user}@${proxmox_vm_qemu.k8s_worker[count.index].default_ipv4_address}:/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/k8s-join-command.sh"
    ]
  }

  triggers = {
    worker_ip = proxmox_vm_qemu.k8s_worker[count.index].default_ipv4_address
  }
}

# Install additional components
resource "null_resource" "k8s_addons" {
  depends_on = [null_resource.k8s_worker_join]

  connection {
    type        = "ssh"
    user        = var.cloud_user
    private_key = file(replace(var.ssh_key_path, ".pub", ""))
    host        = proxmox_vm_qemu.k8s_master[0].default_ipv4_address
  }

  # Install ingress controller
  provisioner "remote-exec" {
    inline = var.k8s_ingress_controller == "nginx" ? [
      "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml"
      ] : var.k8s_ingress_controller == "traefik" ? [
      "kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml",
      "kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml"
    ] : []
  }

  # Install cert-manager
  provisioner "remote-exec" {
    inline = var.k8s_cert_manager ? [
      "kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml"
    ] : []
  }

  # Install monitoring stack
  provisioner "remote-exec" {
    inline = var.k8s_monitoring ? [
      "kubectl create namespace monitoring || true",
      "kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml"
    ] : []
  }

  triggers = {
    ingress_controller = var.k8s_ingress_controller
    cert_manager       = var.k8s_cert_manager
    monitoring         = var.k8s_monitoring
  }
}

# Outputs
output "k8s_master_ips" {
  description = "IP addresses of Kubernetes master nodes"
  value       = proxmox_vm_qemu.k8s_master[*].default_ipv4_address
}

output "k8s_worker_ips" {
  description = "IP addresses of Kubernetes worker nodes"
  value       = proxmox_vm_qemu.k8s_worker[*].default_ipv4_address
}

output "k8s_master_names" {
  description = "Names of Kubernetes master nodes"
  value       = proxmox_vm_qemu.k8s_master[*].name
}

output "k8s_worker_names" {
  description = "Names of Kubernetes worker nodes"
  value       = proxmox_vm_qemu.k8s_worker[*].name
}

output "k8s_cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = "https://${proxmox_vm_qemu.k8s_master[0].default_ipv4_address}:6443"
}

output "kubectl_config_command" {
  description = "Command to copy kubectl config"
  value       = "scp ${var.cloud_user}@${proxmox_vm_qemu.k8s_master[0].default_ipv4_address}:~/.kube/config ~/.kube/config"
}
