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
