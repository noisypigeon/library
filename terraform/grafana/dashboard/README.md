# dashboard

A `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder
and provisions a set of dashboards into it from JSON dashboard models. See
[ADR-0135](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0135-grafana-dashboards-as-code.md) for why
a dedicated folder is required (Scaleway Cockpit's own preconfigured
dashboards live in a folder that is always read-only) and how the `grafana`
provider itself is authenticated against Cockpit (wired by the consuming
leaf, not this module).

Released as `scaleway/grafana-dashboard` up to v0.2.0. It uses only the
`grafana` provider, so it moved to `grafana/dashboard` and restarted its tag
track at v0.1.0, with the same inputs, outputs and resource addresses as
`scaleway/grafana-dashboard` v0.2.0. The old short URLs keep resolving.

## Usage

```hcl
module "grafana_dashboard" {
  source = "https://pigeon.dev/modules/grafana/dashboard/v0.1.0"

  folder_title = "pigeon-cli"
  dashboards = {
    # A pinned version from pigeon-lib's grafana-dashboards track...
    overview = { url = "https://raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/grafana-dashboards/pigeon-cli/v1.0.0/grafana-dashboards/pigeon-cli/overview.json" }
    # ...or an inline JSON model.
    # local_one = { config_json = file("${path.module}/local.json") }
  }

  # Optional: Scaleway's Grafana provisions an IAM identity's role
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
itself is configured by the leaf: in a spoke, by `terragrunt/root-hcl`'s
Grafana provider, which the spoke turns on for this module's leaves in
`spoke.hcl` (LIB-0005).

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
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_dashboards"></a> [dashboards](#input\_dashboards) | Dashboards to create, keyed by a short stable name. Each gives exactly one of config\_json (a Grafana dashboard JSON model) or url (fetched at plan time -- e.g. a pinned grafana-dashboards/<set>/vX.Y.Z raw URL in pigeon-lib) | <pre>map(object({<br/>    config_json = optional(string)<br/>    url         = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_first_access"></a> [first\_access](#input\_first\_access) | Optional: ping grafana\_url/api/org once before creating anything, which Scaleway's Grafana needs to provision an IAM identity's role on first use (ADR-0135). Re-runs when trigger changes -- pass the IAM application ID. Requires first\_access\_auth\_token | <pre>object({<br/>    grafana_url = string<br/>    trigger     = string<br/>  })</pre> | `null` | no |
| <a name="input_first_access_auth_token"></a> [first\_access\_auth\_token](#input\_first\_access\_auth\_token) | The API key secret first\_access authenticates with (X-Auth-Token) | `string` | `null` | no |
| <a name="input_folder_title"></a> [folder\_title](#input\_folder\_title) | Title of the Grafana folder all dashboards are created in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dashboard_uids"></a> [dashboard\_uids](#output\_dashboard\_uids) | UIDs of the created dashboards, keyed the same as var.dashboards |
| <a name="output_folder_uid"></a> [folder\_uid](#output\_folder\_uid) | UID of the created Grafana folder |
<!-- END_TF_DOCS -->
