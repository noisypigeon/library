# DEV-0130: `workloads/pigeon.dev` Terraform self-sufficiency

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-05.
- **Status**: Accepted.

## Context

Every workload in this repo, including `pigeon.dev`, has shared the one repo-wide Terraform state bucket and deployer IAM identity (`workloads/management/terraform/scaleway/`) via the single shared `workloads/root.hcl`. `pigeon.dev` becomes the first workload to decouple from that shared bootstrap entirely — its own state bucket, its own deployer, its own secrets (ADR-0131) — establishing the pattern for other workloads to adopt later. This ADR does not retrofit any other workload; `pigeon.dev` is the only consumer today.

Secondary motivation, now that `pigeon.dev` is a real workload (serving the wiki from Scaleway Object Storage, plus Fastmail DNS) rather than just a DNS pointer: its `terraform/` tree is restructured to group leaves by the sub-service they belong to (`wiki`, `fastmail`) instead of by resource type (`bucket`, `iam`, `dns`).

## Decision

### Dedicated bootstrap: `workloads/pigeon.dev/terraform/state/{bucket,iam}`
Mirrors `workloads/management/terraform/scaleway/`'s existing repo-wide pattern, scoped to the `pigeon-dev` Scaleway project: `state/bucket` is an `object-bucket` (versioned, standard storage class); `state/iam` composes `iam-application` + `iam-policy` + `iam-api-key` (`default_project_id` set — see the "iam-api-key" finding in PR #201/#202 that motivated adding that input in the first place) into a deployer scoped to `ObjectStorageFullAccess` on the `pigeon-dev` project, plus `ProjectManager`/`IAMManager`/`IAMApplicationManager` at the organization level (needed because this deployer also has to manage `terraform/project`, an org-level Scaleway project resource, and `terraform/wiki/iam`, which itself creates IAM application/policy/api-key resources — both org-level operations, confirmed live via an `insufficient permissions: read project` error against the first cut of this policy, which only had the project-scoped grant).

These two leaves deliberately keep using the **outer shared** `workloads/root.hcl`, via an explicit `include` path (`"${get_repo_root()}/workloads/root.hcl"`) rather than `find_in_parent_folders("root.hcl")` — the new per-workload root.hcl below would otherwise be nearer and get picked up instead, which would be circular: that root.hcl's backend points at the very bucket these two leaves are responsible for creating. The repo-wide bootstrap leaf resolves the identical problem by being a self-referential leaf under the one shared root; these two leaves are pigeon.dev's equivalent.

Consequence, confirmed and accepted: these two leaves' own Terraform state permanently stays in the **shared** repo-wide state bucket, never migrated into the new dedicated one. Their `remote_state` backend comes from the shared `SCALEWAY_TERRAFORM_STATE_BUCKET_NAME` secret — the same one every other leaf in the entire repo depends on — so there is no way to repoint it for just these two leaves without breaking everything else. This is not a gap; it's the same reason the repo-wide bootstrap leaf's own state lives in the bucket it manages: for exactly one leaf (or, here, two), "the shared bucket" and "the bucket I manage" are allowed to be different concepts that happen not to matter to each other.

### New `workloads/pigeon.dev/root.hcl`
A full per-workload replacement of the shared root.hcl's logic — not an addition to it. Once this file exists, `find_in_parent_folders("root.hcl")` resolves to it for everything under `workloads/pigeon.dev/terraform/**` except the two leaves above. Mirrors the shared root's structure closely:
- Decrypts `workloads/pigeon.dev/secrets.enc` (ADR-0131) instead of the repo-root `.env.enc`.
- Exposes a plain `scaleway_project_id` local (no `_pigeon_dev` suffix — see the rename below), sourced from `secrets.enc`'s own `SCALEWAY_PROJECT_ID` key, mirroring the shared root's own top-level naming for its one project.
- `remote_state` points at the new dedicated bucket (`secrets.enc`'s `PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME`), key `"${path_relative_to_include()}/terraform.tfstate"` — no `workloads/` prefix, since the bucket is now dedicated solely to this workload.
- `is_valid_leaf` checks one fewer path segment than the shared root's own (`path_segments[0] == "terraform"`, not `[1]`), since there's no `<workload-name>/` prefix at this level anymore.
- Retains the `ENV_SW_`/`ENV_CF_`-prefix generated-local convention (ADR-0006) and the per-leaf `scaleway_config.hcl` region/zone override mechanism (ADR-0098), unchanged in spirit, just reading from `secrets.enc`.

**Known, accepted quirk**: the shared root.hcl's own `workload_dir = dirname(find_in_parent_folders("root.hcl"))` (used for its `scaleway_config.hcl` resolution) gets miscalculated when evaluated for the `state/bucket`/`state/iam` leaves specifically — since this new file now exists as a *nearer* `root.hcl` than the actually-included shared one, that internal lookup resolves to it instead of `workloads/`. The practical effect is harmless: `read_terragrunt_config` against the resulting (wrong, double-nested) path finds no file and falls back to its given default (`fr-par`/`fr-par-1`), which is exactly what both leaves need anyway. Not fixed, because fixing it would require either leaf to lose its own escape hatch or a more invasive change to the shared root's own lookup logic for one cosmetic gain.

### Directory restructure
```
terraform/bucket        -> terraform/wiki/bucket
terraform/iam           -> terraform/wiki/iam
terraform/dns/scaleway  -> terraform/wiki/dns
terraform/dns/fastmail  -> terraform/fastmail/dns
terraform/project                              (unchanged -- pigeon.dev-wide, not wiki-specific; both wiki/bucket and state/bucket live in it)
```
Pure relocations, same resource addresses. State for all 5 affected leaves was migrated live beforehand (the established worktree-based `terragrunt state pull`/`push` runbook), verified clean (`terragrunt plan` → "No changes", identical resource IDs) at each new path, before the PR was opened.

**Critical safety finding, confirmed live**: pulling and pushing a leaf's state into its new location does *not* clear the old location's state. With `--filter-allow-destroy` (ADR-0128) now active, a leaf whose directory disappears from the PR branch still gets planned and applied — and if its old state still holds real resource IDs (the same ones now also tracked at the new path), that apply issues genuine destroy calls against live infrastructure, even though the new path's state is already correct. Evidence this already happened once, silently, for the `pigeon.dev/terraform/dns/fastmail` leaf's own earlier move (PR #199): its old-path apply log shows real `Destruction complete` calls against the live Fastmail DNS records, while its new path's apply shows them being recreated from scratch in the same run (net effect: the same records, but destroy-then-recreate rather than a true no-op, and not something that was safe to leave to chance a second time). Fixed here, for all 4 moved leaves, by pushing an empty Terraform state (`{"version": 4, "resources": [], ...}`) into each old path's backend *before* opening the PR — confirmed via a re-run plan that every old path then reported "No changes. No objects need to be destroyed," and the real apply touched nothing at any old path. Any future leaf move in this repo should do the same: migrating state into a new location is not complete until the old location's state is also emptied, not merely orphaned.

### Renames and cleanup
- `local.scaleway_project_id_pigeon_dev` → `local.scaleway_project_id` in `wiki/bucket` and `wiki/iam` (the two leaves now governed by the new root.hcl) — the cross-workload-disambiguating suffix is no longer needed once the project ID lives in `pigeon.dev`'s own `secrets.enc`/root.hcl. `state/bucket`/`state/iam` keep the old, suffixed name, since they still read it from the *shared* root.hcl's own secrets.
- Removed `pigeon.dev`'s grant from the shared repo-wide deployer's own policy (`workloads/management/terraform/scaleway/iam.tf`) — it no longer needs any access to the `pigeon-dev` project now that `pigeon.dev` has its own dedicated deployer.

### `wiki/dns`'s `www` fix, folded in while touching the leaf anyway
Confirmed live, separately, while this leaf was already being moved: Scaleway's bucket-website gateway resolves which bucket to serve from the incoming `Host` header, not from the CNAME target — a direct `www.pigeon.dev` CNAME to the same `pigeon.dev.s3-website...` target 404s with `NoSuchBucket` (`BucketName: www.pigeon.dev`), since no bucket by that literal name exists. Replaced the direct CNAME with a placeholder record + a `cloudflare_ruleset` redirect to the apex, mirroring the mechanism the now-decommissioned `pigeon.dev/redirect/` leaf (ADR-0105/0127, removed when `pigeon.dev` was cut over to serve the wiki) already used for the same purpose, just narrowed to `www` only.

## Consequences

- `pigeon.dev` can rotate its own deployer credentials, resize or relocate its own state bucket, and manage its own secrets without touching anything the rest of the repo depends on.
- The blast radius of a `pigeon.dev`-specific credential leak or misconfiguration no longer extends to any other workload's Terraform state or deploy identity.
- Every future `pigeon.dev` leaf (under `terraform/wiki/**` or `terraform/fastmail/**`) automatically inherits this independence just by living under `workloads/pigeon.dev/`; nothing per-leaf to opt into.
- `state/bucket`/`state/iam` remain the one documented exception, permanently tied to the shared bootstrap for the chicken-and-egg reasons above.

## Out of scope

- Retrofitting any other existing workload with the same self-sufficiency pattern — this ADR, and ADR-0131, establish it via `pigeon.dev` only.
- Actually getting content synced into the bucket / the remaining `pigeon.dev` deploy-pipeline work — unrelated to this restructure, already resolved separately (PR #201/#202/#203).
