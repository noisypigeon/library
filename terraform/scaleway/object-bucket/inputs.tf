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
  description = "Exact bucket name, bypassing the name_prefix/random-suffix/name_suffix scheme entirely — for buckets whose name must match something external (e.g. a custom domain for bucket-website hosting)"
  default     = null

  validation {
    condition = (
      (var.exact_name != null && var.name_prefix == null && var.name_suffix == null) ||
      (var.exact_name == null && var.name_prefix != null && var.name_suffix != null)
    )
    error_message = "Set either exact_name, or both name_prefix and name_suffix — not a mix of both naming schemes."
  }
}

variable "enable_versioning" {
  type        = bool
  description = "Object versioning enabled (true/false)"
  default     = false
}

variable "storage_class" {
  type        = string
  description = "Storage class for new objects (standard/glacier)"
  default     = "glacier"

  validation {
    condition     = contains(["standard", "glacier"], var.storage_class)
    error_message = "storage_class must be \"standard\" or \"glacier\"."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Boolean that, when set to true, allows the deletion of all objects (including locked objects) when the bucket is destroyed."
  default     = false
}

variable "project_id" {
  type        = string
  description = "Project ID the bucket belongs to (defaults to the provider's own project when unset)"
  default     = null
}

variable "enable_website" {
  type        = bool
  description = "Configure the bucket for static website hosting (scaleway_object_bucket_website_configuration)"
  default     = false
}

variable "website_index_document" {
  type        = string
  description = "Index document suffix for website hosting (only used when enable_website is true)"
  default     = "index.html"
}

variable "website_error_document" {
  type        = string
  description = "Error document key for website hosting (only used when enable_website is true)"
  default     = "404.html"
}

variable "enable_public_read" {
  type        = bool
  description = "Grant the bucket a public-read ACL (scaleway_object_bucket_acl)"
  default     = false
}
