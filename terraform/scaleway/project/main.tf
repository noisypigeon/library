resource "scaleway_account_project" "project" {
  name            = var.name
  description     = var.description
  organization_id = var.organization_id
}

resource "scaleway_iam_ssh_key" "key" {
  count      = var.ssh_key != null ? 1 : 0
  name       = var.ssh_key.alias
  public_key = var.ssh_key.public_key
  project_id = scaleway_account_project.project.id
}
