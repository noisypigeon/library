variable "application_id" {
  type        = string
  description = "IAM application ID this key authenticates as"
}

variable "description" {
  type        = string
  description = "IAM API key description"
  default     = null
}

variable "expires_at" {
  type        = string
  description = "API key expiration timestamp (i.e. 2027-09-25T22:32:12Z). Defaults to 30 days after the key is first created."
  default     = null
}

variable "default_project_id" {
  type        = string
  description = "Default project ID to use for Object Storage operations with this key (defaults to the provider's own project when unset)"
  default     = null
}
