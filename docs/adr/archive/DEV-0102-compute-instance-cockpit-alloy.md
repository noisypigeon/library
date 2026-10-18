# DEV-0102: Scaleway Cockpit wiring on scaleway/compute-instance via Grafana Alloy

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`pigeon-cli`'s `sort/macbook-scratch` instance (and any future `profile =
"pigeon-cli"` instance from this module) runs unattended, reviewed only by
hand-reading its durable JSONL log (`pigeon.jsonl`, `noisypigeon/pigeon-cli`
ADR-0073) over SSH after the fact. The user wants to build Grafana
dashboards for these job runs via Scaleway's managed Cockpit product
(Grafana + Loki + Mimir). `noisypigeon/pigeon-cli`'s own ADR-0092 (merged as
that repo's PR #13) added the application-side half of this: a localhost
Prometheus `/metrics` endpoint (`--metrics-port`, default 9091) dual-emitted
alongside the existing JSONL log, explicitly deferring "shipping these
metrics anywhere" to the terraform side — this ADR is that terraform side.

Cockpit's ingestion model (verified against Scaleway's own `scaleway_cockpit_*`
Terraform resources and a published GPU-monitoring tutorial using the exact
`prometheus.remote_write`/`X-TOKEN` syntax below) is: a `scaleway_cockpit_source`
per data kind (`metrics`/`logs`), each with its own `push_url`, plus a
`scaleway_cockpit_token` carrying the write scopes, sent as an `X-TOKEN`
header. Grafana Alloy is Scaleway's documented agent for both pushing
Prometheus metrics (`prometheus.scrape` + `prometheus.remote_write`) and
tailing a log file into Loki (`loki.source.file` + `loki.write`) — one agent
covers both halves of this instance's new observability surface, so it's
installed once rather than reaching for two separate tools. The deprecated
`data.scaleway_cockpit`/`endpoints` data source is intentionally not used;
per-source `scaleway_cockpit_source` resources are Scaleway's current path.

The actual `scaleway_cockpit_source`/`scaleway_cockpit_token` resources
belong to a *leaf* (they're project-scoped, not instance-scoped, and a leaf
already owns `project_id`-rooted resources like `iam-policy`) — this ADR
covers only `modules/scaleway/compute-instance`'s side: accepting that
wiring as input and rendering the on-host Alloy agent from it. The
`sort/macbook-scratch` leaf's own consumption of this (the new Cockpit
resources + passing `cockpit = {...}` into the module call) is a separate,
follow-up change once this module version is tagged — it needs the new tag
to reference, so it can't land in the same PR.

## Decision

### New optional `cockpit` object variable

```hcl
variable "cockpit" {
  type = object({
    metrics_push_url = string
    logs_push_url    = string
    token_secret      = string
    scrape_port      = optional(number, 9091)
  })
  description = "Scaleway Cockpit wiring for an on-host Grafana Alloy agent that tails pigeon-cli's JSONL log and scrapes its Prometheus metrics endpoint (ADR-0102); only used when profile = \"pigeon-cli\". null disables Alloy entirely."
  default     = null
  sensitive   = true

  validation {
    condition     = var.profile == "pigeon-cli" || var.cockpit == null
    error_message = "cockpit is only used when profile = \"pigeon-cli\"."
  }
}
```

`null` (the default) renders no Alloy-related cloud-init content at all —
purely additive, same "optional object, profile-gated" shape as
ADR-0100/0101's `keyring_entries`/`buckets`.

### `PIGEON_LOG_DIR` pinned to a stable, `$HOME`-independent path

`pigeon-cli`'s default log directory depends on `$HOME`
(`~/.local/share/pigeon/logs/pigeon.jsonl`), which is fine for a human SSH
session but not a stable target for Alloy's static file path. When
`var.cockpit != null`, the existing `/etc/profile.d/pigeon-env.sh`
(ADR-0101) gains one more line:

```
export PIGEON_LOG_DIR="/var/log/pigeon"
```

so the log always lands at `/var/log/pigeon/pigeon.jsonl` regardless of
which user/session runs `pigeon`, and Alloy's `loki.source.file` target
below can hardcode that path.

### `/etc/alloy/config.alloy`, rendered from the module's new variable

A new `write_files` entry, gated on `var.cockpit != null` (nested inside the
existing `profile == "pigeon-cli"` block, alongside `rclone.conf`/
`keyring.toml`):

```
prometheus.exporter.unix "node" { }

prometheus.scrape "node" {
  scrape_interval = "60s"
  targets         = prometheus.exporter.unix.node.targets
  forward_to      = [prometheus.remote_write.cockpit.receiver]
}

prometheus.scrape "pigeon_cli" {
  scrape_interval = "15s"
  targets         = [{"__address__" = "localhost:${var.cockpit.scrape_port}"}]
  forward_to      = [prometheus.remote_write.cockpit.receiver]
}

prometheus.remote_write "cockpit" {
  endpoint {
    url = "${var.cockpit.metrics_push_url}/api/v1/push"
    headers = {
      "X-TOKEN" = "${var.cockpit.token_secret}",
    }
  }
}

loki.source.file "pigeon_logs" {
  targets    = [{"__path__" = "/var/log/pigeon/pigeon.jsonl"}]
  forward_to = [loki.write.cockpit.receiver]
}

loki.write "cockpit" {
  endpoint {
    url = "${var.cockpit.logs_push_url}/loki/api/v1/push"
    headers = {
      "X-TOKEN" = "${var.cockpit.token_secret}",
    }
  }
}
```

`prometheus.exporter.unix`/its scrape block are a cheap addition once Alloy
is installed anyway — whole-instance CPU/mem/disk/network, complementing
`pigeon-cli`'s own app-level metrics. The `pigeon_cli` scrape target only
exists while a `pigeon` process is actually running (ADR-0092's endpoint is
process-lifetime, not a daemon) — Alloy will show that target as down
between runs; this is expected, not a fault to alert on.

**Not independently verified for this ADR**: the `X-TOKEN` header on
`loki.write` is assumed identical to the confirmed `prometheus.remote_write`
case (same token, same header name, per Cockpit's one-token-covers-both-scopes
model) — Scaleway's own published raw-Alloy example for the logs side
wasn't found during research; verify against current Cockpit docs (or just
watch Alloy's own logs after `terragrunt apply`) before trusting this in
production.

### Install Alloy via the Grafana APT repo

New `runcmd` block, same shape as the existing Docker-profile APT-repo
block, gated on `var.cockpit != null`:

```
- mkdir -p /etc/apt/keyrings
- wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg.key
- echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list > /dev/null
- apt-get update
- apt-get install -y alloy
- systemctl enable alloy
- systemctl restart alloy
```

Ordering is safe without any special handling: cloud-init's `write_files`
stage runs before `runcmd`, so `/etc/alloy/config.alloy` already exists on
disk by the time this `apt-get install` (which starts the `alloy.service`
systemd unit as part of package setup) and the explicit `systemctl restart`
run.

### Documentation & versioning

- `README.md` regenerates automatically via `module-docs.yml` on merge.
- `CHANGELOG.md` appended automatically by `module-release.yml` on merge
  with a `release:minor` label — purely additive, `var.cockpit` defaults to
  `null` and every other profile/variable is untouched.
- Tag: `modules/scaleway/compute-instance/v2.3.0`.

## Consequences

- `release:minor` for `scaleway/compute-instance`.
- Applying `cockpit != null` to an *existing* instance is a cloud-init
  content change, so it force-replaces that instance on next apply
  (ADR-0084's `lifecycle.replace_triggered_by`) — call this out explicitly
  in the leaf PR that actually sets `cockpit`, not just discover it at
  apply time.
- `pigeon-cli`-profile instances that opt in now run a second long-lived
  service (`alloy.service`) alongside whatever `pigeon` job a user runs
  manually.

## Out of scope

- The actual `scaleway_cockpit_source`/`scaleway_cockpit_token` resources
  and wiring `cockpit = {...}` into any leaf's `module "compute"` call —
  follow-up leaf-level change, needs this module's new tag to reference.
- A `scaleway_cockpit_grafana_user` (or any other way to actually log into
  the resulting Grafana) — also leaf-level, deferred to the same follow-up.
- Verifying the logs-side `X-TOKEN` header convention against Cockpit's
  current docs — flagged above, not resolved here.
- Any non-`pigeon-cli` profile wanting Alloy/Cockpit — `var.cockpit`'s
  profile-gate validation matches `buckets`/`keyring_entries`'s existing
  precedent; widening it is a future ask if it comes up, not assumed here.
