# DEV-0106: regroup Scaleway-specific leaves under `workloads/scaleway/terraform/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

Following the same function-grouping idea ADR-0105 applied to Cloudflare DNS leaves (`workloads/dns/`), two leaves move into a regrouped `workloads/scaleway/terraform/`:

1. `workloads/scaleway/terraform/` itself (previously 4 files directly in the directory — `terragrunt.hcl`, `bucket.tf`, `iam.tf`, `project.tf`: the repo's own bootstrap leaf, provisioning its Terraform state bucket, deployer IAM application/policy/API key, and Scaleway project/SSH key, moved here by ADR-0094) → `workloads/scaleway/terraform/management/`.
2. `workloads/custodian-buckets/terraform/duck-jellyfish/` (the `nl-ams` cross-region backup bucket, with its `workload_definition.hcl` region override, moved here by ADR-0098) → `workloads/scaleway/terraform/custodian/duck-jellyfish/`.

Both destination directories already existed on disk as empty, untracked placeholders — `workloads/scaleway/terraform/management/` and `workloads/scaleway/terraform/custodian/duck-jellyfish/` — the same pre-scaffolding pattern seen before the `dns/` moves in ADR-0105.

**Research confirmed, verbatim, before planning anything:**

- `workloads/root.hcl`'s `is_valid_leaf` guard only checks that path segment index 1 equals `"terraform"` — any depth below that is fine by design (widened for exactly this purpose by ADR-0096). Both new paths (`scaleway/terraform/management`, `scaleway/terraform/custodian/duck-jellyfish`) already satisfy it. **No `root.hcl` change needed.**
- The `workload_definition.hcl` override mechanism and the `remote_state` backend key are both purely derived from `path_relative_to_include()` plus `root.hcl`'s own fixed location — both resolve correctly at the new, deeper paths automatically. `duck-jellyfish`'s `workload_definition.hcl` (`scaleway_region = "nl-ams"`, `scaleway_zone = "nl-ams-1"`) moved with it unchanged and kept working — confirmed live: the migrated leaf's `scaleway_object_bucket` resource refreshed with id `nl-ams/custodian-gs2qtu-dawna`, proof the region override is still correctly applied at the new path, not just that the move didn't error.
- A fresh repo-wide grep for `dependency`/`dependencies` Terragrunt blocks under `workloads/` found zero real hits — reconfirms ADR-0094's original finding that credentials flow via hand-copied `.env` values (`SCALEWAY_ACCESS_KEY`/`SECRET_KEY`), not live Terragrunt dependencies. Safe to move both leaves independently.
- A grep for the literal strings `"management"` and `"custodian"` found no existing path-segment special-casing anywhere in the repo (the only such branching in `root.hcl` is the unrelated `pigeon.dev` Cloudflare-credential check) — neither new path collides with any hidden behavior.
- **`workloads/custodian-buckets/terraform/duck-jellyfish-import/` (the `fr-par` source-side sibling bucket from ADR-0098) no longer exists** — a repo-wide `find` turned up nothing, and `git log` traced it to a separate, already-committed change (`8adc538 chore(scaleway): reconcile custodian-buckets and pigeon-cli state`) that deleted it outright, not moved it. So `duck-jellyfish` was `workloads/custodian-buckets/`'s *only* remaining leaf going into this move. Moving it out leaves that workload with zero files — consistent with every prior ADR that emptied out a workload (ADR-0105's `workloads/email/`/`workloads/bluesky/`), it's decommissioned entirely.
- The bootstrap leaf (move 1) is the most sensitive leaf in this repo: it provisions the Terraform state bucket holding every leaf's state (including its own) and the deployer IAM identity every other Scaleway leaf authenticates as. ADR-0094 already proved this exact leaf survives a path-based state migration safely — this is its second move, same mechanics — but the live `terragrunt plan` → "No changes" verification afterward was given extra scrutiny rather than a quick glance.
- Both moves require a real state migration (the backend key is `workloads/${path_relative_to_include()}/terraform.tfstate`, purely path-derived) — `terragrunt init -migrate-state` does not work across a directory move (Terragrunt's local init-pointer is keyed by filesystem path), so both went through the established `state pull`/`push`-via-worktree runbook.

## Decision

### Move the management (bootstrap) files

The destination `management/` directory already existed and the source files sat directly in `workloads/scaleway/terraform/` (not inside a subdirectory being renamed) — a plain file-level `git mv`, not the directory-onto-directory case:

```sh
cd workloads/scaleway/terraform
git mv terragrunt.hcl management/terragrunt.hcl
git mv bucket.tf       management/bucket.tf
git mv iam.tf          management/iam.tf
git mv project.tf      management/project.tf
```
The stale, gitignored `.terraform.lock.hcl` at the old location was removed (not `git mv`'d, since it's untracked) — a fresh `terragrunt init` regenerated it at the new location. Verified: `find workloads/scaleway/terraform -maxdepth 1 -type f` showed nothing left; `find workloads/scaleway/terraform/management -type f` showed the 4 moved files.

### Move the duck-jellyfish leaf

This *was* a directory-onto-existing-empty-directory move, so the established ADR-0097/0098 gotcha fix applied — remove the pre-scaffolded empty placeholder immediately before the `git mv`:

```sh
rmdir workloads/scaleway/terraform/custodian/duck-jellyfish
git mv workloads/custodian-buckets/terraform/duck-jellyfish workloads/scaleway/terraform/custodian/duck-jellyfish
# verified: terragrunt.hcl, bucket.tf, iam.tf, workload_definition.hcl, .terraform.lock.hcl -- flat
```

With this leaf moved out, `workloads/custodian-buckets/` had no tracked files left (`git ls-files workloads/custodian-buckets` → empty) — decommissioned entirely, same treatment ADR-0105 gave `workloads/email/`/`workloads/bluesky/`.

### No `workloads/root.hcl` changes

Confirmed above: the leaf-depth guard, `workload_definition.hcl` resolution, and remote-state key are all already path-generic — neither move needed any `root.hcl` edit.

### Documentation

- `CLAUDE.md`'s workloads description paragraph: the `workloads/scaleway/terraform/` sentence now describes the `management/`/`custodian/duck-jellyfish/` split and the `custodian-buckets/` decommission; the `terraform/infrastructure/` decommission sentence's `duck-jellyfish` path reference updated to its new location; ADR index gained this entry.
- `workloads/README.md`: tree example updated (`scaleway/terraform/{management,custodian/duck-jellyfish}/`, `custodian-buckets/` block removed, which also incidentally dropped a stale `duck-jellyfish-import` mention the tree example hadn't been updated to remove when that sibling was deleted); the "infrastructure-only, no `src/`" sentence and the `workload_definition.hcl` example path both updated.
- `docs/USAGE.md`: `workloads/custodian-buckets/terraform/` bullet removed; `workloads/scaleway/terraform/` bullet broadened to describe both sub-leaves.

### The actual state migration — performed live, both leaves verified clean

Same worktree-based `state pull`/`push` runbook as every prior leaf move in this repo:

```bash
git worktree add /tmp/old-scaleway-moves HEAD
cp .env /tmp/old-scaleway-moves/.env

# duck-jellyfish first
cd /tmp/old-scaleway-moves/workloads/custodian-buckets/terraform/duck-jellyfish
terragrunt init -input=false
terragrunt state pull > /tmp/duck-jellyfish.tfstate   # 5 resources: random_string, bucket, iam application/policy/key

cd /Users/pigeon/Developer/noisypigeon/workloads/scaleway/terraform/custodian/duck-jellyfish
terragrunt init -input=false
terragrunt state pull   # confirmed empty before pushing
terragrunt state push /tmp/duck-jellyfish.tfstate
terragrunt plan -input=false   # "No changes" -- bucket id nl-ams/custodian-gs2qtu-dawna confirms region override still correct

# then the bootstrap leaf, with extra scrutiny
cd /tmp/old-scaleway-moves/workloads/scaleway/terraform
terragrunt init -input=false
terragrunt state pull > /tmp/scaleway-management.tfstate   # 7 resources: random_string, bucket, iam application/policy/key, project, ssh key

cd /Users/pigeon/Developer/noisypigeon/workloads/scaleway/terraform/management
terragrunt init -input=false
terragrunt state pull   # confirmed empty before pushing
terragrunt state push /tmp/scaleway-management.tfstate
terragrunt plan -input=false   # "No changes" -- bucket id fr-par/terraform-t0nh1b-state confirms it's the same real state bucket

git worktree remove /tmp/old-scaleway-moves
rm /tmp/duck-jellyfish.tfstate /tmp/scaleway-management.tfstate
```

Neither `state pull` nor `state push` talks to the Scaleway API — only `plan`'s refresh does, and for both leaves it returned the exact same resource IDs as before the move (same bucket names, same IAM application/key IDs), proving this was pure bookkeeping relocation with zero resource disruption — notably including zero disruption to the deployer identity every other leaf in this repo authenticates as.

## Consequences

- `workloads/scaleway/terraform/management/` and `workloads/scaleway/terraform/custodian/duck-jellyfish/` are live and runnable immediately — state migrated and verified via `terragrunt plan` showing "No changes" for each, in this session.
- `workloads/custodian-buckets/` no longer exists in this repo.
- `workloads/scaleway/terraform/` now groups every Scaleway-specific leaf under one workload, mirroring the `dns/` domain-grouping pattern ADR-0105 established for Cloudflare leaves.
- The two leaves' old-backend-key state objects (`workloads/scaleway/terraform/terraform.tfstate`, `workloads/custodian-buckets/terraform/duck-jellyfish/terraform.tfstate`) are now orphaned (their content was copied, not moved). Low-priority cleanup, left for later; S3 versioning on the state bucket remains an independent safety net regardless.

## Out of scope

- Deleting the orphaned old-backend-key state objects — optional cleanup, left to the user's discretion and timing, same treatment every prior leaf-move ADR here has given its own orphaned state object.
- Any further regrouping of other `workloads/` leaves — this ADR covers exactly the two leaves named above.
