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
  # ADR-0145 amendment: scaleway_instance_server's own private_ips attribute
  # does NOT reflect a NIC attached via the separate scaleway_instance_private_nic
  # resource -- confirmed by a real apply returning an empty list for it. It
  # only ever reflected the deprecated inline private_network block, which
  # this module has never used. The private NIC resource has its own,
  # separate private_ips block -- read from that first.
  description = "Private IPs attached to the instance (null if enabled = false or no private network attached)"
  value       = try(scaleway_instance_private_nic.private_nic[0].private_ips, scaleway_instance_server.server[0].private_ips, null)
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
