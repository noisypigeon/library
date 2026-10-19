# observability/pigeon-cli

[`pigeon-cli`](https://github.com/noisypigeon/pigeon-cli)'s local observability
stack, hoisted from that repo by its CLI-0161 (the stack itself is its
CLI-0128). Versioned as `observability/pigeon-cli/vX.Y.Z`.

| Service | Port | What it does |
| --- | --- | --- |
| Prometheus | 9090 | Scrapes a bare-metal `pigeon` run's `/metrics` at `host.docker.internal:9091`. |
| Loki | 3100 | Stores the JSONL log Promtail ships. |
| Promtail | — | Tails `~/Library/Application Support/pigeon/logs` (macOS). |
| Grafana | 3000 | Renders [`grafana-dashboards/pigeon-cli`](../../grafana-dashboards/pigeon-cli) over both. |

The dashboard is not copied here. Grafana mounts
`../../grafana-dashboards/pigeon-cli` from the same checkout, so a stack version
renders the dashboard as it was at that commit. Its node-exporter disk panel
stays empty locally, because nothing here runs a node-exporter.

## Consuming a version

From a checkout of the tag, run
`docker compose -f observability/pigeon-cli/docker-compose.yml up -d`.
pigeon-cli's `mise run observability-up` does this from its `.lib-src/` clone at
the version its `.mise.toml` pins.

## Editing

Change the stack here and open a PR. The `release:*` label sets the bump.
