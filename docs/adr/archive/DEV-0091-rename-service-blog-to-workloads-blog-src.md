# DEV-0091: rename `service/blog` to `workloads/blog/src`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`service/` originally held two siblings per ADR-0067's framing — `service/pigeon-cli/` and `service/blog/`. `pigeon-cli` has since split into its own repo (ADR-0084), leaving `service/` holding only `blog/` — effectively a single-child directory.

The user wants to rename `service/blog/` to `workloads/blog/src/`, establishing a `workloads/<name>/src/` convention for this repo going forward. This is forward-looking, not just a terminology swap: `workloads/` is intended to hold future, additional workloads beyond the blog, and the `src/` subdirectory leaves room for future sibling directories per workload (e.g. a hypothetical `workloads/blog/deploy/` later) — the same split-by-concern shape `terraform/` already uses (`modules/`/`infrastructure/` as siblings).

Confirmed via research: `service/blog/` has no internal self-references to its own path (`config.toml` has no filesystem paths — title/description/base_url/feed/search-index flags only), so this is a pure directory move with no content changes. Five files reference the old path and need updating; two contain the literal string but are historical records left untouched, consistent with this repo's established precedent (ADR-0086, ADR-0089) of not rewriting history.

## Decision

### Move

`git mv service/blog workloads/blog/src` — single history-preserving rename covering `config.toml`, `content/` (62 files), `templates/` (6 files), `static/` (CSS + ~70 images + `CNAME`). `service/` no longer exists once empty (git doesn't track empty directories).

### Update the 5 referencing files

- **`.gitignore`**: `/service/blog/public` → `/workloads/blog/src/public`.
- **`.mise.toml`**: `blog-build`/`blog-serve` tasks' `dir = "service/blog"` → `dir = "workloads/blog/src"`.
- **`.github/workflows/blog-pages.yml`** (the live GitHub Pages deploy workflow): `paths: ["service/blog/**"]`, `working-directory: service/blog`, and `path: "service/blog/public"` all become `workloads/blog/src` equivalents.
- **`CLAUDE.md`**: repo-structure paragraph, the ADR-0067 index-summary bullet, and the `mise run blog-build`/`blog-serve` command description, each updated to the new path; gains a new ADR-0091 index bullet (this entry).
- **`docs/USAGE.md`**: the structure-list bullet (link text + href) and the two `mise run blog-build`/`blog-serve` command-description lines.

### Left untouched (historical records)

`docs/adr/0067-rewrite-blog-to-zola.md` — the original Zola-migration ADR; its body accurately describes `service/blog` as it existed when written, and isn't retroactively rewritten (same precedent as ADR-0086 leaving DigitalOcean-era ADRs alone, ADR-0089 leaving ADR-0088's text alone). `CHANGELOG.md`'s `[blog]` entry for ADR-0067 — a historical changelog line, not a current-state claim.

## Consequences

- `service/` no longer exists as a concept in this repo — any future non-Terraform addition follows the `workloads/<name>/src/` pattern established here, not a new `service/<name>/`.
- The live GitHub Pages deploy (`blog-pages.yml`) depends on this PR landing all three of its path changes together — a partial path update would break the next deploy (wrong trigger filter, wrong build directory, or wrong artifact path).
- No content, template, or asset changes — purely a path rename, verified by `config.toml` having no internal path self-references.
- This isn't a `terraform/modules/*` change, so the `release-pr` skill's per-module versioning/tagging (`release:*` labels, module tags) doesn't apply — ships as a normal PR/merge, no label needed.

## Out of scope

- Actually adding any other `workloads/<name>/` directory — this ADR only performs the one rename; the convention is established for future use, not populated further here.
- Renaming or restructuring anything under `terraform/` — unaffected, uses its own existing `modules/`/`infrastructure/` split.
- Updating the dormant, out-of-tree `noisypigeon.github.io` repo (left untouched per ADR-0067, still the pre-Zola historical record) — unaffected by an internal path rename in this repo.
