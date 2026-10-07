# ADR-0122: compute-instance composes iam-policy/iam-api-key internally for
# this one pairing, so callers configure iam_config instead of wiring two
# separate module calls themselves. Pinned to released tags (not a relative
# path) per ADR-0121.
module "iam_policy" {
  count  = var.enabled && var.iam_config != null ? 1 : 0
  source = "https://pigeon.dev/modules/scaleway/iam-policy/v4.0.0"
  name   = "${var.name_prefix}-${var.name_suffix}-iam-policy"

  application_id = var.iam_config.application_id
  project_ids    = var.iam_config.project_ids
  # ADR-0138: self_delete_on_exit needs InstancesFullAccess to delete its own
  # server/IP/volume -- folded in automatically so callers don't need to know
  # the permission set name just to opt into self-deletion.
  project_permission_sets = distinct(concat(
    coalesce(var.iam_config.project_permission_sets, []),
    var.self_delete_on_exit ? ["InstancesFullAccess"] : []
  ))
}

module "iam_api_key" {
  count  = var.enabled && var.iam_config != null ? 1 : 0
  source = "https://pigeon.dev/modules/scaleway/iam-api-key/v0.1.0"

  application_id = var.iam_config.application_id
  description    = coalesce(var.iam_config.description, "${var.name_prefix}-${var.name_suffix} API key")
  expires_at     = var.iam_config.api_key_expires_at
}
