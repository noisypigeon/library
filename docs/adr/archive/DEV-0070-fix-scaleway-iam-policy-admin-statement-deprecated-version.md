# DEV-0070: fix scaleway/iam-policy's admin bucket-policy statement (deprecated version rejection)

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-27.
- **Status**: Accepted.

## Context

ADR-0069 (merged, released as `terraform/modules/scaleway/iam-policy/v1.1.0`) added an `admin_project_id` variable so a bucket-scoped IAM key's generated `scaleway_object_bucket_policy` always keeps the deployer identity able to manage the bucket it just configured. The generated admin statement:

```hcl
{
  Sid       = "IamPolicyBucketAccessAdmin"
  Effect    = "Allow"
  Principal = { SCW = "project_id:${var.admin_project_id}" }
  Action    = ["s3:*"]
  Resource  = [each.value, "${each.value}/*"]
}
```

was written under the same `Version = "2023-04-17"` the module's existing narrow statement already used. The first live field-test — `tofu apply` against `noisypigeon/cli/scratch` with `v1.1.0` — rejected it outright:

```
Error: error putting SCW bucket policy: operation error S3: PutBucketPolicy, https response error
StatusCode: 400, ... api error MalformedPolicy: project_id Principal is deprecated and only
supported in the bucket-policy version 2012-10-17
```

Confirmed against Scaleway's own `terraform-provider-scaleway` docs (`docs/resources/object_bucket_policy.md`): a `project_id:` `Principal` is only accepted under the deprecated `Version = "2012-10-17"` policy format. `Version = "2023-04-17"` only accepts `application_id:`/`user_id:`/wildcard principals. So `admin_project_id`'s mechanism was broken from the start — the module fails to `apply` at all for any bucket-scoped caller with `admin_project_id` set, regardless of which project id is supplied.

`noisypigeon/cli/scratch`'s bucket is still in the original locked-out state from before ADR-0069 (the owner-credentialed recovery step was never run). This ADR doesn't change that — it's still a separate, pending manual step.

## Decision

Downgrade the whole generated policy document to `Version = "2012-10-17"`. Scaleway's own provider documentation confirms this version still accepts a `project_id:` principal, in exactly the same Statement shape (Sid/Effect/Principal/Action/Resource) already used:

```hcl
resource "scaleway_object_bucket_policy" "bucket_access" {
  for_each = var.bucket_names

  bucket = each.value
  policy = jsonencode({
    Version = "2012-10-17"
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

This is a pure bugfix: `admin_project_id`'s name, type, and default (`null`) are unchanged — only the internal policy-generation detail changes. Both live call sites (`cli/scratch`, `vault/email`) need no changes beyond bumping the module `ref`.

Accepted trade-off: `2012-10-17` is a version Scaleway documents as deprecated. The only non-deprecated alternative would be naming the deployer's specific `application_id` instead of its whole project — considered, and explicitly deferred, since it needs new plumbing (a new `.env`/generated-local entry exposing the deployer's `scaleway_iam_application` id to every bucket-scoped call site, mirroring how `SCALEWAY_PROJECT_ID_NOISYPIGEON` already works). If Scaleway ever removes `2012-10-17` support entirely, this mechanism needs revisiting via that deferred alternative.

## Consequences

- No input/output signature change — `release:patch`, next tag `terraform/modules/scaleway/iam-policy/v1.1.1`.
- `cli/scratch/iam.tf` and `vault/email/iam.tf` both bump their module `ref` from `v1.1.0` to `v1.1.1`; no other changes.
- `noisypigeon/cli/scratch`'s bucket still needs its one-time manual recovery (owner-credentialed `aws s3api delete-bucket-policy`) before a clean `apply` can succeed — unrelated to this fix, still pending.

## Out of scope

- Switching the admin statement to an `application_id:`-based principal (the non-deprecated alternative) — deferred, since it requires new cross-leaf plumbing for the deployer's application id. Tracked as a future revisit if `2012-10-17` support is ever removed.
