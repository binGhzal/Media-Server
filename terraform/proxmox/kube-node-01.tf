resource "proxmox_vm_qemu" "kube-node-01" {

  # General Settings
  name = "kube-node-01"
  desc = "Ubuntu Server 25.04 Kube Node"
  agent = 1
  target_node = "pve"
  vmid = "1001"
  tags = ["ubuntu", "kube", "server"]

  # Template Settings
  clone = "ubuntu-server-25-04"
  full_clone = true

  # Boot Processing Settings
  onboot = true
  startup = ""
  automatic_reboot = true

  # Hardware Settings
  qemu_os = "other"
  bios = "seabios"

  # cpu Settings
  cpu {
    type = "host"
    cores = 2
    sockets = 1
  }

  # Memory Settings
  memory = 2048
  balloon = 2048

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
          storage = "bigdisk"
        }
      }
    }
    virtio {
      virtio0 {
        disk {
          storage = "bigdisk"
          size = "20G"
          iothread = true
          replicate = false
        }
      }
    }
  }

  # Cloud Init Settings
  ipconfig0 = "ip=dhcp,ip6=dhcp"
  nameserver = ""
  ciuser = "binghzal"
  cipassword = var.CLOUD_INIT_PASSWORD
  sshkeys = var.PUBLIC_SSH_KEY
}
