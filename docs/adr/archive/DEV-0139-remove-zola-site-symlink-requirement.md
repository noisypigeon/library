# DEV-0139: remove the committed symlink requirement from `templates/zola-site` consumption

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-06.
- **Status**: Accepted.

## Context

[ADR-0114](DEV-0114-pin-templates-zola-site-version.md) gave each consuming site
(`workloads/noisypigeon.com/src`, `workloads/pigeon.dev/src`) a committed
symlink at `themes/zola-site`, pointed not directly at `templates/zola-site`
(ADR-0112's original design) but at a gitignored indirection layer,
`.theme-resolved/zola-site`:

```
workloads/<site>/src/themes/zola-site -> ../.theme-resolved/zola-site
```

`templates/zola-site/resolve-theme.sh`, run as the first step of every
`mise` build/serve task and every deploy workflow, populates
`.theme-resolved/zola-site` — either a live symlink straight to
`templates/zola-site` (`[extra].theme_version = "main"`, the default) or a
`git archive`-materialized copy of a tagged version. That's two layers (a
file git tracks, pointing at a path git is told to ignore) to express one
outcome: "`themes/zola-site` should contain whatever `theme_version`
resolves to."

`templates/terraform/` doesn't need anything checked into a consumer at all
to get the same kind of outcome — a consumer just writes the version
directly into its own source string (`source = ".../vX.Y.Z"`, or a bare
`ref=` on a `git::` URL), and the build tool (`terraform init`, via
go-getter) resolves it fresh every run. `resolve-theme.sh` is already the
equivalent "build tool" for zola-site, already invoked first by every build
path — it never needed a committed symlink to do its job; the symlink was
only there so the repo had *something* at `themes/zola-site` to browse
without running the script first. That's not a requirement anything in this
repo actually relies on (nothing reads `themes/zola-site` except
`zola build`/`zola serve`, both of which already run `resolve-theme.sh`
immediately beforehand).

## Decision

Collapse the two-layer `committed symlink → gitignored .theme-resolved/<name>`
indirection into one: `resolve-theme.sh` now writes directly into
`themes/<name>` (the real path Zola expects), and nothing related to theme
resolution is committed to git in a consuming site at all.

- `resolve-theme.sh`: `RESOLVED_DIR` changes from
  `"$SITE_DIR/.theme-resolved/$THEME_NAME"` to `"$SITE_DIR/themes/$THEME_NAME"`.
  The `rm -rf`/`mkdir -p`/symlink-or-`git archive` logic underneath is
  otherwise unchanged — same `"main"` vs. pinned-tag branching, same hard
  failure on an unknown tag.
- The two committed symlinks (`workloads/noisypigeon.com/src/themes/zola-site`,
  `workloads/pigeon.dev/src/themes/zola-site`) are deleted outright via
  `git rm`.
- `.gitignore`'s `/workloads/*/src/.theme-resolved/` entry becomes
  `/workloads/*/src/themes/zola-site` — kept name-specific rather than a
  blanket `themes/*`, in case a future second theme is ever added alongside
  it.
- `templates/zola-site/README.md`'s Consuming/Versioning sections are
  updated to match (no symlink step; `resolve-theme.sh` populates
  `themes/<name>` directly), and its remaining stale `workloads/blog/src`
  references — pre-existing since ADR-0132 renamed that workload, never
  caught at the time — are fixed to name both current consumers.
- No change to `.mise.toml`'s tasks or either deploy workflow: both already
  invoke `resolve-theme.sh` as the first step before any Zola command, with
  the exact same relative-path invocation (`../../../templates/zola-site/resolve-theme.sh`).
  Only what the script does internally changes.
- No change to `[extra].theme_version` or the `"main"`-vs-tag semantics
  (ADR-0114) — that part was already "direct versioning"; this ADR only
  removes the symlink plumbing sitting on top of it.

### Does this trigger a `templates/zola-site` release?

No. `template-release.yml`'s zola-site change-detection glob is
`^templates/zola-site/(templates/|static/|theme\.toml$)` — it deliberately
does not match `resolve-theme.sh` or `README.md`. ADR-0114 already flagged
this gap explicitly ("`resolve-theme.sh` itself is not covered by
ADR-0113's content-change glob... revisit the glob if `resolve-theme.sh`
ever needs its own real release discipline independent of the theme content
it resolves"). This change is exactly that scenario, but revisiting the
glob is a separate decision from removing the symlink requirement and is
left out of scope below — this PR lands with no `release:*` label and no
new tag, consistent with how the script has always been treated.

## Consequences

- A fresh clone no longer has anything at `workloads/<site>/src/themes/`
  until `resolve-theme.sh` runs once — this was already effectively true
  (the old committed symlink pointed at a gitignored, not-yet-populated
  path, so `zola build` without first running the script failed exactly the
  same way before this change as after).
- `git status` in a consuming site's directory is simpler to reason about:
  there is now exactly one path under `themes/` and it is always either
  absent or gitignored, never a tracked file.
- Any future `workloads/<name>/src` consumer needs zero symlink setup — just
  `theme = "zola-site"` + `[extra].theme_version` in its own `config.toml`,
  and `resolve-theme.sh` wired into its build/serve path.

## Out of scope

- Revisiting `template-release.yml`'s zola-site content-change glob to also
  cover `resolve-theme.sh`/`README.md` — a real gap ADR-0114 already named,
  but a separate decision from this one.
- Any change to `[extra].theme_version` semantics, the pinned-tag redirect
  pages (ADR-0114 §4), or `templates/terraform/`'s own consumption model —
  all unchanged.
