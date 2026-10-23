variable "account_id" {
  type        = string
  description = "Cloudflare account the token belongs to, and the account its account policies grant"
}

variable "name" {
  type        = string
  description = "Token name"
}

variable "policies" {
  type = list(object({
    permission_groups = list(string)
    zones             = optional(list(string), [])
    all_zones         = optional(bool, false)
    account           = optional(bool, false)
    effect            = optional(string, "allow")
  }))
  description = "The token's policies. Each names its permission groups (e.g. \"DNS Write\") and exactly one resource: zones by apex domain, all_zones for every zone in the account, or account for the account itself"

  validation {
    condition = alltrue([
      for p in var.policies :
      (length(p.zones) > 0 ? 1 : 0) + (p.all_zones ? 1 : 0) + (p.account ? 1 : 0) == 1
    ])
    error_message = "Each policy needs exactly one of zones, all_zones or account."
  }

  validation {
    condition     = alltrue([for p in var.policies : contains(["allow", "deny"], p.effect) && length(p.permission_groups) > 0])
    error_message = "Each policy needs at least one permission group, and an effect of allow or deny."
  }
}

variable "expires_on" {
  type        = string
  description = "RFC 3339 expiry. Null means a week past the next rotation with rotation_days, or 365 days after creation without"
  default     = null
}

variable "rotation_days" {
  type        = number
  description = "Replace the token every this many days, create-before-destroy (LIB-0024 §4, LIB-0033 §3). Null never rotates"
  default     = null

  validation {
    condition     = var.rotation_days == null || try(var.rotation_days > 0, false)
    error_message = "rotation_days must be a positive number of days."
  }
}
