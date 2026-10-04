# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-04

### Add scaleway/cockpit-observability module

Adds a new `scaleway/cockpit-observability` module: a wrapper around `scaleway_cockpit_source`/`scaleway_cockpit_token` that creates a metrics source, a logs source, and a shared push token, each source individually toggleable via `enable_metrics`/`enable_logs` (both default `true`). The push token's `write_metrics`/`write_logs` scopes follow the matching toggle, so a disabled source never carries a live write scope for it.

Inputs: `name` (prefix for the source/token names, e.g. `"pigeon-cli"` produces `pigeon-cli-metrics`, `pigeon-cli-logs`, `pigeon-cli-push`), `project_id`, `enable_metrics`, `enable_logs`. Outputs: `metrics_push_url`, `logs_push_url` (each `null` when its source is disabled), and `token_secret` (sensitive).

This generalizes the Cockpit resources currently hand-rolled inline in `workloads/pigeon-cli/terraform/observability/cockpit.tf` (docs/adr/0103-shared-cockpit-store.md) so any future workload needing its own Cockpit source/token pair can reuse this module instead of copy-pasting the resources. A follow-up PR will rewire that leaf to consume this module via a state migration.

## Test plan

- [x] `mise run fmt-check-terraform` passes.
- [ ] After merge: confirm the `templates/terraform/scaleway/cockpit-observability/v0.1.0` tag and GitHub Release are created, and `README.md`'s Inputs/Outputs tables are injected by `module-docs.yml`.

[#149](https://github.com/noisypigeon/noisypigeon/pull/149)
