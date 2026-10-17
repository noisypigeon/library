# Changelog

All notable changes to this theme are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.1] - 2026-10-17

### Name the hub noisypigeon/library

This repo is now `noisypigeon/library`, renamed from `noisypigeon/pigeon-lib` (LIB-0015).

- **`generate-module-redirects.sh`** defaults `TAG_REPO` to `noisypigeon/library`. Once a site takes this `workflows` release, every module short URL's `terraform-get` meta resolves to `git::https://github.com/noisypigeon/library.git//…`, and the overview and release links name the new repo too. The old `pigeon-lib.git` sources keep working through GitHub's redirect in the meantime. The short URLs themselves don't change.
- **The theme's `homepage`** points at the new repo.
- **Docs.** The `root.hcl` template header, the READMEs (including the raw dashboard URLs), CLAUDE.md and the release-pr skill now name the library. ADRs and changelogs keep the old name as history.

No inputs, outputs or behaviour change for any consumer.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#70](https://github.com/noisypigeon/library/pull/70)

## [1.2.0] - 2026-10-07

### Generalize changelog.html to reuse the section it's rendering

\`changelog.html\` listed its posts by re-fetching \`get_section(path="changelog/_index.md")\` instead of using the \`section\` variable Zola already passes into a section template. That hardcoded path meant the template could only ever be used for a section literally named \`changelog\` — any other section (e.g. a future release-notes or post-stream section under a different name) couldn't reuse it without duplicating the whole template.

This replaces the hardcoded lookup with the ambient \`section.pages\`, which is equivalent for the existing \`changelog\` section and makes the template reusable by any section that sets \`template = "changelog.html"\` with \`page_template = "post.html"\`, regardless of its path. No behavior change for existing consumers.

[#232](https://github.com/noisypigeon/noisypigeon/pull/232)

## [1.1.1] - 2026-10-05

### Fix homepage h1 styling to match plain site-title link

PR #189 wrapped the homepage site-title in a real `<h1>` for SEO
purposes. That introduced one extra level of nesting (`.site-title >
h1 > a` instead of `.site-title > a`), which broke the direct-child
CSS selector that kept the link unstyled, and let the global/default
`h1` styling (2x font size, added margin, underlined link) show
through — visibly larger and underlined compared to every other
page's header.

This resets the nested `<h1>` to inherit `.site-title`'s own
typography (font size, line height, letter spacing, no margin) and
switches the link color/decoration override to a descendant
selector so it keeps working whether or not an `<h1>` sits between
`.site-title` and the link. Purely a visual fix — the `<h1>` tag
itself, and the SEO benefit it provides, is unchanged. Verified
side-by-side in a browser that the homepage header now renders
identically to the About page's.

[#191](https://github.com/noisypigeon/noisypigeon/pull/191)

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
