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
  input = md5(coalesce(var.cloud_init, ""))
}

resource "scaleway_instance_server" "server" {
  count = var.enabled ? 1 : 0

  name                  = "${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"
  image                 = var.image
  type                  = var.type
  ip_ids                = var.ip_ids
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
