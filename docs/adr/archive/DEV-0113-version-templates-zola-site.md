# DEV-0113: version `templates/zola-site`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

[ADR-0112](DEV-0112-extract-reusable-zola-site-template.md) extracted `templates/zola-site` as a reusable Zola theme, but explicitly left "no versioning/release process yet" as Out of scope — it was a deliberate boundary, not a gap: the theme had exactly one consumer (`workloads/blog/src`, via a committed relative symlink designed for live, unversioned `main`-tracking), and no concrete need to pin independently existed yet. That boundary is now being closed: this ADR adds the same kind of versioning/release mechanism `templates/terraform/`'s modules already have (`.github/workflows/module-release.yml`'s per-unit discovery → `release:*` label → semver tag → `CHANGELOG.md` → GitHub Release), adapted for a single-unit Zola theme rather than a multi-module Terraform tree.

The initial seed version is `v1.0.0`, not the `v0.1.0` the terraform modules' own very first hand-written changelog entry used — a deliberate departure from that precedent. The theme has zero prior tags, but it is not experimental: it is the exact code already running the live blog at `noisypigeon.com` (and has been since before its ADR-0112 extraction). `v1.0.0` reflects that production status truthfully; `v0.1.0` would not, and tags in this repo are permanent (never renamed or deleted per `templates/terraform/README.md`'s own stated policy), so this is a one-time, hard-to-revisit choice worth getting right at the start.

## Decision

### 1. A third independent track in `module-release.yml`

`module-release.yml` already runs two independent, separately-gated tracks in one workflow: Terraform "modules" (multi-directory, `versions.tf`-discovered, `release:*`-label-gated, tagged/released) and "blog" (single-path, unversioned, no label, no tag). Zola-site becomes a third track, parallel to both — not folded into the terraform loop, since that loop's `${dir#templates/terraform/}` prefix-strip and `for dir in $MODULE_DIRS` iteration are specific to a multi-module tree and don't fit a single fixed path.

**Content-change detection** (replacing terraform's `.tf`-only filter, which doesn't translate — zola-site content spans `.html`/`.xml`/`.css`/`.toml` with no single extension):
```bash
grep -qE '^templates/zola-site/(templates/|static/|theme\.toml$)'
```
Matches real theme content; excludes `templates/zola-site/README.md` and `CHANGELOG.md` — a docs-only edit (including this very ADR's own implementation PR) shouldn't trigger a release, mirroring how a README-only edit inside a terraform module directory already doesn't.

**Workflow changes:**
- New step **"Determine zola-site change"** (id `zola_site`), parallel to "Determine blog change", gated on the glob above.
- **Narrowed "Determine blog change"**: dropped `templates/zola-site/` from its grep (reverting the widening ADR-0112 §4 made), back to `^workloads/blog/src/` only — zola-site now has its own track, so it shouldn't also land an entry in `workloads/blog/CHANGELOG.md`. (`blog-pages.yml`'s own push-trigger path filter, which governs Pages deploys rather than changelog bookkeeping, still includes `templates/zola-site/**` and is untouched — still correct.)
- **"Configure git identity"** and **"Commit changelog updates"** gates both extended with `|| steps.zola_site.outputs.changed == 'true'`.
- New step **"Update zola-site changelog and compute version"** (id `zola_site_version`, gated on the zola-site track): a single-unit version of the terraform loop body — same `git tag -l` lookup, same `release:*`-label bump arithmetic (reusing the one repo-wide `steps.bump.outputs.level`, already generic — no changes needed there), same `CHANGELOG.md` header/splice pattern, same root `CHANGELOG.md` rollup (labeled literally `[zola-site]`, not path-stripped — the terraform-specific strip is a no-op here anyway). Its empty-`$LATEST` fallback is `NEXT="1.0.0"`, not `0.1.0` — a safety net matching this ADR's seed-version decision, in case the manual seed step below is ever skipped or lands late.
- **"Trigger blog Pages deploy"** gate extended with `|| steps.zola_site.outputs.changed == 'true'` — bot-authored pushes via `GITHUB_TOKEN` don't trigger `blog-pages.yml`'s own push event (per ADR-0107's PR #137 fix), so without this a zola-site release would tag/changelog correctly but never actually redeploy the blog now consuming the newly-tagged theme.
- **"Tag and release each changed module"** renamed **"...module/theme"**, gate extended with `|| steps.zola_site.outputs.changed == 'true'`, and its `RELEASE_TAGS` combines `steps.versions.outputs.tags` with `steps.zola_site_version.outputs.tag` — the tag/push/`gh release create` loop body is pure mechanical plumbing with no terraform-specific logic, safe to share across both tracks.

### 2. No fetch-by-URL consumption mechanism for the theme

Unlike Terraform modules, Zola has no HTTP module-source/go-getter-style discovery protocol for themes — there is no way to build a `noisypigeon.com/...` short-URL equivalent to ADR-0109's module redirects, and none is proposed. `templates/zola-site/README.md`'s Versioning section documents the only real consumption path for a tagged version: clone this repo at that tag (or vendor/submodule `templates/zola-site` at that ref) and point a consuming site's `themes/<name>` symlink or copy at it.

`workloads/blog/src`'s own `themes/zola-site` symlink does **not** change behavior — it keeps tracking `main` live, exactly as ADR-0112 designed it. Tags exist for a hypothetical future *external* consumer that needs to pin independently of this repo's own `main`; this repo's own first-party consumer has no reason to pin to anything but the latest code.

### 3. `release-pr` skill generalized, not forked

`.claude/skills/release-pr/SKILL.md` already encodes the exact PR discipline this mechanism needs (branch → commit → PR body as changelog text → one `release:*` label → squash-merge → sync main) — generalized in place (title, frontmatter description, intro prose, the changelog-path sentence, and the no-label carve-out) to mention `templates/zola-site/` alongside the existing `templates/terraform/<provider>/<module>/` references, rather than writing a second, near-duplicate skill file.

### 4. Manual one-time seed tag

Because this ADR's own implementation PR only touches `module-release.yml`, `templates/zola-site/README.md`, `.claude/skills/release-pr/SKILL.md`, `CLAUDE.md`, and this ADR file — none of which match the content-change glob in §1 — merging it will not auto-fire the new track. `templates/zola-site/v1.0.0` is therefore seeded by hand immediately after merge: a hand-written `templates/zola-site/CHANGELOG.md` first entry (mirroring how the original terraform modules' very first changelog entry was also hand-written, pre-automation, documenting the ADR-0037 merge-in rather than a real automated release), a matching root `CHANGELOG.md` rollup line, then `git tag templates/zola-site/v1.0.0` + `gh release create`.

## Consequences

- `templates/zola-site` is now a versioned, releasable unit with the same `release:*`-label discipline as a Terraform module, via its own `CHANGELOG.md` and `templates/zola-site/vX.Y.Z` tags.
- A theme-only PR no longer produces a `workloads/blog/CHANGELOG.md`/daily-digest entry (narrowed per §1) — it produces a `templates/zola-site/CHANGELOG.md` entry and a tagged release instead, matching how a terraform module change is treated, not how a blog-content change is treated.
- The blog's live `main`-tracking symlink is unchanged; tags are purely additive, for a consumer that doesn't exist yet.

## Out of scope

- No actual second consumer of `templates/zola-site` is added by this ADR — only the versioning mechanism and the documentation of how a future one would pin to a tag.
- No `noisypigeon.com/...` short-URL redirect mechanism for theme versions (unlike ADR-0109's module redirects) — Zola has no fetch-by-theme-URL feature for this to hook into, so none is designed here.
