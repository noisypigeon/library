resource "scaleway_iam_application" "application" {
  name        = var.name
  description = var.description
}
