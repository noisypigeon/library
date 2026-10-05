moved {
  from = random_string.suffix
  to   = random_string.suffix[0]
}

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

resource "scaleway_object_bucket" "bucket" {
  name          = local.bucket_name
  project_id    = var.project_id
  force_destroy = var.force_destroy

  versioning {
    enabled = var.enable_versioning
  }

  dynamic "lifecycle_rule" {
    for_each = var.storage_class == "glacier" ? [1] : []
    content {
      enabled = true

      transition {
        days          = 90
        storage_class = "GLACIER"
      }
    }
  }
}

resource "scaleway_object_bucket_acl" "bucket" {
  count = var.enable_public_read ? 1 : 0

  bucket     = scaleway_object_bucket.bucket.id
  project_id = var.project_id
  acl        = "public-read"
}

resource "scaleway_object_bucket_website_configuration" "bucket" {
  count = var.enable_website ? 1 : 0

  bucket     = scaleway_object_bucket.bucket.id
  project_id = var.project_id

  index_document {
    suffix = var.website_index_document
  }

  error_document {
    key = var.website_error_document
  }
}
