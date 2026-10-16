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

# A deliberately thin pass-through: beyond the family's bucket naming scheme,
# every argument goes to the provider as given, and null means "not set", never
# a default chosen here. It exists so a leaf that manages an R2 bucket calls a
# pigeon-lib module like every other leaf (LIB-0004), not to add behaviour.
resource "cloudflare_r2_bucket" "this" {
  account_id    = var.account_id
  name          = local.bucket_name
  location      = var.location
  jurisdiction  = var.jurisdiction
  storage_class = var.storage_class
}
