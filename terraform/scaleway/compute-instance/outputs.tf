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

output "ipv4_address" {
  description = "The instance's routed IPv4 address (null if enable_ipv4 or enabled = false)"
  value       = var.enabled && var.enable_ipv4 ? scaleway_instance_ip.ipv4[0].address : null
}

output "private_ips" {
  description = "Private IPs attached to the instance (null if enabled = false)"
  value       = try(scaleway_instance_server.server[0].private_ips, null)
}

output "access_key_id" {
  description = "IAM API key access key (null if iam_config not set)"
  value       = try(module.iam_api_key[0].access_key, null)
  sensitive   = true
}

output "secret_key" {
  description = "IAM API key secret key (null if iam_config not set)"
  value       = try(module.iam_api_key[0].secret_key, null)
  sensitive   = true
}
