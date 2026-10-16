# Zola site theme

A reusable [Zola](https://www.getzola.org/) theme — the shared engine behind
the `noisypigeon.com` and `noisypigeon.garden` sites, and any future
Zola site in this family. Extracted from the blog by
[ADR-0112](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0112-extract-reusable-zola-site-template.md), once
almost everything in the blog's own `templates/` and `static/assets/css/`
turned out to already be generic/config-driven, with no hardcoded
noisypigeon identity strings. It sat under the `templates/<kind>/`
convention [ADR-0110](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0110-move-modules-to-templates-terraform.md)
opened up until LIB-0002 flattened this repo's roots, making it a top-level
`zola-site/` beside `terraform/`.

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
- [`resolve-theme.sh`](resolve-theme.sh) (ADR-0114, ADR-0139) — resolves a
  consuming site's `[extra].theme_version` directly into `themes/<name>`,
  run as a pre-build step. See Consuming and Versioning below.

## Consuming

Zola requires `theme = "<name>"` in `config.toml` to resolve to a real
`<site_root>/themes/<name>/` directory — it has no mechanism for an
arbitrary/configurable theme path. Rather than committing anything at that
path, a consuming site runs [`resolve-theme.sh`](resolve-theme.sh)
(ADR-0114, ADR-0139) before every build/serve, which reads that site's own
`[extra].theme_version` and materializes `themes/<name>` directly — nothing
under `themes/<name>` is ever tracked by git (each site gitignores its own
`themes/<name>`). `noisypigeon.com` does this:

```toml
# noisypigeon.com's config.toml
theme = "zola-site"

[extra]
theme_version = "main"
```

```toml
# .mise.toml, as the first steps of this site's build/serve tasks
"../../fetch-lib.sh"
'"${LIB_SRC:-$(git rev-parse --show-toplevel)/.lib-src}/zola-site/resolve-theme.sh"'
```

Since ADR-0154 this theme lives in its own repo, so a consuming site fetches a
clone of it first (`fetch-lib.sh`, which lives in the consuming repo)
and runs `resolve-theme.sh` out of that clone. The script resolves everything
relative to its own location, so it needs no argument or environment variable
to find the templates root — wherever that clone is, is the root.

`resolve-theme.sh` reads `[extra].theme_version` and either symlinks
`themes/<name>` straight at this directory inside that clone (`"main"`, the
default — the latest code as of the clone's last fetch) or materializes a
specific tagged version into it via `git archive` (any other value — see
Versioning below). A future consuming site repeats the same pattern with no
path adjustment at all.

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
  the same filename — e.g. `pigeon.dev`'s own `templates/module-redirect.html`
  for [ADR-0109](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0109-short-module-source-urls-via-blog-redirect.md)'s
  Terraform-module redirect pages, or `theme-redirect.html` for this theme's
  own version-redirect pages (ADR-0114) — both have no business being part of
  a generic site theme.

## Versioning

Releases are tagged on this repo's `main` as `zola-site/vX.Y.Z`
([ADR-0113](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0113-version-templates-zola-site.md),
relocated to `noisypigeon/pigeon.dev` by
[ADR-0154](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0154-hoist-templates-to-pigeon-dev-repo.md)
and re-cut here without the `templates/` prefix by LIB-0002). A
consuming site pins to one by setting `[extra].theme_version = "v1.0.0"` (the
`v` prefix is optional) instead of the default `"main"` — `resolve-theme.sh`
(ADR-0114, ADR-0139) then materializes that exact tagged tree directly into
`themes/<name>` via `git archive`, instead of symlinking live. The tag has to
exist in the clone the script is running out of, which is what makes that
clone's `--tags` fetch load-bearing. Note that since ADR-0154 moved this theme
into its own repo, resolving a theme at all involves a network fetch, where
previously it read only the consuming repo's own history.

Each tag also gets a short, human-facing redirect page at
`noisypigeon.garden/templates/zola-site/vX.Y.Z` (ADR-0114; on `pigeon.dev`
until LIB-0009), alongside `terraform/`'s
`noisypigeon.garden/terraform/...` pages — generated by
the same `generate-module-redirects.sh` script, as a parallel loop (the tag
shape doesn't fit that script's provider/module pattern). **Unlike** the
Terraform pages, this is a plain redirect to the tag's GitHub Release page,
not a fetchable build input: Zola has no HTTP module-source/go-getter-style
discovery protocol for themes, so nothing can resolve this URL into content
the way `terraform init` resolves a module source URL. It exists purely so a
version mentioned in a changelog or commit message has somewhere short and
memorable to point a human at.

Both of this theme's consumers — the `noisypigeon.com` and `noisypigeon.garden`
sites, each now its own repo — tracked live `main` via
`theme_version = "main"` for a long time, exactly as ADR-0112 designed it.
LIB-0001 invariant 2 reverses that default: a spoke pins a version. The
mechanism exists so either
(or any future consumer, in any repo) *can* run an independent version when
needed, not because it needs one now.
