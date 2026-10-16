# grafana-dashboard

A `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder
and provisions a set of dashboards into it from JSON dashboard models. See
[ADR-0135](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0135-grafana-dashboards-as-code.md) for why
a dedicated folder is required (Scaleway Cockpit's own preconfigured
dashboards live in a folder that is always read-only) and how the `grafana`
provider itself is authenticated against Cockpit (wired by the consuming
leaf, not this module).

## Usage

```hcl
module "grafana_dashboard" {
  source = "https://pigeon.dev/modules/scaleway/grafana-dashboard/v0.2.0"

  folder_title = "pigeon-cli"
  dashboards = {
    # A pinned version from pigeon-lib's grafana-dashboards track...
    overview = { url = "https://raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/grafana-dashboards/pigeon-cli/v1.0.0/grafana-dashboards/pigeon-cli/overview.json" }
    # ...or an inline JSON model, as in v0.1.0.
    # local_one = { config_json = file("${path.module}/local.json") }
  }

  # Optional (v0.2.0): Scaleway's Grafana provisions an IAM identity's role
  # lazily on first API access, so ping it once, before anything is created.
  first_access = {
    grafana_url = data.scaleway_cockpit_grafana.grafana.grafana_url
    trigger     = local.iam_application_id # re-ping when the identity changes
  }
  first_access_auth_token = local.grafana_auth_token
}
```

Each dashboard gives exactly one of `config_json` or `url`. A `url` is fetched
at plan time with `hashicorp/http`, and a non-200 response fails the plan
rather than applying an error page as a dashboard. The `grafana` provider
itself is configured by the leaf: in a spoke, by `terragrunt/root-hcl`'s latent
Grafana provider (`grafana_config.hcl`).

Moving a leaf's own `terraform_data` first-access hook into this module is an
address change only:

```hcl
moved {
  from = terraform_data.grafana_first_access
  to   = module.grafana_dashboard.terraform_data.first_access[0]
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
