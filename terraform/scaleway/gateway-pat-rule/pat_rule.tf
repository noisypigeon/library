# LIB-0043: forwards a port on the gateway's IP to one instance on its Private
# Network. ADR-0146's bastion path, for any instance that sets sshViaGateway.
resource "scaleway_vpc_public_gateway_pat_rule" "this" {
  gateway_id   = var.gateway_id
  private_ip   = var.private_ip
  private_port = var.private_port
  public_port  = var.public_port
  protocol     = var.protocol
}

data "scaleway_vpc_public_gateway" "this" {
  public_gateway_id = var.gateway_id
}

data "scaleway_vpc_public_gateway_ip" "this" {
  ip_id = data.scaleway_vpc_public_gateway.this.ip_id
}
