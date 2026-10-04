#
# Block volumes follow the same namespaced naming scheme as object-bucket/
# compute-instance.
# Format: {namespace}-{random_code}-{name}
#
variable "namespace" {
  type        = string
  description = "Volume name prefix"
}

variable "name" {
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
