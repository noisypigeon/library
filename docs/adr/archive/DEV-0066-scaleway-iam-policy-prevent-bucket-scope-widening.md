# DEV-0066: prevent bucket-scope widening in scaleway/iam-policy

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-27.
- **Status**: Accepted.

## Context

The goal motivating this ADR is simple: mint a Scaleway Object Storage API key (access key + secret key) that can only **read** a specific bucket. `terraform/modules/scaleway/iam-policy` has supported this mechanically since ADR-0049 (`bucket_names` + `bucket_actions`, via a per-bucket `scaleway_object_bucket_policy`, independently optional from any org/project `scaleway_iam_policy` grant) — but the one real prior attempt to use it never worked, and it failed in exactly the way ADR-0048 anticipated but explicitly chose not to guard against:

> Preventing or warning about the composition hazard with blanket `ObjectStorage*` permission sets in code (e.g. via a `validation` block) — documented here instead; both mechanisms remain independently available.

That attempt — `terraform/infrastructure/scaleway/fr-par/pigeon.dev/scratch/iam.tf`, merged in commented-out, verbatim, from the former `pigeon-do` repo (ADR-0052) — reads:

```hcl
# module "iam" {
#   source = "...iam-policy?ref=terraform/modules/scaleway/iam-policy/v0.1.0"
#   name   = "${module.bucket.name}-iam"
#   project_ids = [
#     local.scaleway_project_id
#   ]
#   project_permission_sets = [
#     "ObjectStorageObjectsWrite",
#     "ObjectStorageObjectsRead"
#   ]
#   expires_at = "2027-09-25T22:32:12Z"
#   bucket_names = {
#     email = module.bucket.name
#   }
#   bucket_actions = [
#     "s3:ListBucket",
#     "s3:GetObject",
#     "s3:PutObject"
#   ]
# }
```

Two independent mistakes compound here: the `project_ids` value is wrong (this file lives under the `pigeon.dev` project tree but references `noisypigeon_com`'s project id — a call-site bug this ADR doesn't fix), and — the one in scope here — `project_permission_sets` grants a blanket `ObjectStorageObjectsRead`/`ObjectStorageObjectsWrite` on the whole project in the same call that also sets `bucket_names`. Per ADR-0048's own findings, Scaleway IAM rules are allow-only with no explicit deny, so the project-wide grant already covers every bucket in that project — the `bucket_names` restriction becomes decorative, and the key isn't read-only regardless (it also isn't, separately, since `bucket_actions` includes `s3:PutObject`). The module accepted this input without complaint; only manual review (or a failed expectation at use time) would catch it. Left commented out, unreviewed, uncorrected.

ADR-0048 treated this as a documentation problem. It's now a demonstrated, reproducible one: the exact hazard it described is what sits in the one real consumer that tried to use bucket scoping. `bucket_names` cross-referencing `organization_permission_sets`/`project_permission_sets` is enforceable today — the module has required Terraform/OpenTofu `>= 1.9.0` for cross-variable `validation` blocks since ADR-0049, and already uses one on `name` for a structurally identical "at least one scope fully set" check.

## Decision

Add a `validation` block to `bucket_names` in `inputs.tf` that rejects combining it with any `ObjectStorage*`-family organization/project permission set in the same module call:

```hcl
variable "bucket_names" {
  type        = map(string)
  description = "Map of static logical key => exact Object Storage bucket name to grant access to (no bucket access is granted by default)"
  default     = {}

  validation {
    condition = length(var.bucket_names) == 0 || !anytrue([
      for permission_set in concat(coalesce(var.organization_permission_sets, []), coalesce(var.project_permission_sets, [])) :
      startswith(permission_set, "ObjectStorage")
    ])
    error_message = "bucket_names cannot be combined with an ObjectStorage*-family organization_permission_sets/project_permission_sets grant in the same module call: a blanket Object Storage permission set already grants access to every bucket in scope, making bucket_names/bucket_actions scoping ineffective. Grant blanket Object Storage access via a separate module call instead."
  }
}
```

`startswith(permission_set, "ObjectStorage")` catches every Scaleway Object Storage permission set observed so far (`ObjectStorageFullAccess`, `ObjectStorageObjectsRead`, `ObjectStorageObjectsWrite`) without hardcoding an exhaustive enum that would need updating if Scaleway adds more. No other resource file changes — the bucket-scoping mechanism itself (`bucket_access.tf`) already works correctly; it just wasn't guarded against being silently overridden.

`bucket_actions` is deliberately left unrestricted beyond its existing validated set (`s3:ListBucket`/`s3:GetObject`/`s3:PutObject`/`s3:DeleteObject`) — "read-only" stays a consumer choice (`bucket_actions = ["s3:ListBucket", "s3:GetObject"]`), since this module is also legitimately used for read-write bucket keys.

The module's `README.md` gains a `## Usage` section (above the `terraform-docs`-managed block, so it isn't overwritten) showing the correct bucket-scoped, read-only pattern:

```hcl
module "iam" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/iam-policy?ref=terraform/modules/scaleway/iam-policy/v1.0.0"
  name   = "${module.bucket.name}-iam"

  bucket_names   = { email = module.bucket.name }
  bucket_actions = ["s3:ListBucket", "s3:GetObject"]
}
```

## Consequences

- Breaking release (`release:major`): a config combining `bucket_names` with a blanket `ObjectStorage*` permission set — previously silently accepted — now fails `validate`/`plan` instead. No change for the module's one other live consumer, `noisypigeon.com/terraform/iam.tf`, which grants `ObjectStorageFullAccess` but never sets `bucket_names`.
- Supersedes ADR-0048's "Out of scope" bullet declining to enforce this in code.
- Unblocks correcting `terraform/infrastructure/scaleway/fr-par/pigeon.dev/scratch/iam.tf` to a genuinely least-privilege, read-only bucket key — tracked as a follow-up in `terraform/infrastructure`, not part of this module release.

## Out of scope

- Fixing the wrong `project_ids` reference in `pigeon.dev/scratch/iam.tf` itself — a call-site bug in `terraform/infrastructure`, not this module.
- A `bucket_actions` "read-only" convenience flag/preset — left as an explicit consumer choice.
- Enumerating or validating against a fixed list of Scaleway Object Storage permission-set names — `startswith(..., "ObjectStorage")` is intentionally prefix-based to avoid drifting out of date.
