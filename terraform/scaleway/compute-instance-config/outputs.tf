output "cloud_init" {
  description = "The rendered cloud-init document, for scaleway_instance_server's user_data[\"cloud-init\"]. Sensitive: it interpolates every keyring secret and base64-embeds the self-delete credential."
  value       = local.cloud_init
  sensitive   = true
}
