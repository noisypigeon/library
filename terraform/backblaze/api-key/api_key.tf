resource "b2_application_key" "key" {
  key_name                  = var.key_name
  capabilities              = var.capabilities
  bucket_ids                = var.bucket_ids
  valid_duration_in_seconds = var.valid_duration_in_seconds
}
