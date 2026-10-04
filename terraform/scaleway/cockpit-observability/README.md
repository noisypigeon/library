# cockpit-observability

A Scaleway Cockpit (`scaleway_cockpit_source`/`scaleway_cockpit_token`) wrapper that
creates a metrics and/or logs source plus a shared push token, each individually
toggleable via `enable_metrics`/`enable_logs`.

## Usage

```hcl
module "cockpit" {
  source = "https://noisypigeon.com/modules/scaleway/cockpit-observability/v0.1.0"

  name       = "pigeon-cli"
  project_id = local.scaleway_project_id_noisypigeon
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_logs"></a> [enable\_logs](#input\_enable\_logs) | Create a logs source (write\_logs push-token scope follows this) | `bool` | `true` | no |
| <a name="input_enable_metrics"></a> [enable\_metrics](#input\_enable\_metrics) | Create a metrics source (write\_metrics push-token scope follows this) | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Cockpit source/token name prefix, e.g. "pigeon-cli" | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_logs_push_url"></a> [logs\_push\_url](#output\_logs\_push\_url) | Loki ingest endpoint (null if enable\_logs is false) |
| <a name="output_metrics_push_url"></a> [metrics\_push\_url](#output\_metrics\_push\_url) | Mimir ingest endpoint (null if enable\_metrics is false) |
| <a name="output_token_secret"></a> [token\_secret](#output\_token\_secret) | Push token secret |
<!-- END_TF_DOCS -->
