#
# Buckets follow a consistent naming scheme unless exact_name is set.
# Format: {name_prefix}-{random_code}-{name_suffix}
# I.e. example-com-q82q17-sample
#
variable "name_prefix" {
  type        = string
  description = "Bucket name prefix (ignored if exact_name is set)"
  default     = null
}

variable "name_suffix" {
  type        = string
  description = "Bucket name suffix (ignored if exact_name is set)"
  default     = null
}

variable "exact_name" {
  type        = string
  description = "Exact bucket name, bypassing the name_prefix/random-suffix/name_suffix scheme entirely — for buckets whose name must match something external"
  default     = null

  validation {
    condition = (
      (var.exact_name != null && var.name_prefix == null && var.name_suffix == null) ||
      (var.exact_name == null && var.name_prefix != null && var.name_suffix != null)
    )
    error_message = "Set either exact_name, or both name_prefix and name_suffix — not a mix of both naming schemes."
  }
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID the bucket belongs to (in a spoke leaf, local.cloudflare_account_id)"
}

variable "location" {
  type        = string
  description = "Location hint for the bucket (apac, eeur, enam, weur, wnam, oc). Null leaves it to Cloudflare"
  default     = null

  validation {
    condition     = var.location == null || contains(["apac", "eeur", "enam", "weur", "wnam", "oc"], var.location)
    error_message = "location must be one of apac, eeur, enam, weur, wnam, oc, or null."
  }
}

variable "jurisdiction" {
  type        = string
  description = "Jurisdiction the bucket's data is restricted to (default, eu, fedramp, us). Null leaves it unset"
  default     = null

  validation {
    condition     = var.jurisdiction == null || contains(["default", "eu", "fedramp", "us"], var.jurisdiction)
    error_message = "jurisdiction must be one of default, eu, fedramp, us, or null."
  }
}

variable "storage_class" {
  type        = string
  description = "Default storage class for new objects (Standard, InfrequentAccess). Null leaves it unset"
  default     = null

  validation {
    condition     = var.storage_class == null || contains(["Standard", "InfrequentAccess"], var.storage_class)
    error_message = "storage_class must be \"Standard\" or \"InfrequentAccess\", or null."
  }
}
