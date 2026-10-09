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

variable "description" {
  type        = string
  description = "Free-form description, stored in the bucket's bucket_info metadata"
  default     = null
}
