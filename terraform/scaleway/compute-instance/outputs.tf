output "id" {
  description = "Instance ID (null if enabled = false)"
  value       = try(scaleway_instance_server.server[0].id, null)
}

output "name" {
  description = "Computed instance name (null if enabled = false)"
  value       = try(scaleway_instance_server.server[0].name, null)
}

output "public_ips" {
  description = "Public IPs attached to the instance (null if enabled = false)"
  value       = try(scaleway_instance_server.server[0].public_ips, null)
}

output "private_ipv4" {
  description = "The instance's IPv4 address on its Private Network (null without one, or if enabled = false). private_ips is dual-stack, so the IPv6 one is filtered out."
  value       = try([for ip in scaleway_instance_private_nic.this[0].private_ips : ip.address if !strcontains(ip.address, ":")][0], null)
}
