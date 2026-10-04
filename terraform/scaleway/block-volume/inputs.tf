#
# Block volumes follow the same naming scheme as object-bucket/
# compute-instance.
# Format: {name_prefix}-{random_code}-{name_suffix}
#
variable "name_prefix" {
  type        = string
  description = "Volume name prefix"
}

variable "name_suffix" {
  type        = string
  description = "Volume name suffix"
}

variable "size" {
  type        = number
  description = "Volume size, in GB"
}

variable "iops" {
  type        = number
  description = "Volume IOPS"
  default     = 15000
}

variable "project_id" {
  type        = string
  description = "Project ID"
}
