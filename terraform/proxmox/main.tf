resource "proxmox_vm_qemu" "kube-node" {

  # General Settings
  count = var.vm_count
  name  = "kube-node-${count.index + 1}"
  desc  = "Ubuntu Server Kube Node"
  agent = 1


  target_node = var.node_name
  vmid        = 2000 + count.index
  tags        = "kube"

  # Template Settings
  clone_id   = var.template_id
  full_clone = true

  # Boot Processing Settings
  onboot           = true
  startup          = ""
  automatic_reboot = true

  # Hardware Settings
  qemu_os = "l26"
  bios    = "seabios"

  # cpu Settings
  cpu {
    type    = "host"
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
  }

  # Memory Settings
  memory  = var.memory_size
  balloon = var.balloon_size

  # Network Settings
  network {
    id     = 0
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Disk Settings
  scsihw = "virtio-scsi-single"
  disks {
    ide {
      ide0 {
        cloudinit {
          storage = var.storage_pool
        }
      }
    }
    virtio {
      virtio0 {
        disk {
          storage   = var.storage_pool
          size      = var.disk_size
          iothread  = true
          replicate = false
        }
      }
    }
  }

  # Cloud Init Settings
  ipconfig0  = "ip=dhcp,ip6=dhcp"
  nameserver = ""
  ciuser     = "binghzal"
  cipassword = var.cloud_init_password
  ciupgrade  = true
  sshkeys    = var.public_ssh_key
}
