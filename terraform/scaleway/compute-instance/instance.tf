resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ADR-0153: launders var.cloud_init into a resource attribute so the server's
# replace_triggered_by can point at it -- lifecycle blocks can't reference a
# variable or local directly. The md5 keeps the stored value small, and keeps
# the rendered document (which carries keyring secrets and the self-delete
# credential) out of state in plaintext. Deliberately uncounted, like
# random_string.suffix above: both only hold a value, so leaving them alone
# across an enabled = false cycle keeps the instance's name stable (ADR-0126).
resource "terraform_data" "cloud_init" {
  input = md5(var.cloud_init == null ? "" : var.cloud_init)
}

resource "scaleway_instance_server" "server" {
  count = var.enabled ? 1 : 0

  name                  = "${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"
  project_id            = var.project_id
  image                 = var.image
  type                  = var.type
  ip_ids                = concat(var.ip_ids, scaleway_instance_ip.ipv4[*].id)
  tags                  = var.ssh_key != null ? ["AUTHORIZED_KEY=${replace(var.ssh_key, " ", "_")}"] : []
  additional_volume_ids = var.additional_volume_ids

  user_data = var.cloud_init == null ? {} : {
    cloud-init = var.cloud_init
  }

  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init.output]
  }
}

# ADR-0126: giving the server a kill switch moves it from a singleton
# resource to count = var.enabled ? 1 : 0, changing its address. This
# protects any existing state through that change for any caller.
moved {
  from = scaleway_instance_server.server
  to   = scaleway_instance_server.server[0]
}

# LIB-0043: the routed IPv4 comes back into this module, reversing ADR-0153 for
# it. One module can create an IP and the server that references it; the IP
# goes with the server, as self-delete already has it. Gated by public_ipv4
# only, so an enabled = false cycle keeps the address.
resource "scaleway_instance_ip" "ipv4" {
  count      = var.public_ipv4 ? 1 : 0
  type       = "routed_ipv4"
  project_id = var.project_id
}

# LIB-0043: the NIC comes back into this module too. A workload's instance is a
# leaf of its own, and a NIC in another leaf would attach a stage after the
# server booted, after a gateway-only cloud-init had already failed. Still a
# standalone resource, not an inline private_network block, so attaching or
# detaching never replaces the server (ADR-0145).
resource "scaleway_instance_private_nic" "this" {
  count = var.enabled && var.enable_private_network ? 1 : 0

  server_id          = scaleway_instance_server.server[0].id
  private_network_id = var.private_network_id
}
