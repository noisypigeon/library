variable "name" {
  type        = string
  description = "Cockpit source/token name prefix, e.g. \"pigeon-cli\""
}

variable "project_id" {
  type        = string
  description = "Project ID"
}

variable "enable_metrics" {
  type        = bool
  description = "Create a metrics source (write_metrics push-token scope follows this)"
  default     = true
}

variable "enable_logs" {
  type        = bool
  description = "Create a logs source (write_logs push-token scope follows this)"
  default     = true
}
