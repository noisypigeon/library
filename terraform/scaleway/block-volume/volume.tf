resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "scaleway_block_volume" "volume" {
  name       = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  size_in_gb = var.size
  iops       = var.iops
  project_id = var.project_id
}
