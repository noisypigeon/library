variable "zone_id" {
  type        = string
  description = "Cloudflare zone ID the ruleset belongs to"
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
