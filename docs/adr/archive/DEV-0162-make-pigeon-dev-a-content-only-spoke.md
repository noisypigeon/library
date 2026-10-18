# DEV-0162: make `pigeon.dev` a content-only spoke

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted.

## Context

LIB-0001 described a hub-and-spoke architecture: one hub, `noisypigeon/pigeon-lib`,
owning every versioned reusable asset, and spokes holding content plus their own
infrastructure, consuming the hub by pinned version. LIB-0002 created the hub and
named the end state for this repo. This record is what `pigeon.dev` actually did to
reach it.

`pigeon.dev` was the wrong shape for a spoke, and had been accumulating that shape
deliberately. ADR-0154 hoisted `templates/` here from `noisypigeon/noisypigeon`
keeping the `templates/…` paths byte-identical, so every pre-existing tag prefix,
workflow glob and short URL kept working. ADR-0156 then hoisted the Zola site in
alongside, as `pigeon.dev/src`, specifically so that the redirect generator could
read `templates/` off local disk instead of a fetched clone and `resolve-theme.sh`
could use a live `"main"` symlink. Both were good calls for a repo that owned the
templates. Neither survives a repo that doesn't.

So this repo held, simultaneously: 13 Terraform modules, a Zola theme, ten GitHub
workflows of which six were `workflow_call`-only reusables for *other* repos, a
release automation, a vendored changelog script, a release-PR skill, and the site.
The only part of that a spoke keeps is the site.

One thing had to stay, and it is the reason this repo continues to exist.
`pigeon.dev/modules/<provider>/<module>/vX.Y.Z` is a public interface with a
stability guarantee (ADR-0109/0110), consumed by `source =` pins that are not ours
to break. Serving it is a property of the **domain**, not of the code — and the
decoupling ADR-0110 insisted on, where the public path never encodes internal
layout, is precisely what made the rest of this migration possible. The source moved
to another repo under every live pin without breaking one.

## Decision

`pigeon.dev` becomes content plus its own deploy. It holds no templates, no reusable
scripts, no release automation, and cuts no releases.

### 1. Consume the hub by pin, not by branch

`.lib-version` names a `pigeon-lib` ref; `fetch-lib.sh` materializes it into a
gitignored `.lib-src/`, blobless, with tags. Everything reusable is read from there:
`zola-site/resolve-theme.sh` for the theme, `.github/scripts/generate-module-redirects.sh`
for the redirect, overview and release pages, and `.github/scripts/root-changelog.sh`
when CI writes a changelog line.

`fetch-lib.sh` is the one script this repo keeps, and the deliberate exception to "a
spoke contains no scripts": a spoke cannot fetch its own fetcher. Setting `LIB_SRC`
points it at a local checkout and it leaves that alone, which is how to iterate
against an unreleased hub change.

This is a pin, never a branch — LIB-0001 invariant 2. Taking a hub change is an
explicit bump, reviewable as a diff.

### 2. Keep two workflows, both thin

`pigeon-dev-pages.yml` is a thin caller of the hub's reusable `zola-site-pages.yml`.
It stays here rather than in the hub because `actions/deploy-pages` always deploys to
the **calling** repo's Pages site; a hub-side deploy would publish to the hub.

`root-changelog.yml` keeps DEV-0160's contract — one root `CHANGELOG.md` line per
merged PR, no `paths:` filter, no exceptions — and runs the hub's script rather than
a vendored copy.

Everything else is deleted: `template-release.yml`, `module-docs.yml`, the six
`workflow_call`-only reusables whose callers already point at the hub, the
`release-pr` skill, and the vendored `root-changelog.sh`.

**`root-changelog.yml` loses its stand-down block.** It existed to defer to
`template-release.yml` for releasing PRs, by duplicating that workflow's detection
predicates. With nothing to defer to, the block is not merely dead but actively
wrong: its predicate matched `^templates/terraform/.*\.tf$`, which is exactly the
shape of the diff that *deletes* those modules. Left in place it would have deferred
to a workflow that no longer existed and silently produced no changelog entry at all.

### 3. Delete `templates/`, keep its tags

`templates/terraform/` and `templates/zola-site/` are removed. All 53 `templates/*`
tags stay — ADR-0154's permanent boundary, no superseded tag is ever deleted — and
the module `CHANGELOG.md` history hangs off them. They are simply unreferenced: every
short URL now resolves to `pigeon-lib`.

### 4. Rename the site root to `web/`

`pigeon.dev/src` becomes `web/`. A repo named `pigeon.dev` does not need a directory
named `pigeon.dev` inside it — the same redundancy DEV-0161 removed from the ADR
corpus. Done as a separate change from the deletion, per ADR-0110's "pure rename
first, rewiring second".

`root-changelog.yml`'s precedence now matches `^web/` while still **labelling the
entry `pigeon.dev`**: the directory was renamed, the site it publishes was not.

## Consequences

A change spanning the hub and this repo is two PRs in two repos, hub first. That is
the cost of versioning, and it is the point: this repo can no longer be broken by an
edit to a script it does not contain.

`pigeon.dev` has no releasable unit, so `release:*` labels do not apply here. (They
never existed in this repo at all: `git filter-repo` copies history, not repo
settings, so ADR-0154's split left them in `noisypigeon`. Every release ever cut here
therefore went through `template-release.yml`'s `defaulting to patch` warning, and a
minor or major bump was unexpressible. The labels now exist in `pigeon-lib`, where
that contract is load-bearing.)

Local iteration costs a clone. `mise run pigeon-dev-build` fetches the hub before
building; the previous arrangement read templates off local disk. Blobless cloning
keeps that cheap, and `LIB_SRC` removes it entirely when working across both repos.

The two localisations ADR-0154 and ADR-0156 bought are given back. Both ADRs stand as
filed and their reasoning was sound for the repo that existed then; this record
supersedes their *conclusions* about where the site and templates live, not their
accounts of why.

**The Pages deploy has one unmitigated failure mode.** `actions/deploy-pages` gives
up after 600000 ms, and that is a hard ceiling, not a default — the action clamps any
larger `timeout` and warns. When it expires while GitHub still reports
`updating_pages`, it cancels a deployment the Pages service still holds, and every
later deployment fails with `due to in progress deployment` until a server-side
reaper clears it, about 45 minutes in the one incident recorded. No client-reachable
API shortens that: the cancel endpoint returns 204 and is reflected in the read path
without releasing the creation lock, a Deployments-API status write is accepted with
no effect, and reruns fail identically. The read and write sides of the Pages API
disagree for the duration. This is tracked as an issue, not solved.

## Out of scope

- **The Terraform hoist.** LIB-0001 step 3 gives this repo its own `terraform/` and
  moves `root.hcl` into the hub as a versioned template. Blocked on LIB-0001 §8's
  `state/iam` problem. This repo ends with `web/` and no `terraform/`.
- `terragrunt/root-hcl/` in the hub, which serves that step.
- Deleting any superseded tag, anywhere. ADR-0154's permanent boundary.
- Re-pinning `noisypigeon.com` past `workflows/v1.0.2`. Its deploys are healthy and
  the delta does not concern it.
- The stale `pigeon.dev/generate-module-redirects.sh` copy still tracked in
  `noisypigeon`, which that repo's `ARCHITECTURE.md` already calls a leftover.
- Aligning `fetch-lib.sh` and `.lib-version` placement between the two spokes. This
  repo keeps them at the root; `noisypigeon.com` keeps them under its site directory.

## Verification

1. All 15 distinct pinned module versions found in `noisypigeon` return 200, each
   naming `pigeon-lib.git//terraform/…`, with public paths unchanged; the retired
   `scaleway/project/v1.0.0` still 404s. Run before and after the deletion.
2. Rebuilding with `templates/` moved aside produced a **byte-for-byte identical**
   published tree — proof the deletion could not change the site, obtained before
   deleting rather than after.
3. `git tag -l` stays at 53 across every step.
4. The deletion PR fired no `module-docs` run, that workflow having been removed
   first. It triggers on `push`, so the ordering was load-bearing. (DEV-0154 §9's
   claim that a `pull_request` workflow runs from the base ref is **wrong** — it runs
   from the head ref, which LIB-0002 records; the `push` trigger is the real
   constraint.)
5. `root-changelog.yml` wrote its entry using the *fetched* script, dry-run locally
   first and then exercised live on its own merge.
6. `mise run pigeon-dev-build` from `web/` produces 49 redirect pages, 13 overviews,
   4 theme-version redirects, 87 release posts, 153 pages, 0 orphans; no generated
   file becomes trackable.
