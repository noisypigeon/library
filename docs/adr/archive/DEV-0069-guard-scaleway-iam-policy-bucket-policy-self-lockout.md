# DEV-0069: guard scaleway/iam-policy against bucket-policy self-lockout

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-27.
- **Status**: Accepted.

## Context

Every `scaleway/*` leaf under `terraform/infrastructure/scaleway/` authenticates as one identity: the `noisypigeon/terraform` leaf's self-managed "deployer" IAM application (`InstancesFullAccess`/`ObjectStorageFullAccess`/`VPCFullAccess` on the `noisypigeon` project, plus org-level `IAMManager`/`IAMApplicationManager`/`ProjectManager`). Its `access_key`/`secret_key` populate `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`, which the shared root `.env` (ADR-0062, ADR-0063) feeds into the provider and remote-state backend for every leaf, including bucket-scoped `iam-policy` consumers like `noisypigeon/cli/scratch` and `noisypigeon/vault/email`.

`terraform/modules/scaleway/iam-policy/bucket_access.tf` writes each bucket's `scaleway_object_bucket_policy` with exactly one `Allow` statement, naming only the module's own freshly-minted, narrowly-scoped `scaleway_iam_application`:

```hcl
Principal = { SCW = "application_id:${scaleway_iam_application.application.id}" }
```

Scaleway's bucket-policy model is allow-only: the moment *any* bucket policy exists on a bucket, every other principal — including the deployer — loses access to that bucket unless it is also explicitly named in the policy. Scaleway carves out exactly one exception to this: the literal Organization **Owner** account always retains the right to `put`/`delete` a bucket policy. The deployer is not that account. So applying this module's bucket-scoped grant locks the deployer itself out of the very bucket it just configured — the only recovery is deleting the rogue policy out-of-band with genuine owner credentials (`aws s3api delete-bucket-policy`). This is exactly what happened applying the module against `noisypigeon/cli/scratch`.

This is a distinct hazard from the one ADR-0066 fixed. ADR-0066 guards the *narrow key's own* scope (rejecting a blanket `ObjectStorage*` grant combined with `bucket_names` in the same call, since it would make `bucket_names` decorative). It says nothing about the *applier itself* — the module never grants continuing access back to whatever identity is running Terraform, so every bucket-scoped call is a live self-lockout risk regardless of how `bucket_names`/`bucket_actions` are set.

## Decision

Add an optional `admin_project_id` variable to `terraform/modules/scaleway/iam-policy`. When set, `bucket_access.tf` appends a second `Allow` statement to the generated bucket policy, granting `s3:*` to `project_id:<admin_project_id>` — i.e. to any principal that already holds IAM permissions in that project, the deployer included:

```hcl
variable "admin_project_id" {
  type        = string
  description = "Project id that should always retain full access to bucket_names, even if excluded from the narrow bucket_names/bucket_actions grant (prevents the applying/deployer identity from locking itself out of a bucket policy it just created)"
  default     = null
}
```

```hcl
resource "scaleway_object_bucket_policy" "bucket_access" {
  for_each = var.bucket_names

  bucket = each.value
  policy = jsonencode({
    Version = "2023-04-17"
    Statement = concat([
      {
        Sid       = "IamPolicyBucketAccess"
        Effect    = "Allow"
        Principal = { SCW = "application_id:${scaleway_iam_application.application.id}" }
        Action    = var.bucket_actions
        Resource  = [each.value, "${each.value}/*"]
      }
      ], var.admin_project_id != null ? [
      {
        Sid       = "IamPolicyBucketAccessAdmin"
        Effect    = "Allow"
        Principal = { SCW = "project_id:${var.admin_project_id}" }
        Action    = ["s3:*"]
        Resource  = [each.value, "${each.value}/*"]
      }
    ] : [])
  })
}
```

`project_id:<id>` (rather than naming the deployer's `application_id` directly) is Scaleway's own documented mechanism for this: it defers to whatever IAM permissions already exist in that project, so the safety-valve statement doesn't need updating if the deployer identity is ever rotated or replaced. `s3:*` is used rather than mirroring `bucket_actions`, since the point of this statement is unconditional recovery access, not a narrow grant — the project already holds `ObjectStorageFullAccess` via IAM regardless.

`admin_project_id` is optional (default `null`) rather than required: it composes independently of `organization_id`/`project_ids`/`bucket_names`, and forcing it would mean every non-bucket-scoped caller has to reason about a variable that doesn't apply to them. Both live bucket-scoped consumers are updated to set it in the same change that introduces it, so no consumer is left exposed to the hazard this ADR describes.

## Consequences

- Additive, backward-compatible module change (`release:minor`): existing callers that don't set `admin_project_id` get byte-identical generated policies to before.
- `noisypigeon/cli/scratch/iam.tf` and `noisypigeon/vault/email/iam.tf` both add `admin_project_id = local.scaleway_project_id` (already available via Terragrunt-generated `scaleway_ids_generated.tf` at every `fr-par/noisypigeon/*` leaf) and bump their module `ref` to the new release.
- `noisypigeon/cli/scratch`'s bucket, already locked out by the pre-fix policy, needs a one-time manual recovery (owner-credentialed `aws s3api delete-bucket-policy`) independent of this code change — the fix only prevents *future* lockouts, it doesn't undo an already-applied policy.
- The module README's ADR-0066 `## Usage` example is updated to include `admin_project_id`, so it's not silently omitted by future bucket-scoped callers.

## Out of scope

- Enforcing `admin_project_id` via a `validation` block whenever `bucket_names` is set — left as a documented convention (README `## Usage` example) rather than a hard requirement, consistent with the variable being independently optional.
- Any change to the module's `organization_id`/`project_ids`/`project_permission_sets` (org/project-scope) code path — unaffected; this ADR only touches `bucket_access.tf`'s per-bucket policy generation.
