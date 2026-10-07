# Zola site theme

A reusable [Zola](https://www.getzola.org/) theme — the shared engine behind
`workloads/blog/src` and any future `workloads/<name>/src` site in this repo.
Extracted from the blog by
[ADR-0112](../../docs/adr/0112-extract-reusable-zola-site-template.md), once
almost everything in the blog's own `templates/` and `static/assets/css/`
turned out to already be generic/config-driven, with no hardcoded
noisypigeon identity strings. Follows the `templates/<kind>/` convention
[ADR-0110](../../docs/adr/0110-move-modules-to-templates-terraform.md) opened
up with `templates/terraform/`.

This directory is a Zola theme per Zola's own
[themes](https://www.getzola.org/documentation/themes/) convention: a
`theme.toml` manifest plus `templates/`/`static/` directories that a
consuming site's own `templates/`/`static/` override on a per-file basis.
It is never built standalone — only ever consumed as a theme by a real Zola
site.

## What this provides

- `templates/base.html` — SEO-ready base layout: canonical URLs, OG/Twitter
  Card meta, favicon/manifest links, KaTeX math rendering, Bunny Fonts.
- `templates/header.html` — site header (avatar, title, nav), fully driven
  by `config.title`/`config.extra.avatar`/`config.extra.nav`.
- `templates/index.html` — homepage: year-grouped post listing, plus
  `WebSite`/`Person` JSON-LD (the `Person`'s `sameAs` is derived from
  `config.extra.nav` entries whose `link` starts with `http`, not
  hardcoded).
- `templates/post.html` — single post: `BlogPosting` JSON-LD,
  `og:type=article`, per-post `og:image` with a site-wide fallback.
- `templates/page.html` — generic standalone content page.
- `templates/changelog.html` — year-grouped changelog section listing.
- `templates/posts_feed.xml` — Atom feed.
- `templates/tags/{list,single}.html` — tags taxonomy index + per-tag
  listing.
- `static/assets/css/main.css` — the default stylesheet (the
  `color-theme-gameboy font-theme-ibm-plex` look is a default aesthetic
  choice, not a personal-identity artifact).
- [`resolve-theme.sh`](resolve-theme.sh) (ADR-0114) — resolves a consuming
  site's `[extra].theme_version` into `.theme-resolved/<name>`, run as a
  pre-build step. See Consuming and Versioning below.

## Consuming

A consuming site needs a symlink at `themes/<name>` pointing back at this
directory (Zola requires `theme = "<name>"` in `config.toml` to resolve to a
real `<site_root>/themes/<name>/` directory — it has no mechanism for an
arbitrary/configurable theme path), plus that same `theme = "<name>"` line
in its own `config.toml`.

Rather than pointing that symlink directly at this directory, point it at a
gitignored indirection layer, `.theme-resolved/<name>`, and run
[`resolve-theme.sh`](resolve-theme.sh) (ADR-0114) before every build/serve to
populate it — this is what lets a site pin a version (below) without ever
leaving a dirty tracked path in `git status`. `workloads/blog/src` does
this:

```
workloads/blog/src/themes/zola-site -> ../.theme-resolved/zola-site
```

```toml
# workloads/blog/src/config.toml
theme = "zola-site"

[extra]
theme_version = "main"
```

```toml
# .mise.toml, as the first step of this site's build/serve tasks
"../../../templates/zola-site/resolve-theme.sh"
```

`resolve-theme.sh` reads `[extra].theme_version` and either symlinks
`.theme-resolved/<name>` straight at this directory (`"main"`, the default —
always the latest code, zero extra cost) or materializes a specific tagged
version into it via `git archive` (any other value — see Versioning below).
A future `workloads/<other>/src` site repeats the same pattern, adjusting
only the `resolve-theme.sh` relative-path prefix for its own nesting depth
under the repo root.

## What a consuming site must still supply itself

- `content/` — all actual site content.
- `config.toml` populated with `title`, `description`, `base_url`,
  `extra.avatar`, `extra.social_preview`, `extra.nav`, and a `tags`
  taxonomy if it wants one.
- Site-specific `static/` assets this theme deliberately does not provide —
  Zola copies `static/` verbatim (no templating), so none of these can be
  made generic: `CNAME`, `manifest.json`, `robots.txt`, favicon/icon files,
  the social-preview image, and any per-post images.
- Any workload-specific template override, placed directly in the site's
  own `templates/` where it takes precedence over this theme's version of
  the same filename — e.g. `workloads/blog/src/templates/module-redirect.html`
  for [ADR-0109](../../docs/adr/0109-short-module-source-urls-via-blog-redirect.md)'s
  Terraform-module redirect pages, or `theme-redirect.html` for this theme's
  own version-redirect pages (ADR-0114) — both have no business being part of
  a generic site theme.

## Versioning

Releases are tagged on `noisypigeon`'s `main` as `templates/zola-site/vX.Y.Z`
([ADR-0113](../../docs/adr/0113-version-templates-zola-site.md)). A
consuming site pins to one by setting `[extra].theme_version = "v1.0.0"` (the
`v` prefix is optional) instead of the default `"main"` — `resolve-theme.sh`
(ADR-0114) then materializes that exact tagged tree into
`.theme-resolved/<name>` via `git archive`, instead of symlinking live. This
requires the tag to exist in the consuming clone's local git history (a full
clone, same assumption `templates/terraform/README.md`'s "Consuming" section
already makes) — there is no network fetch involved.

Each tag also gets a short, human-facing redirect page at
`pigeon.dev/templates/zola-site/vX.Y.Z` (ADR-0114), mirroring
`templates/terraform/`'s `pigeon.dev/modules/...` pages — generated by
the same `generate-module-redirects.sh` script, as a parallel loop (the tag
shape doesn't fit that script's provider/module pattern). **Unlike** the
Terraform pages, this is a plain redirect to the tag's GitHub Release page,
not a fetchable build input: Zola has no HTTP module-source/go-getter-style
discovery protocol for themes, so nothing can resolve this URL into content
the way `terraform init` resolves a module source URL. It exists purely so a
version mentioned in a changelog or commit message has somewhere short and
memorable to point a human at.

`workloads/blog/src`, this theme's current first-party consumer, does not
pin to a tag today — its `theme_version` is `"main"`, deliberately tracking
live `main` with no extra step, exactly as ADR-0112 designed it. The pin
mechanism exists so it (or any future `workloads/<name>/src` consumer) *can*
run an independent version when needed, not because it needs one now.
