# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.3] - 2026-10-16

### Drop pigeon.dev from comments and docs

Comments and docs across the hub now describe the current architecture only. `pigeon.dev` is gone from them: the site repo is `noisypigeon/garden`, and module sources are `https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z`.

- **`terragrunt/root-hcl`:** the template's header drops how it was generalized from the monorepo's per-domain roots, and its example secret is a real current one. Only comments change, so every leaf renders exactly as it did under v2.2.0, and a spoke can take this version as a no-op.
- **`scaleway/project`:** the header comment drops the module's relocation history. No inputs, outputs or resources change.
- **`generate-module-redirects.sh`:** a comment change only.
- **Docs:** `CLAUDE.md`, `terraform/README.md`, `terragrunt/root-hcl/README.md`, `zola-site/README.md` and the `release-pr` skill name `noisypigeon/garden` and the current host, without the pigeon.dev history.
- **LIB-0009** gets an amendment line. `pigeon.dev` redirects to `https://noisypigeon.com`, not the garden (noisypigeon/noisypigeon.com#33).

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#55](https://github.com/noisypigeon/pigeon-lib/pull/55)

## [2.0.2] - 2026-10-16

### Use noisypigeon.garden/terraform/ short URLs

Module short URLs now live at `https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z` ([LIB-0009](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0009-terraform-short-urls-move-to-noisypigeon-garden.md)). The old `https://pigeon.dev/modules/...` URLs no longer resolve.

- **`scaleway/pigeon-cluster`** sources its ten nested modules from the new URLs, at the same versions as before. Every earlier `pigeon-cluster` tag nests `pigeon.dev` URLs and can no longer `terraform init`, so a consumer of this module should pin this release or later. Nothing else about its inputs, outputs or resources changes.
- **`scaleway/project`** changes only a comment, which names the new URL.
- **Docs:** every module README's usage example, `terraform/README.md`, the root `README.md` and `CLAUDE.md`, `zola-site/README.md` and the `release-pr` skill use the new host.

Verified by running `terraform init` and `terraform validate` on `pigeon-cluster`: all ten nested sources downloaded from `noisypigeon.garden`, and the configuration is valid.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#53](https://github.com/noisypigeon/pigeon-lib/pull/53)

## [2.0.1] - 2026-10-15

### Note why the ssh key uses count, not for_each

`ssh_key` is a single optional object rather than a collection, so `count` is right and the address is always `[0]` when set. The consequence worth writing down is the one a reader won't infer: toggling the input between `null` and a value is a **create/destroy of that address, not a move** — flipping it rotates the registered key rather than renaming one in place.

Comment-only: four lines, zero non-comment additions, `terraform fmt -recursive -check` clean.

### This also re-attempts what #9 was meant to prove

#9 was the comment-only release intended to exercise the module-release chain end to end. It did exercise it — and **found that the chain was broken**. Its `template-release` run was cancelled while pending, because three workflows shared one concurrency group and GitHub allows only one pending run per group. Fixed in #10.

**Re-running #9 could not recover it.** The root `CHANGELOG.md` had since gained #10's line at the same sentinel position, so the rebase conflicted:

```
Auto-merging CHANGELOG.md
CONFLICT (content): Merge conflict in CHANGELOG.md
error: could not apply b28f832... chore: update changelog(s) for PR #9
```

That is the correct outcome twice over: a conflict means two writers touched the same lines and guessing is worse than failing, and because the push happens *before* tagging, the failure left **no tag, no Release and no changelog entry** — a clean no-op rather than a half-applied release. Worth knowing as an operational fact: **a dropped release cannot be recovered by re-run once `main` has moved.** It needs a fresh PR, which is this one.

So the provenance comment from #9 is on `main` but is not in any published version. This PR is the first module release to run against the fixed workflows, and `v2.0.1` will carry both comments.

### What should happen on merge

1. `terraform/scaleway/project/v2.0.1` tagged and released
2. Full body into `terraform/scaleway/project/CHANGELOG.md` under `## [2.0.1]`
3. One root line tagged `[scaleway/project]`, with `root-changelog` standing down
4. `pigeon-dev-pages.yml` dispatched **cross-repo** into `noisypigeon/pigeon.dev`
5. `/modules/scaleway/project/v2.0.1/` live, plus an overview entry and a release post

Steps 4–5 are still unproven: every release so far has been on the `workflows/` track, which cuts no module tag and so never reaches the dispatch. This is the first run that should.


[#11](https://github.com/noisypigeon/pigeon-lib/pull/11)

## [2.0.0] - 2026-10-03

### Continue this module's version lineage under the templates/terraform prefix

DEV-0110 moved `modules/` to `templates/terraform/` and cut one tag per module
under the new prefix to continue each module's version lineage there. This
version's own GitHub Release describes it as "Bookkeeping only -- same tree
content as the move commit, no resource/behavior change", following the same
pattern DEV-0093 used for its own prior move. The tag and its Release were created
with PR #144; only the changelog entry was missed, which is what this backfills by
hand, since the automation writes entries from PR bodies alone.

**No behaviour change.** This version's `main.tf`, `inputs.tf`, `outputs.tf` and `versions.tf` are byte-identical to
`v1.0.0`'s. The major bump records a change to the module's *source path* only:
a module's source path is part of its public interface, so relocating it is
breaking for every consumer regardless of whether any resource definition changed
(DEV-0093, DEV-0110).

Consumers pinning `v1.0.0` and `v2.0.0` resolve identical module content; the
difference is which repo and tag the short URL resolves to.

[#144](https://github.com/noisypigeon/noisypigeon/pull/144)

## [1.0.0] - 2026-10-02

### Move scaleway modules to top-level modules/, major release each

Moves `terraform/modules/scaleway/*` to top-level `modules/scaleway/*` and cuts a major release for every module, fixing the stale `noisypigeon/pigeon.git` repo name (a prior name of this same repo) to the real current name, `noisypigeon/noisypigeon.git`, in every source string along the way.

**Version bumps** (next available major per module, not a blanket v1.0.0 — two modules were already past 1.0):

| Module | Before | After |
|---|---|---|
| `project` | 0.2.1 | **1.0.0** |
| `object-bucket` | 0.2.0 | **1.0.0** |
| `iam-policy` | 1.1.1 | **2.0.0** |
| `compute-instance` | 0.9.1 | **1.0.0** |
| `block-volume` | 1.0.0 | **2.0.0** |

To make the existing automation compute these correctly (its version lookup is tag-prefix-based and all 22 existing tags live under the old `terraform/modules/scaleway/*` prefix), 5 bookkeeping-only seed tags mirroring each module's current version were pushed directly to origin under the new prefix before this PR — no GitHub Release, no CHANGELOG entry, just enough for `module-release.yml`'s `$LATEST` lookup to find a baseline.

**All 16 live consumers** across `terraform/infrastructure/scaleway/**` updated to the new repo name, new path, and new major tag — this also converges pre-existing version drift (`iam-policy` had one consumer on v0.1.0 against five on v1.1.1; `object-bucket` had three different pinned versions across seven consumers). Verified safe: every variable beyond the always-supplied required ones has a default in both modules, so no consumer needs a new argument added.

Also: `module-release.yml`/`module-docs.yml`'s hardcoded `terraform/modules/scaleway` paths, the `release-pr` skill's path references, `modules/README.md` (moved, repo name and tag-scheme examples fixed), and `terraform/README.md` deleted (its "two independent trees" premise no longer holds once `modules/` isn't under `terraform/`).

Checked every other repo in the `noisypigeon` org (`pigeon-cli`, `pigeon-os`, `dotfiles`) for external consumers — none found.

Full rationale in [ADR-0093](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0093-move-scaleway-modules-to-top-level-modules.md).

## Test plan
- [x] `terraform fmt -check -recursive` clean on `modules/` and `terraform/infrastructure/scaleway/`
- [x] `terragrunt hcl format --check` clean on `modules/`
- [x] `grep -rn "terraform/modules/scaleway\|noisypigeon/pigeon\.git"` returns nothing outside historical ADRs/CHANGELOGs
- [x] All 16 consumer leaves + 1 dead/commented reference verified updated
- [ ] User to run `terragrunt init` on affected leaves to confirm the new module source resolves correctly (not performed here — would need real credentials)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#120](https://github.com/noisypigeon/noisypigeon/pull/120)

## [0.2.1] - 2026-09-30

### Fix scaleway/project ssh_key to scope to the created project

`scaleway/project`'s `scaleway_iam_ssh_key` resource (added in v0.2.0) was missing `project_id`, so it registered the SSH key against the Scaleway provider's default project rather than the project this module just created. This adds `project_id = scaleway_account_project.project.id` so the key is correctly scoped to the module's own project.

No input or output changes — this only fixes the behavior of the existing `ssh_key` input.

[#107](https://github.com/noisypigeon/noisypigeon/pull/107)

## [0.2.0] - 2026-09-30

### Add optional ssh_key input to scaleway/project

`scaleway/project` now accepts an optional `ssh_key` input (`{ alias, public_key }`) that registers a Scaleway IAM SSH key alongside the project via `scaleway_iam_ssh_key`. It's opt-in — omitting `ssh_key` (the default) skips creating the resource entirely, so existing consumers of this module are unaffected. When provided, the new `ssh_key_id` output exposes the created key's ID so it can be wired into a `scaleway/compute-instance` or similar downstream resource without a separate lookup.

This mirrors the pattern `scaleway/compute-instance` already uses for bucket access: project-adjacent identity/access resources are composed through the project module's own inputs rather than requiring a second module invocation.

[#106](https://github.com/noisypigeon/noisypigeon/pull/106)

## [0.1.0] - 2026-09-26

### Consolidate as terraform/modules/scaleway/project 0.1.0

A thin wrapper around `scaleway_account_project`, mirroring
`terraform/modules/digitalocean/project`'s layout and passthrough style —
this was `pigeon-tf`'s first module under the `scaleway/` provider root
(documented in
[ADR-0043](../../../../docs/adr/0043-add-scaleway-provider.md)), which also
generalized the release automation beyond a single hardcoded provider root.

Consolidates this module's prior `pigeon-tf` version history (`v0.1.0`) into
a single 0.1.0 release as part of merging `pigeon-tf` into this repo — see
[ADR-0037](../../../../docs/adr/0037-merge-pigeon-tf-terraform-modules.md)
for the merge.
