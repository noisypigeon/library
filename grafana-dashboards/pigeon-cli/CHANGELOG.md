# Changelog

All notable changes to this dashboard set are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
