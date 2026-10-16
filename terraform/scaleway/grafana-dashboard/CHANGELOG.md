# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-10-15

### grafana-dashboard: dashboards by URL, and an optional first-access hook

Two additive changes to `scaleway/grafana-dashboard`. Existing callers that pass `config_json` and nothing else are unchanged.

### Dashboards by URL

Each `dashboards` entry may now give `url` instead of `config_json`:

```hcl
dashboards = {
  overview = { url = "https://raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/grafana-dashboards/pigeon-cli/v1.0.0/grafana-dashboards/pigeon-cli/overview.json" }
}
```

- The module fetches the URL at plan time with `hashicorp/http`, which is a new provider requirement (`~> 3.4`).
- A non-200 response fails the plan, so an error page is never applied as a dashboard.
- Each entry must set exactly one of `config_json` or `url`; validation enforces it.

This is how a leaf pins a version from the new `grafana-dashboards/<set>` track, without keeping its own copy of the JSON.

### Optional first-access hook

Scaleway's Grafana provisions an IAM identity's role lazily, on its first API access, and no resource does that (ADR-0135). Leaves have carried a `terraform_data` curl hook as glue to handle it. The module can now run it:

- `first_access = { grafana_url, trigger }` with a sensitive `first_access_auth_token`.
- It runs once before the folder and dashboards are created, and again whenever `trigger` changes. Pass the IAM application ID.
- The token is a separate variable on purpose. Terraform won't base `count` on a sensitive value, so the hook's settings must stay non-sensitive.

Moving a leaf's existing hook in is an address change only, done with one `moved` block. The README has it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#31](https://github.com/noisypigeon/pigeon-lib/pull/31)

## [0.1.0] - 2026-10-06

### Add grafana-dashboard module

Introduces `scaleway/grafana-dashboard`, a `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder and provisions a set of dashboards into it from JSON dashboard models, keyed by a short stable name so adding or removing one dashboard doesn't reindex the rest.

Scaleway Cockpit's own preconfigured dashboards live in a folder that's always read-only, so Terraform-managed dashboards need a folder of their own — this module creates it alongside the dashboards it provisions.

See [ADR-0135](docs/adr/0135-grafana-dashboards-as-code.md) for the full design, including how the `grafana` provider itself gets authenticated against Cockpit's IAM-proxied Grafana (handled by the consuming leaf, not this module, since Scaleway's `scaleway_cockpit_grafana_user` resource was removed after its backing API's EOL).

This PR also adds the first consumer: `workloads/willowgraysen.com/terraform/pigeon-cli/shared/grafana/`, a shared leaf with its own dedicated, narrowly-scoped IAM credential (`ObservabilityGrafanaEditor`) and a sample "pigeon-cli overview" dashboard covering CPU/memory and job logs.

[#217](https://github.com/noisypigeon/noisypigeon/pull/217)
