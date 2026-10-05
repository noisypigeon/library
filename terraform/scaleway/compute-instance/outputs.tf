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
