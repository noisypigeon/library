# DEV-0094: move the Scaleway bootstrap leaf to `workloads/scaleway/terraform`, pure state surgery

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`terraform/infrastructure/scaleway/fr-par/noisypigeon/terraform/` is this repo's most sensitive leaf. Its `bucket.tf` provisions the S3 bucket that holds every leaf's own Terraform remote state (`terraform-t0nh1b-state`, via `modules/scaleway/object-bucket`), and its `iam.tf` provisions the deployer IAM application/policy/API key every other `scaleway/*` leaf authenticates as — confirmed directly in ADR-0069's text: *"Every `scaleway/*` leaf... authenticates as one identity: the `noisypigeon/terraform` leaf's self-managed 'deployer' IAM application... Its `access_key`/`secret_key` populate `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`"*.

The user wanted it moved into the `workloads/` convention (ADR-0092/0093) at `workloads/scaleway/terraform`, explicitly as a **state surgery** — the underlying cloud resources (bucket, IAM application, policy, API key) must not be destroyed or recreated.

**Research confirmed, verbatim, before planning anything:**

- The leaf has exactly 3 tracked files — `terragrunt.hcl`, `bucket.tf`, `iam.tf` (the latter also holding the two inline `output` blocks, `access_key`/`secret_key`, both `sensitive = true`). Both `.tf` files already referenced the current `modules/scaleway/*` paths at their current major versions (v1.0.0/v2.0.0, ADR-0093) — zero content changes needed, a pure file relocation.
- **No `dependency` block anywhere in the repo reads this leaf's outputs** — confirmed via a repo-wide grep. Every other `iam.tf` under `terraform/infrastructure/scaleway/**` defines its own independent `module "iam"` block. The link from this leaf's `access_key`/`secret_key` to every other leaf's actual credentials is purely manual: hand-copied into the shared root `.env`'s `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`, which every `root.hcl` reads via `get_env(...)`. This is exactly why "resources shouldn't change" matters here specifically — if the IAM resources were destroyed and recreated instead of state-migrated, the real credential values would change, and `.env` (along with every other leaf's auth) would silently break, since nothing re-reads them automatically.
- `bucket.tf` already has `enable_versioning = true` on the state bucket — S3 object versioning was already protecting every state object in it, including this leaf's own, before this ADR. A pre-existing safety net, not something added here.
- Current backend (from `scaleway/root.hcl`'s `remote_state`, read verbatim): bucket `terraform-t0nh1b-state`, key `scaleway/${path_relative_to_include()}/terraform.tfstate` → resolved to `scaleway/fr-par/noisypigeon/terraform/terraform.tfstate`.
- `workloads/root.hcl` (ADR-0092) already reuses the **same** S3 bucket for its own `remote_state` block, just under a `workloads/` key prefix. After the move, this leaf's key becomes `workloads/scaleway/terraform/terraform.tfstate` — inside the exact same bucket. The bucket itself never moves or gets renamed; only this leaf's state *key* changes. The leaf's new path also satisfies `workloads/root.hcl`'s existing `exclude` guard (`scaleway/terraform` → 2 segments, second literally `terraform`) with no changes needed to that guard.
- **A real gap found**: `workloads/root.hcl` had no `provider "scaleway"` block at all — only `cloudflare` (ADR-0092 deliberately deferred this: "add a provider when a future workload actually does"). It also lacked the `scaleway_organization_id`/`scaleway_project_id` locals `iam.tf` references (previously generated only by `scaleway/root.hcl`'s `generate "scaleway_ids"` block). Both needed to be added, or the moved leaf would fail to resolve those locals entirely.
- Neither `bucket.tf` nor `iam.tf` needs `scaleway/root.hcl`'s other machinery (the `ENV_SW_*`-prefixed `bucket_names_generated.tf` mechanism, region/zone-by-path-segment detection) — kept out of `workloads/root.hcl` to stay minimal.

## Decision

### Extended `workloads/root.hcl`: Scaleway provider + ids

Scaleway was combined into the **existing** `generate "provider"` block rather than added as a separate one — mirroring a real precedent in this repo's own history (the pre-provider-split root.hcl era, per ADR-0060's context: "every leaf already receives both providers' `generate "provider"` blocks regardless of whether that leaf actually uses both"), and avoiding any uncertainty about whether two separate `generate` blocks each declaring their own `terraform { required_providers {} }` would merge cleanly. Region/zone hardcoded to `fr-par`/`fr-par-1` (matching this leaf's already-applied provider config exactly) rather than replicating `scaleway/root.hcl`'s path-segment-based region detection — `workloads/<name>/terraform` leaves have no region segment in their path to detect from, and there's only one such leaf today. Add real multi-region support when a second `workloads/*/terraform` leaf actually needs a different region.

A new `generate "scaleway_ids"` block produces the two exact local names `iam.tf` references, unchanged in shape from `scaleway/root.hcl`'s own version. No change was needed to `workloads/root.hcl`'s `remote_state` block or `exclude` guard — both already compatible.

**Verified safe** (without displaying any secret content — checked by redirecting `terragrunt render --json` output to a file and inspecting only the exit code and error count, consistent with this session's established practice after an earlier credential-exposure incident): the moved leaf renders successfully against the extended `workloads/root.hcl` with zero errors.

### Move

`git mv terraform/infrastructure/scaleway/fr-par/noisypigeon/terraform workloads/scaleway/terraform` — all 3 files move unchanged. `terraform/infrastructure/scaleway/fr-par/noisypigeon/` keeps its other leaves (`custodian/dhj/`, `import/*`).

### Documentation

`workloads/README.md` gains the `scaleway/terraform/` example and a note that not every workload needs a `src/` sibling (this one is infrastructure/bootstrap plumbing, not a deployable app). `CLAUDE.md` and `docs/USAGE.md` updated with the new leaf's description/location. `terraform/infrastructure/README.md`'s Structure-section example path swapped from the now-moved leaf to a still-live one (`fr-par/noisypigeon/custodian/dhj`).

### The actual state migration — manual, not performed in this session

This is a live state relocation against this repo's own state-bucket-and-deployer-credential leaf. Consistent with this session's established caution around real credentials, and with every prior leaf-move ADR in this repo (ADR-0092) deferring live `terragrunt init`/state migration to the user, **this ADR does not execute it.**

**First attempt (tried live, documented here because it failed instructively):** running plain `terragrunt init` then `terragrunt plan` in the new `workloads/scaleway/terraform` directory did **not** prompt to migrate state — it did a normal fresh init against the new, empty backend key and `plan` proposed creating all 5 resources from scratch. Root cause: `terraform init`'s "backend changed, copy state?" detection depends on a *local* pointer file (`.terraform/terraform.tfstate`) in the **same working directory** that previously ran `init` against the old backend. Terragrunt runs the actual `terraform`/`tofu` commands inside a `.terragrunt-cache/<hash-of-absolute-path>/...` directory derived from the leaf's filesystem path — since `workloads/scaleway/terraform` is a brand-new path (via `git mv`), its cache directory has no memory of ever being initialized against the old backend, so no migration prompt is possible. **This means the interactive `init -migrate-state` flow does not work across a Terragrunt leaf's directory move — only for an in-place backend reconfig.** No damage was done (`plan` is non-mutating), but `apply` was correctly not run on that plan.

**Working runbook** — transfers the real state content directly via `terraform state pull`/`push`, sourcing the old state from a temporary `git worktree` checked out at the commit before the move:

```bash
# 1. Temporary worktree at the commit before the leaf moved, so the OLD
#    terragrunt.hcl (pointing at scaleway/root.hcl's OLD backend key) exists on disk again.
cd /Users/pigeon/Developer/noisypigeon
git worktree add /tmp/old-scaleway-leaf <commit-before-the-move>

# 2. Init against the OLD backend and pull its real, current state.
cd /tmp/old-scaleway-leaf/terraform/infrastructure/scaleway/fr-par/noisypigeon/terraform
terragrunt init
terragrunt state pull > /tmp/scaleway-bootstrap.tfstate

# 3. Push that exact state content to the NEW backend key.
cd /Users/pigeon/Developer/noisypigeon/workloads/scaleway/terraform
terragrunt state push /tmp/scaleway-bootstrap.tfstate

# 4. Verify -- MUST show "No changes." before trusting this is done.
terragrunt plan

# 5. Clean up.
cd /Users/pigeon/Developer/noisypigeon
git worktree remove /tmp/old-scaleway-leaf
rm /tmp/scaleway-bootstrap.tfstate
```

Neither `state pull` nor `state push` talks to the Scaleway API or touches any real resource — they only move the state file's content (a JSON description of what already exists and its resource IDs) between backend locations. Step 4's "No changes" is the proof the new key's state now agrees with reality.

Optional, low-priority, can be done anytime later or skipped entirely: remove the now-orphaned old state object at `scaleway/fr-par/noisypigeon/terraform/terraform.tfstate` directly (not a Terraform operation; S3 versioning on the bucket is an additional, independent safety net regardless).

## Consequences

- Until the user runs the manual migration, `workloads/scaleway/terraform` exists with no state behind it yet at its new key — not runnable as-is immediately after merge. Expected, not a defect.
- Every other `scaleway/*` leaf's `.env`-sourced credentials are unaffected by this move, provided the migration step is a state copy rather than a destroy+apply — verified safe by the lack of any `dependency` block and the existing S3 versioning safety net.
- `terraform/infrastructure/scaleway/fr-par/noisypigeon/` loses one leaf but keeps the others; no other leaf references this one by path or Terragrunt dependency.
- The original runbook's `init -migrate-state` approach doesn't generalize to *any* future Terragrunt leaf directory move in this repo — the same local-pointer-file gap applies whenever a leaf's filesystem path changes, not just this one. The working `state pull`/`push`-via-worktree runbook above is the pattern to reuse next time, not the original one.

## Out of scope

- Running the actual state migration — the user's job, per the runbook above.
- Deleting the orphaned old state object — optional cleanup, left to the user's discretion and timing.
- Multi-region support in `workloads/root.hcl`'s Scaleway provider block — add when a second `workloads/*/terraform` leaf actually needs a region other than `fr-par`.
