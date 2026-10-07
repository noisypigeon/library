# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-06

### Add grafana-dashboard module

Introduces `scaleway/grafana-dashboard`, a `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder and provisions a set of dashboards into it from JSON dashboard models, keyed by a short stable name so adding or removing one dashboard doesn't reindex the rest.

Scaleway Cockpit's own preconfigured dashboards live in a folder that's always read-only, so Terraform-managed dashboards need a folder of their own — this module creates it alongside the dashboards it provisions.

See [ADR-0135](docs/adr/0135-grafana-dashboards-as-code.md) for the full design, including how the `grafana` provider itself gets authenticated against Cockpit's IAM-proxied Grafana (handled by the consuming leaf, not this module, since Scaleway's `scaleway_cockpit_grafana_user` resource was removed after its backing API's EOL).

This PR also adds the first consumer: `workloads/willowgraysen.com/terraform/pigeon-cli/shared/grafana/`, a shared leaf with its own dedicated, narrowly-scoped IAM credential (`ObservabilityGrafanaEditor`) and a sample "pigeon-cli overview" dashboard covering CPU/memory and job logs.

[#217](https://github.com/noisypigeon/noisypigeon/pull/217)
