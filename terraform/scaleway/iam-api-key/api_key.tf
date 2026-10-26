resource "time_static" "created" {}

# With rotation_days (LIB-0038 §2, as LIB-0024 §4 gave the deployer), the key
# is replaced every rotation_days and expires a week after each scheduled
# rotation, so a month without a plan doesn't strand whoever signs in with it.
# The addresses are terraform-deployer-iam's, so a deployer's key moves here
# with its rotation timestamp.
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
  application_id = var.application_id
  description    = var.description
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
