resource "scaleway_cockpit_source" "metrics" {
  count = var.enable_metrics ? 1 : 0

  project_id     = var.project_id
  name           = "${var.name}-metrics"
  type           = "metrics"
  retention_days = 31
}

resource "scaleway_cockpit_source" "logs" {
  count = var.enable_logs ? 1 : 0

  project_id     = var.project_id
  name           = "${var.name}-logs"
  type           = "logs"
  retention_days = 31
}

resource "scaleway_cockpit_token" "push" {
  project_id = var.project_id
  name       = "${var.name}-push"

  scopes {
    write_metrics = var.enable_metrics
    write_logs    = var.enable_logs
  }
}
