variable "name" {
  type        = string
  description = "IAM policy name"

  validation {
    condition = var.name != "" && (
      (var.organization_id != null && length(coalesce(var.organization_permission_sets, [])) > 0) ||
      (var.project_ids != null && length(coalesce(var.project_permission_sets, [])) > 0)
    )
    error_message = "name must be non-empty, and at least one of organization_id+organization_permission_sets or project_ids+project_permission_sets must be fully set."
  }
}

variable "application_id" {
  type        = string
  description = "IAM application ID this policy is attached to"
}

variable "description" {
  type        = string
  description = "IAM policy description"
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
