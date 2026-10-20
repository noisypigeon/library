# LIB-0021: Spoke prose is minimal

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Accepted. Amends LIB-0017 §1: a spoke's `CLAUDE.md` no longer
  names its load-bearing records.

## Context

garden, blog and runway hold no reusable code and no ADRs (LIB-0001,
LIB-0017). What they hold is content or leaves, a pin on this repo, and
prose about both. Most of that prose restates this repo:

| Spoke | `CLAUDE.md` | `README.md` |
|---|---|---|
| garden | 185 lines | 90 lines |
| blog | 300 lines | 60 lines |
| runway | 194 lines | 27 lines |

They carry dependency tables, layout trees, a table of every leaf, a
description of each workflow, a list of the records that are load-bearing
for the spoke, and the COM-/RUN- fold-in tables. Comments do the same.
`spoke.hcl`, `fetch-lib.sh` and every workflow open with a paragraph of
provenance. Each of these is a second copy of something kept here, and the
copies have drifted:

- runway's `CLAUDE.md` names the repo `noisypigeon/willowgraysen`, two renames
  out of date. It also names a `scaleway/project/com` leaf that is really
  `scaleway/project/runway`.
- blog and runway both send readers to `noisypigeon/noisypigeon#310` for why
  apply's auto-merge fails. That link points at the deleted monorepo.
- Every spoke's `root-changelog.yml` still maps `^adr/=adr`, which LIB-0017 left
  dead and deferred as [#75](https://github.com/noisypigeon/library/issues/75).
- Counts go stale as soon as they're written, such as blog's "54 posts" and
  runway's "eighteen leaves".

A reader of a spoke needs to know three things: what the spoke is for, how
a change gets merged, and what in this spoke can hurt them. Everything else
already has its one home here.

## Decision

Spoke prose follows *you aren't going to need it*: a sentence is written only
when its absence would cause a mistake, and nothing is restated that this repo
already says.

### 1. `README.md` is static

It says what the repo is and where the result lives, and nothing else:

- **garden**: the site at [noisypigeon.garden](https://noisypigeon.garden),
  and the short-URL host for this repo's Terraform modules.
- **blog**: the blog at [noisypigeon.com](https://noisypigeon.com).
- **runway**: infrastructure that isn't publicly exposed. It keeps one line
  asking for security issues to be reported privately, because the repo is
  public (RUN-0000).

There are no dev instructions, record lists, consumption contracts or
contribution notes. Those belong in `CLAUDE.md` or here.

### 2. `CLAUDE.md` is the spoke's purpose, its dev cycle and its hazards

- **Purpose**: a few lines on what the spoke is for and what it must never
  hold (modules, theme files, reusable scripts and ADRs all belong here).
- **Dev cycle**, per this repo's standards:
  - every change is a PR with a Conventional Commit title;
  - the changelogs are generated;
  - the spoke cuts no releases;
  - Terraform is planned on the PR and applied by a `terragrunt apply`
    comment;
  - `root.hcl` is generated and never edited;
  - a hub change is taken by bumping `.lib-version` or `spoke.hcl`.
- **Hazards particular to the spoke**:
  - runway's sensitivity rules;
  - blog's published PR titles and bodies, and its load-bearing
    `web/CHANGELOG.md` header;
  - that a failed garden deploy breaks every consumer's `terraform init`.
- **Commands**.

Left out: tables or trees that restate the files, history, counts, a
description of each workflow, and lists of records. Decisions live here
(LIB-0017), and one line saying so is enough. **This amends LIB-0017 §1**,
which asked each spoke to name its load-bearing records. A list like that is
a copy, and copies drift.

### 3. A comment earns its place

A comment stays only if it says something the code can't, and leaving it out
would cause a mistake. "DNS-only, because GitHub Pages can't issue a certificate
behind the proxy" stays. Provenance, ADR history, and a sentence that restates
the next line all go.

### 4. Some things are not touched

- Generated files: `root.hcl`, `secrets-schema.json`, every `CHANGELOG.md` and
  blog's dated `web/content/changelog/` digests.
- Blog posts and pages, which are content, not documentation.
- Commented-out code. Removing it is a decision about the resource, not about
  prose.

### 5. Citations are deleted, never rewritten

LIB-0017 §3 still holds. A `DEV-`, `COM-` or `RUN-` citation that no longer
earns its place is deleted outright. It is never renumbered to the `LIB-`
record it was folded into.

### 6. Dead config goes with the prose

Each spoke's `root-changelog.yml` drops `^adr/=adr`, which closes #75.

## Consequences

- **The spoke PRs are mostly deletions.** One per spoke, each citing this
  record.
- **A spoke's `CLAUDE.md` goes stale less.** There are fewer facts in it to
  drift, and the ones left change only when the dev cycle changes, which is
  here.
- **Readers follow links to this repo more often.** That is the cost: a reader
  who wants the module index or a record's reasoning reads it here, not in the
  spoke.
- **New spoke prose is held to the same bar.** A PR that adds a table, tree or
  record list to a spoke's `CLAUDE.md` contradicts this record.

## Out of scope

- **pigeon-cli's prose.** It keeps its own ADRs (LIB-0017 §5) and its own
  standards. A permanent boundary.
- **This repo's own prose.** The hub is where the detail is meant to live. A
  permanent boundary.
- **Commented-out code in the spokes.** Per §4, it is not a prose decision. A
  permanent boundary for this record.
- **runway's `scaleway/pigeon-cluster` and `scaleway/object-bucket` leaves.**
  LIB-0020's rename rewrites them. They are left alone here so the two changes
  don't conflict. A permanent boundary.

## Verification

1. **Each spoke PR is net deletion.** `git diff --stat origin/main` removes more
   lines than it adds, across `README.md`, `CLAUDE.md` and comments.
2. **Nothing generated moved.** None of the spoke PRs touches `root.hcl`,
   `secrets-schema.json` or a `CHANGELOG.md`, and each spoke's
   `resolve-root-hcl.sh --check` passes.
3. **Nothing is planned.** Each spoke PR's `terragrunt-plan` reports
   `No changes.` for every leaf it touches.
4. **The stale facts are gone.**
   `grep -rnE 'noisypigeon/noisypigeon#|noisypigeon/willowgraysen|project/com|\^adr/'`
   finds nothing in any spoke.
5. **The sites still build.** `mise run garden-build` and `mise run blog-build`
   succeed, and leave `git status` clean.
