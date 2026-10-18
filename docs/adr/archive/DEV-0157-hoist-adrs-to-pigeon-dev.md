# DEV-0157: hoist `docs/adr/` to the `pigeon.dev` repo as `adr/infrastructure/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-12.
- **Status**: Accepted.

## Context

This repo is now a consumer of `noisypigeon/pigeon.dev` for everything reusable it once owned: the Terraform modules and the `zola-site` theme (ADR-0154), and the job bodies of every GitHub Actions workflow (ADR-0155). `pigeon.dev` has since grown past what either ADR anticipated — its own Zola site source moved there too, something ADR-0154 explicitly listed as out of scope — and is in practice this project's upstream repo rather than a template bucket. The ADR corpus is the last large body of shared documentation still pinned here.

`docs/adr/` holds 112 files, 11,518 lines, 1.1M, numbered 0031–0156. Roughly 60 of them have a subject that no longer exists in this repo at all: the internal design of modules that now live in `pigeon.dev` (`compute-instance` and its 24 ADRs, `object-bucket`, the IAM trio, `pigeon-cluster`, the Backblaze pair), the `zola-site` theme, and the workflow implementations. Someone reading `compute-instance`'s code in `pigeon.dev` has no ADRs beside it; someone reading this repo gets 60 ADRs about code that isn't here. Putting the corpus at `pigeon.dev/adr/infrastructure/` inverts that in the direction the code already went, and the `infrastructure/` path segment leaves room for a sibling domain later without a second move — the same forward-compatibility argument ADR-0124 used for its `scaleway/` segment, which ADR-0127 then actually exercised.

The cost is that this repo loses its in-repo design narrative at exactly the moment ADR-0156 made `docs/adr/` the thing `CLAUDE.md` points at for rationale. A new `docs/ARCHITECTURE.md` takes over that role: longform, current-state-only design reasoning, kept in this repo and readable by `CLAUDE.md` on demand, with the decision records themselves one repo away.

### What this reverses

ADR-0154 §8 made this a deliberate boundary, not a deferral:

> ADRs are **not** renumbered, split, or archived. All 29 `templates/`-referencing ADRs stay here, as the decision history of the repo that made those decisions and still owns the site that serves their output; the new repo's `CLAUDE.md` points back at `noisypigeon/noisypigeon`'s `docs/adr/` rather than keeping a filtered copy. This differs from ADR-0084, which gave the departing repo a filtered `docs/adr/`, because there the departing code was the *subject* of 51 ADRs; here the subject of nearly every `templates/`-touching ADR is the monorepo's own layout and automation, which is staying.

and its Out of scope repeated: *"Renumbering, splitting, or archiving this repo's ADRs, per §8. Not deferred — a deliberate boundary."*

That argument turned on a factual claim — that the ADRs' subject is this repo's own layout and automation, which stays. ADR-0155 then moved the automation out, and `pigeon.dev` absorbed the site source. The claim no longer holds for the ~60 module/theme/workflow ADRs, so the boundary it justified is reversed here. Note this ADR does **not** adopt the part of ADR-0154 §8 it argued against: nothing is renumbered or split, and no filtered copy is kept. The whole corpus moves intact.

ADR-0156 is also superseded in part: it made `docs/adr/` "the sole record of how the repo got here" and pointed `CLAUDE.md` at it. The in-repo half of that role passes to `docs/ARCHITECTURE.md`. ADR-0156's actual decision — that `CLAUDE.md` documents current state only and is edited only when a current-state fact changes — stands unchanged.

### Findings that shaped this

- **Nothing in CI breaks.** No workflow reads `docs/adr/`; the only references are two cosmetic comments (`terragrunt-plan.yml:5`, `zola-sites-deploy.yml:24`). Every PR in this sequence is docs-only, so ADR-0129's `detect` job sets `terragrunt/apply` to success without a real run.
- **`.templates-src` cannot host ADR authoring.** `workloads/pigeon.dev/fetch-templates.sh` does `git reset --quiet --hard origin/HEAD` on every build; an in-progress ADR there would be destroyed by the next `mise run pigeon-dev-build`. A separate clone is required, and it must not share that script's reset semantics.
- **`adr-issue.sh` needs one fix, not a rewrite.** Its ADR paths are already fully parameterized (`--adr-line FILE:LINE`, resolved against CWD), so they work at any path. But every `gh` call omits `-R`, inferring the repo from the CWD's git remote — the same latent fragility ADR-0155 found and fixed in `blog-changelog`'s trailing `gh workflow run`. Pointed at an ADR in another checkout it would silently file the issue in the wrong repo.
- **The destination is non-empty**, so the seed is `git filter-repo` plus `git merge --allow-unrelated-histories` — ADR-0037's recipe for merging `pigeon-tf` *in*, now run to push ADRs *out*. ADR-0154 could use a plain `push -u origin main` only because `pigeon.dev` was pre-created empty for it.
- **Numbering is already not unique.** Duplicate numbers exist at `0136` (`move-module-redirect-urls-to-pigeon-dev`, `pigeon-cli-jobs-dashboard`) and `0138` (`fix-terragrunt-filter-affected-non-tf-files`, Accepted; `autoscale-compute-instances-per-job`, Exploration), from parallel branches. Four ADRs use unbolded `- Status:` rather than `- **Status**:`. Both are pre-existing warts that a flat directory tolerates; normalizing them is out of scope and would break citations.
- **`ADR-0084` is a reused number.** The original `0084-split-pigeon-cli-repo.md` was deleted here in `1dad8f7` and the number reassigned to `0084-force-instance-replacement-on-scaleway-compute-instance-cloud-init-change.md`. The original survives only in `noisypigeon/pigeon-cli`. Every `ADR-0084` citation meaning "the pigeon-cli split" — including two that ADR-0156 wrote into `CLAUDE.md` days ago, and one in `docs/USAGE.md` — therefore resolves to an unrelated ADR about cloud-init. Fixed here by naming the repo.
- **`CLAUDE.md` had drifted again within days of ADR-0156 rewriting it**, which is the sharpest available evidence for why `ARCHITECTURE.md` must be written against the live tree rather than from prior prose. Three errors, all introduced by ADR-0156 and all fixed here: the per-leaf region override file is `scaleway_config.hcl`, not `workload_definition.hcl`; its claimed sole user (`willowgraysen.com/terraform/custodial-storage/duck-jellyfish`, `nl-ams`) does not exist — the mechanism currently has **zero** users and there is no `nl-ams` leaf anywhere; and the two `(ADR-0084)` citations above. `workloads/root.hcl` additionally cites `docs/adr/0006-automatic-bucket-name-locals.md`, which has not existed in this repo since the pigeon-cli split deleted 0001–0030.

## Decision

Move all 112 ADRs to `noisypigeon/pigeon.dev` at `adr/infrastructure/`, preserving git history; add `docs/ARCHITECTURE.md` as this repo's standalone design narrative; and add tooling so an ADR authored from here lands in the right repo. ADR numbers are unchanged — renumbering would break several hundred `ADR-NNNN` citations across `root.hcl`, `*.tf`, `CHANGELOG.md`, and published site content, for no reader benefit.

Lands as three ordered steps, by blast radius, matching ADR-0154/0155.

### PR 1 — this ADR, `ARCHITECTURE.md`, and the tooling

All of it tolerant of `adr/infrastructure/` not existing yet, so it can land before the seed.

- This ADR, plus `Status` edits marking ADR-0154 and ADR-0156 superseded in part. These must land in PR 1 so the seed carries them.
- **`docs/ARCHITECTURE.md`** — comprehensive and current-state-only, covering: the workload layout; Terragrunt roots, state keys and provider generation; the secrets model; the module **consumption** contract (short URLs and version pinning, not module internals); Zola site and theme consumption; CI as this repo consumes it; `pigeon-cluster`, the one design area still wholly here; and a short decommissioned-history note. Every path, task and resource it names was checked against the live tree, not against prior prose.
- **`.github/scripts/fetch-adrs.sh`** — maintains a gitignored full clone of `pigeon.dev` at `/.adr-src/`. Deliberately *not* modeled on `fetch-templates.sh`'s reset semantics: it clones if absent, otherwise fetches, and **refuses to run** with a clear message if the clone is dirty or mid-rebase, rather than resetting over work in progress. Honors an `ADR_SRC` override the way `fetch-templates.sh` honors `TEMPLATES_SRC`.
- **`.github/scripts/adr-new.sh`** — `--title "..."` fetches, computes the next number as `max+1` across `adr/infrastructure/`, slugifies the title, branches off `origin/main`, writes the four-section skeleton with today's date, and prints the follow-up `git`/`gh pr create -R noisypigeon/pigeon.dev` commands. It scaffolds and branches but deliberately does not commit: writing the ADR is the actual work, and an auto-commit would just have to be amended.
- **`.github/scripts/adr-issue.sh`** — gains `--repo SLUG`, defaulting to `noisypigeon/noisypigeon`, passed as `-R` to all four `gh` call sites. The default is deliberate: the ADR *text* now lives in `pigeon.dev`, but an Out-of-scope item is work against *this* repo's infrastructure, so the issue belongs here. Making it explicit also removes the CWD-inference fragility.
- `.mise.toml` gains `adr-fetch` and `adr-new`; `.gitignore` gains `/.adr-src/`.

### Step 2 — seed `pigeon.dev` (performed by hand)

Like ADR-0052 and ADR-0154, this ADR does not execute its own move. Run after PR 1 merges, so this ADR and the two `Status` edits are included:

```sh
# 1. Filter a throwaway clone down to the ADRs, renaming the path in place.
git clone git@github.com:noisypigeon/noisypigeon.git /tmp/adr-seed
cd /tmp/adr-seed
git filter-repo --path docs/adr/ --path-rename docs/adr/:adr/infrastructure/

# 2. Merge that history into a real pigeon.dev checkout (NOT .templates-src).
git clone git@github.com:noisypigeon/pigeon.dev.git /tmp/pigeon-dev
cd /tmp/pigeon-dev
git checkout -b hoist-adrs
git remote add adr-seed /tmp/adr-seed
git fetch adr-seed
git merge --allow-unrelated-histories adr-seed/main
git push -u origin hoist-adrs        # note: no --tags
```

Two guardrails:

- **Never `git push --tags`** from the seed clone. `--path docs/adr/` prunes the commits the 20 legacy `modules/*` tags point at, and one of those tags (`scaleway/project/v1.0.0`) is still live-pinned by a leaf here. Pushing tags from a filtered clone risks disturbing tags that must keep resolving as module sources — ADR-0154's central complication, re-encountered from the other direction.
- Before merging, verify `ls adr/infrastructure | wc -l` is 112 and that `git log --follow adr/infrastructure/0031-*.md` shows real pre-move history.

### PR 3 — removal and rewiring

`git rm -r docs/adr/`, leaving `docs/` as `ARCHITECTURE.md`, `USAGE.md` and `pigeon.gif`; then repoint every reference: `CLAUDE.md` (at `adr/infrastructure/` and `ARCHITECTURE.md`, plus the `ADR-0084` and `scaleway_config.hcl` fixes above), `docs/USAGE.md` (its broken relative link, its `ADR-0084` reference, and its stale `blog-build` paths that ADR-0156 left out of scope), `workloads/README.md` (six relative `../docs/adr/*` links that would 404, rewritten as absolute URLs), and the bare path comments in `.env.example` and `generate-module-redirects.sh`.

The ~40 bare `ADR-NNNN` citations in `workloads/**/*.{hcl,tf}` are deliberately left alone. They are numbers, not paths; they still identify the right record, just in another repo. Rewriting them is churn.

## Consequences

- The ADR corpus lands in a repo with **no branch protection and no required status checks** (`rulesets` is empty; `branches/main/protection` returns 404). ADR-0155 flagged exactly this when CI definitions moved and called it the sharpest thing it left open; the ADR corpus now inherits it. Deferred, with an issue.
- Writing an ADR becomes a cross-repo PR, gated by nothing. `mise run adr-new` removes the clone-and-numbering friction but not the context switch. This is the real recurring cost of the decision.
- Two absolute `blob/main/docs/adr/...` URLs in `workloads/noisypigeon.com/CHANGELOG.md` will 404 after PR 3, one of them already pointing at a stale branch. Per ADR-0108's no-rewrite-history precedent for changelogs, they are left as-is rather than edited; an issue tracks whether to redirect them.
- This repo's `git log` retains commits for ADRs no longer checked out — the same side effect ADR-0084 accepted for its split, and unavoidable without rewriting this repo's history, which is not on the table.
- Reading rationale now means either `docs/ARCHITECTURE.md` (current state, in-repo, always consistent with the tree) or `pigeon.dev/adr/infrastructure/` (full history, one repo away). The failure mode to watch is `ARCHITECTURE.md` drifting the way `CLAUDE.md` did twice; it is a current-state document and is edited when the tree changes, same rule as ADR-0156 set for `CLAUDE.md`.
- `pigeon.dev` now holds four distinct kinds of thing (modules, theme, reusable workflows, ADRs) plus its own site. If that repo ever needs its own structural ADR, it has somewhere to put it — which was the point of the `infrastructure/` segment.

## Out of scope

- Renumbering, deduplicating the two collided numbers (0136, 0138), or normalizing the four unbolded `Status` lines. All pre-existing; all would break citations.
- Adding branch protection or required checks to `pigeon.dev`. Genuinely deferred — tracked.
- Fixing the two stale `blob/main/docs/adr/...` URLs in published changelog content. Genuinely deferred — tracked.
- Rewriting the ~40 bare `ADR-NNNN` comment citations in `*.hcl`/`*.tf`, or the dangling `docs/adr/0006-*` citation in `workloads/root.hcl` left over from the pigeon-cli split.
- Any ADR for `pigeon.dev`'s own concerns (`adr/templates/` or similar). This ADR only establishes that `adr/<domain>/` has room for it.
- `docs/USAGE.md`'s broader overlap with the new `ARCHITECTURE.md`. PR 3 fixes its broken links and stale commands but does not reconcile the two documents' scope.
