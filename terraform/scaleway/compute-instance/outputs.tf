output "id" {
  description = "Instance ID"
  value       = scaleway_instance_server.server.id
}

output "name" {
  description = "Computed instance name"
  value       = scaleway_instance_server.server.name
}

output "public_ips" {
  description = "Public IPs attached to the instance"
  value       = scaleway_instance_server.server.public_ips
}

output "ipv4_address" {
  description = "The instance's routed IPv4 address (null if enable_ipv4 = false)"
  value       = var.enable_ipv4 ? scaleway_instance_ip.ipv4[0].address : null
}

output "private_ips" {
  description = "Private IPs attached to the instance"
  value       = scaleway_instance_server.server.private_ips
}
