# DEV-0115: move `workloads/pigeon-cli/terraform/observability` to `workloads/scaleway/terraform/pigeon-cli/cockpit`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

`workloads/pigeon-cli/terraform/observability/` — the shared Scaleway Cockpit metrics/logs source and push token for every `pigeon-cli` compute instance ([ADR-0103](DEV-0103-shared-cockpit-store.md)) — moves to `workloads/scaleway/terraform/pigeon-cli/cockpit/`, grouping it under `workloads/scaleway/terraform/`'s "every Scaleway-specific leaf" convention alongside `management/` and `custodian/duck-jellyfish/` ([ADR-0106](DEV-0106-regroup-scaleway-leaves-under-workloads-scaleway-terraform.md)), nested one level deeper by owning workload (`pigeon-cli/`) the same way `custodian/duck-jellyfish/` is nested by purpose. The destination existed on disk beforehand as an empty, untracked placeholder directory — the same pre-scaffolding pattern ADR-0105/ADR-0106 used before their own moves.

## Decision

### 1. Directory move

Destination pre-existed empty, so: remove the leaf's gitignored `.terragrunt-cache/`/`.terraform.lock.hcl`, `rmdir` the empty destination, then `git mv` the source directory onto it — moving exactly two tracked files (`terragrunt.hcl`, `cockpit.tf`; the lock file is repo-wide gitignored and regenerates on next `init`). No `workloads/root.hcl` change is needed for leaf validity, state-key derivation, or region/zone resolution — all three are purely derived from `path_relative_to_include()`, already confirmed working at this nesting depth by `custodian/duck-jellyfish/`, and this leaf has never had a `workload_definition.hcl` of its own (always default `fr-par`/`fr-par-1`).

### 2. State migration

Migrated via the same `git worktree add ... HEAD` + `terragrunt state pull`/`push` runbook ADR-0106 established — deliberately a pristine checkout of the last *committed* tree, not the live working tree:

```sh
git worktree add /tmp/observability-move HEAD
cp .env /tmp/observability-move/.env
cd /tmp/observability-move/workloads/pigeon-cli/terraform/observability
terragrunt init -input=false
terragrunt plan -input=false      # baseline check before touching state
terragrunt state pull > /tmp/observability.tfstate

cd workloads/scaleway/terraform/pigeon-cli/cockpit
terragrunt init -input=false
terragrunt state pull             # confirmed empty
terragrunt state push /tmp/observability.tfstate
terragrunt plan -input=false      # "No changes" -- confirmed against the live working tree

git worktree remove /tmp/observability-move
```

This repo currently has an unrelated, uncommitted, in-flight rename (`scaleway_project_id_noisypigeon` → `scaleway_project_id`, a `local` name used across `workloads/root.hcl` and most `workloads/` leaves) touching this exact leaf's `cockpit.tf` among many other files. This move does not touch, stage, or resolve any part of that rename — the worktree-based migration exists specifically so state surgery is isolated from it entirely.

One live consequence of that rename surfaced during the baseline check: `.env` has already been updated to the new `SCALEWAY_PROJECT_ID` key (the old `SCALEWAY_PROJECT_ID_NOISYPIGEON` key is gone), but the *committed* `root.hcl` at `HEAD` still looks up the old key — so the pristine-`HEAD` baseline plan failed outright (`invalid UUID: `, i.e. an empty `project_id`) until the old key was supplied as a temporary, local-only environment variable (same value, read from `.env`'s new key) for the duration of this migration. No file was changed to make this work — it's a session-local shim, not a fix, and this repo-wide inconsistency (affecting every leaf's plan against real `HEAD`, not just this one) remains for the in-flight rename to resolve on its own.

Once that temporary variable was supplied, the baseline plan at the old location showed "No changes" (3 resources: `scaleway_cockpit_source.logs`, `scaleway_cockpit_source.metrics`, `scaleway_cockpit_token.push`), and the post-push plan at the new location — run directly against the real, dirty working tree (whose `cockpit.tf` already uses the new `local.scaleway_project_id` name, matching `.env`'s actual current key) — also showed "No changes" against the identical resource IDs, confirming both the move and the in-flight rename's eventual value resolve to the same real infrastructure.

Old-location state object (`workloads/pigeon-cli/terraform/observability/terraform.tfstate` in the Scaleway state bucket) is left as low-priority cleanup, per ADR-0106's own precedent.

## Consequences

- `workloads/pigeon-cli/terraform/` now holds only `deduplication/` and `import/` — no further observability-specific leaf.
- `workloads/scaleway/terraform/` gains its first workload-nested subdirectory (`pigeon-cli/`), alongside its existing purpose-nested one (`custodian/`).

## Out of scope

- The unrelated `scaleway_project_id_noisypigeon` → `scaleway_project_id` rename in flight across this repo — not touched, not landed, not reconciled by this ADR.
