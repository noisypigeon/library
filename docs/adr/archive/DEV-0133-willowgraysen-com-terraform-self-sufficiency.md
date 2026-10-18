# DEV-0133: `workloads/willowgraysen.com` Terraform self-sufficiency (bootstrap takeover)

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-06.
- **Status**: Accepted.

## Context

ADR-0130/0131 gave `pigeon.dev` and ADR-0132 gave `noisypigeon.com` dedicated Terraform self-sufficiency: own Scaleway project, own state bucket, own deployer IAM, own `root.hcl`/`secrets.enc`. This is the third and final migration in that sequence, but structurally different from the other two: rather than a workload decoupling from a generic shared pool, it takes over and relocates the repo's own foundational shared bootstrap (`workloads/management/terraform/scaleway/`) itself, plus every other leaf still living under that shared umbrella (`custodial-storage`, the `willowgraysen.com` Cloudflare redirect, and all of `pigeon-cli`), consolidating all of it under a new top-level workload, `workloads/willowgraysen.com/`.

`workloads/management/terraform/scaleway/` was one combined Terragrunt unit (single state) holding `module.project` + `module.bucket` + `module.iam_application`/`iam_policy`/`iam_api_key` together — 8 resources, live bucket `terraform-t0nh1b-state`. The Scaleway project itself was already renamed to `"willowgraysen"` live before this migration started (an uncommitted edit from earlier work, applied and confirmed as a deliberate keep).

## Decision

### `project` relocates; `state/bucket` and `state/iam` are fresh resources — the combined state is not split

Splitting `management/terraform/scaleway`'s one Terraform state three ways was considered and rejected. Instead: `project` relocates as the same existing resource (state pull/push, no new resource, `name = "willowgraysen"` carried over unchanged). `state/bucket` and `state/iam` are brand-new, genuinely dedicated resources, built with the exact same playbook ADR-0132 already proved for `noisypigeon.com`. The old leaf's `bucket.tf`/`iam.tf` resources become **unmanaged, not destroyed** — removed from Terraform tracking (empty state + deleted `.tf` files) but left alive on Scaleway, since `.env.enc`'s `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`/`SCALEWAY_TERRAFORM_STATE_BUCKET_NAME` continue referencing them — permanently load-bearing for `pigeon.dev`'s and `noisypigeon.com`'s own `state/iam` leaves, and `pigeon.dev`'s still-unfixed `state/bucket` (see ADR-0132's "Out of scope").

### `workloads/willowgraysen.com/terraform/state/iam` (new, permanent shared-root pin)

Mirrors `noisypigeon.com/terraform/state/iam`: `iam-application` (v0.1.0) → `iam-policy` (v4.0.0) → `iam-api-key` (v0.2.0, `default_project_id` set). `terragrunt.hcl` uses the explicit `include { path = "${get_repo_root()}/workloads/root.hcl" }` permanently, by design — an IAM-rotation leaf shouldn't depend on the credential it itself manages. Its policy ended up needing a broader permission-set list than `noisypigeon.com`'s equivalent, assembled live across the migration as each relocated leaf's `terragrunt plan` surfaced the next missing grant: project-scoped `InstancesFullAccess`, `ObjectStorageFullAccess`, `VPCFullAccess`, `BlockStorageFullAccess`, `SSHKeysReadOnly`, `SSHKeysFullAccess`, `ObservabilityFullAccess`, plus organization-scoped `ProjectManager`, `IAMManager`, `IAMApplicationManager` — this workload's deployer governs a compute instance, a block volume, and a Cockpit integration in addition to buckets and DNS, unlike the other two workloads' bootstraps.

### `workloads/willowgraysen.com/terraform/state/bucket` (new, temp-pin-then-self-govern)

Same procedure as `noisypigeon.com`'s fix from ADR-0132, but with a key simplification: the *existing* shared deployer already had full `ObjectStorageFullAccess` on this exact project (it's the same project the shared deployer always used), so there was no need for a temporary policy-widening at all. `terragrunt.hcl` started with the explicit shared-root pin, applied live with zero permission friction, then switched to plain `find_in_parent_folders("root.hcl")` once the bucket existed, with a one-time state migration into the bucket it now self-governs. Resulting bucket: `willowgraysen-com-qgjrnp-terraform-state`.

### Twelve leaves relocated unchanged

`redirect/dns` (from `management/terraform/cloudflare/willowgraysen.com/redirect`), `custodial-storage/duck-jellyfish` (its `nl-ams` `scaleway_config.hcl` region override re-verified post-move; a pre-existing `lifecycle_rule` drift was confirmed present identically before and after — not caused by this migration, not fixed here), `pigeon-cli/shared/{cockpit,iam-application,reports}`, and all 11 `pigeon-cli/bucket/*` leaves. Of those 11, only `backblaze/import`, `macbook/import`, and `macbook/deduplicate` had real, previously-applied state and a real backing bucket; the other 8 `backblaze-*` variants had always-empty state and — confirmed via a full bucket inventory scan — their buckets were never actually created at all. All 12 leaves' content is byte-identical at the new path; every relocation followed the same pull → recreate → push → verify-clean-plan → empty-old-state → verify-zero-destroy → delete procedure used by every migration in this sequence.

### `pigeon-cli/job`: one real leaf, one leaf that no longer exists

`import-backblaze` — a real `compute-instance/v5.3.0` job (instance + block volume + scoped IAM key) — relocated with a clean "No changes" plan at the new path on the first attempt, confirming the `state/iam` permission set assembled above was already sufficient. `import-macbook` turned out to hold no resources at all: its job content had already been renamed to a `deduplicate-macbook` leaf in an earlier, unrelated change (commit `ce9fa0d`), and that dedupe job was itself killed outright in a later commit (`2f85a0c`) — `import-macbook` is now a permanently empty placeholder (`terragrunt.hcl` only, confirmed via `terragrunt state pull` showing zero resources). It was relocated as a trivial empty leaf, not migrated as a resource.

### Decommissioning

With all of their leaves moved, `workloads/custodial-storage/` (including its `README.md`), `workloads/management/`, and `workloads/pigeon-cli/` are deleted entirely — matching this repo's established precedent for every prior leaf-emptying ADR.

### Regression check

Post-migration, `terragrunt plan` was re-run at `workloads/pigeon.dev/terraform/state/iam` and `workloads/noisypigeon.com/terraform/state/iam` — both clean, confirming the shared `workloads/root.hcl`/`.env.enc` (untouched by this migration) still resolves correctly for them. `workloads/pigeon.dev/terraform/state/bucket` reproduced the same pre-existing `403 AccessDenied` bug ADR-0132 already documented and explicitly left out of scope for `pigeon.dev` — confirmed unrelated to this migration (same failure mode, same root cause, nothing in this PR touches that leaf or the shared deployer's live permissions).

## Consequences

- `willowgraysen.com` can rotate its own deployer credentials, resize or relocate its own state bucket, and manage its own secrets independently of every other workload — the same self-sufficiency `pigeon.dev` and `noisypigeon.com` already have.
- The repo's own original bootstrap (`workloads/management/terraform/scaleway/`) no longer exists as a Terraform-managed unit. Its underlying Scaleway resources (the `terraform-t0nh1b-state` bucket and its deployer IAM) remain alive and unmanaged, permanently load-bearing for `pigeon.dev`'s and `noisypigeon.com`'s own `state/iam` leaves and `pigeon.dev`'s `state/bucket`.
- `workloads/custodial-storage/`, `workloads/management/`, and `workloads/pigeon-cli/` no longer exist. Every leaf that previously lived under the shared bootstrap now lives under `workloads/willowgraysen.com/`, `workloads/pigeon.dev/`, or `workloads/noisypigeon.com/`.
- `state/bucket` and `state/iam` end up on different roots (self-governing and shared-forever, respectively) — the same deliberate asymmetry ADR-0132 established, not an inconsistency.

## Out of scope

- Fixing `pigeon.dev/terraform/state/bucket`'s pre-existing `AccessDenied` gap (ADR-0132's own documented out-of-scope item) — still not fixed here; `pigeon.dev` is untouched by this PR.
- The pre-existing `lifecycle_rule` drift on `custodial-storage/duck-jellyfish` (now `willowgraysen.com/terraform/custodial-storage/duck-jellyfish`) — confirmed present identically before and after the move, unrelated to it.
- Any further retrofitting — every workload in this repo now either has its own dedicated bootstrap (`pigeon.dev`, `noisypigeon.com`, `willowgraysen.com`) or no longer manages Scaleway/Cloudflare resources of its own.
