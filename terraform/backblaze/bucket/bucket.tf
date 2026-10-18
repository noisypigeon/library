resource "random_string" "suffix" {
  count = var.exact_name == null ? 1 : 0

  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# random_string.suffix gained count with exact_name; existing callers keep
# their suffix, and so their bucket name.
moved {
  from = random_string.suffix
  to   = random_string.suffix[0]
}

locals {
  bucket_name = var.exact_name != null ? var.exact_name : "${var.name_prefix}-${random_string.suffix[0].result}-${var.name_suffix}"
}

resource "b2_bucket" "bucket" {
  bucket_name = local.bucket_name
  bucket_type = "allPrivate"
  bucket_info = var.description != null ? { description = var.description } : null
}
