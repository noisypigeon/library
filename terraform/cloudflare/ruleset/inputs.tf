variable "zone" {
  type        = string
  description = "Apex domain of the zone the ruleset belongs to, looked up by name (LIB-0011, LIB-0030). Set this or zone_id, not both"
  default     = null
}

variable "zone_id" {
  type        = string
  description = "Cloudflare zone ID the ruleset belongs to. Set this or zone, not both"
  default     = null

  validation {
    condition     = (var.zone == null) != (var.zone_id == null)
    error_message = "Set exactly one of zone and zone_id."
  }
}

variable "name" {
  type        = string
  description = "Ruleset name"
}

variable "kind" {
  type        = string
  description = "Ruleset kind, e.g. \"zone\""
}

variable "phase" {
  type        = string
  description = "Ruleset phase, e.g. \"http_request_dynamic_redirect\""
}

variable "rules" {
  type        = any
  description = "The ruleset's rules, passed to the provider exactly as given (the cloudflare_ruleset rules schema)"
}

variable "description" {
  type        = string
  description = "Ruleset description. Null leaves it unset"
  default     = null
}
