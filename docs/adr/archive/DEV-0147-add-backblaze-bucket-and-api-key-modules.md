# DEV-0147: add backblaze/bucket and backblaze/api-key modules

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-09.
- **Status**: Accepted.

## Context

A `cloudflare/bucket` module wrapping `cloudflare_r2_bucket` was explored first, but was abandoned after running into a practical limitation with Cloudflare R2 — Backblaze B2 is used instead.

This adds two new modules under a brand-new `templates/terraform/backblaze/` provider root — `bucket` (wraps `b2_bucket`) and `api-key` (wraps `b2_application_key`) — landing together in one ADR, the same way ADR-0119/ADR-0085 each bundled multiple related modules into a single decision record.

Verified against the live `Backblaze/b2` provider (latest `v0.14.0`) schema:

- `b2_bucket`: `bucket_name` (required, string, force-replace) and `bucket_type` (required, enum `allPublic`/`allPrivate`) are the only required fields. Optional: `bucket_info` (metadata map, keys ≤50 bytes/values ≤10,000 bytes), `cors_rules`, `default_server_side_encryption`, `lifecycle_rules`, `file_lock_configuration`. Read-only: `account_id`, `bucket_id`, `id`, `options`, `revision`.
- `b2_application_key`: `key_name` and `capabilities` (set of string) are required, both force-replace. Optional: `bucket_id` (deprecated, force-replace, conflicts with `bucket_ids`), `bucket_ids` (set of string, force-replace), `name_prefix`, `valid_duration_in_seconds` (force-replace). Read-only/sensitive: `application_key_id`, `application_key` (sensitive), `expiration_timestamp`, `options`.

B2 bucket names are globally unique across *all* B2 accounts (like S3), not just within a project (unlike Scaleway's `scaleway_object_bucket`) — so this repo's established `name_prefix`/random-suffix/`name_suffix` naming convention ([ADR-0118](DEV-0118-simplify-scaleway-compute-instance-interface.md), `scaleway/object-bucket`/`compute-instance`/`block-volume`) matters even more here:

- `bucket` only needs `name_prefix`/`name_suffix` — no `exact_name` escape hatch, simpler than `object-bucket`, matching `compute-instance`/`block-volume`'s plain required-pair style; no `moved` block needed since this is a new module.
- `bucket_type` is hardcoded to `"allPrivate"` inside the module, not exposed as a variable — least-privilege default, consistent with `object-bucket` never auto-enabling public access.
- `bucket_info` is exposed as a single friendly `description` string input (not the full free-form map), optional.
- `api-key` exposes `capabilities` (required, no local validation — same "provider's own catalog changes too often" rationale as [ADR-0079](DEV-0079-add-scaleway-compute-instance-module.md)/[ADR-0085](DEV-0085-add-scaleway-block-volume-module.md)'s instance-type/image fields) and `bucket_ids` (optional, to scope a key to one or more buckets — composes naturally with the new `bucket` module's `bucket_id` output). The deprecated singular `bucket_id` is deliberately not exposed. `valid_duration_in_seconds` defaults to 30 days (`2592000`), mirroring `scaleway/iam-api-key`'s own 30-day default-expiry policy for new credentials — but as a plain default, no `time_static` anchor needed, since B2's field is a relative duration from creation, not an absolute timestamp.

**Real wiring gap found while checking how a new module gets released:** `.github/workflows/template-release.yml`'s module-discovery step hardcodes `find templates/terraform/scaleway -mindepth 2 -maxdepth 2 -name versions.tf` — it is not generic across provider roots. Since DigitalOcean was fully decommissioned ([ADR-0086](DEV-0086-decommission-digitalocean.md)), Scaleway has been the only provider under `templates/terraform/`, so this was never exercised. Adding `backblaze/` as a second provider root needs the exact same generalization [ADR-0043](DEV-0043-add-scaleway-provider.md) did the first time this repo had two provider roots. `.github/workflows/module-docs.yml`'s `working-dir` list is separately hand-maintained (not derived from `find`), so it just needs the two new paths appended, same as any other new module.

## Decision

### New provider root: `templates/terraform/backblaze/`

First module root added since ADR-0086 removed DigitalOcean; same file-layout convention as every `scaleway/*` module (resource-named `.tf` file, `inputs.tf`, `outputs.tf`, `versions.tf`, `README.md` — no hand-written `CHANGELOG.md`; `template-release.yml` creates it from scratch on first merge, same as every other module's first release).

### Module: `backblaze/bucket`

`bucket.tf`:

```hcl
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  bucket_name = "${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"
}

resource "b2_bucket" "bucket" {
  bucket_name = local.bucket_name
  bucket_type = "allPrivate"
  bucket_info = var.description != null ? { description = var.description } : null
}
```

Inputs: `name_prefix` (string, required), `name_suffix` (string, required), `description` (string, default `null`, stored in the bucket's `bucket_info` metadata).

Outputs: `bucket_id` (→ `b2_bucket.bucket.bucket_id`, the value an `api-key` caller feeds into `bucket_ids`), `bucket_name` (→ `b2_bucket.bucket.bucket_name`).

`versions.tf`:

```hcl
terraform {
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

### Module: `backblaze/api-key`

`api_key.tf` (file name mirrors `scaleway/iam-api-key`'s `api_key.tf`):

```hcl
resource "b2_application_key" "key" {
  key_name                  = var.key_name
  capabilities               = var.capabilities
  bucket_ids                 = var.bucket_ids
  valid_duration_in_seconds  = var.valid_duration_in_seconds
}
```

Inputs: `key_name` (string, required), `capabilities` (`set(string)`, required, no validation block), `bucket_ids` (`set(string)`, default `null`), `valid_duration_in_seconds` (number, default `2592000` — 30 days; pass `null` for a key that never expires).

Outputs: `application_key_id` (plain), `application_key` (`sensitive = true`).

`versions.tf`: same `b2` provider pin, no `random` (key names don't need global uniqueness).

### Wiring

- Fix `template-release.yml`'s module-discovery `find` to scan every provider root instead of just `scaleway`: `find templates/terraform/scaleway -mindepth 2 -maxdepth 2 -name versions.tf` becomes `find templates/terraform -mindepth 3 -maxdepth 3 -name versions.tf` (provider/module/versions.tf = 3 levels under `templates/terraform`). No other line in that workflow references `scaleway` by name — `PROVIDER`/`MODULE` are already derived generically via `basename`/`dirname`.
- Append `templates/terraform/backblaze/bucket,templates/terraform/backblaze/api-key` to `module-docs.yml`'s `working-dir` list.
- Add two rows to `templates/terraform/README.md`'s Modules table.
- Each `README.md` ships with the one-paragraph description plus a hand-typed empty `<!-- BEGIN_TF_DOCS -->`/`<!-- END_TF_DOCS -->` skeleton (table headers, no rows) — same pattern `pigeon-cluster` shipped in its own first commit — for `module-docs.yml` to fill in on the next push to `main`.

### Versioning

Both modules are new, no prior tags → `template-release.yml` computes `0.1.0` for each independently on first merge, same as every other first release in this repo. Lands as a single PR (both modules are brand-new — no existing tagged module directory to collide with, unlike ADR-0136's two-PR split), carrying one `release:minor` label per the `release-pr` skill.

## Consequences

- Re-opens multi-provider support in `templates/terraform/`, last true since before ADR-0086; `template-release.yml`'s module discovery becomes provider-generic again, closing a gap that would otherwise have silently skipped `backblaze/*` changelogs/tags forever.
- `backblaze/bucket` always creates a private bucket; a public bucket needs a separate module change later if ever needed.
- `backblaze/api-key` composes directly with `backblaze/bucket`'s `bucket_id` output for per-bucket key scoping.
- No `workloads/*` consumer wired up yet — this ADR only adds the two modules.

## Out of scope

- Wiring a real `workloads/*` consumer for either module — left for a future, separate change once an actual B2 bucket/key is needed.
- Exposing `b2_bucket`'s `cors_rules`, `default_server_side_encryption`, `lifecycle_rules`, and `file_lock_configuration` — genuinely deferred, not a permanent boundary, to be added once a concrete dataset needs one of them.
- Exposing the full free-form `bucket_info` map (beyond the single `description` key) — same deferred status as above.
- A `bucket_type` override (public buckets) — explicit design choice per the user, not merely deferred.
- Validating `capabilities` against B2's capability catalog locally — deliberately not done, the catalog is provider-defined and changes independently of this repo (same precedent as ADR-0079/ADR-0085's instance-type/image fields).
- The deprecated singular `bucket_id` input on `api-key` — deliberately not exposed.
