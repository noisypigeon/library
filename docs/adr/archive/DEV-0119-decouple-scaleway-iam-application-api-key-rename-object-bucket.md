# DEV-0119: Decouple Scaleway IAM application/API-key from iam-policy; rename object-bucket's naming inputs

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

Two independent cleanups land together here because the second genuinely depends on the first.

**`object-bucket`'s `namespace`/`name` inputs read badly at call sites** (`namespace = local.namespace` pairs a generic variable name with an already-namespace-shaped value) — the same complaint ADR-0118 already fixed for `compute-instance`'s `namespace`/`name` → `name_prefix`/`name_suffix`. Nearly every real `object-bucket` consumer is cold/archival data (`poisoned/*`, `email`, `media`, `macbook-scratch`, `backblaze`), yet `storage_class` defaults to `"standard"`, so each would have to opt into `glacier` by hand.

**`iam-policy` bundles three independent concerns into one module**: `scaleway_iam_application`, `scaleway_iam_policy`, and `scaleway_iam_api_key`. A repo-wide census found exactly two real consumers — `workloads/scaleway/terraform/management/iam.tf` (the bootstrap/deployer identity every other Scaleway leaf authenticates as) and `workloads/pigeon-cli/terraform/job/iam.tf` (the one live `pigeon-cli` compute job) — and confirmed **zero** consumers use `bucket_names`/`bucket_actions`/`admin_project_id`: ADR-0066/ADR-0069's bucket-scoped policy feature never had a second real caller. Worse, `job/iam.tf` mints its *own* throwaway application rather than sharing one, even though every other `pigeon-cli` leaf convention in this repo assumes one shared identity per concern (e.g. the shared Cockpit source, ADR-0103). This ADR splits `iam-policy` into three modules — new `iam-application`, new `iam-api-key` (with a 30-day-from-creation default `expires_at`), and a slimmed `iam-policy` (policy-only, takes `application_id` as input, drops the dead bucket-scoping inputs) — and introduces the first real shared `iam-application` leaf, `workloads/scaleway/terraform/pigeon-cli/iam-application/`, onto which `job/iam.tf` is migrated.

`management/iam.tf`'s own identity is the live credential (`SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY` in the root `.env`) that Terraform itself uses to authenticate *every* Scaleway leaf (`workloads/root.hcl`'s generated `provider_generated.tf`). Migrating it to the new modules means destroying and recreating that application+key — done naively in one shot, this deletes the very credential the apply needs to keep authenticating with. Per explicit instruction, this is sequenced as two phases: add the new application/policy/key alongside the old ones first, rotate `.env` to the new key once confirmed live, then remove the old ones in a second, separate apply.

## Decision

### `templates/terraform/scaleway/object-bucket` (v3.0.0 → v4.0.0)

- Renamed `namespace` → `name_prefix`, `name` → `name_suffix` (same `"${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"` naming scheme, just clearer call-site names).
- `storage_class`'s default changed from `"standard"` to `"glacier"`.

### Three IAM modules under `templates/terraform/scaleway/`

- **New `iam-application`** (`v0.1.0`): wraps `scaleway_iam_application` only. Inputs `name` (required), `description` (optional). Outputs `id`, `name`.
- **New `iam-api-key`** (`v0.1.0`): wraps `scaleway_iam_api_key` only. Inputs `application_id` (required), `description` (optional), `expires_at` (optional, defaults to 30 days after first creation):
  ```hcl
  resource "time_static" "created" {}
  resource "scaleway_iam_api_key" "api_key" {
    application_id = var.application_id
    description     = var.description
    expires_at      = coalesce(var.expires_at, timeadd(time_static.created.rfc3339, "720h"))
  }
  ```
  `time_static` only evaluates once, at creation, so the default doesn't drift on every `plan`. Adds a `hashicorp/time ~> 0.9` provider dependency. Outputs `access_key`/`secret_key` (both `sensitive`).
- **`iam-policy`, refactored** (v3.0.0 → v4.0.0): deleted `bucket_access.tf` entirely; removed `bucket_names`, `bucket_actions`, `admin_project_id`, `expires_at` inputs and the `access_key`/`secret_key` outputs; removed the `scaleway_iam_application`/`scaleway_iam_api_key` resources, leaving only `scaleway_iam_policy` (unchanged `count`/`dynamic "rule"` logic, existing `moved` block kept as-is); added a required `application_id` input; simplified `name`'s validation to drop the now-gone bucket-scoping branch; added a new `id` output for the policy itself.

### New shared `iam-application` leaf for pigeon-cli

`workloads/scaleway/terraform/pigeon-cli/iam-application/` is a new leaf — one `module "iam_application"` call, `name = "pigeon-cli"`, output `id`. Its output is hand-copied into the root `.env` as `PIGEON_CLI_IAM_APPLICATION_ID` and surfaced as a new `pigeon_cli_iam_application_id` local in `workloads/root.hcl`'s existing `generate "scaleway_ids"` block, following the exact precedent already there for `pigeon_cockpit_*` (ADR-0103) — this repo's established pattern for cross-leaf values is a hand-copied `.env` entry surfaced via `root.hcl`, not a Terragrunt `dependency` block (no leaf in this repo uses one).

`workloads/pigeon-cli/terraform/job/iam.tf` migrates from one `module "iam"` (old bundled module, minted its own application) to `module "iam_policy"` + `module "iam_api_key"`, both pointed at `local.pigeon_cli_iam_application_id`. The job's existing explicit `expires_at = "2027-09-25T22:32:12Z"` is preserved on the new `iam_api_key` call — it deliberately does not fall onto the new 30-day default, which would expire this live job's bucket credentials in a month. `compute.tf`'s two `keyring` entries now read `module.iam_api_key.access_key`/`.secret_key`.

This changes the compute instance's `keyring`/cloud-init content, which (per ADR-0104/ADR-0118's existing `lifecycle.replace_triggered_by`) replaces the live `mega-storage-consolidation` deduplication instance on its next apply — new IP, new SSH host key, and the old bucket API key is revoked as the new one takes over.

### `workloads/scaleway/terraform/management/iam.tf` — two-phase credential rotation

**Phase 1 (additive only)**: added `module "iam_application"`, `module "iam_policy"` (same permission sets as before, also fixing a pre-existing duplicate `InstancesFullAccess` entry in the list), and `module "iam_api_key"` (explicit `expires_at = "2027-09-25T22:32:12Z"`, matching the prior value) — alongside, not replacing, the existing `module "iam"` block. Once applied, the new `access_key`/`secret_key` outputs get hand-copied into the root `.env`'s `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`, verified live via `terragrunt plan` against a couple of unrelated leaves.

**Phase 2 (destructive, separate apply)**: once Phase 1 is verified live, the old `module "iam" { source = iam-policy/v2.0.0 ... }` block is deleted outright, destroying the old application/policy/key.

This is this repo's own live deployer identity, used by every other Scaleway leaf's provider authentication — the highest blast-radius step in this ADR. Each phase's apply is a deliberate, confirmed step, not bundled into an unattended run.

### Mechanical consumer sweep

All 12 `object-bucket` consumers got `namespace`/`name` → `name_prefix`/`name_suffix` renamed and their module source bumped to `v4.0.0`: the 10 leaves under `workloads/bucket/terraform/noisypigeon/{backblaze,email,macbook-scratch,media,poisoned/*}/...`, plus `workloads/scaleway/terraform/management/bucket.tf` and `workloads/scaleway/terraform/custodian/duck-jellyfish/bucket.tf`. `management/bucket.tf` (the Terraform state bucket) also got an explicit `storage_class = "standard"` added, so its behavior doesn't silently change under the new default. The other 9 leaves that didn't already set `storage_class` pick up the new `glacier` default — expected to show a real lifecycle-rule diff on `plan` rather than "No changes", since they're all cold-storage-appropriate datasets; applying that diff is left to a deliberate follow-up, not bundled into this rename sweep.

## Consequences

- `release:major` for `templates/terraform/scaleway/object-bucket` (v3.0.0 → v4.0.0) — breaking rename of `namespace`/`name`, plus a behavior-changing default (`storage_class`). (`v3.0.0` was a bookkeeping-only seed tag from ADR-0110's directory move, never actually released with a CHANGELOG entry — this is the module's first real release since `v2.0.0`.)
- `release:major` for `templates/terraform/scaleway/iam-policy` (v3.0.0 → v4.0.0) — breaking removal of `bucket_names`/`bucket_actions`/`admin_project_id`/`expires_at`/`access_key`/`secret_key`, breaking addition of a required `application_id`. (As with `object-bucket`, `v3.0.0` was a bookkeeping-only seed tag from ADR-0110's move, never actually released — this is the module's first real release since `v2.0.1`.)
- New modules `templates/terraform/scaleway/iam-application` and `templates/terraform/scaleway/iam-api-key`, both seeded at `v0.1.0`.
- `workloads/pigeon-cli/terraform/job/` loses its private, throwaway IAM application in favor of the shared `pigeon-cli` one — the next apply replaces the live `mega-storage-consolidation` deduplication compute instance (new IP, new SSH host key, rotated bucket credentials).
- `workloads/scaleway/terraform/management/iam.tf`'s deployer identity is rotated end to end — a new application, policy, and API key replace the originals, requiring a manual `.env` update between Phase 1 and Phase 2's applies.
- 9 of the 12 `object-bucket` consumers silently pick up a new 90-day glacier-transition lifecycle rule once their `plan` is applied; `management/bucket.tf` and the 2 leaves that already set `storage_class` explicitly are unaffected.

## Out of scope

- Actually applying the new `glacier`-default lifecycle rule for the 9 affected `object-bucket` leaves. This ADR only lands the rename/default-change and version bump; applying the resulting diff (and thus changing real bucket lifecycle behavior on live data) is left to a deliberate follow-up.
- A Terragrunt `dependency`-block mechanism for cross-leaf references. The hand-copied-`.env` pattern (ADR-0103's precedent) continues to cover this case; a real dependency mechanism remains unexplored.
- Enforcing a single shared `iam-application` per consumer group beyond `pigeon-cli` (e.g. a similar shared-identity convention for any future non-`pigeon-cli` job family). Not needed until a second such family exists.
