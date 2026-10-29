output "id" {
  description = "Public Gateway ID"
  value       = scaleway_vpc_public_gateway.this.id
}

output "ip_address" {
  description = "The gateway's public IPv4 address"
  value       = scaleway_vpc_public_gateway_ip.this.address
}

output "gateway_network_id" {
  description = "ID of the gateway's attachment to the Private Network"
  value       = scaleway_vpc_gateway_network.this.id
}
