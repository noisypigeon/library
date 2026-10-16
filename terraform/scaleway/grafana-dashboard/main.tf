data "http" "dashboard" {
  for_each = { for k, d in var.dashboards : k => d if d.url != null }

  url = each.value.url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Fetching dashboard ${each.key} returned HTTP ${self.status_code}."
    }
  }
}

locals {
  config_json = {
    for k, d in var.dashboards : k => d.url != null ? data.http.dashboard[k].response_body : d.config_json
  }
}

# Scaleway's Grafana lazily provisions an IAM identity's role on its first API
# access, and there is no resource for that (ADR-0135), so this pings the org
# endpoint once per trigger (the IAM application), before any folder or
# dashboard is created against it.
resource "terraform_data" "first_access" {
  count = var.first_access == null ? 0 : 1

  input = var.first_access_auth_token

  triggers_replace = {
    application_id = var.first_access.trigger
  }

  provisioner "local-exec" {
    command = "curl -sf -H \"X-Auth-Token: ${self.input}\" \"${var.first_access.grafana_url}/api/org\" >/dev/null"
  }
}

resource "grafana_folder" "this" {
  title = var.folder_title

  depends_on = [terraform_data.first_access]
}

resource "grafana_dashboard" "this" {
  for_each = var.dashboards

  folder      = grafana_folder.this.id
  config_json = local.config_json[each.key]
}
