# grafana-dashboards/pigeon-cli

Grafana dashboards for [`pigeon-cli`](https://github.com/noisypigeon/pigeon-cli)
jobs, against the metrics and logs its jobs push to Scaleway Cockpit. Versioned
as `grafana-dashboards/pigeon-cli/vX.Y.Z`.

| File | Dashboard |
| --- | --- |
| `overview.json` | the pigeon-cli job overview |

## Consuming a version

Fetch a dashboard by its tag's raw URL. The `refs/tags/` form is needed because
the tag itself contains slashes:

```
https://raw.githubusercontent.com/noisypigeon/library/refs/tags/grafana-dashboards/pigeon-cli/v1.0.0/grafana-dashboards/pigeon-cli/overview.json
```

From Terraform, pass that URL to
[`scaleway/grafana-dashboard`](../../terraform/scaleway/grafana-dashboard)'s
`dashboards = { overview = { url = "…" } }`.

[`observability/pigeon-cli`](../../observability/pigeon-cli) mounts this
directory from the same checkout, so pigeon-cli's local stack renders this JSON
rather than a copy of its own (pigeon-cli's CLI-0161). The `instance`
variable's "All" is `.*`, so the pigeon panels still populate on a stack with no
node-exporter.

## Editing

The JSON omits a top-level `uid`: Grafana assigns one, and its stored form
drops a null `uid`, so including `"uid": null` makes every plan show a change.
Export from Grafana, strip any `uid` and `version` it adds at the top level,
and open a PR here. The `release:*` label sets the bump.
