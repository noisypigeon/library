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
