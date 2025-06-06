# Proxmox User Example
resource "proxmox_user" "example" {
  userid   = "terraform@pve"
  password = "example-password"
  groups   = ["PVEAdmin"]
  comment  = "Terraform managed user"
}
