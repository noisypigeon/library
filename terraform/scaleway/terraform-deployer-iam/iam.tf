resource "scaleway_iam_application" "application" {
  name        = var.name
  description = var.description
}

resource "scaleway_iam_policy" "policy" {
  count = (
    (var.organization_id != null && length(coalesce(var.organization_permission_sets, [])) > 0) ||
    (var.project_ids != null && length(coalesce(var.project_permission_sets, [])) > 0)
  ) ? 1 : 0

  name           = coalesce(var.policy_name, "${var.name}-policy")
  description    = var.description
  application_id = scaleway_iam_application.application.id

  dynamic "rule" {
    for_each = (var.organization_id != null && length(coalesce(var.organization_permission_sets, [])) > 0) ? [1] : []
    content {
      organization_id      = var.organization_id
      permission_set_names = var.organization_permission_sets
    }
  }

  dynamic "rule" {
    for_each = (var.project_ids != null && length(coalesce(var.project_permission_sets, [])) > 0) ? [1] : []
    content {
      project_ids          = var.project_ids
      permission_set_names = var.project_permission_sets
    }
  }
}

resource "time_static" "created" {}

# With rotation_days (LIB-0024 §4), the key is replaced every rotation_days and
# expires a week after each scheduled rotation, so a month without a plan
# doesn't strand whoever signs in with it.
resource "time_rotating" "key" {
  count         = var.rotation_days == null ? 0 : 1
  rotation_days = var.rotation_days
}

# replace_triggered_by can't name a resource that may have no instances, so the
# rotation is carried by one that always exists. Its input changes, and so
# triggers the key's replacement, only when time_rotating rotates.
resource "terraform_data" "rotation" {
  input = try(time_rotating.key[0].id, "none")
}

resource "scaleway_iam_api_key" "api_key" {
  application_id = scaleway_iam_application.application.id
  description    = var.api_key_description
  expires_at = coalesce(
    var.expires_at,
    var.rotation_days == null ? timeadd(time_static.created.rfc3339, "720h") : timeadd(time_rotating.key[0].rotation_rfc3339, "168h"),
  )
  default_project_id = var.default_project_id

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.rotation]
  }
}
