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

## Consuming

A consuming site needs a symlink at `themes/<name>` pointing back at this
directory (Zola requires `theme = "<name>"` in `config.toml` to resolve to a
real `<site_root>/themes/<name>/` directory — it has no mechanism for an
arbitrary/configurable theme path), plus that same `theme = "<name>"` line
in its own `config.toml`. `workloads/blog/src` does this:

```
workloads/blog/src/themes/zola-site -> ../../../../templates/zola-site
```

```toml
# workloads/blog/src/config.toml
theme = "zola-site"
```

A future `workloads/<other>/src` site repeats the same pattern, adjusting
the symlink's relative-depth prefix for its own nesting depth under the
repo root.

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
  Terraform-module redirect pages, which has no business being part of a
  generic site theme.

## Versioning

None yet — see ADR-0112's Out of scope section.
