# LIB-0043: the gateway, its IP and its attachment are always one to one, and
# no other module wraps any of them, so they sit in one module. Lifted from
# compute-cluster, whose shared gateway this is.
resource "scaleway_vpc_public_gateway_ip" "this" {
  project_id = var.project_id
}

resource "scaleway_vpc_public_gateway" "this" {
  name       = var.name
  type       = var.type
  ip_id      = scaleway_vpc_public_gateway_ip.this.id
  project_id = var.project_id
}

# Neither enable_masquerade nor push_default_route defaults on in the
# provider, so both are set explicitly (ADR-0145).
resource "scaleway_vpc_gateway_network" "this" {
  gateway_id         = scaleway_vpc_public_gateway.this.id
  private_network_id = var.private_network_id
  enable_masquerade  = var.enable_masquerade

  ipam_config {
    push_default_route = var.push_default_route
  }
}
