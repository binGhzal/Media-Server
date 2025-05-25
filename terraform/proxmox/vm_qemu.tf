resource "proxmox_vm_qemu" "ubuntu" {

  # General Settings

  name = "ubuntu"
  desc = "Ubuntu VM created with Terraform"
  agent = 1  # <-- (Optional) Enable QEMU Guest Agent

  # FIXME Before deployment, set the correct target node name
  target_node = "pve"

  # FIXME Before deployment, set the desired VM ID (must be unique on the target node)
  vmid = "901"

  # Template Settings

  # FIXME Before deployment, set the correct template or VM name in the clone field
  #       or set full_clone to false, and remote "clone" to manage existing (imported) VMs
  clone = "cloudinit"
  full_clone = true

  # Boot Process

  onboot = true

  # NOTE Change startup, shutdown and auto reboot behavior
  startup = ""
  automatic_reboot = false

  # Hardware Settings
  qemu_os = "other"
  bios = "seabios"

  cpu {
    type = "host"
    cores = 2
    sockets = 1
  }

  memory = 2048
  # NOTE Minimum memory of the balloon device, set to 0 to disable ballooning
  balloon = 2048

  # Network Settings

  network {
    id     = 0  # NOTE Required since 3.x.x
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Disk Settings

  # NOTE Change the SCSI controller type, since Proxmox 7.3, virtio-scsi-single is the default one
  scsihw = "virtio-scsi-single"

  # NOTE New disk layout (changed in 3.x.x)
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

          # NOTE Since 3.x.x size change disk size will trigger a disk resize
          size = "20G"

          # NOTE Enable IOThread for better disk performance in virtio-scsi-single
          #      and enable disk replication
          iothread = true
          replicate = false
        }
      }
    }
  }

  # Cloud Init Settings

  # FIXME Before deployment, adjust according to your network configuration
  ipconfig0 = "ip=dhcp,ip6=dhcp"
  nameserver = ""
  ciuser = "binghzal"
  sshkeys = var.PUBLIC_SSH_KEY
}
