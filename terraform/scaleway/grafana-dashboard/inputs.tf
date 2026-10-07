variable "folder_title" {
  type        = string
  description = "Title of the Grafana folder all dashboards are created in"
}

variable "dashboards" {
  type = map(object({
    config_json = string
  }))
  description = "Dashboards to create, keyed by a short stable name -- each config_json is a Grafana dashboard JSON model"
  default     = {}
}
