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
<!-- END_TF_DOCS -->
