# terraform-deployer-iam

A spoke's Terraform deployer identity in one call: a `scaleway_iam_application`, its `scaleway_iam_policy`, and a `scaleway_iam_api_key` for it (LIB-0014). It rolls up `iam-application`, `iam-policy` and `iam-api-key` with the same inputs, inlined rather than nested so the resource addresses are fixed and a short URL can't break underneath it.

The leaf that calls it manages the key every other leaf deploys with, so it must not authenticate with that key itself. Allowlist the leaf for the spoke's Scaleway breakglass credential in `spoke.hcl` (`providers.scaleway.breakglass.leaves`, root.hcl v4.1.0+).

`policy_name` is used exactly as given (unlike `iam-policy`, which appends `-policy`), so an existing policy can be adopted under its current name. The API key's `expires_at` defaults to 30 days after first creation, anchored by `time_static`, as in `iam-api-key`.

## Usage

```hcl
module "terraform_deployer_iam" {
  source = "https://noisypigeon.garden/terraform/scaleway/terraform-deployer-iam/v0.1.0"
  name   = "runway-terraform-deploy"

  project_ids             = [local.scaleway_project_id]
  project_permission_sets = ["ObjectStorageFullAccess"]

  organization_id              = local.scaleway_organization_id
  organization_permission_sets = ["IAMManager", "IAMApplicationManager"]

  default_project_id = local.scaleway_project_id
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
