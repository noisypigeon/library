# DEV-0112: extract a reusable `templates/zola-site` theme from the blog

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

`workloads/blog/src` is a Zola site for the personal blog at `noisypigeon.com` (ADR-0067, ADR-0091). A survey of its `templates/` and `static/assets/css/` found that almost everything in them is already generic and config/content-driven, with no hardcoded noisypigeon identity strings — confirmed by grepping every template file. Only two fragments were actually site-specific: a hardcoded footer initial (`"WG"`, for Willow Graysen) in `base.html`, and a hardcoded `sameAs` URL array in `index.html`'s `Person` JSON-LD (ADR-0111), which that ADR had explicitly chosen to hardcode rather than derive from `config.extra.nav`, since `nav` also contains a relative, non-`http` "About" link. One template, `module-redirect.html`, is genuinely workload-specific — it exists only to serve ADR-0109's Terraform-module redirect pages and has no place in a generic site engine.

In other words, the blog's engine was already, almost by accident, a reusable site template — it just wasn't packaged as one. `templates/` is an established top-level convention in this repo (ADR-0110, `templates/terraform/`), open to "other versioned/reusable scaffolding kinds later." This ADR adds a second occupant: a reusable Zola theme, so that a future `workloads/<name>/src` site can reuse this engine instead of recreating it, and so `workloads/blog/src` itself shrinks down to just its content plus the few things that must remain site-specific.

## Decision

### 1. Package the generic engine as a Zola theme

Zola supports `theme = "<name>"` in `config.toml`, which makes Zola look for `<site_root>/themes/<name>/` — a `theme.toml` manifest plus `templates/`/`static/` directories. This location is not configurable; it must be literally there. A site's own `templates/`/`static/` take precedence over the theme's, per file; everything else falls back to the theme. This is exactly the override relationship `workloads/blog/src` needs for `module-redirect.html` to keep working unmodified.

`templates/zola-site` is the new canonical, directly-editable theme source (`theme.toml`, `templates/`, `static/assets/css/main.css`), named `zola-site` to match its directory.

### 2. Consume it via a committed relative symlink, not a vendored copy

`workloads/blog/src/themes/zola-site` is a **committed relative symlink** → `../../../../templates/zola-site` (4 levels up from `workloads/blog/src/themes/`: `themes`→`src`→`blog`→`workloads`→repo root). A copy/vendor step was rejected: it would reintroduce the exact drift problem this ADR exists to avoid — a theme edit wouldn't take effect until someone remembered to re-run the copy. The symlink gives true live invocation: edits to `templates/zola-site` apply on the next `zola build`/`serve`, no extra step. Symlinks survive `git`/`actions/checkout@v4` on the `ubuntu-latest` runner the Pages deploy workflow uses; Zola resolves the symlink at build time and writes fully-resolved static output into `workloads/blog/src/public/`, so the deployed artifact itself contains no symlinks. `workloads/blog/src/config.toml` gets the one line that actually activates the mechanism: `theme = "zola-site"`.

Any future `workloads/<other>/src` site adopting this theme repeats the same pattern — its own `themes/zola-site` symlink, with the relative-depth prefix adjusted for its own nesting under the repo root.

### 3. File-by-file migration

Moved verbatim into `templates/zola-site/templates/`: `header.html`, `post.html`, `page.html`, `changelog.html`, `posts_feed.xml`, `tags/list.html`, `tags/single.html`. Moved verbatim into `templates/zola-site/static/assets/css/`: `main.css` (grep-confirmed clean of brand strings; its `color-theme-gameboy font-theme-ibm-plex` body classes are a default aesthetic choice, not a personal-identity artifact).

Moved with a small generalizing edit:
- `base.html` — the footer's hardcoded `WG` becomes `{{ config.title }}`, consistent with every other identity string already in the file.
- `index.html` — the `Person` JSON-LD's hardcoded three-URL `sameAs` array becomes a loop over `config.extra.nav`, filtered with Tera's `is starting_with("http")` test to just the absolute-URL entries (accumulated into a fresh array via `concat` rather than filtering mid-loop, to sidestep a trailing-comma defect that a naive `loop.last`-on-the-unfiltered-loop approach would hit). This is exactly what ADR-0111 considered and skipped — doing it now removes the last reason `index.html` couldn't be generic.

Stayed behind, unchanged, in `workloads/blog/src/templates/`: `module-redirect.html` only — it is workload-specific, not engine.

Stayed behind, unchanged, in `workloads/blog/src/static/`: `CNAME`, `manifest.json`, `robots.txt`, `assets/images/site/*` (avatar, social_preview, 5 derived icons), `assets/images/posts/<slug>/*`. Zola copies `static/` verbatim — it is never run through Tera — so none of this can be made generic with config substitution the way `.html` templates can; each consuming site must supply its own.

### 4. Widen the two blog-automation path filters

`.github/workflows/blog-pages.yml`'s push-trigger `paths` and `.github/workflows/module-release.yml`'s blog-change detection (`grep '^workloads/blog/src/'`, feeding ADR-0107's changelog/digest automation) both now also match `templates/zola-site/**`, since a theme-only edit changes the blog's build output exactly as much as a `workloads/blog/src/` edit does, and today the blog is the theme's only consumer.

## Consequences

- `workloads/blog/src/templates/` now contains exactly one file (`module-redirect.html`) — the only thing about the blog's templating that is genuinely site-specific rather than engine.
- `templates/` now has a second occupant alongside `templates/terraform/`, with `templates/zola-site/README.md` documenting what it provides and what a consuming site must still supply itself, mirroring `templates/terraform/README.md`'s spirit.
- The two path-filter widenings (§4) assume `templates/zola-site` has exactly one consumer. The moment a second `workloads/<name>/src` site adopts this theme, a theme-only PR will be mis-attributed as a blog-only change by both workflows — revisit both when that happens.

## Out of scope

- No versioning/release process for `templates/zola-site`, unlike `templates/terraform` (ADR-0110). This is a deliberate boundary, not a gap: the symlink is designed for live, unversioned consumption by its one current consumer, and a version-pinning scheme is only a real question once a second, independently-releasing consumer exists. Not filed via `mise run adr-issue` — there is no concrete deferred action today, the same precedent as ADR-0110's own "no other `templates/<kind>` sibling is designed... only the naming convention is opened up."
- No second consumer of `templates/zola-site` is added by this ADR — only the theme and the convention for consuming it.

## Verification

- `readlink workloads/blog/src/themes/zola-site` → `../../../../templates/zola-site`; `ls workloads/blog/src/themes/zola-site/theme.toml` resolves.
- `mise run blog-build` succeeds with no Zola errors about missing templates.
- The built homepage's `Person` JSON-LD `sameAs` array reproduces the same 3 URLs, same order, no trailing comma, as before the change.
- The footer renders the site title in place of `WG`; favicons/manifest/CSS still load (confirming the theme/site `static/` merge).
- `git ls-files -s workloads/blog/src/themes/zola-site` reports mode `120000` — the symlink itself is what's tracked, not a resolved copy.
