# DEV-0095: merge the `project` leaf into `workloads/scaleway/terraform`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`terraform/infrastructure/scaleway/global/project/project.tf` managed the `scaleway_account_project` "noisypigeon" project plus a `scaleway_iam_ssh_key`. The user wanted it moved into `workloads/scaleway/terraform/` — the leaf ADR-0094 already relocated there (holding `bucket.tf`/`iam.tf`) — merging three previously-separate concerns into one leaf and **one state**, not just relocating a directory.

**Research confirmed, verbatim, before planning anything:**

- `project.tf`'s module call contains two resource addresses inside `modules/scaleway/project`: `scaleway_account_project.project` and `scaleway_iam_ssh_key.key[0]` (the `[0]` index exists because the leaf's `ssh_key` argument is non-null — `count = var.ssh_key != null ? 1 : 0` in the module). Both needed to move, not just one.
- A real blocker: `project.tf` references `local.ssh_key_alias`/`local.ssh_key_public_key`, which previously existed only because `terraform/infrastructure/scaleway/root.hcl` has a generic `ENV_SW_*`-prefix-scanning `generate "bucket_names"` block turning `.env`'s `ENV_SW_SSH_KEY_ALIAS`/`ENV_SW_SSH_KEY_PUBLIC_KEY` into those two locals. `workloads/root.hcl` had no equivalent. Since Terragrunt's `get_env()`/`local.secrets` machinery only exists inside `.hcl` files (a moved `.tf` file can't call `get_env()` itself), this had to be fixed in `workloads/root.hcl`.
- Confirmed clean via a full repo-wide search: zero `dependency` blocks, zero `terraform_remote_state` data sources, zero `mock_outputs` anywhere. No leaf reads this project leaf's outputs (`id`/`name`/`ssh_key_id`) — every consumer of the project ID gets it from `.env`'s `SCALEWAY_PROJECT_ID_NOISYPIGEON` directly. The merge was purely a state-mechanics problem, not a cross-leaf rewiring problem.
- `terraform/infrastructure/scaleway/global/` held only `project/` — it was removed entirely once `project.tf` moved out, same pattern as every other now-empty directory removed earlier this session.
- Precondition verified before starting (safely — redirected `terragrunt state pull` to a file and grepped only for resource `"type"` strings, never displaying values): the target leaf's state already held real `scaleway_object_bucket`/`scaleway_iam_application`/`scaleway_iam_policy`/`scaleway_iam_api_key` resources — ADR-0094's migration had already been completed.

## Decision

### Extended `workloads/root.hcl`: `ssh_key_alias`/`ssh_key_public_key` locals

Two explicit locals added (matching this file's existing per-key style, not the generic `ENV_SW_*`-prefix-scan pattern `scaleway/root.hcl` uses — only these two specific keys are needed here), folded into the existing `generate "scaleway_ids"` block rather than a new one:

```hcl
ssh_key_alias      = get_env("ENV_SW_SSH_KEY_ALIAS", lookup(local.secrets, "ENV_SW_SSH_KEY_ALIAS", ""))
ssh_key_public_key = get_env("ENV_SW_SSH_KEY_PUBLIC_KEY", lookup(local.secrets, "ENV_SW_SSH_KEY_PUBLIC_KEY", ""))
```

**Verified safe** (exit-code-only check, never displaying generated content — same practice as every prior credential-adjacent step this session): the merged 3-file leaf (`bucket.tf`, `iam.tf`, `project.tf`) renders successfully against the extended `workloads/root.hcl` with zero errors.

### Move

`git mv terraform/infrastructure/scaleway/global/project/project.tf workloads/scaleway/terraform/project.tf` — content unchanged. The old leaf's own `terragrunt.hcl` was removed (no longer a standalone Terragrunt leaf), and `terraform/infrastructure/scaleway/global/` was removed once empty.

### State merge — `terraform state mv` across two local state files, then push

Performed after this PR merges, against live state — not a blind pull/push like ADR-0094's leaf moves, since the target already holds real resources (`module.bucket.*`/`module.iam.*`) that a blind overwrite would destroy. Procedure:

1. Pull the old project leaf's state (via a temporary `git worktree` at the commit before this move) → a local file.
2. Pull the target leaf's current (already-correct, bucket+iam) state → a local file.
3. `terraform state mv -state=<old> -state-out=<target> module.project.scaleway_account_project.project module.project.scaleway_account_project.project` and the same for `'module.project.scaleway_iam_ssh_key.key[0]'` — address unchanged on both sides, no renaming.
4. Push the now-combined state back to the target backend key. No `-force` expected to be needed — the push's lineage descends directly from the target's own current state (resources are added via `state mv`, not replaced), so the lineage check should pass naturally.
5. Verify: `terragrunt plan` in `workloads/scaleway/terraform` must show **"No changes."** across all resources — bucket, the three IAM resources, and the project's two resources.

Neither `state pull`/`push` nor `state mv` call the Scaleway API or touch any real resource — they only rewrite the state file's bookkeeping.

## Consequences

- `workloads/scaleway/terraform` becomes a 3-file leaf (`bucket.tf`, `iam.tf`, `project.tf`) under one shared state once the merge completes — any future `terragrunt plan`/`apply` there affects all three together.
- The old `scaleway/global/project/terraform.tfstate` object becomes an orphan in the same bucket, same as the two prior leaf moves this session — optional cleanup, no rush.
- No credential rotation, no resource recreation expected — to be confirmed by the final "No changes." plan, not assumed.

## Out of scope

- Renaming the `project` module block now that it's merged into a bigger leaf — kept as-is (`module "project"`) to avoid unnecessary extra `state mv` risk for zero functional benefit.
- Deleting the orphaned old state object — optional, left for later.
