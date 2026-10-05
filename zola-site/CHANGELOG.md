# Changelog

All notable changes to this theme are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-10-05

### Strengthen name-entity SEO signals on homepage and posts

Fixes a few on-page SEO gaps left after the ADR-0111 pass, aimed at helping
search engines correctly identify and rank the site's author entity:

- The homepage `<title>` was rendering as a duplicated `"Willow Graysen -
  Willow Graysen"`. It now uses the site title plus description, giving the
  homepage distinct, keyword-rich title/OG/Twitter text.
- The homepage previously had no `<h1>` anywhere on the page. The site name
  in the header is now wrapped in a real `<h1>` when rendering the homepage
  specifically (every other page keeps it as a plain link, since those pages
  already have their own `<h1>` for their title).
- The homepage body copy now says "Willow Graysen" in full, not just
  "Willow."
- Every post now includes a byline ("By Willow Graysen") linking to the
  About page, giving it real internal-linking weight instead of being
  reachable only from the nav bar.
- The homepage `Person` JSON-LD now includes Bluesky in `sameAs` (also added
  to the visible nav) and an `alternateName` list covering the author's
  prior public identity names, to help search engines connect the entity
  across a recent legal name change.

None of this changes the theme's public interface (no renamed Tera
variables, no changed `config.toml` schema) — it's purely template/content
behavior.

[#189](https://github.com/noisypigeon/noisypigeon/pull/189)

## [1.0.0] - 2026-10-03

### First versioned release

`templates/zola-site` is now a versioned, releasable unit
([ADR-0113](../../docs/adr/0113-version-templates-zola-site.md)). This
release has no code changes of its own — it marks the theme's existing,
already-production state (extracted from the live blog by
[ADR-0112](../../docs/adr/0112-extract-reusable-zola-site-template.md), and
running `noisypigeon.com` since before that extraction) as its formal
`1.0.0` baseline, rather than restarting at `0.1.0` the way the original
Terraform modules' own pre-automation changelog entries did.

[#146](https://github.com/noisypigeon/noisypigeon/pull/146)
