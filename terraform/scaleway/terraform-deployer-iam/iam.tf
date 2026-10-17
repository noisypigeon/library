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

resource "scaleway_iam_api_key" "api_key" {
  application_id     = scaleway_iam_application.application.id
  description        = var.api_key_description
  expires_at         = coalesce(var.expires_at, timeadd(time_static.created.rfc3339, "720h"))
  default_project_id = var.default_project_id
}
