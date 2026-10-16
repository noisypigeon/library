resource "random_string" "suffix" {
  count = var.exact_name == null ? 1 : 0

  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  bucket_name = var.exact_name != null ? var.exact_name : "${var.name_prefix}-${random_string.suffix[0].result}-${var.name_suffix}"
}

# Every bucket is in R2's eu jurisdiction, which Cloudflare enforces, unlike a
# location hint; there is deliberately no input for either (LIB-0006). The
# storage class defaults to Standard.
resource "cloudflare_r2_bucket" "this" {
  account_id    = var.account_id
  name          = local.bucket_name
  jurisdiction  = "eu"
  storage_class = var.storage_class
}
