resource "time_static" "created" {}

resource "scaleway_iam_api_key" "api_key" {
  application_id = var.application_id
  description    = var.description
  expires_at     = coalesce(var.expires_at, timeadd(time_static.created.rfc3339, "720h"))
}
