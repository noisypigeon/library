variable "zone" {
  type        = string
  description = "Apex domain of the Cloudflare zone to redirect, e.g. \"example.com\". The zone ID is looked up from it"
}

variable "target_url" {
  type        = string
  description = "URL every redirected request goes to, e.g. \"https://example.org\". The path is not preserved"

  validation {
    condition     = can(regex("^https?://[^/]+", var.target_url))
    error_message = "target_url must be an absolute http:// or https:// URL."
  }
}

variable "status_code" {
  type        = number
  description = "HTTP status code of the redirect"
  default     = 301

  validation {
    condition     = contains([301, 302, 303, 307, 308], var.status_code)
    error_message = "status_code must be one of 301, 302, 303, 307 or 308."
  }
}

variable "include_www" {
  type        = bool
  description = "Whether the www subdomain is redirected too, with its own placeholder CNAME"
  default     = true
}

variable "preserve_query_string" {
  type        = bool
  description = "Whether the request's query string is appended to target_url"
  default     = false
}
