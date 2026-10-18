# DEV-0136: pigeon-cli jobs dashboard (phases, resource usage, logs)

- Status: Accepted
- Date: 2026-10-07
- Author: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).

## Context

ADR-0135 shipped Grafana-dashboards-as-code against Scaleway Cockpit and dropped in `dashboards/overview.json` as a minimal placeholder — just enough to prove the pipeline end-to-end (CPU, memory, a logs panel). Now that it's live, the placeholder needs to become a real, useful dashboard for watching `pigeon-cli` job runs: phase-by-phase progress, host resource usage, and logs, all split per instance.

`pigeon_job_phase_total` (defined in `noisypigeon/pigeon-cli`'s `src/observability/metrics.rs`) is a **counter** with labels `pigeon_job`, `phase`, `outcome`, `instance`, `source_bucket`. It resets to 0 on every `pigeon` invocation — `pigeon` is a short-lived CLI, not a daemon, so a raw/cumulative value is meaningless across runs; `increase()`/`rate()` (both reset-aware) are the correct query shape.

`pigeon-cli` also exposes process-scoped resource gauges (`pigeon_resource_cpu_percent`, `pigeon_resource_mem_bytes`, `pigeon_resource_disk_{read,written}_bytes_total`), and since every `pigeon-cli` job runs on its own dedicated compute instance (one job per host, per the `job/<name>/` leaf convention), host-level and process-level numbers would be practically identical anyway. `node_exporter` (via Alloy's `prometheus.exporter.unix "node"`, default collector set, 60s scrape) was expected to expose filesystem (`node_filesystem_*`), disk I/O (`node_disk_*`), and network (`node_network_*`) metrics with no Alloy config changes needed. In practice, Grafana's live metrics browser confirmed `node_disk_*` and `node_network_*` don't exist at all in this environment — only `node_filesystem_*` is actually present and working — so the dashboard ends up using a mix of process-level and host-level sources; see the "Resource panels" decision below.

Both Cockpit metrics and logs sources are capped at 31-day retention (`templates/terraform/scaleway/cockpit-observability`) — a hard ceiling on any default/allowed time range.

## Decision

### Edit `dashboards/overview.json` in place

The file is edited, not replaced/renamed — `grafana.tf`'s `fileset`-driven `for` loop keys the Terraform map (and thus the dashboard's resource address) off the filename stem, so renaming would needlessly recreate the dashboard (new UID) even though this is the same conceptual "pigeon-cli overview" dashboard, now filled in for real instead of being a placeholder.

### Job phases panel: `increase()`, not `rate()`

`sum by (phase, instance) (increase(pigeon_job_phase_total{instance=~"$instance"}[$__rate_interval]))`, one line per phase/instance combination (`legendFormat: "{{phase}} - {{instance}}"`). `increase()` shows "how many phase completions in this window" — intuitive for a sparse, bursty, per-run-resetting counter, where `rate()`'s per-second framing would produce tiny, less legible fractional numbers. `$__rate_interval` (Grafana's built-in, scrape-interval-aware variable) is used instead of a hardcoded window since the `pigeon_cli` scrape interval (15s) differs from `node`'s (60s).

### Resource panels: a mix of process-level and host-level, based on what's actually scraped

The original intent was host-level `node_exporter` metrics for CPU, memory, and disk, for consistency and because one job per host makes host-level and process-level numbers practically equivalent. In practice, `node_disk_read_bytes_total`/`node_disk_written_bytes_total`/`node_network_receive_bytes_total`/`node_network_transmit_bytes_total` turned out not to exist at all in this environment — confirmed via Grafana's live metrics browser, not just absent from the dashboard — despite `diskstats`/`netdev` being enabled by default in both Alloy's `prometheus.exporter.unix` component and node_exporter itself (verified by reading both projects' source directly). The root cause of their absence is still unconfirmed; the dashboard adapts to what's actually available rather than block on diagnosing it further.

CPU, memory, and disk I/O panels use pigeon-cli's own process-level metrics instead — `pigeon_resource_cpu_percent`, `pigeon_resource_mem_bytes`, `pigeon_resource_disk_{read,written}_bytes_total` — all confirmed present with real data. Disk space utilization stays on `node_filesystem_*` (host-level), since that data is real and working; there's no process-level equivalent for filesystem capacity anyway. It's also squashed to one line per instance via `max by (instance)` across all mountpoints, rather than one line per (instance, mountpoint) pair — "is it running out" is answered by whichever mounted volume is closest to full, and per-mountpoint detail is an abstraction the dashboard doesn't need to expose.

There is no network-I/O metric at either level — pigeon-cli has no general network byte counter. The panel originally planned as "Network usage" ships as "Upload throughput" instead, using `pigeon_upload_bytes_total` (bytes successfully uploaded to a destination bucket) as the closest available proxy for network activity.

### Disk: both space utilization and I/O throughput

Two separate panels, since "disk usage" is ambiguous between "is it filling up" and "how hard is it working": space utilization (`node_filesystem_avail_bytes` / `node_filesystem_size_bytes`, host-level and real; squashed to one line per instance via `max by (instance)` across mountpoints — see the "Resource panels" decision above) and I/O throughput (`pigeon_resource_disk_read_bytes_total` / `pigeon_resource_disk_written_bytes_total`, process-level since the host-level equivalent doesn't exist in this environment, rate, split by instance).

### Upload throughput panel

No network-I/O metric exists at either the host or process level in this environment (see "Resource panels" above). `pigeon_upload_bytes_total`, rate, split by instance, is used as the closest available proxy — bytes successfully uploaded to a destination bucket, not raw network throughput.

## Consequences

- The placeholder dashboard becomes a real one: job-phase progress, resource usage (CPU/memory/disk I/O at process level, disk space at host level, upload throughput as a network proxy), and logs, all per-instance.
- No `templates/terraform/` module is touched and no Terraform interface changes — this is a dashboard-content-only change, so no `release:*` label applies.
- The dashboard's Terraform resource address and UID are unchanged (same map key), so any existing bookmark/link to it keeps working.

## Out of scope

- A process-scoped equivalent for the disk space utilization panel — pigeon-cli has no process-level filesystem-capacity metric, and host-level `node_filesystem_*` is confirmed present and working, so there's no gap to fill.
- Root-causing why `node_disk_*`/`node_network_*` are missing from this environment's `node_exporter` scrape — deferred as a separate investigation, unblocking this dashboard in the meantime by using pigeon-cli's own process-level metrics instead.
- Cockpit Alertmanager alerting on any of these panels — already tracked by [#218](https://github.com/noisypigeon/noisypigeon/issues/218) per ADR-0135, unaffected by this change.
