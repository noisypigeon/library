# DEV-0111: improve blog SEO — canonical URLs, structured data, per-post social images, tags, icons

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

An audit of `workloads/blog/src` (the Zola site behind `noisypigeon.com`) found the blog's SEO surface was thin:

- No `robots.txt` in source at all. A `public/robots.txt` existed locally, but `public/` is gitignored and `zola build` doesn't generate `robots.txt` on its own — the deployed site had none.
- No `<link rel="canonical">` anywhere.
- No Twitter Card meta tags.
- No structured data (no JSON-LD `Article`/`BlogPosting`/`Person`/`WebSite` markup).
- `og:image` was one hardcoded sitewide asset (`social_preview.png`), never overridden per post, even though 20 of the 53 posts already have their own image directory under `static/assets/images/posts/<slug>/` that content references inline.
- `og:type` was hardcoded `"website"` everywhere — posts were never marked `"article"`, and there was no `article:published_time`.
- Favicon/apple-touch-icon both pointed at a single 239×239 PNG with no `sizes`, no manifest, no icon set.
- No tags/taxonomy content model at all.
- 5 pages/posts (`about.md`, `lineage.md`, and the 3 auto-generated changelog digest posts) had no `description` front matter, falling back to the generic site description.
- The sitemap (Zola's default) had `<lastmod>` missing on the ~26 Terraform module-redirect pages (`content/modules/*.md`, ADR-0109) because they have no `date` field.

**Research confirmed, verbatim, before planning anything:**

- Zola version is `0.23.6` (pinned in `.mise.toml`). Taxonomies are configured as `taxonomies = [ { name = "tags", feed = false } ]`; per-page terms via a `[taxonomies]` front-matter table.
- Zola has no `in_sitemap` field; the correct mechanism to exclude a page from the sitemap/search/feeds while keeping it reachable at its direct URL is the `hidden = true` front-matter field — exactly what the module-redirect pages need (`terraform init` still resolves them via their `<meta name="terraform-get">` tag; ADR-0109).
- `<lastmod>` is computed from `page.meta.updated`, falling back to `page.meta.date`; it's omitted when neither is present. Sections, static pages (`content/pages/*.md`), and taxonomy list/term pages have no `date` concept at all in this site and never did — that's unrelated to the module-redirect gap and isn't something to fabricate a date for.
- `sips` (macOS built-in) is available for icon resizing; `imagemagick`/`convert` are not installed.
- `templates/index.html` and `templates/changelog.html` already share an identical year-grouped post-listing markup/CSS (`t-list-of-posts site-list-of-posts h-feed`, `post-list-year-h2`), reusable as-is for a new tag-listing template.
- `templates/base.html` already has a reusable `extra_head` block, and `og_title`/`og_description`/`og_url` are already per-template-overridden blocks following a repeated `{% if page.description %}...{% else %}...{% endif %}` house style — new blocks below follow the same convention.
- Tera's `default()` filter only substitutes when a value is *undefined*, not when it's explicit `null` — which is what Zola sets `page.updated` to when a post doesn't set it. Discovered live when the first build attempt failed (`error: Invalid value: expected a string or integer, got none` at the `date` filter); fixed by using `{% if page.updated %}...{% else %}...{% endif %}` instead of `| default(value=page.date)`.

## Decision

### 1. `config.toml`

Added a `tags` taxonomy:

```toml
taxonomies = [
  { name = "tags", feed = false },
]
```

### 2. `templates/base.html`

- Added `<link rel="canonical">` as a new overridable `canonical` block.
- Replaced the single favicon/apple-touch-icon lines with a real sized-icon set (`favicon-16x16.png`, `favicon-32x32.png`, `apple-touch-icon.png`) plus `<link rel="manifest" href="/manifest.json">`.
- Made `og:type` and `og:image` overridable blocks (defaulting to `"website"` and the sitewide `social_preview.png`, respectively). Added an `og_image_extra` block carrying `og:image:width`/`height` (1188×670) — only meaningful for the sitewide fallback, since per-post images under `static/` have no dimensions Zola can introspect; posts override this block to empty rather than guess.
- Added Twitter Card tags (`twitter:card=summary_large_image`, `twitter:title`, `twitter:description`, `twitter:image`) as new blocks mirroring the existing `og_*` pattern.

### 3. `templates/post.html`

- `canonical` → `page.permalink`; `og_type` → `"article"`.
- `og_image`/`twitter_image` → `page.extra.og_image` when set, else the sitewide fallback; `og_image_extra` → empty.
- `twitter_title`/`twitter_description` mirror the existing `og_title`/`og_description` overrides.
- New `extra_head` block: `article:published_time`/`article:modified_time` meta tags, and a `BlogPosting` JSON-LD block (headline, description, `datePublished`/`dateModified`, url, image, author/publisher as `Person`). `modified_date` is computed via `{% if page.updated %}...{% else %}{{ page.date }}{% endif %}` (see the Tera `default()` gotcha above).

### 4. `templates/page.html`, `templates/index.html`, `templates/changelog.html`

Added `canonical`/`twitter_title`/`twitter_description` overrides mirroring each template's existing `og_*` pattern. `index.html` additionally gained an `extra_head` block with two JSON-LD blocks — `WebSite` and `Person` (name, url, avatar image, `sameAs`: GitHub/LinkedIn/Unsplash, hardcoded rather than looped from `config.extra.nav` since that list also contains an internal, non-`http` "About" link).

### 5. `templates/module-redirect.html` + `generate-module-redirects.sh`

Added a `canonical` override, and added `hidden = true` to the front matter the generator writes for every module-redirect page. This excludes all ~26 of them from the sitemap/search/feeds (they were never meant to be crawled — they exist solely for `terraform init`'s HTTP module-source discovery) while keeping them reachable at their direct URL.

### 6. New `templates/tags/list.html` and `templates/tags/single.html`

`list.html` is a flat alphabetical list of tags with post counts. `single.html` reuses `index.html`'s exact year-grouped post-listing markup/CSS, iterating `term.pages`. No new CSS needed.

### 7. Tag vocabulary + backfill

Introduced 9 tags derived from the site's own bio ("Infra dev, data hoarder, mechanic-ish, photographer") plus genuinely recurring themes: `personal-essays` (22 posts), `career` (14), `software-engineering` (13), `hardware-and-builds` (8), `data-hoarding` (5), `travel` (5), `press-and-interviews` (4), `identity-and-transition` (3), `photography` (3) — no orphan tags. Applied to all 53 posts via a one-off script (fixed slug→tags mapping decided up front, no per-post judgment at run time; run once, then discarded — not committed). `content/changelog/` stays untagged — it's operational content, not editorial (ADR-0107 already split it out from `content/posts/` for the same reason).

The same script wrote `[extra]\nog_image = "/assets/images/posts/<slug>/<file>"` for the 20 posts that already have an image directory, picking the alphabetically-first file in each as a deterministic, mechanical choice.

### 8. Missing descriptions

Backfilled `description` front matter for all 5 gaps: hand-written one-liners for `content/pages/about.md` and `content/pages/lineage.md`; the existing `title` reused verbatim for the 3 auto-generated changelog digest posts. Also fixed `.github/workflows/module-release.yml`'s digest-generation step to always write (and keep in sync via the same `sed` that already recomputes `title`) a matching `description`, so this gap can't reopen on future auto-generated digests.

### 9. `static/robots.txt` (new)

```
User-agent: *
Allow: /

Sitemap: https://noisypigeon.com/sitemap.xml
```

### 10. Icon set + `manifest.json`

Generated a real sized-icon set from the existing `avatar.png` (239×239) via `sips` (no `imagemagick` installed, and none needed):

```bash
sips -z 16  16  avatar.png --out favicon-16x16.png
sips -z 32  32  avatar.png --out favicon-32x32.png
sips -z 180 180 avatar.png --out apple-touch-icon.png
sips -z 192 192 avatar.png --out icon-192.png
sips -z 512 512 avatar.png --out icon-512.png
```

The 192/512 icons upscale from the 239px source — an accepted quality tradeoff; no new higher-res source asset was in scope. Added `static/manifest.json` (name/short_name/description/theme_color/icons).

### 11. Sitemap

The `hidden = true` change in §5 removes the only pages that were missing `<lastmod>` for a fixable reason (module-redirect pages have no natural date). Static pages, section indices, and the new taxonomy pages still have no `<lastmod>` — that's unchanged from before this ADR and correct: they have no `date` concept, and fabricating one would be worse than omitting it.

`<priority>`/`<changefreq>` were deliberately **not** added — Google has stated publicly that both are ignored by its crawler since ~2020, and Zola's built-in sitemap template doesn't support either natively. Adding them would mean maintaining a hand-rolled sitemap template indefinitely for no demonstrated benefit.

## Consequences

- Every post now gets correct `og:type=article`, article timestamps, a `BlogPosting` JSON-LD block, and (for the 20 posts that have one) its own social-preview image instead of the generic one.
- The homepage carries `WebSite`/`Person` structured data, improving how search engines and social platforms represent the site and its author.
- The site now has a real favicon/icon set and `manifest.json` instead of one reused low-res PNG.
- All 53 posts are now browsable by topic via `/tags/`.
- `robots.txt` is finally part of the reproducible build output, not a stale local artifact.
- Future auto-generated changelog digest posts will always have a `description`.

## Out of scope

- A `favicon.ico` and a Safari pinned-tab `mask-icon` SVG — modern browsers don't need a `.ico` fallback, and a mask-icon needs a hand-vectorized monochrome silhouette that `sips` (a raster tool) can't mechanically derive from a photographic avatar.
- `<priority>`/`<changefreq>` in the sitemap — explicitly rejected above, not an oversight.
- Tagging `content/changelog/` entries — deliberately kept untagged as operational, not editorial, content.
- `og:image:width`/`height` for per-post images — Zola can't introspect dimensions of `static/`-rooted assets, so per-post `og:image` omits them (valid per the OG spec; crawlers fetch the image when these are absent).
- Commissioning a higher-resolution avatar source image for the 192/512 manifest icons.
- Per-post custom social-preview images for the 33 posts that don't already have an image directory — only existing assets were wired in; no new images were created.

## Verification

- `mise run blog-build` completes with zero Tera errors (after fixing the Tera `default()`-on-null gotcha above).
- Homepage output contains the `WebSite`/`Person` JSON-LD blocks, `<link rel="canonical" href="https://noisypigeon.com/">`, the manifest link, and both sized favicon links.
- `posts/cmda-zip-scatter/index.html` (a post with its own image) has `og:type=article`, `article:published_time`, a `BlogPosting` JSON-LD block, and `og:image`/`twitter:image` pointing at `https://noisypigeon.com/assets/images/posts/cmda-zip-scatter/img_2722.jpg`.
- `posts/why-i-dropped-out-of-high-school/index.html` (a post with no image directory) falls back to `social_preview.png` for both `og:image` and `twitter:image`.
- `/tags/` lists all 9 tags with correct post counts (verified against the per-post tag assignments); `/tags/personal-essays/` lists all 22 of its posts grouped by year.
- `robots.txt`, `manifest.json`, and all 5 generated icon files exist in `public/`.
- `sitemap.xml` contains zero `modules/...` redirect URLs (down from ~26 `<url>` entries that previously had no `<lastmod>`).
- `pages/about/index.html`, `pages/lineage/index.html`, and all 3 changelog digest pages now render their own `<meta name="description">` instead of the generic site description.
