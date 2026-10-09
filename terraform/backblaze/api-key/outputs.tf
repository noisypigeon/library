output "application_key_id" {
  description = "Application key ID"
  value       = b2_application_key.key.application_key_id
}

output "application_key" {
  description = "Application key secret value"
  value       = b2_application_key.key.application_key
  sensitive   = true
}
