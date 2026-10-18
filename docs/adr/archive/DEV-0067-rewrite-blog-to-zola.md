# DEV-0067: rewrite the `noisypigeon.github.io` blog from Jekyll to Zola, as `service/blog`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-27.
- **Status**: Accepted.

## Context

`noisypigeon.github.io` (github.com/noisypigeon/noisypigeon.github.io) is a
separate, public repo: a personal blog, currently a hand-rolled Jekyll site
(no theme gem) with a CSS purged/adapted from Pika's "gameboy" theme, served
via GitHub Pages at the custom domain `noisypigeon.com`. This ADR moves its
*engine* into this monorepo as `service/blog/`, rewritten from Jekyll/Ruby to
Zola/Rust — continuing the same monorepo-consolidation direction ADR-0037 and
ADR-0052 established for `pigeon-tf`/`pigeon-do`. **The site's rendered
HTML/CSS is explicitly frozen** — this is an engine swap only, not a redesign.

Researched directly from the live repo (cloned read-only), confirmed rather
than assumed:

- **Content**: `_config.yml` (title/description, `permalink: /posts/:slug/`,
  `markdown: kramdown` with `input: GFM`, `syntax_highlighter: rouge`,
  `jekyll-feed` plugin emitting an Atom feed at a custom path,
  `feed: {path: posts_feed}`), four Liquid layouts
  (`default`/`home`/`page`/`post`), one include (`header.html`), a `nav`
  collection (`output: false`, four static links: about/github/linkedin/
  unsplash, ordered via `nav_order`), a `pages` collection (`output: true`:
  `index.md` at `/`, `about.md` at `/pages/about/`, `names.md` at
  `/pages/names/`), and ~60 `_posts/YYYY-MM-DD-slug.md` files with
  `title`/`date`/`description` front matter.
- **Assets**: `assets/css/main.css` (a single purged/minified stylesheet,
  hand-authored, no build step) and `assets/images/**` — plain static files,
  no Sass/asset pipeline.
- **No syntax-highlighting CSS exists today.** Grepped `main.css` for
  `.highlight`/`.language-*` rules — none. Rouge's `<span>` classes render in
  the HTML but are entirely unstyled; fenced code blocks currently appear as
  plain monospace text with no color.
- **Deploy**: `.github/workflows/pages.yml` already uses the "modern"
  `actions/configure-pages` → `bundle exec jekyll build` →
  `actions/upload-pages-artifact` → `actions/deploy-pages` shape (not a
  `gh-pages` branch). A root `CNAME` file (contents: `noisypigeon.com`) is
  committed and carried into the build output.
- **Toolchain**: `Gemfile` pins `jekyll ~> 4.3`, `jekyll-feed`, `webrick`;
  no other plugins.
- This repo (`pigeon`) has no existing GitHub Pages usage in any workflow
  today (`module-docs.yml`/`module-release.yml` don't touch Pages) — enabling
  Pages here is new, not a reconfiguration of something already wired up.

## Decision

### Location & scope

New content lives at `service/blog/`, a Zola project root, added as a new
sibling under `service/` alongside `service/pigeon-cli/` (ADR-0008/ADR-0036's
one-folder-per-service precedent, both now archived in
`noisypigeon/pigeon-cli`). It is **not** a Cargo crate — no
`[[bin]]`/`[[test]]` entries, just a Zola site.

Content (posts' Markdown, CSS, images) is **copied in fresh**, not merged via
`git filter-repo` the way ADR-0037/ADR-0052 preserved history for
`pigeon-tf`/`pigeon-do`. Those were mechanical path-renames of otherwise
unchanged content; this is a full engine rewrite (Liquid → Tera, YAML → TOML
front matter, Ruby/Jekyll build → Zola build), so a history-preserving merge
wouldn't preserve much meaningful blame anyway. The standalone
`noisypigeon.github.io` repo is left untouched, keeping its full history as
the historical record — the same "repo stays, history isn't reconciled"
precedent ADR-0037/ADR-0052 set for `pigeon-tf`/`pigeon-do`.

### Directory / concept mapping (Jekyll → Zola)

| Jekyll | Zola | Notes |
|---|---|---|
| `_config.yml` | `config.toml` | `title`/`description`/`base_url` ported directly |
| `_layouts/default.html` | `templates/base.html` | Liquid → Tera; same `<head>`/OG tags, same body-class logic |
| `_layouts/home.html` | `templates/index.html` | pulls posts via `get_section(path="posts/_index.md")`, groups by year exactly like the current `{% assign post_year = ... %}` loop |
| `_layouts/page.html` | `templates/page.html` | used by `content/pages/*.md` |
| `_layouts/post.html` | `templates/post.html` | used by `content/posts/*.md`, selected via `page_template = "post.html"` on `content/posts/_index.md` |
| `_includes/header.html` | `templates/header.html` | pulled in via Tera `{% include "header.html" %}` |
| `_nav/*.md` (4 files, `output: false`) | `[[extra.nav]]` in `config.toml` | static link data, not renderable content — moves out of `content/` entirely |
| `_pages/index.md` | `content/_index.md` | site-root section; `template = "index.html"` |
| `_pages/about.md`, `_pages/names.md` | `content/pages/about.md`, `content/pages/names.md` | Zola's default page URL (`<section-path>/<slug>/`) already reproduces `/pages/about/` and `/pages/names/` with no `path =` override needed |
| `_posts/YYYY-MM-DD-slug.md` (~60 files) | `content/posts/slug.md` | mechanical, same pattern for all ~60: strip the leading `YYYY-MM-DD-` filename prefix (Zola takes the slug straight from the filename, it doesn't parse date-prefixed filenames), add the date as an explicit `date =` front-matter field, front matter YAML → TOML with values unchanged |
| `assets/**` | `static/assets/**` | byte-identical copy; CSS/images keep their exact existing URLs |
| `CNAME` | `static/CNAME` | copied verbatim into the build output root, like any other static file |
| `Gemfile`/`Gemfile.lock`, Ruby/Bundler | *(removed)* | replaced by `zola` pinned in root `.mise.toml` |

`content/pages/_index.md` and `content/posts/_index.md` both get
`render = false` — neither `/pages/` nor `/posts/` is a real page today, and
`render = false` on a section suppresses its own index while still rendering
the pages inside it.

### Syntax highlighting: deliberately left off

Zola's `highlight_code` defaults to `false`. Explicitly leaving it off —
rather than opting into Zola's built-in syntect-based highlighting, which
would require picking a `[markdown.highlighting]` theme — is what actually
satisfies "the UI stays exactly the same": since today's fenced code blocks
already render unstyled (see Context), turning highlighting on would be a
visible, unrequested change, not parity.

### Feed

Current: `jekyll-feed` emits an Atom feed at `/posts_feed`. Zola equivalent:
`generate_feeds = true` on `content/posts/_index.md`, plus a top-level
`feed_filenames = ["posts_feed.xml"]` and a custom `templates/posts_feed.xml`
Atom template. Confirmed during implementation, two constraints push the
final URL to `/posts/posts_feed.xml` rather than the original `/posts_feed`:
Zola's template loader only discovers feed templates with a recognized
extension (an extensionless custom feed filename silently fails to
resolve), and a section-scoped feed always renders under that section's own
path, not the site root. Close, not exact, parity; accepted, since feed
markup isn't part of the frozen UI/CSS, and the generated XML itself
wouldn't have been byte-identical either way (different Atom template
internals).

### Toolchain / mise

Root `.mise.toml` `[tools]` gains `zola = "0.23.6"` (current stable). New
tasks, scoped the same way ADR-0052's `infra-*` tasks are:

```toml
[tasks.blog-build]
dir = "service/blog"
run = "zola build"

[tasks.blog-serve]
dir = "service/blog"
run = "zola serve"
```

Not wired into `mise run ci` — matching the existing precedent that the
Terraform `fmt-terraform`/`fmt-check-terraform` tasks also sit outside `ci`
(each stack gets its own gate; `ci` stays Rust-crate-scoped).

### CI/deploy workflow

New `.github/workflows/blog-pages.yml` in this repo, `paths:
["service/blog/**"]`-filtered, triggered on push to `main` plus
`workflow_dispatch`. Same `permissions`/`concurrency`/
`environment: github-pages` shape as the current
`noisypigeon.github.io` workflow. Build step: install the pinned Zola
binary, run `zola build` from `service/blog` (output `service/blog/public`)
in place of the Ruby/`bundle exec jekyll build` step; `actions/configure-
pages`, `actions/upload-pages-artifact`, `actions/deploy-pages` stay
unchanged. No `--baseurl` override needed — it's an apex custom domain, so
`base_path` is always empty.

### GitHub Pages hosting cutover — manual, not automated by this ADR

1. In the `noisypigeon/pigeon` repo's Settings → Pages, set Source to
   "GitHub Actions".
2. Remove the custom domain from `noisypigeon.github.io`'s Pages settings
   first — GitHub only lets one repo per account claim a verified custom
   domain at a time.
3. Set custom domain `noisypigeon.com` on the `pigeon` repo's Pages settings,
   enable "Enforce HTTPS" once the certificate issues.
4. Merge/deploy the new workflow so the Pages site is populated before or at
   the same moment as the domain switch, to minimize downtime.

Same precedent as ADR-0052: the code (everything in Decision above) is
implemented as part of this ADR; flipping a live public domain's hosting is
executed by the user via GitHub's UI, not by this agent or by Terraform.

### DNS — no changes required

GitHub Pages' custom-domain-to-repo mapping is account-level, configured
through each repo's Settings → Pages plus the `CNAME` file in its build
output — it is **independent of what the DNS record actually points at**.
The existing apex + `www` CNAME records in
`terraform/infrastructure/cloudflare/global/noisypigeon.com/github/cname.tf`
already target `noisypigeon.github.io`, which remains the correct DNS target
no matter which repository backs the Pages site — GitHub's edge routes by
Host header to whichever repo currently has that domain configured, not by
DNS target. Domain verification is also account-level (already verified for
the `noisypigeon` account via the existing site), so reassigning the domain
to a different repo under the same account needs no new TXT verification
record either.

**Conclusion: `terraform/infrastructure/cloudflare/global/noisypigeon.com/github/cname.tf`
is untouched by this ADR.** Called out explicitly since a repo migration
easily reads as implying a DNS migration, and here it doesn't.

## Consequences

- `service/blog/` is a new, non-Rust service folder — `mise run ci` doesn't
  cover it; validating it locally means running `mise run blog-build`/
  `blog-serve` directly, the same separate-gate-per-stack pattern the
  Terraform tasks already established.
- The standalone `noisypigeon.github.io` repo keeps existing but goes
  dormant once the cutover happens; its own `pages.yml` workflow should be
  disabled or the repo's Pages settings cleared by the user as part of the
  manual cutover (see above), or both sites would compete to publish to the
  same domain. Not managed by this ADR.
- ~60 posts' individual git blame/history doesn't carry over into
  `service/blog` (see Location & scope); it remains intact in the standalone
  repo.
- Root `/CHANGELOG.md` gains a new `[blog]` tag prefix (alongside the
  existing `[pigeon-cli]`) for this new service, applying ADR-0050's (now
  archived in `noisypigeon/pigeon-cli`) per-service tagging convention to a
  service that's neither the Rust crate
  nor a Terraform module.
- This repo's root `CLAUDE.md` gains a one-line description of
  `service/blog/`'s stack, alongside its existing `pigeon-cli`/`terraform/`
  descriptions.

## Out of scope

- Any visual/CSS/theme change — explicitly frozen by this ADR's premise.
- Executing the manual GitHub Pages settings cutover, and disabling or
  archiving the old repo's workflow — performed by the user, as above.
- Deciding the long-term fate (archive/delete/repurpose) of the standalone
  `noisypigeon.github.io` repo.
- Adding themed syntax highlighting for code blocks — today's blog has none;
  if wanted later, it's a follow-up, not something to smuggle into this
  rewrite.
- Any content changes (new posts, edited copy) beyond the mechanical format
  port described above.
