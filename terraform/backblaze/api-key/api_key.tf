# With rotation_days, the key is replaced every rotation_days and expires a
# week after each scheduled rotation, as cloudflare/api-token's token does
# (LIB-0041 §1). B2 counts a key's validity from its creation, so that's
# rotation_days plus seven days.
resource "time_rotating" "key" {
  count         = var.rotation_days == null ? 0 : 1
  rotation_days = var.rotation_days
}

# replace_triggered_by can't name a resource that may have no instances, so the
# rotation is carried by one that always exists.
resource "terraform_data" "rotation" {
  input = try(time_rotating.key[0].id, "none")
}

resource "b2_application_key" "key" {
  key_name                  = var.key_name
  capabilities              = var.capabilities
  bucket_ids                = var.bucket_ids
  valid_duration_in_seconds = var.rotation_days == null ? var.valid_duration_in_seconds : (var.rotation_days + 7) * 86400

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.rotation]
  }
}
