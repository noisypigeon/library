output "folder_uid" {
  description = "UID of the created Grafana folder"
  value       = grafana_folder.this.uid
}

output "dashboard_uids" {
  description = "UIDs of the created dashboards, keyed the same as var.dashboards"
  value       = { for k, v in grafana_dashboard.this : k => v.uid }
}
