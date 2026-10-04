#
# Buckets follow a consistent naming scheme.
# Format: {name_prefix}-{random_code}-{name_suffix}
# I.e. example-com-q82q17-sample
#
variable "name_prefix" {
  type        = string
  description = "Bucket name prefix"
}

variable "name_suffix" {
  type        = string
  description = "Bucket name suffix"
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
