# LIB-0002: create `pigeon-lib`, flatten its roots, and make `pigeon.dev` content-only

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-13.
- **Status**: Accepted; amended 2026-10-17 (see `## Amendments`).

## Context

LIB-0001 named a hub-and-spoke target and a six-step rollout. DEV-0160 step 0
shipped: every module version now resolves through one rule, because the last
consumer of a `modules/*`-era tag was repinned and the frozen mapping arm
deleted. This ADR executes steps 1 and 2.

**They cannot be separated.** Step 1 moves `templates/` and the scripts out of
`pigeon.dev`; step 2 is what teaches that repo to fetch them back. But the site
build has four hard dependencies on those assets being local — the module
`README.md` and `CHANGELOG.md` reads, this repo's own tag list, the theme
directory, and the generator itself. Done literally and in order, step 1 leaves
`pigeon.dev` unable to build, and every published module short URL 404s on the
next deploy. LIB-0001 §7(7) predicted exactly this: splitting the site from
`templates/` again "re-opens every coupling DEV-0156 closed".

So the work lands as one effort. Step 3, the Terraform hoist, stays out — it is
separately blocked on LIB-0001 §8's `state/iam` problem.

## Decision

### 1. Flatten the hub's roots, not just its tags

LIB-0001 §5 drops the `templates/` segment from *tags* while §2's role table
keeps it on *directories*. That decouples two things the generator has always
held as one string — `//${prefix}/${provider}/${module}?ref=${full_tag}` uses
`${prefix}` as both the in-repo subdirectory and the tag prefix.

This ADR flattens both. The hub's roots are `terraform/` and `zola-site/`, and
tags are `terraform/<provider>/<module>/vX.Y.Z` and `zola-site/vX.Y.Z`. Prefix
and subdirectory stay identical, the generator keeps one value, and the
`templates/` segment — which DEV-0154 §1 kept *only* to hold its own blast radius
down, and which DEV-0154's `## Out of scope` costed as deferred work — is gone.
It refines LIB-0001's role table rather than following it.

The seed was one `filter-repo` pass with three `--path-rename`s and a
`--tag-rename templates/:`, verified on a throwaway clone before any push.

### 2. Everything reusable moves; one thing deliberately does not

`terraform/` (13 modules), `zola-site/`, the five reusable workflows,
`template-release.yml`, `module-docs.yml`, `.github/scripts/root-changelog.sh`,
the `release-pr` skill, the generator, and `adr/pigeon-lib/` → `docs/adr/`.

`pigeon-dev-pages.yml` stays in `pigeon.dev`: `actions/deploy-pages` targets the
calling repo, which DEV-0156 established is a constraint and not a style choice.

`zola-site-deploy.yml` is **deleted rather than moved.** It had no caller in any
of the three repos, and its `:60` hardcoded `noisypigeon.com/fetch-templates.sh`
— a path into a caller's checkout that DEV-0159 moved away. Both sites are on
Pages now, so the Scaleway-bucket variant has no future consumer. Carrying dead,
broken code into a new repo to preserve it is not preservation.

### 3. The reusable CI becomes a third release track

LIB-0001 invariant 2 says a spoke consumes versions, never branches, but all
five callers pinned `@main`. DEV-0155 deferred a `workflows/vX.Y.Z` track
deliberately — live `@main` was cheaper than paying for the track upfront, with
the track named as the escape hatch "if it ever actually bites". With three
spokes consuming the hub it stops being cheaper, so the track exists:
`.github/workflows/*.yml` and `.github/scripts/` travel under one version.

GitHub's docs say a reusable-workflow `{ref}` may be "a SHA, a release tag, or a
branch name" and say nothing about slashes, which this whole track depends on.
Verified empirically with a throwaway caller at `@workflows/v1.0.0` before
committing to the design; it resolves.

`workflows/v1.0.0` is a seed tag, cut by hand for the bootstrapping reason
DEV-0110's five module seeds had: the automation that cuts the track is added by
the PR the track would be documenting.

### 4. The generator reads two roots, and neither is `git rev-parse`

The generator moves to the hub and takes `--content-root` (the consuming site's
`content/` directory; required, because only the caller knows it), with
`LIB_ROOT` derived from `${BASH_SOURCE[0]}` and the repo slug an input
defaulting to `noisypigeon/pigeon-lib`.

Deriving from the script's own path rather than git is the property DEV-0154 gave
`resolve-theme.sh`, for the reason it recorded: an env override "fails
*silently*", because the copy that runs is the one in the fetched clone, so until
that clone is override-aware `git rev-parse` quietly resolves the **consuming**
repo and the output looks right while pointing at the wrong tree.

`url_path` is untouched. DEV-0110 called that line "the entire stable-URL
guarantee", and it is the reason this ADR rewrites zero consumer `source =`
lines — the third time that decision has paid for itself, after ADR-0136's
hostname swap and ADR-0154's repo swap.

### 5. The flatten breaks `resolve-theme.sh`, and the patch ships with it

That script is `../..`-relative by design, so dropping a path level invalidated
its root, its symlink target, its tag shape and its archive strip depth. All
four are patched, and the patch lands **in the hub**, because the clone's copy is
the one that runs — DEV-0154 §9 hit this and carried its patch across rather than
relying on seed timing.

A related trap, recorded so the next reader does not design against it: DEV-0154
§5, DEV-0154 `:184` and DEV-0156 §1 all describe a `TEMPLATES_REPO_ROOT`
environment override. It was considered, rejected for the silent-failure reason
above, and never shipped. `grep` finds nothing.

### 6. Two pre-existing breakages fixed in passing

- `template-release.yml` dispatched `zola-sites-deploy.yml` in
  `noisypigeon/noisypigeon`, a workflow DEV-0159 deleted from that repo. Every
  theme release had been failing that step. It now dispatches
  `noisypigeon-com-pages.yml` in `noisypigeon/noisypigeon.com`, the repo that
  actually renders with the theme.
- `zola-site-pages.yml` hardcoded `.templates-src/templates/zola-site/resolve-theme.sh`.
  It now takes `fetch_script` and `theme_script` as inputs — the hardcoded path
  being precisely the bug `zola-site-deploy.yml` died of.

## Consequences

- **`pull_request: closed` runs from the head ref, not the base.** DEV-0154 §9
  justified splitting "retire the automation" from "delete the content" on the
  grounds that GitHub "runs the workflow file from the **base** branch". It does
  not: the first `.github/`-touching PR here fired a `template-release.yml` step
  that existed only on the branch. The split is still the right order — smaller
  diffs, one failure mode each — but its stated *reason* is wrong, and anything
  inheriting that reason should be re-checked rather than trusted.
- **DEV-0160's predicate-drift warning came true within one commit.** Adding the
  `workflows/` track to `template-release.yml` without the matching arm in
  `root-changelog.yml`'s stand-down test made both write a root changelog line
  for the same PR; they collided on rebase. DEV-0160 wrote "if one drifts, a PR
  gets either two root lines or none" when it created the duplication. Three
  predicates now live in two files and nothing enforces that they agree.
- **A new repo needs provisioning that no ADR had enumerated.** The hub's own
  three workflows need `BOT_GITHUB_TOKEN`, and the bot account needs write
  access on the new repo — the first `root-changelog` run failed on the missing
  secret, and the second on `Permission to noisypigeon/pigeon-lib.git denied`.
  Neither is in any prior split's runbook. `release:*` labels also do not exist
  on the hub, though they do not exist on `pigeon.dev` either, so
  `template-release.yml` has always taken its documented no-label path.
- **Three repos now carry tags for the same 53 versions.** `noisypigeon` has the
  original `templates/*` set plus 20 `modules/*`, `pigeon.dev` has the
  `templates/*` set it was seeded with, and only this repo's `terraform/*` and
  `zola-site/*` tags resolve. None are deleted — DEV-0154 made that a permanent
  boundary — so the cost is three inert sets a reader may mistake for live ones.
- **The hub hosts nothing, so every deploy it triggers is cross-repo.** DEV-0156
  collapsed that coupling by colocation and this ADR re-opens it deliberately.
  DEV-0154 called the dispatch "the one piece that fails silently rather than
  loudly if missed"; there are now two of them.
- **`pigeon.dev` gains a fetch step it had deleted.** DEV-0156 removed
  `fetch-templates.sh` from that repo as the whole point of colocating. It comes
  back, which is the honest price of the spoke role.

## Out of scope

- **Step 3, the Terraform hoist.** Blocked on LIB-0001 §8: each spoke's
  `state/iam` leaf pins the monorepo's shared `root.hcl` by
  `${get_repo_root()}`, which cannot cross a repo boundary, and LIB-0001
  deliberately left the resolution to the spoke. Nothing here touches a `.tf`.
- **`terragrunt/root-hcl/`** (LIB-0001 §6). It exists to serve step 3.
- **Making `module-docs.yml`'s `working-dir` list dynamic.** Its 10-of-13
  hardcoded paths are flatten-adjusted and no more; `grafana-dashboard`,
  `iam-api-key` and `iam-application` still get no generated tables. Genuinely
  deferred, as LIB-0001 already logged. Needs an issue.
- **Dispersing `adr/pigeon.dev/` or `adr/noisypigeon.com/`.** Only the `LIB-`
  domain moved, because this is the `pigeon-lib` migration LIB-0001 deferred the
  decision to. The other two stay in `pigeon.dev` pending their own ADRs.
- **Deleting any superseded tag,** in any of the three repos. Permanent
  boundary, inherited from DEV-0154.
- **Enforcing that the three release predicates stay in sync** across
  `template-release.yml` and `root-changelog.yml`. Genuinely deferred; the
  collision above is the argument for it. Needs an issue.
- **Branch protection on the hub.** Permanent boundary for now — raised for the
  sixth time across DEV-0157, DEV-0159, NPC-0000, DEV-0160, LIB-0001 and here.

## Verification

1. The seed, before any push: 53 tags, all matching
   `^(terraform/[a-z0-9-]+/[a-z0-9-]+|zola-site)/v[0-9]+\.[0-9]+\.[0-9]+$`, zero
   non-conforming; `git log --oneline -- terraform/scaleway/compute-instance/`
   returns 46 commits, matching the source exactly, so history followed the
   rename rather than being squashed.
2. `resolve-theme.sh` against the flattened tree, all three modes: `"main"`
   symlinks to `zola-site/`; a pinned `1.2.0` materializes via `git archive`
   with `theme.toml` at the top level; an unknown version exits 1 with
   `::error::Unknown tag zola-site/v99.0.0`.
3. **The flatten's whole safety argument** — run the ported generator against a
   `pigeon.dev` content tree and diff against the pre-move output. Identical file
   sets in all three directories; all 87 release posts byte-identical; 111
   changed lines, **every one of them** a `git_source` or `github_url`. No
   `path`, `title`, `description`, `latest_version` or `versions` entry changes,
   confirmed by diffing those keys in isolation. The public contract is
   byte-identical; only the private internals moved.
4. The `workflows/` track cuts its own release end to end: `workflows/v1.0.1`
   tagged and released, with exactly one `[workflows]` root changelog line and no
   second line from `root-changelog.yml`.
5. After the spoke cutover, the live regression guard: every one of the 15
   distinct pinned versions still returns 200 with an unchanged public path, each
   `git::` target now naming `pigeon-lib.git//terraform/…`, and a real
   `terragrunt init` + `plan` on a consumer leaf reporting no changes.
6. One trivial module PR in the hub, walked end to end: tag cut under the new
   shape, Release created, unit `CHANGELOG.md` written, root rollup written, both
   dispatches fired, and the new version's redirect page, overview entry and
   release post live on `pigeon.dev`.

## Amendments

### 2026-10-17: the spokes' side of this record, folded in by LIB-0017

This record created the hub and named the end state for `pigeon.dev`. The two
records below say what each content spoke actually did to reach it. They were
filed in the spokes' own repos and are folded in here because LIB-0017 gives
spokes no ADRs of their own.

### 2026-10-17: DEV-0162, `pigeon.dev` becomes a content-only spoke (folded from `noisypigeon/garden`)

Filed 2026-10-15 in `noisypigeon/pigeon.dev`, now `noisypigeon/garden`.
Accepted. The full text is also kept verbatim in the archive, as
[`archive/DEV-0162`](archive/DEV-0162-make-pigeon-dev-a-content-only-spoke.md).

**Context.** DEV-0154 and DEV-0156 had deliberately made `pigeon.dev` hold the
templates and the site side by side. That was right for a repo that owned the
templates, and wrong for a spoke. The one thing that had to stay was the
module short URL, a stable public interface (DEV-0109, DEV-0110) that belongs
to the domain rather than to the code.

**Decision.**

1. **The hub is consumed by pin.** `.lib-version` names a hub ref, and
   `fetch-lib.sh` materializes it, blobless and with tags, into a gitignored
   `.lib-src/`. Setting `LIB_SRC` points it at a local checkout, which is how
   to iterate against an unreleased hub change. `fetch-lib.sh` is the one
   script a spoke keeps, because a spoke cannot fetch its own fetcher.
2. **Two thin workflows remain.**
   - The Pages caller stays in the spoke, because `actions/deploy-pages`
     always deploys the *calling* repo's site.
   - `root-changelog.yml` keeps DEV-0160's contract and runs the hub's script.
     It lost its stand-down block: with `template-release.yml` gone, that
     block's predicate matched exactly the diff that deleted the modules, and
     would have silently dropped the entry.

   Deleted: `template-release.yml`, `module-docs.yml`, the six reusables
   (whose callers already pointed at the hub), the `release-pr` skill and the
   vendored `root-changelog.sh`.
3. **`templates/` was deleted and its 53 tags kept.** That is DEV-0154's
   boundary: no superseded tag is ever deleted. The tags are now unreferenced.
4. **`pigeon.dev/src` became `web/`,** as a pure rename separate from the
   deletion, per DEV-0110's "pure rename first, rewiring second".

**Still true.**

- A change spanning hub and spoke is two PRs, hub first.
- A spoke has no releasable unit and carries no `release:*` labels.
- A local build costs a blobless clone, unless `LIB_SRC` is set.
- **The Pages deploy has one unmitigated failure mode.** `actions/deploy-pages`
  gives up after a hard 600000 ms ceiling. If that expires while Pages still
  reports `updating_pages`, it cancels a deployment the service still holds.
  Every later deploy then fails with `due to in progress deployment` until a
  server-side reaper clears it, which took about 45 minutes in the one
  incident recorded. No client-side API shortens that wait.

**Verification facts worth keeping.**

- The deletion was proven inert before it happened: a rebuild with
  `templates/` moved aside was byte-identical.
- `module-docs.yml` had to be removed first, because it triggers on `push`.
- DEV-0154 §9's claim that a `pull_request` workflow runs from the base ref is
  wrong: it runs from the head ref.

Original: [DEV-0162](https://github.com/noisypigeon/garden/blob/13bcee9a79c86a3a0054ebda7cd6d7fa7c238df2/adr/DEV-0162-make-pigeon-dev-a-content-only-spoke.md).

### 2026-10-17: COM-0001, `noisypigeon.com` becomes a content-only spoke (folded from `noisypigeon/blog`)

Filed 2026-10-15. This is the content half of LIB-0001 §7 step 4. Accepted.

**Decision.**

1. **Hub first.** pigeon-lib#13 added an optional `src_dir` input to
   `blog-changelog.yml` (`workflows/v1.1.0`, additive). The workflow refuses a
   call passing both `src_dir` and `site_dir`, or neither, or `src_dir`
   without `changelog_path`. The spoke's pin bump landed alone before the
   rename, so any regression would show on its own.
2. **`noisypigeon.com/src` became `web/`** (noisypigeon.com#8), a pure rename.
   `fetch-lib.sh` moved to the repo root to match `pigeon.dev`. `web/` was
   chosen over the repo root for parity between the spokes, which pass the same
   inputs to the same reusables, and to keep Zola's directories apart from the
   repo's.
3. **DEV-0160's two-tier changelog.**
   - The PR-body long form moved to `web/CHANGELOG.md`, five-line header
     byte-identical. Zola ignores loose files in the site root, so it is not
     published.
   - The root `CHANGELOG.md` gets one line per merged PR, backfilled by hand
     for the earlier PRs (noisypigeon.com#9). `blog-changelog.yml` keeps
     `root_changelog_tag` empty, so the root file has one writer.
4. **`NPC-` became `COM-`.** `NPC-0000` was renamed `COM-0000`, file and H1
   only. Existing `NPC-` citations are aliases and are never rewritten, which
   is DEV-0160's method for `ADR-`.

**Still true.**

- A blog PR produces two bot commits: the long form and digest, then the root
  line.
- A content PR that also touches `.github/` is tagged `blog`, because the
  first match wins.

**Verification fact.** The rename was proven inert by building both trees with
`SITE_COMMIT_SHA` pinned: `diff -r` printed nothing across 66 pages.

**Later.** COM-0002 made the root writer a thin caller, closing
noisypigeon/noisypigeon#306. COM-0003 hoisted the Terraform.

Original: [COM-0001](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0001-make-noisypigeon-com-a-content-only-spoke.md).
