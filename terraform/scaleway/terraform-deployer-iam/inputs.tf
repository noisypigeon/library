variable "name" {
  type        = string
  description = "IAM application name"

  validation {
    condition = var.name != "" && (
      (var.organization_id != null && length(coalesce(var.organization_permission_sets, [])) > 0) ||
      (var.project_ids != null && length(coalesce(var.project_permission_sets, [])) > 0)
    )
    error_message = "name must be non-empty, and at least one of organization_id+organization_permission_sets or project_ids+project_permission_sets must be fully set."
  }
}

variable "policy_name" {
  type        = string
  description = "IAM policy name, used exactly as given (defaults to \"<name>-policy\")"
  default     = null
}

variable "description" {
  type        = string
  description = "Description for the IAM application and its policy"
  default     = null
}

variable "organization_id" {
  type        = string
  description = "Organization id"
  default     = null
}

variable "organization_permission_sets" {
  type        = list(string)
  description = "Organization permission set grants"
  default     = null
}

variable "project_ids" {
  type        = list(string)
  description = "Project ids"
  default     = null
}

variable "project_permission_sets" {
  type        = list(string)
  description = "Project permission set grants"
  default     = null
}

variable "default_project_id" {
  type        = string
  description = "Default project ID to use for Object Storage operations with the API key (defaults to the provider's own project when unset)"
  default     = null
}

variable "expires_at" {
  type        = string
  description = "API key expiration timestamp (i.e. 2027-09-25T22:32:12Z). Defaults to 30 days after the key is first created."
  default     = null
}

variable "api_key_description" {
  type        = string
  description = "IAM API key description"
  default     = null
}

variable "rotation_days" {
  type        = number
  description = "Replace the API key every this many days, expiring it a week after each scheduled rotation (LIB-0024). Unset, the key expires 30 days after it was first created and is never replaced."
  default     = null

  validation {
    condition     = var.rotation_days == null || try(var.rotation_days > 0, false)
    error_message = "rotation_days must be a positive number of days."
  }
}
