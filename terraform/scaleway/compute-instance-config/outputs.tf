output "cloud_init" {
  description = "The rendered cloud-init document, for scaleway_instance_server's user_data[\"cloud-init\"]. Sensitive: it interpolates every keyring secret and base64-embeds the self-delete credential."
  value       = local.cloud_init
  sensitive   = true

  # LIB-0043 §4: these were keyring's own validations until v1.1.0. They now
  # check each entry after keyring_wiring and keyring_secrets are merged in.
  precondition {
    condition = alltrue([for e in local.keyring : e.kind != "email" || (
      e.email != null && e.provider != null && e.host != null && e.port != null && e.secret != null
    )])
    error_message = "keyring email entries require email, provider, host, port and secret."
  }

  precondition {
    condition = alltrue([for e in local.keyring : e.kind != "bucket" || (
      e.endpoint != null && e.bucket != null && e.access_key_id != null && e.secret_key != null
    )])
    error_message = "keyring bucket entries require endpoint, bucket, access_key_id and secret_key."
  }

  precondition {
    condition     = length(setsubtract(concat(keys(var.keyring_wiring), keys(var.keyring_secrets)), local.keyring_aliases)) == 0
    error_message = "keyring_wiring and keyring_secrets may only name aliases that keyring has."
  }
}
