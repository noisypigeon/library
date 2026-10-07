resource "grafana_folder" "this" {
  title = var.folder_title
}

resource "grafana_dashboard" "this" {
  for_each = var.dashboards

  folder      = grafana_folder.this.id
  config_json = each.value.config_json
}
