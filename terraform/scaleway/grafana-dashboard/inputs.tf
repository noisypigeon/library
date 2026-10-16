variable "folder_title" {
  type        = string
  description = "Title of the Grafana folder all dashboards are created in"
}

variable "dashboards" {
  type = map(object({
    config_json = optional(string)
    url         = optional(string)
  }))
  description = "Dashboards to create, keyed by a short stable name. Each gives exactly one of config_json (a Grafana dashboard JSON model) or url (fetched at plan time -- e.g. a pinned grafana-dashboards/<set>/vX.Y.Z raw URL in pigeon-lib)"
  default     = {}

  validation {
    condition     = alltrue([for d in values(var.dashboards) : (d.config_json == null) != (d.url == null)])
    error_message = "Each dashboard must set exactly one of config_json or url."
  }
}

variable "first_access" {
  type = object({
    grafana_url = string
    trigger     = string
  })
  description = "Optional: ping grafana_url/api/org once before creating anything, which Scaleway's Grafana needs to provision an IAM identity's role on first use (ADR-0135). Re-runs when trigger changes -- pass the IAM application ID. Requires first_access_auth_token"
  default     = null
}

variable "first_access_auth_token" {
  type        = string
  description = "The API key secret first_access authenticates with (X-Auth-Token)"
  default     = null
  sensitive   = true
}
