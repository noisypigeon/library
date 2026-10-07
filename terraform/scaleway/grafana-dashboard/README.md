# grafana-dashboard

A `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder
and provisions a set of dashboards into it from JSON dashboard models. See
[ADR-0135](../../../../docs/adr/0135-grafana-dashboards-as-code.md) for why
a dedicated folder is required (Scaleway Cockpit's own preconfigured
dashboards live in a folder that is always read-only) and how the `grafana`
provider itself is authenticated against Cockpit (wired by the consuming
leaf, not this module).

## Usage

```hcl
module "grafana_dashboard" {
  source = "https://noisypigeon.com/modules/scaleway/grafana-dashboard/v0.1.0"

  folder_title = "pigeon-cli"
  dashboards = {
    overview = { config_json = file("${path.module}/dashboards/overview.json") }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_dashboards"></a> [dashboards](#input\_dashboards) | Dashboards to create, keyed by a short stable name -- each config\_json is a Grafana dashboard JSON model | `map(object({ config_json = string }))` | `{}` | no |
| <a name="input_folder_title"></a> [folder\_title](#input\_folder\_title) | Title of the Grafana folder all dashboards are created in | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dashboard_uids"></a> [dashboard\_uids](#output\_dashboard\_uids) | UIDs of the created dashboards, keyed the same as var.dashboards |
| <a name="output_folder_uid"></a> [folder\_uid](#output\_folder\_uid) | UID of the created Grafana folder |
<!-- END_TF_DOCS -->
