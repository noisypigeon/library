# DEV-0151: Rename `enable_heic_transcoding` to `enable_transcoding`, add optional lifecycle expiration to `object-bucket`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-10.
- **Status**: Accepted.

## Context

Two independent changes, recorded together because both landed in the same session off the back of the same `pigeon-cli transform` work.

### The `enable_heic_transcoding` name is narrower than what it does

ADR-0150 landed yesterday, adding `instance_config.enable_heic_transcoding` to `compute-instance` (`templates/terraform/scaleway/compute-instance/inputs.tf:41`) and a matching `jobs[*]` passthrough to `pigeon-cluster` (`templates/terraform/scaleway/pigeon-cluster/inputs.tf:126`). What the flag actually does, at `templates/terraform/scaleway/compute-instance/instance.tf:327-334`, is add `ppa:savoury1/ffmpeg4` and `apt-get install ffmpeg` — a general-purpose ffmpeg build. libheif-based HEIC decode is the capability that motivated reaching for that PPA rather than Ubuntu's archive build, but it is one codec among everything else the build ships.

The naming strain is already visible in the only consumer. `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/cluster_definition.tf` currently defines a `transform-heic-to-jpg` job, where the name happens to match — but a `--input-file-type=png` or `--input-file-type=webp` transform would need exactly the same flag, and reading `enable_heic_transcoding = true` on a PNG job would look like a mistake rather than the correct configuration. Renaming to `enable_transcoding` makes the input describe its effect ("install ffmpeg for transcoding work") instead of one motivating use of it.

This is a pure rename. The PPA, the package list, the cloud-init position (after the `pigeon-cli` gist bootstrap, before the Cockpit/Alloy block) and the resulting instance are all unchanged.

Current released versions: `compute-instance` `v5.7.0` and `pigeon-cluster` `v1.3.0` (both tagged 2026-10-10, PRs #257/#258).

### `object-bucket` has no way to expire objects

`object-bucket` renders exactly one lifecycle rule today (`templates/terraform/scaleway/object-bucket/bucket.tf:29-39`): a 90-day `GLACIER` transition, gated entirely on `var.storage_class == "glacier"`, with `days = 90` hardcoded because Scaleway's API enforces that floor (ADR-0072). There is no `expiration` block anywhere in the module, and ADR-0044/0045 explicitly deferred a general `lifecycle_rule` passthrough, which has never been added.

That leaves the two `pigeon-cli` reports buckets — `workloads/willowgraysen.com/terraform/pigeon-cli/shared/reports/phase-deduplicate/` and its `phase-transform/` sibling — accumulating job reports indefinitely. These are short-lived diagnostic artifacts; the wanted retention is 72 hours.

**Scaleway lifecycle expiration is day-granular.** Confirmed from the provider's own schema (`tofu providers schema -json`, scaleway v2.86.0 — what the leaves' `.terraform.lock.hcl` resolves to under the module's `~> 2.0`). `lifecycle_rule.expiration` exposes exactly three fields:

| Field | Type | Note |
|---|---|---|
| `days` | number | "number of days after object creation when the specific rule action takes effect" |
| `date` | string | an absolute timestamp, which S3 requires be midnight UTC — not a relative duration |
| `expired_object_delete_marker` | bool | versioning cleanup, unrelated to retention |

There is no hour-based field anywhere in the rule, in any of its four nested blocks. This is a property of the S3 lifecycle API the provider wraps, not a provider gap, so no provider upgrade changes it.

Consequently the input is named in **days**, not hours. An `expiration_hours` input would have to either silently round (making `1` and `24` behave identically) or reject everything that isn't a multiple of 24, which is days with extra steps. 72 hours is expressed as `expiration_days = 3`.

## Decision

### 1. `compute-instance`: rename `instance_config.enable_heic_transcoding` to `enable_transcoding`

```hcl
enable_transcoding = optional(bool, false)
```

The `instance_config` description (`inputs.tf:43`) is rewritten to lead with the general effect and keep HEIC as the stated reason for the PPA choice, since that description is the only documentation surface a caller sees — `README.md`'s input table is regenerated from it by `module-docs.yml`. The `%{~if~}` guard and its comment at `instance.tf:327-330` are updated to match.

**Versioning**: breaking, and worth being precise about *how*. Confirmed by `tofu validate` against the renamed module: a caller still passing `enable_heic_transcoding` does **not** get an error. It gets a warning — "the object type for input variable `instance_config` does not include an attribute named `enable_heic_transcoding`, so this definition is unused" — and validation otherwise succeeds. The key is silently dropped, the instance provisions with no ffmpeg, and the failure surfaces much later as the transform job dying on its first file.

A silent no-op is a worse upgrade hazard than a hard failure, not a milder one, so this is unambiguously `release:major`, **v5.7.0 → v6.0.0** — consistent with ADR-0118/0119, where an `optional()` default likewise did not make a rename non-breaking. No `moved` block applies; a variable rename is caller-side only, with no state address to migrate.

### 2. `pigeon-cluster`: rename the passthrough, re-pin `compute-instance`

The `jobs[*]` field is renamed to `enable_transcoding` (`inputs.tf:126`), along with its comment block and the trailing sentence of the long `jobs` description (`inputs.tf:129`). The passthrough at `cluster.tf:190` becomes `enable_transcoding = each.value.enable_transcoding`.

Both `compute-instance` source pins — `cluster.tf:153` (`module "job"`) and `cluster.tf:215` (`module "bastion"`) — move from `v5.7.0` to `v6.0.0`. `module "bastion"` passes no `instance_config` at all, so it needs the re-pin but no field change.

**Versioning**: breaking, for the same reason as above. `release:major`, **v1.3.0 → v2.0.0**.

### 3. `object-bucket`: new optional `expiration_days`

```hcl
variable "expiration_days" {
  type        = number
  description = "..."
  default     = null

  validation {
    condition     = var.expiration_days == null || var.expiration_days >= 1
    error_message = "expiration_days must be at least 1 (the S3 lifecycle API's minimum), or null for no expiration rule."
  }
}
```

Rendered as a second `dynamic "lifecycle_rule"`, added after the existing glacier one, which is left byte-identical so no current consumer sees a plan diff:

```hcl
  dynamic "lifecycle_rule" {
    for_each = var.expiration_days != null ? [1] : []
    content {
      id      = "expire-objects"
      enabled = true

      expiration {
        days = var.expiration_days
      }
    }
  }
```

A separate rule rather than an `expiration` block folded into the existing one, because the existing rule is gated on `storage_class == "glacier"` — a `standard` bucket wanting expiration would otherwise get no rule block at all.

The `id` is a static `"expire-objects"` rather than one interpolating the day count, so changing the retention is an in-place rule update instead of a rule replacement. It is also the first explicit `id` in this module: with two rules now able to coexist, leaving both to the provider's generated-ID behavior is a needless unknown.

The description documents the day-granularity constraint and notes the interaction with `storage_class`: an expiration shorter than 90 days means objects are deleted before the glacier transition could ever fire, so a short expiration should be paired with `storage_class = "standard"`. This is left as documentation rather than a cross-variable validation, since a long expiration alongside a glacier transition is perfectly coherent.

**Versioning**: purely additive — `null` default emits no rule and preserves today's behavior for all eight existing consumers. `release:minor`, **v4.1.1 → v4.2.0**.

### 4. Both reports leaves wired to a 3-day expiry

`shared/reports/phase-deduplicate/bucket.tf` and `shared/reports/phase-transform/bucket.tf` both move from `object-bucket/v4.0.0` to `v4.2.0` and gain:

```hcl
  storage_class   = "standard"
  expiration_days = 3
```

`storage_class` is set explicitly rather than left to inherit: ADR-0119 flipped the module default to `"glacier"`, and these `pigeon-cli` leaves are among the only consumers still relying on that implicit default. Under a 3-day expiry the 90-day transition can never fire, so carrying it is dead weight on the live `phase-deduplicate` bucket.

### 5. Four PRs, two of them ordered

`template-release.yml` applies one bump level to every module changed in a PR, so the two `release:major` renames and the `release:minor` `object-bucket` change cannot share a PR. And a module's short source URL only resolves once its tag exists, which orders the first two:

1. `compute-instance` rename, plus this ADR — `release:major`, cuts `compute-instance/v6.0.0`.
2. `pigeon-cluster` rename and re-pin to `v6.0.0` — `release:major`, cuts `pigeon-cluster/v2.0.0`.
3. `object-bucket` `expiration_days` — `release:minor`, cuts `object-bucket/v4.2.0`.
4. Both reports leaves — no `release:*` label; goes through the `terragrunt-plan.yml`/`terragrunt-apply.yml` gate (ADR-0129) instead.

PR 1 must merge and tag before PR 2 opens. PR 3 is independent of both and can land at any point; PR 4 depends only on PR 3. This follows the same split ADR-0136 and ADR-0150 each used to keep tag-cutting and leaf-gating off one diff.

The consumer leaf `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/` is deliberately excluded from all four. It needs `enable_heic_transcoding = true` → `enable_transcoding = true` in `cluster_definition.tf` and a `pigeon-cluster` re-pin to `v2.0.0` in `cluster.tf`, but both files carry substantial unrelated in-flight work (the cluster uncommented, bastion and private-network/public-gateway toggles enabled, the `transform-heic-to-jpg` job added). Those two edits ride with that branch rather than dragging it into a module release PR.

### 6. ADR-0150 keeps `Status: Accepted`

Only the name chosen by ADR-0150 changes here. Its actual decision — install a libheif-capable ffmpeg from `ppa:savoury1/ffmpeg4`, gate it behind an `instance_config` flag, pass it through per job — is untouched and still in force, so it is not marked Superseded. This section exists so the naming mismatch between the two records reads as a deliberate amendment rather than undocumented drift.

## Consequences

- `release:major` for `templates/terraform/scaleway/compute-instance` (v5.7.0 → v6.0.0) and `templates/terraform/scaleway/pigeon-cluster` (v1.3.0 → v2.0.0) — a breaking rename in both, despite no behavior change whatsoever. The blast radius is small in practice: `pigeon-cluster` is `compute-instance`'s only consumer, and the one job in `workloads/` is the only place that sets the field.
- The rename fails *quietly* on an un-migrated caller, which is the sharpest edge here. Terraform treats an unknown attribute on an object-typed variable as a warning, not an error, so a stale `enable_heic_transcoding` is dropped and the instance comes up with no ffmpeg at all — a clean plan and apply, then a job that dies on its first file. The major version bump is the only real guard; anyone pinning by major gets stopped at the source URL rather than at apply time.
- `release:minor` for `templates/terraform/scaleway/object-bucket` (v4.1.1 → v4.2.0) — additive, with every existing consumer unaffected by the `null` default.
- The reports buckets self-empty on a 3-day cycle, so job reports are no longer a monotonically growing storage cost. The flip side is a real retention ceiling: a report older than 3 days is gone, and nothing archives it first.
- `object-bucket` now has a general shape for lifecycle rules — a second `dynamic` block alongside the glacier one — that further rule types can follow without restructuring the first.
- Bumping the reports leaves from `v4.0.0` to `v4.2.0` also picks up v4.1.0's `exact_name`/website/public-read additions and v4.1.1's `project_id` fix. All default to `null`/`false`, and v4.1.0's `moved` block absorbs the `random_string.suffix` → `suffix[0]` change, so the only intended plan diff is the lifecycle rules.

## Out of scope

- Hour-granular expiration. Not deferred — a permanent boundary: the S3 lifecycle API has no sub-day unit (`expiration.date` exists but is an absolute midnight-UTC timestamp, not a finer-grained duration), so no provider version or module change can express it. Anything needing true 72-hour precision would have to delete objects out-of-band rather than through a lifecycle rule.
- Other lifecycle rule types — `abort_incomplete_multipart_upload_days`, noncurrent-version expiration, and `prefix`/`tags`-scoped rules are all available on the resource and none are exposed.
- Whether `ppa:savoury1/ffmpeg4` covers every codec a future non-HEIC `transform` might need. The rename broadens the input's name, not its package set; ADR-0150's own "verify the PPA live" caveat still stands unverified.
- The consumer leaf's rename and `v2.0.0` re-pin, left to the in-flight cluster branch (§5).
- Giving the two reports buckets distinguishable names. Both leaves compute `name_suffix = "reports"`, so both produce `pigeon-cli-<random>-reports` with no phase in the name. Fixing `phase-transform` is free since it has never been applied, but `phase-deduplicate` is live and a rename means destroy/recreate — a separate decision, not folded in here.
- Backfilling `object-bucket`'s missing `[4.1.1]` CHANGELOG entry (the tag exists; PR #196's changelog commit never landed). Harmless, since `template-release.yml` computes the next version from `git tag -l` rather than the changelog.
