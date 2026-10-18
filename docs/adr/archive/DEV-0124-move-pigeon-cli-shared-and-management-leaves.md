# DEV-0124: Move pigeon-cli's shared leaves and the management leaf out of `workloads/scaleway/terraform`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

Three leaves live under the provider-rooted `workloads/scaleway/terraform/`:

- `pigeon-cli/cockpit/` — the shared Cockpit metrics/logs source + push token for every `pigeon-cli` compute instance (ADR-0103), moved here by ADR-0115.
- `pigeon-cli/iam-application/` — the shared IAM application every `pigeon-cli` job policy attaches to (ADR-0119).
- `management/` — this repo's own Terraform state bucket and deployer IAM application/policy/API key (ADR-0094), regrouped here by ADR-0106.

This continues the workload-colocation regrouping this repo has done repeatedly (ADR-0106, 0115, 0116, 0117). The two `pigeon-cli/*` leaves move to `workloads/pigeon-cli/terraform/shared/{cockpit,iam-application}/`, landing them next to the existing `workloads/pigeon-cli/terraform/job/` leaf that actually consumes their outputs — colocated by **owning workload** instead of by provider, the same shift ADR-0115/ADR-0116/ADR-0117 already made for every other `pigeon-cli`-adjacent leaf. `management/` is promoted to a first-class top-level workload, `workloads/management/terraform/scaleway/` — the `scaleway/` segment anticipates this leaf staying Scaleway-specific today while leaving room for a future non-Scaleway management leaf (e.g. Cloudflare) without a second move.

Both destinations existed on disk beforehand as empty, untracked, pre-scaffolded placeholder directories — the same pre-scaffolding pattern ADR-0105/0106/0115 used before their own moves.

A census of `workloads/` confirms zero Terragrunt `dependency` or `mock_outputs` blocks exist anywhere in this repo — these three leaves have no live Terragrunt consumers. Their outputs are hand-copied into the root `.env` (`PIGEON_COCKPIT_*`, `PIGEON_CLI_IAM_APPLICATION_ID`, `SCALEWAY_TERRAFORM_STATE_BUCKET_NAME`/`SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`) and read back by `workloads/pigeon-cli/terraform/job/`. The move can't break a dependency graph, but each leaf's remote-state key is derived from `path_relative_to_include()` in `workloads/root.hcl`, so moving a leaf's directory changes its backend key — a plain `git mv` plus `terragrunt init -migrate-state` does not work across a directory move (confirmed again by this ADR, following ADR-0094/0106/0115's precedent); the worktree-based `state pull`/`push` runbook is required. `workloads/root.hcl` needs no changes — leaf validity, state-key derivation, and region/zone resolution are all purely path-derived, already proven at this nesting depth by `custodian/duck-jellyfish/` and by ADR-0115's own `pigeon-cli/cockpit` nesting.

At the time this move's state migration started, this repo had an unrelated, uncommitted, in-flight migration to sops-encrypted secrets (a new `.env.enc`, decrypted via `age`, replacing the plaintext root `.env`) and a Cloudflare env-var rename, both touching `workloads/root.hcl` and several other files — landed independently partway through this work as ADR-0123. Per ADR-0115's exact precedent for this situation, this move's state migration ran from a separate worktree checked out at the last committed `HEAD` at the time, deliberately isolated from that WIP. One live consequence: by the time this migration ran, the plaintext `.env` had already been deleted from the main checkout (superseded by `.env.enc`), so the worktree's `.env` was produced by decrypting `.env.enc` fresh with the user's `age` key (`~/.config/sops/age/noisypigeon.txt`) rather than copied from a plaintext file — a one-time, session-local step, not a change to any tracked file.

## Decision

### 1. Directory moves

For each leaf: delete its gitignored `.terraform.lock.hcl`/`.terragrunt-cache/`, then `git mv` the source onto the (non-existent, since the placeholders are untracked) destination, creating parent directories as needed:

- `workloads/scaleway/terraform/pigeon-cli/cockpit` → `workloads/pigeon-cli/terraform/shared/cockpit`
- `workloads/scaleway/terraform/pigeon-cli/iam-application` → `workloads/pigeon-cli/terraform/shared/iam-application`
- `workloads/scaleway/terraform/management` → `workloads/management/terraform/scaleway`

`workloads/scaleway/terraform/pigeon-cli/` is removed once both its children move out; `workloads/scaleway/terraform/` itself survives via `custodian/duck-jellyfish/`, its only remaining leaf.

### 2. State migration

Migrated via the same `git worktree add ... HEAD` + `terragrunt state pull`/`push` runbook ADR-0106/0115 established:

```sh
git worktree add -b move-pigeon-cli-management-leaves /tmp/pigeon-cli-management-move HEAD
SOPS_AGE_KEY_FILE=~/.config/sops/age/noisypigeon.txt sops --decrypt --input-type dotenv --output-type dotenv .env.enc > /tmp/pigeon-cli-management-move/.env

# for each leaf, at its OLD path (before the git mv):
terragrunt init -input=false
terragrunt plan -input=false      # baseline -- "No changes" for all three
terragrunt state pull > /tmp/<leaf>.tfstate

# perform the three git mv's (see above)

# for each leaf, at its NEW path:
terragrunt init -input=false
terragrunt state pull             # confirmed empty
terragrunt state push /tmp/<leaf>.tfstate
terragrunt plan -input=false      # "No changes" -- confirmed against the live baseline
```

All three leaves' baseline and post-push plans showed "No changes," with identical resource IDs before and after:

- `cockpit`: 3 resources (`scaleway_cockpit_source.logs`, `scaleway_cockpit_source.metrics`, `scaleway_cockpit_token.push`).
- `iam-application`: 1 resource (`scaleway_iam_application.application`).
- `management`: 8 resources (`scaleway_account_project.project`, `scaleway_iam_ssh_key.key`, `scaleway_object_bucket.bucket`, `random_string.suffix`, `scaleway_iam_application.application`, `scaleway_iam_policy.policy`, `scaleway_iam_api_key.api_key`, `time_static.created`) — extra scrutiny here given it provisions the state bucket and deployer identity every other Scaleway leaf depends on.

The three `/tmp/<leaf>.tfstate` files were deleted immediately after verification (they carry live state, including secrets). Old-location state objects in the Scaleway state bucket are left as low-priority cleanup, per ADR-0106's own precedent.

## Consequences

- `workloads/scaleway/terraform/` now holds only `custodian/duck-jellyfish/`.
- `workloads/management/` is a new top-level workload, `terraform/`-only (no `src/`), holding the leaf every other Scaleway leaf's deployer identity depends on.
- `workloads/pigeon-cli/terraform/` now holds `job/` and `shared/{cockpit,iam-application}/` as siblings — every `pigeon-cli`-related leaf in this repo is colocated under one workload, none left grouped by provider.
- `CLAUDE.md`, `workloads/README.md`, and `docs/USAGE.md` are updated to describe the new layout; `CLAUDE.md`'s long-stale "`workloads/pigeon-cli/` is fully decommissioned" claim (inaccurate since `job/` landed via ADR-0097/0118/0120/0122, never corrected) is also fixed in the same edit.

## Out of scope

- ADR-0123's sops-encrypted-`.env` migration and Cloudflare env-var rename — landed independently (as PR #169) partway through this work; not touched or reconciled by this ADR.
- Backfilling `CLAUDE.md`'s missing ADR-0121/ADR-0122 bullets — a pre-existing gap, unrelated to this move.
