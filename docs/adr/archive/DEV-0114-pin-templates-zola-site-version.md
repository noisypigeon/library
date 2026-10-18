# DEV-0114: let consumers pin a `templates/zola-site` version

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

[ADR-0113](DEV-0113-version-templates-zola-site.md) gave `templates/zola-site` real versioning — git tags, a `CHANGELOG.md`, GitHub Releases — but no consumer could actually use any of it: `workloads/blog/src`'s `themes/zola-site` symlink unconditionally tracks `main`'s live content, with no config knob to point it anywhere else. ADR-0113 also explicitly declined a `noisypigeon.com/...` short-URL mechanism for theme versions, reasoning Zola has no fetch-by-theme-URL feature for such a thing to hook into.

Both of those are closed here, at the user's explicit request: (1) a real way for a consuming site to pin to a specific tagged version instead of always living on `main`, so "the next consumer of the zola-site template can run an independent version if needed"; (2) a short redirect URL per theme tag at `noisypigeon.com/templates/zola-site/vX.Y.Z`, mirroring `noisypigeon.com/modules/...` — this explicitly reverses ADR-0113's "none planned" stance on that specific point, confirmed by the user even knowing it can only ever be a documentation/discovery redirect, not a fetchable build input the way the Terraform pages are.

## Decision

### 1. Pin config: `[extra].theme_version`

Added to a consuming site's `config.toml`, e.g. `workloads/blog/src/config.toml`:
```toml
[extra]
theme_version = "main"
```
Lives under `[extra]`, not as a bare top-level key — Zola's `config.toml` schema rejects unrecognized top-level keys; `[extra]` is the only schema-flexible escape hatch. `"main"` is an explicit sentinel for today's live-tracking behavior (not an absent-key convention), so the knob is visible and documented at the one real consumer even while unused. Any other value (`"v1.0.0"` or `"1.0.0"`, the `v` prefix optional) pins to that tag.

### 2. `templates/zola-site/resolve-theme.sh` resolves the pin

A new script shipped with the theme itself, run from a consuming site's `src/` directory before `zola build`/`serve`. It infers the theme's own name from its own parent directory (zero required arguments), greps `[extra].theme_version` out of `config.toml` with a section-scoped `awk`/`sed` (no TOML library is pinned or available in this repo's toolchain — confirmed only unpinned `python3`/`jq` exist, no TOML CLI anywhere — so this matches the repo's existing bash/awk/sed scripting idiom), then:
- `"main"`: `ln -s "$REPO_ROOT/templates/<name>" .theme-resolved/<name>` — an absolute symlink. Absolute is safe (unlike the committed symlink, which must stay relative to survive different clone locations) because `.theme-resolved/` is fully gitignored and regenerated fresh on every machine/run.
- any tag: validates it exists (`git rev-parse templates/<name>/v<version>`, hard error if not — no silent fallback to `main`), then materializes it via `git archive "$TAG" -- "templates/<name>" | tar -x -C .theme-resolved/<name> --strip-components=2`. This is the first use of `git archive` anywhere in this repo; it's a clean fit, since tags here are already-established immutable full-repo snapshots (`templates/terraform/README.md`'s own stated policy) — this just reads that history rather than inventing new semantics.

### 3. The committed symlink now points through a gitignored indirection

`workloads/blog/src/themes/zola-site` moves from `-> ../../../../templates/zola-site` (direct, per ADR-0112) to `-> ../.theme-resolved/zola-site` — a short, fixed relative path, since `themes/` and `.theme-resolved/` are always direct siblings under `src/` regardless of how deep the site itself is nested. This keeps the *default*, unpinned case exactly as cheap as before (one static committed symlink, nothing to run just to browse the repo), while isolating the part the resolve script actually mutates (`.theme-resolved/`) from anything git tracks — pinning locally never leaves a dirty tracked path in `git status`. `.gitignore` gains `/workloads/*/src/.theme-resolved/` (a wildcard already has precedent in this file via `*.tfstate*`).

`resolve-theme.sh` is wired into `.mise.toml`'s `blog-build`/`blog-serve` tasks (as the new first step, before `generate-module-redirects.sh` and `zola build`/`serve`) and into `blog-pages.yml`'s CI build job (a new step calling it directly, since that job doesn't go through `mise`).

### 4. Short redirect pages: `noisypigeon.com/templates/zola-site/vX.Y.Z`

`generate-module-redirects.sh`'s existing tag loop is shaped for 4-segment `prefix/provider/module/vX.Y.Z` tags and doesn't fit zola-site's flat 3-segment `templates/zola-site/vX.Y.Z` shape, so a second, parallel loop was added rather than contorting the existing regex — the same choice `module-release.yml` already made for zola-site's release track (ADR-0113 §1), kept consistent here. It writes one `.md` file per `templates/zola-site/v*` tag into a new `content/theme-versions/` directory (gitignored except a hand-authored `_index.md`, mirroring `content/modules/`'s exact pattern), each setting `path = "templates/<name>/v<version>"` (the same content-path-override trick `content/modules/*.md` already uses) and `template = "theme-redirect.html"`.

`theme-redirect.html` (new, `workloads/blog/src/templates/`, workload-specific — not part of the generic theme, matching exactly why `module-redirect.html` already lives there instead of in `templates/zola-site`) renders a real `<meta http-equiv="refresh">` to the tag's GitHub Release page, plus a visible fallback link. This differs deliberately from `module-redirect.html`, which has no auto-redirect at all — that page exists for `terraform init`'s `<meta name="terraform-get">` discovery protocol, with the human fallback link being merely passive, since a human visiting a Terraform module source URL is inspecting, not trying to get somewhere. A theme-version URL has nothing for a program to consume, so for a human visiting it the only sensible behavior is to actually land them on the real content.

## Consequences

- `workloads/blog/src` can now specify a `templates/zola-site` version; it currently specifies `"main"`, preserving ADR-0112's live-tracking design exactly — the mechanism exists so it (or a future `workloads/<name>/src` consumer) *can* pin independently when needed, not because anything needs to today.
- `resolve-theme.sh` itself is not covered by ADR-0113's content-change glob (`^templates/zola-site/(templates/|static/|theme\.toml$)`), so a future edit to the script won't bump a theme release on its own. Acceptable for now; revisit the glob if `resolve-theme.sh` ever needs its own real release discipline independent of the theme content it resolves.
- The short redirect pages are purely a human/documentation convenience — they carry zero build-time meaning and cannot be fetched by any tool the way the Terraform module pages can.

## Out of scope

- No change to how `templates/terraform`'s own redirect pages or discovery logic work — the new loop is additive and parallel.
- `workloads/blog/src` is not actually pinned to anything by this ADR — only given the ability to be.
