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

variable "description" {
  type        = string
  description = "Free-form description, stored in the bucket's bucket_info metadata"
  default     = null
}
