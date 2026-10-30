# library (archived)

**This repository moved into [`noisypigeon/runway`](https://github.com/noisypigeon/runway)**, under
[`lib/`](https://github.com/noisypigeon/runway/tree/main/lib)
([LIB-0047](https://github.com/noisypigeon/runway/blob/main/adr/LIB-0047-hoist-the-library-into-runway.md)).
Everything that was here now lives there:

| Was here | Now in runway |
| --- | --- |
| `terraform/`, `zola-site/`, `terragrunt/`, `grafana-dashboards/`, `observability/`, `claude-plugins/` | `lib/<same>` |
| `.github/scripts/` | `lib/scripts/` |
| `.github/workflows/` | `.github/workflows/` |
| `docs/adr/` | `adr/` |
| `docs/runbooks/` | `runbooks/` |
| `CHANGELOG.md` | `lib/CHANGELOG.md` |

Every tag was recreated in runway under its own name, and new versions continue
there. Open issues moved to runway too.

This repository is archived and keeps all its tags, so an existing pin still
resolves:

- a `git::https://github.com/noisypigeon/library.git//terraform/...?ref=<tag>`
  source;
- a `raw.githubusercontent.com/noisypigeon/library/refs/tags/<tag>/...` URL;
- a `noisypigeon/library/.github/workflows/...@workflows/vX.Y.Z` call.

Nothing new is released here. To take a newer version, pin runway instead:
`noisypigeon/runway/...@workflows/vX.Y.Z`, or the
`https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z` short URL,
which already resolves to runway.
