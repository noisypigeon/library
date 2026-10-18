# DEV-0135: Grafana dashboards as code via Scaleway Cockpit

- Status: Accepted
- Date: 2026-10-06
- Author: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).

## Context

Every `pigeon-cli` compute instance already pushes metrics and logs into a shared Scaleway Cockpit store (`workloads/willowgraysen.com/terraform/pigeon-cli/shared/cockpit/`, ADR-0102/0103, relocated by ADR-0115/0124/0133), and Cockpit gives every Scaleway project a managed Grafana instance to view that data. But nothing in this repo manages the *Grafana* side as code — any dashboard has to be hand-built in the Cockpit-hosted Grafana UI, unreviewed and unreproducible. ADR-0102 explicitly flagged "a way to actually log into the resulting Grafana" as deferred to a follow-up; it was never picked up.

The login path has moved since ADR-0102. `scaleway_cockpit_grafana_user` — the resource that used to mint a basic-auth Grafana login (`login`/`role`/computed `password`) — is gone: its backing API (`CreateGrafanaUser`) was disabled 2025-11-03 and hit full EOL 2026-01-20, and the resource itself was removed from the `scaleway/scaleway` provider in v2.84.0. There is also no `scaleway_cockpit_token` scope for Grafana — that resource's scopes (`query_metrics`, `write_logs`, `setup_alerts`, etc.) are purely for the underlying Prometheus/Loki/Tempo query-and-write and ruler APIs, never accepted as Grafana auth.

The only currently supported way in is **IAM-proxied auth**:

- `data "scaleway_cockpit_grafana"` (provider v2.63.0+) returns a project's Grafana URL (`https://<project_id>.dashboard.cockpit.scaleway.com`).
- The generic `grafana/grafana` Terraform provider (which works against any Grafana HTTP API, not just Grafana Cloud) authenticates against it by sending a Scaleway IAM secret key as an `X-Auth-Token` HTTP header, via the provider's `http_headers` attribute. Its own `auth` field is set to the literal `"anonymous"` only because the schema requires some value there — the real authentication happens at Scaleway's reverse proxy in front of Grafana, which maps `X-Auth-Token` to an IAM identity.
- That identity's Grafana role (Admin/Editor/Viewer) is derived entirely from its Scaleway IAM permission set — `ObservabilityFullAccess`, `ObservabilityGrafanaEditor`, or `ObservabilityReadOnly` — not from anything Terraform sets on the Grafana side directly.
- Scaleway's Grafana requires a one-time "first access" lazy-provisioning call per IAM identity (documented as `GET {grafana_url}/api/org` with the `X-Auth-Token` header, or simply logging in once) before that identity has a usable Grafana role at all. There is no Terraform resource for this yet — an upstream PR adding a `scaleway_cockpit_activate_grafana` action exists but is open and unmerged.
- Scaleway's preconfigured dashboards live in a folder that is always read-only, so Terraform-managed dashboards need their own folder.
- Scaleway explicitly does not support Grafana-native alerting against Cockpit: Grafana's own Unified Alerting resources (`grafana_rule_group`, `grafana_contact_point`, `grafana_notification_policy`, `grafana_mute_timing`) do not work there. Only Scaleway's own Cockpit Alertmanager (`scaleway_cockpit_alert_manager` + `scaleway_cockpit_preconfigured_alert`) or datasource-managed (Prometheus/Loki ruler) rules are supported.

Given the alerting restriction, this ADR scopes itself to dashboards only; Cockpit-Alertmanager-based alerting is deferred to a follow-up (see Out of scope).

## Decision

### A dedicated Grafana-scoped IAM identity

Rather than reusing the workload's own Terraform deployer credential (which already carries broad `ObservabilityFullAccess`, `InstancesFullAccess`, `ObjectStorageFullAccess`, etc. per ADR-0133), a new IAM application/policy/API key is minted specifically for Grafana, scoped only to `ObservabilityGrafanaEditor` on the `willowgraysen-com` project. This keeps Grafana access narrowly scoped and its credential lifecycle independent of the main deployer identity, composed from the existing `iam-application`/`iam-policy`/`iam-api-key` modules (ADR-0119) exactly as `workloads/willowgraysen.com/terraform/state/iam/iam.tf` composes the deployer's own identity — no raw `scaleway_iam_*` resources written by hand.

### IAM-proxied Grafana auth, wired directly in the leaf

The new leaf, `workloads/willowgraysen.com/terraform/pigeon-cli/shared/grafana/`, declares the `grafana` provider itself:

```hcl
data "scaleway_cockpit_grafana" "this" {
  project_id = local.scaleway_project_id
}

provider "grafana" {
  url  = data.scaleway_cockpit_grafana.this.grafana_url
  auth = "anonymous"

  http_headers = {
    "X-Auth-Token" = module.iam_api_key.secret_key
  }
}
```

This is the repo's first use of the `grafana` provider. The `provider "grafana" { ... }` *configuration* block above is leaf-local — unlike `scaleway`/`cloudflare`, `grafana` has exactly one consumer so far, and nothing else in this workload needs its IAM-proxied credential wired in. Its `required_providers` *declaration*, however, could not stay leaf-local: Terraform allows only one `required_providers` block per module, and `workloads/willowgraysen.com/root.hcl`'s `generate "provider"` block already generates one (for `cloudflare`/`scaleway`) into every leaf under this workload — a second one in the leaf's own `.tf` files fails `terraform init` with "Duplicate required providers configuration" (confirmed live, via this leaf's first real CI plan run). So `grafana`'s entry joins that same generated block instead, inert for every other leaf that doesn't configure it.

### First-access bootstrap via `local-exec`

Since no Terraform resource exists yet for Grafana's per-identity first-access provisioning, the leaf automates it with an idempotent provisioner instead of a manual step:

```hcl
resource "terraform_data" "grafana_first_access" {
  input = module.iam_api_key.secret_key

  triggers_replace = {
    application_id = module.iam_application.id
  }

  provisioner "local-exec" {
    command = "curl -sf -H \"X-Auth-Token: ${self.input}\" \"${data.scaleway_cockpit_grafana.this.grafana_url}/api/org\" >/dev/null"
  }
}
```

It re-runs only when the IAM application itself is replaced (keyed on `module.iam_application.id`, not the rotating API key) — the thing being lazily provisioned is the application's Grafana presence, which is stable across key rotations. `module.grafana_dashboard` depends on it so dashboards are never created against an identity that hasn't been provisioned into Grafana yet. This is the repo's first use of a Terraform provisioner.

### New module: `templates/terraform/scaleway/grafana-dashboard`

Following this repo's convention of giving every new resource grouping its own versioned module regardless of initial consumer count (`cockpit-observability`, `iam-application`, etc. all started with exactly one caller), a new module wraps the generic `grafana_folder`/`grafana_dashboard` resources:

```hcl
resource "grafana_folder" "this" {
  title = var.folder_title
}

resource "grafana_dashboard" "this" {
  for_each    = var.dashboards
  folder      = grafana_folder.this.id
  config_json = each.value.config_json
}
```

`dashboards` is a `map(object({ config_json = string }))` keyed by a short stable name, not a list, so adding or removing one dashboard doesn't reindex every other dashboard's resource address. Dashboard JSON itself is authored as committed `.json` files in the consuming leaf (Grafana's own export format), kept out of `.tf` source and easy to diff. Like every other module under `templates/terraform/`, it declares `required_providers` in its own `versions.tf` and configures no provider itself — the leaf does that, per above.

A separate `grafana_folder` is required because Scaleway's own preconfigured dashboards live in a folder that is always read-only; Terraform-managed dashboards need a folder of their own.

## Consequences

- First repo use of the `grafana` Terraform provider and of a Terraform provisioner (`local-exec`).
- `templates/terraform/scaleway/grafana-dashboard` ships at `v0.1.0`; its introducing PR needs a `release:minor` label (any PR touching `templates/terraform/<provider>/<module>/` does, per the `release-pr` skill) even though a brand-new module lands at `v0.1.0` regardless of label, per the established empty-tag fallback (ADR-0113).
- The dedicated Grafana IAM API key inherits `iam-api-key`'s standard 30-day-from-creation expiry (no `expires_at` override) — this leaf needs a periodic `terragrunt apply` to keep Grafana access and dashboard provisioning working, same operational reality already accepted by every other `iam-api-key` consumer in this repo, not a new problem introduced here.
- Dashboard content becomes reviewable, diffable, and reproducible instead of living only in the Grafana UI's own database.
- Alerting is not addressed by this change; see Out of scope.

## Out of scope

- Alerts-as-code via Scaleway's Cockpit Alertmanager (`scaleway_cockpit_alert_manager` + `scaleway_cockpit_preconfigured_alert`) or datasource-managed ruler rules — genuinely deferred, not a permanent boundary. ([#218](https://github.com/noisypigeon/noisypigeon/issues/218))
- Replacing the `local-exec` first-access bootstrap with a native Terraform resource once (if) the upstream `scaleway_cockpit_activate_grafana` action merges.
- Wiring `scaleway_cockpit_grafana_sync_data_sources` (the action that forces Cockpit to push/refresh its data sources into Grafana, since that sync is otherwise asynchronous and can silently lag) onto the existing `shared/cockpit` leaf's sources — left for implementation time to confirm whether the repo's pinned Terraform `1.16.3` (`.mise.toml`) actually supports the HCL `action` block this requires; if not, file as a follow-up rather than blocking this ADR.
