resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  bucket_name = "${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"
}

resource "b2_bucket" "bucket" {
  bucket_name = local.bucket_name
  bucket_type = "allPrivate"
  bucket_info = var.description != null ? { description = var.description } : null
}
