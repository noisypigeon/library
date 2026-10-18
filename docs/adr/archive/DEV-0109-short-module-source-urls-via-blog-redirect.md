# DEV-0109: short Terraform module source URLs via blog-hosted redirects

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

Every module `source` line in this repo looks like:

```hcl
source = "git::https://github.com/noisypigeon/noisypigeon.git//modules/scaleway/object-bucket?ref=modules/scaleway/object-bucket/v1.0.0"
```

long, repetitive, and easy to mistype (the provider/module name appears twice — once in the path, once in the `ref`). The goal is a short equivalent:

```hcl
source = "https://noisypigeon.com/modules/scaleway/object-bucket/v1.0.0"
```

served from the existing Zola blog at `workloads/blog/src`, published to `noisypigeon.com` via GitHub Pages.

**Research confirmed, verbatim, before planning anything:**

- Terraform's module installer (go-getter) resolves a module `source` that's a plain HTTP(S) URL by issuing `GET <url>?terraform-get=1` and checking, in order: an `X-Terraform-Get` response header, then — if absent — a `<meta name="terraform-get" content="...">` tag in the response body. The `content` value must be a fully-formed URL; a `git::https://...?ref=...` forced-getter string is the documented, standard form for this (it's exactly what HashiCorp's own module-registry-protocol examples use). GitHub Pages cannot set custom per-path response headers, so the meta-tag fallback is the only mechanism available here — that's an intended fallback in the protocol, not a workaround.
- The `?terraform-get=1` query string is irrelevant to a static file server — GitHub Pages serves the same file regardless of query string — so a plain static HTML page per module version, with no backend logic, is sufficient.
- `workloads/blog/src` has no existing mechanism for generating many pages from a data source (no `data/` directory, no `load_data()` usage anywhere) — the only precedent for "many similar pages" is one hand-authored `.md` file per page in a flat section directory (`content/posts/`, `content/changelog/`, `content/pages/`). Zola's `path` front-matter field lets any page set its exact permalink regardless of where its `.md` file physically lives under `content/`, avoiding any need for real nested section directories.
- `templates/base.html` defines Tera blocks for `title`/`description`/`og_*`/`body_class`/`content`, extended by every other template, but has no block for injecting extra `<head>` tags.
- `.github/workflows/module-release.yml` runs on every PR merge to `main`, tags each changed module `modules/<provider>/<module>/v<X.Y.Z>`, and — in its `Trigger blog Pages deploy` step — already imperatively fires `gh workflow run blog-pages.yml --ref main` whenever the merge touched `workloads/blog/src/**` (`steps.blog.outputs.changed == 'true'`). This is the repo's only cross-workflow trigger; there is no `workflow_run`/`repository_dispatch` listener anywhere.
- `.github/workflows/blog-pages.yml`'s checkout step has no `fetch-depth`/`fetch-tags` override, so it does a shallow, tagless checkout by default — insufficient for a step that needs to enumerate module tags.
- 22 `source = "git::...` lines exist today across `workloads/scaleway/terraform/**` and `workloads/pigeon-cli/terraform/**` (confirmed via `grep -rn 'source *= *"git::https://github.com/noisypigeon' workloads/ --include="*.tf"`, excluding `.terragrunt-cache/`), all using the current `modules/<provider>/<module>` form.

## Decision

### 1. A `terraform-get` redirect page per module version tag

New script `workloads/blog/generate-module-redirects.sh` lists `git tag --list 'modules/*/*/v*'` (this glob alone excludes legacy pre-ADR-0093/pre-ADR-0037 tag forms, which don't start with `modules/`), and for each tag writes a flat Zola content page `workloads/blog/src/content/modules/<provider>-<module>-v<version>.md`:

```toml
+++
title = "<provider>/<module> v<version>"
description = "Terraform module source redirect for modules/<provider>/<module> v<version>."
path = "modules/<provider>/<module>/v<version>"
template = "module-redirect.html"
in_search_index = false
include_in_feeds = false

[extra]
git_source = "git::https://github.com/noisypigeon/noisypigeon.git//modules/<provider>/<module>?ref=modules/<provider>/<module>/v<version>"
github_url = "https://github.com/noisypigeon/noisypigeon/releases/tag/modules/<provider>/<module>/v<version>"
+++
```

`github_url` points at the module's GitHub Release page, guaranteed to exist since `module-release.yml` already runs `gh release create "$tag"` for every tag it pushes. The script is fully regenerate-all/idempotent: every run wipes and rewrites every page under `content/modules/` except the hand-authored `content/modules/_index.md` (`render = false`), so it stays correct as new tags appear with zero per-tag bookkeeping.

New template `workloads/blog/src/templates/module-redirect.html` extends `base.html` and overrides a new `extra_head` block with the actual meta tag:

```html
{% block extra_head %}
  <meta name="terraform-get" content="{{ page.extra.git_source }}">
{% endblock extra_head %}
```

plus a human-readable fallback body (the resolved `git::` source and a link to the GitHub release) for anyone who opens the short URL directly in a browser. `templates/base.html` gained the matching `{% block extra_head %}{% endblock extra_head %}` right before `</head>` — additive/no-op for every other template, none of which overrides it.

Generated pages are **gitignored, not committed** (`/workloads/blog/src/content/modules/*.md`, with `!/workloads/blog/src/content/modules/_index.md`), matching the existing precedent of `/workloads/blog/src/public` (the Zola build output) already being gitignored as a fully-derived artifact. Unlike the changelog digest (incrementally hand-appended per PR, so it carries information not otherwise recoverable), these pages are 100%-regeneratable from tags with no information loss, and are regenerated fresh by every build — committing them would only create sync-staleness confusion and review noise on every module release.

### 2. Wiring into local and CI builds

`.mise.toml`'s `blog-build`/`blog-serve` tasks now run the generator before Zola (mise already supports a `run` array of sequential commands, e.g. `fmt-terraform`):

```toml
[tasks.blog-build]
dir = "workloads/blog/src"
run = [
  "../generate-module-redirects.sh",
  "SITE_COMMIT_SHA=$(git rev-parse --short HEAD) zola build",
]
```

`blog-pages.yml`'s checkout step gained `fetch-depth: 0` + `fetch-tags: true` (needed to see the tags at all), followed by a new `Generate module redirect pages` step before `Install Zola`:

```yaml
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          fetch-tags: true
      - name: Generate module redirect pages
        run: workloads/blog/generate-module-redirects.sh
```

### 3. Tagging a module now also triggers a blog deploy

A new module tag needs its redirect page live even when no file under `workloads/blog/src/` changed in that merge. `module-release.yml`'s `Trigger blog Pages deploy` step's condition broadened from:

```yaml
if: steps.blog.outputs.changed == 'true'
```

to:

```yaml
if: steps.blog.outputs.changed == 'true' || steps.versions.outputs.tags != ''
```

reusing the existing `steps.versions.outputs.tags` output (space-separated list of tags created this run, non-empty exactly when ≥1 module was tagged) and the existing imperative `gh workflow run blog-pages.yml --ref main` call — no new cross-workflow trigger mechanism was introduced.

### 4. `modules/README.md`

The "## Consuming" section now leads with the short URL as the recommended form, documents the `git::` form as what it resolves to, and leaves the local-sibling-clone path-based iteration flow unchanged (that path never goes through the redirect).

### 5. Migrating existing consumers

All 22 existing `source = "git::...` lines across `workloads/scaleway/terraform/**` and `workloads/pigeon-cli/terraform/**` were rewritten to the short form (mechanical substitution, alignment/whitespace preserved). This is not a breaking change — the old `git::` form keeps working unchanged for anyone still using it — but there was no reason to leave the repo's own consumers on the long form once the short one existed.

## Consequences

- Every module version tag now has a stable, short `https://noisypigeon.com/modules/<provider>/<module>/v<X.Y.Z>` source URL, resolved via go-getter's standard HTTP module-source discovery protocol with zero backend logic — just a static page.
- The blog gains a `content/modules/` section whose pages are build-time-generated and gitignored, not hand-authored or committed — a new, different-from-everything-else-in-this-section content pattern, documented here for anyone who later wonders why `content/modules/*.md` never shows up in `git log`.
- `blog-pages.yml` now always does a full, untagged-aware checkout (`fetch-depth: 0`) instead of a shallow one, and runs one extra lightweight step — negligible cost, but worth knowing if that workflow's run time is ever being tuned.
- A module release (any `release:*`-labeled PR merge touching `modules/scaleway/*`) now unconditionally triggers a blog Pages redeploy, even when nothing under `workloads/blog/src/` changed — necessary so the new tag's redirect page goes live promptly, but means every module release now costs one extra `blog-pages.yml` run.
- This repo's own 22 module consumers now read noticeably shorter `source` lines; the pattern is established for any future consumer (in this repo or external) to do the same.

## Out of scope

- Legacy pre-ADR-0093 (`terraform/modules/<provider>/<module>/vX.Y.Z`) and pre-ADR-0037 tags don't get redirect pages — they're frozen and never renamed (see `modules/README.md`'s Versioning section), so there's no real gap to fill; consumers of those tags keep using the full `git::` form. Permanent boundary, not deferred.
- A bare "latest" alias with no version segment (e.g. `https://noisypigeon.com/modules/scaleway/object-bucket` resolving to that module's newest tag) — genuinely useful, genuinely deferred. ([#141](https://github.com/noisypigeon/noisypigeon/issues/141))
- Custom `X-Terraform-Get` response headers instead of the `<meta>`-tag fallback — not possible on GitHub Pages, which has no per-path header control. Permanent boundary, not deferred.
