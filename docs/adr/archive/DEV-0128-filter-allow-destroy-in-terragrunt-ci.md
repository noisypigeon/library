# DEV-0128: Pass `--filter-allow-destroy` in the terragrunt plan/apply CI

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-05.
- **Status**: Accepted.

## Context

`.github/workflows/terragrunt-plan.yml` (PR-triggered) and `.github/workflows/terragrunt-apply.yml` (gated behind a `terragrunt apply` PR comment from an OWNER/MEMBER/COLLABORATOR) both invoke:

```
terragrunt --no-color run --all --filter-affected --non-interactive -- plan   # or apply
```

Neither workflow ever got its own ADR — they were added across several commits (`a0bda50`, `92c3674`, `0a12260`, `bd8bdcc`, `41f79ac`, `1151063`) and only mentioned in passing by ADR-0127 ("this repo now also has `terragrunt-plan.yml`/`terragrunt-apply.yml`"). This ADR is their first real documentation, prompted by a real gap found while preparing to merge a branch that deletes 9 leaves outright.

`--filter-affected` scopes a run to units changed relative to `main`. For a unit whose directory still exists, this works as expected. For a unit whose directory was **deleted** on the current branch, Terragrunt can still resolve its old configuration from the `main` git ref and queue a `destroy` for it — but only when `--filter-allow-destroy` is also passed. Without it, Terragrunt excludes the unit from the run entirely and prints:

```
WARN  The `<unit path>` unit was removed in the `main` Git reference, but the
      `--filter-allow-destroy` flag was not used. The unit will be excluded
      during applies unless --filter-allow-destroy is used.
```

This surfaced concretely on the `delete-dev-buckets` branch, which deletes all 9 of:

```
workloads/bucket/terraform/noisypigeon/backblaze/import
workloads/bucket/terraform/noisypigeon/macbook-scratch/deduplication
workloads/bucket/terraform/noisypigeon/media/deduplication
workloads/bucket/terraform/noisypigeon/poisoned/computer-snapshots/deduplication
workloads/bucket/terraform/noisypigeon/poisoned/computer-snapshots/import
workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/deduplication
workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/import
workloads/bucket/terraform/noisypigeon/poisoned/t7-backup/deduplication
workloads/bucket/terraform/noisypigeon/poisoned/t7-backup/import
```

Without this fix, merging that branch and commenting `terragrunt apply` would silently skip all 9 leaves rather than destroying them — their Terraform state and the real Scaleway resources behind it would become orphaned, with no error and no visible indication beyond a WARN line buried in the job log (the PR comment body doesn't even surface it as a distinct section).

## Decision

Add `--filter-allow-destroy` to both invocations, unconditionally:

```diff
-          terragrunt --no-color run --all --filter-affected --non-interactive -- plan > output.txt 2>&1
+          terragrunt --no-color run --all --filter-affected --filter-allow-destroy --non-interactive -- plan > output.txt 2>&1
```

(and the equivalent `-- apply` line in `terragrunt-apply.yml`).

No opt-in mechanism (a label, a second comment phrase, a `workflow_dispatch` input) was added to gate this per-PR. `terragrunt-plan.yml` always previews the destroy before anyone can act on it, and the existing `terragrunt apply` comment — already restricted to OWNER/MEMBER/COLLABORATOR — is the same human-approval gate every other plan/apply diff already goes through. Treating a removed leaf's destroy as just another line in that same diff is simpler than introducing a second, destroy-specific confirmation step, and this repo's existing review discipline (reading the plan comment before commenting apply) already covers it.

## Consequences

- Any future PR that deletes a leaf's directory will now have that leaf's destroy actually previewed by `terragrunt-plan.yml` and, once a reviewer comments `terragrunt apply`, actually applied — rather than silently excluded.
- Reviewers must treat an unexpected `destroy` block in a plan comment as a real signal to catch before commenting apply, same as any other unexpected diff — there is no second confirmation step specific to destroys.
- No consumer/module changes; this only touches the two CI workflow files.

## Out of scope

- Any mechanism to opt a specific PR *out* of destroy behavior (e.g. to intentionally leave a removed leaf's resources in place without destroying them). Not needed today — a leaf that should survive simply shouldn't have its directory deleted.
