# claude-plugins/pigeon-cli

A Claude Code plugin with the skills for working on
[`pigeon-cli`](https://github.com/noisypigeon/pigeon-cli), hoisted from that
repo by its CLI-0161. Versioned as `claude-plugins/pigeon-cli/vX.Y.Z` and
listed in this repo's [`/.claude-plugin/marketplace.json`](../../.claude-plugin/marketplace.json).

| Skill | What it does |
| --- | --- |
| `analyze-job-run` | Diagnoses a `pigeon` job run from its JSONL log (`pigeon.jsonl`) and its Prometheus metrics. |

## Consuming a version

Pin the marketplace to this plugin's tag and enable the plugin in the
consuming repo's committed `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "library": {
      "source": { "source": "github", "repo": "noisypigeon/library", "ref": "claude-plugins/pigeon-cli/v1.0.0" }
    }
  },
  "enabledPlugins": { "pigeon-cli@library": true }
}
```

The entries apply once the folder is trusted. If Claude Code reports the plugin
is enabled but not installed, run
`claude plugin install pigeon-cli@library --scope project` once.

No `version` is set in `plugin.json` or the marketplace entry: the pinned tag
is the version.

## Editing

Change the skill here, open a PR with a `release:*` label, then bump the pin in
pigeon-cli. The skill's cheat sheet tracks pigeon-cli's logging code, so a
pigeon-cli PR that changes logging needs a matching PR here.
