# Changelog

All notable changes to this dashboard set are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-10-19

### Add pigeon-cli's observability stack and Claude Code plugin

Hoists two more of `pigeon-cli`'s assets into the library, per its [CLI-0161](https://github.com/noisypigeon/pigeon-cli/pull/133). Each gets its own per-set release track.

- **`observability/pigeon-cli/`**, released as `observability/pigeon-cli/vX.Y.Z`. This is pigeon-cli's local Docker Compose stack: Prometheus, Loki, Promtail and Grafana. Grafana no longer keeps its own copy of the dashboard. It mounts `grafana-dashboards/pigeon-cli/` from the same checkout, so there is one dashboard to edit. The compose project name is pinned to `observability`, so an existing stack keeps its Prometheus and Grafana volumes across the move.
- **`claude-plugins/pigeon-cli/`**, released as `claude-plugins/pigeon-cli/vX.Y.Z`. This is a Claude Code plugin holding the `analyze-job-run` skill. The repo root gains `.claude-plugin/marketplace.json`, a marketplace named `library`. A consumer pins the marketplace to the plugin's tag in its `.claude/settings.json` and enables `pigeon-cli@library`.
- **`grafana-dashboards/pigeon-cli`**: the `instance` variable's "All" is now `.*`. Its values come from node-exporter, so on a stack without one, "All" used to match nothing and every pigeon panel came up empty. On Cockpit, "All" still means every instance.
- **`template-release.yml`** treats `observability/<set>/` and `claude-plugins/<set>/` like `grafana-dashboards/<set>/`: one release track per set, and a set's README/CHANGELOG are never a release on their own.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#82](https://github.com/noisypigeon/library/pull/82)

## [1.0.0] - 2026-10-15

### Add the pigeon-cli Grafana dashboard set

The first dashboard set on the new `grafana-dashboards` track: `grafana-dashboards/pigeon-cli/overview.json`, the `pigeon-cli` job overview against Cockpit's metrics and logs.

The file is **byte-identical** to the dashboard `willowgraysen.com` applies today. That includes the fix in noisypigeon/willowgraysen.com#4, which dropped a top-level `"uid": null` that had made every plan show a change. So `v1.0.0` is exactly what is live. Pointing that repo's Grafana leaf at this version's URL changes nothing, and the plan there will be the proof.

Consume it by tag URL:

```
https://raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/grafana-dashboards/pigeon-cli/v1.0.0/grafana-dashboards/pigeon-cli/overview.json
```

`pigeon-cli`'s local observability stack still ships its own copy. Linking it to this version is a later step.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#29](https://github.com/noisypigeon/pigeon-lib/pull/29)
