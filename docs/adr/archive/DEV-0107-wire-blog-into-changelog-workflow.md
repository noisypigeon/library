# DEV-0107: wire the blog into the changelog workflow, restructure the changelog channel, fix the date timezone

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

This repo already has an automated changelog pipeline for Terraform modules: `.github/workflows/module-release.yml` runs on every PR merge to `main`, detects which `modules/scaleway/<module>` directories changed, writes a dated entry into that module's own `CHANGELOG.md`, rolls up a one-line summary into the root `CHANGELOG.md`, then tags and releases the module. The root `CHANGELOG.md`'s own header already documents `blog` as a valid `<scope>` value — anticipating this extension — but the workflow's module-discovery logic is hardcoded to `modules/scaleway` + `versions.tf` + `*.tf`-file changes, so it has never actually fired for blog changes.

Meanwhile the on-site `/changelog/` channel (added earlier this session) worked by tagging ordinary posts in `content/posts/` with `[extra]\npost_type = "changelog"` and filtering them in/out of two templates — a workaround bolted onto the posts section, not a real content split.

**Research confirmed, verbatim, before planning anything:**

- `module-release.yml`'s only date computation is a single line, `TODAY=$(date -u +%Y-%m-%d)`, shared by the per-module changelog heading and the root rollup's date section. GitHub Actions runners default to UTC regardless of `-u`, so a late-night Pacific merge (e.g. 10pm PDT = 5am UTC the next day) stamps tomorrow's UTC calendar date — the exact "late-night commits show as next day" bug reported.
- Module discovery (`find modules/scaleway -mindepth 2 -maxdepth 2 -name versions.tf`) and the changed-file filter (`.tf` files only) are both hardcoded to the Terraform-module tree; nothing about them generalizes to `workloads/blog/`. The three `release:*` labels (`major`/`minor`/`patch`) exist specifically to drive semver tagging for that tree — the blog isn't versioned or tagged, so it needs no label at all, just detection of whether the merge touched `workloads/blog/src/`.
- Zola derives every page's URL from its frontmatter `slug` field (`<section-path>/<slug>/`), independent of the markdown filename — confirmed against the built site output, where every `public/posts/<slug>/` directory matches its source file's `slug =` value, not its numeric filename prefix. Renumbering files is a pure bookkeeping rename; moving a post to a different **section** changes its URL prefix, which is a real change `aliases` front matter (already used by `content/pages/lineage.md`) can paper over.
- Exactly 4 posts carried `post_type = "changelog"`: `0003-hello-medium-introduction.md`, `0025-hiya-svbtle-re-introduction.md`, `0049-hihi-pika-lets-consolidate-re-introduction.md`, `0057-hello-jekyll-re-introduction.md` — all announcement/migration posts, none of this blog's regular content.

## Decision

### 1. Extend `module-release.yml` with a blog path, in the same job

A new `Determine blog change` step greps the merge diff for `^workloads/blog/src/`. Rather than a second parallel job (which would race the existing job's `git push origin HEAD:main` from the same workflow run), the blog logic runs as additional sequential steps in the existing single `release` job, sharing its checkout and git identity, and folding into the same final commit:

```yaml
      - name: Determine blog change
        id: blog
        env:
          MERGE_SHA: ${{ github.event.pull_request.merge_commit_sha }}
        run: |
          CHANGED_FILES=$(git diff --name-only "${MERGE_SHA}~1" "$MERGE_SHA")
          if echo "$CHANGED_FILES" | grep -q '^workloads/blog/src/'; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
          else
            echo "changed=false" >> "$GITHUB_OUTPUT"
          fi
```

`Configure git identity` and `Commit changelog updates` both broaden their `if` to `steps.modules.outputs.changed != '' || steps.blog.outputs.changed == 'true'`; `Tag and release each changed module` stays gated on `steps.modules.outputs.changed != ''` only — the blog never gets a version tag or GitHub Release.

A new `Update blog changelog and daily digest` step (gated on `steps.blog.outputs.changed == 'true'`) does three things per merged blog PR: appends a dated, unversioned entry to `workloads/blog/CHANGELOG.md` (same 5-line-header-splice idiom as the module changelogs, just without a `[X.Y.Z]` version bracket, since the blog has none); appends a `- [blog] <title> (#N)` one-liner to the root `CHANGELOG.md`, reusing the exact same `awk` insert-or-append-under-today's-heading block the module step already uses; and writes or appends to a daily digest post at `workloads/blog/src/content/changelog/${TODAY}-changelog.md`. The digest step is idempotent — `grep -q "#${PR_NUMBER}\]" "$DIGEST"` skips re-adding a PR's bullet on a workflow retry — and naturally groups same-day merges into one on-site post, since the file is keyed by date, not by PR.

Every change under `workloads/blog/src/**` counts, including template/CSS/config-only tweaks — matching the module workflow's own "any `.tf` file" granularity rather than trying to distinguish "meaningful" content changes from infrastructure ones.

### 2. Timezone fix

```diff
-          TODAY=$(date -u +%Y-%m-%d)
+          TODAY=$(TZ="America/Los_Angeles" date +%Y-%m-%d)
```

The one shared date line, fixed once, fixes module changelogs, the root rollup, and (via the identical pattern in the new blog step) the blog changelog and daily digest simultaneously. `America/Los_Angeles` tzdata already encodes PST/PDT DST transitions, so no separate DST handling is needed. The daily digest's own frontmatter `date` field uses the matching Pacific UTC offset (`TZ="America/Los_Angeles" date +%z`, reformatted with a colon for TOML).

### 3. Restructure: changelog posts move to `content/changelog/`

The 4 historical changelog-tagged posts moved out of `content/posts/` into `content/changelog/`, renumbered `0001`-`0004`, with their now-unneeded `[extra]\npost_type = "changelog"` block removed (section membership does that job now) and an `aliases = ["posts/<slug>"]` entry added so their old `/posts/<slug>/` URLs keep resolving — the same pattern `content/pages/lineage.md` already uses for its own legacy redirect:

```diff
 slug = "hello-medium-introduction"
 description = "Medium blog announcement post."
-
-[extra]
-post_type = "changelog"
+aliases = ["posts/hello-medium-introduction"]
```

The remaining 53 posts in `content/posts/` were renumbered `0001`-`0053` to close the 4 gaps, processed in ascending numeric order (each target slot already free by the time it's reached, since the 4 changelog posts were moved out first) — the same collision-avoidance approach ADR-0097 established for this repo's batch-rename gotcha. Frontmatter untouched throughout; confirmed zero live URL impact since permalinks are slug-driven, not filename-driven.

### 4. Section/template wiring

`content/changelog/_index.md` gained `sort_by = "date"` and `page_template = "post.html"` — the same keys `content/posts/_index.md` already uses — so Zola treats its children as real dated pages instead of the section being a standalone page with hand-rolled listing logic:

```diff
 title = "Changelog"
 template = "changelog.html"
+sort_by = "date"
+page_template = "post.html"
```

`templates/changelog.html` now does `get_section(path="changelog/_index.md")` directly, with the `is_changelog_post` filter removed entirely (every child of this section is a changelog entry by definition). `templates/index.html` lost the same filter, reverting to the simple unfiltered loop it had before `content/posts/` ever contained changelog-tagged posts.

### 5. `workloads/blog/CHANGELOG.md`

Created now with just the standard header — no backfill of prior blog history, matching the root `CHANGELOG.md`'s own stated "starts fresh — no backfill" precedent (ADR-0050).

### 6. Root `CHANGELOG.md` — incidental doc fix

Its header pointed to `service/pigeon-cli/CHANGELOG.md`, a path that no longer exists in this repo since the `pigeon-cli` crate split out via ADR-0084. Fixed to point at the new `workloads/blog/CHANGELOG.md` instead and note that `pigeon-cli`'s own changelog now lives in its own repo.

### 7. Documentation

`CLAUDE.md` gained this ADR in its index, and its `workloads/blog/` description sentence now covers `CHANGELOG.md` and the `content/changelog/` restructure.

## Consequences

- `workloads/blog/CHANGELOG.md` exists; future blog PRs get a real changelog entry automatically, rolling up into root `CHANGELOG.md` under `[blog]`, with no `release:*` label and no version tag/release created.
- `/changelog/` on the live site is now a real Zola section mixing 4 hand-authored historical posts (`0001`-`0004`) with CI-generated daily digests (`YYYY-MM-DD-changelog.md`), one post per day with blog changelog activity, aggregating only blog-scoped entries (not the whole repo's module/pigeon-cli activity).
- The 4 moved posts' public URLs change from `/posts/<slug>/` to `/changelog/<slug>/`; `aliases` keeps the old URLs resolving.
- `content/posts/` is renumbered `0001`-`0053` (was `0001`-`0057` with 4 gaps); `content/changelog/`'s hand-authored posts are `0001`-`0004`. No live URLs changed from the renumbering itself.
- Both the module and blog changelog date stamps move from UTC to `America/Los_Angeles`, fixing late-night Pacific merges landing under the wrong calendar day.
- `release:patch`/`release:minor`/`release:major` labels remain meaningless for blog-only PRs, same as for any other PR that doesn't touch `modules/<provider>/<module>/` — this ADR doesn't change that, it only adds a changelog-only path that needs no label at all.

## Out of scope

- No RSS/Atom feed for the `content/changelog/` section (`generate_feeds` left off) — can be added later the same way `content/posts/_index.md` already does it.
- No automated tests for the new/changed shell logic in `module-release.yml` — relies on live verification on a real PR merge, same as the rest of this workflow's history; this ADR's own local verification was limited to `zola build` and static checks (see below), since plan mode / a local session cannot execute GitHub Actions.
- No backfill of blog-related history that predates this ADR into `workloads/blog/CHANGELOG.md` or root `CHANGELOG.md` — matches the root changelog's existing no-backfill precedent.

## Verification

- `mise run blog-build` (`zola build` from `workloads/blog/src`) succeeds with no Tera errors after the template/content changes.
- `/changelog/` lists exactly the 4 renumbered historical posts grouped by year; `/posts/hello-jekyll-re-introduction/` (an old URL) still resolves via its new `aliases` entry; `/changelog/hello-jekyll-re-introduction/` is the new canonical URL.
- `/` (home) no longer contains any changelog-tagged entries and has no leftover filter logic.
- No two files in `content/posts/` or `content/changelog/` collide on numeric prefix after the renumbering.
- `.github/workflows/module-release.yml` parses as valid YAML after the edits (checked locally; the actual CI path can only be verified live on a real PR merge).
