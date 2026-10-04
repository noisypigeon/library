# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
