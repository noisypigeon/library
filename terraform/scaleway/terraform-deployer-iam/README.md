# terraform-deployer-iam

> **Deprecated** ([LIB-0038](../../../docs/adr/LIB-0038-compose-deployers-and-redirects-from-single-resource-modules.md)). No further releases; its tags and short URLs still resolve. Compose [`iam-application`](../iam-application), [`iam-policy`](../iam-policy) and [`iam-api-key`](../iam-api-key) instead, as a unit's deployer does since root.hcl v7.0.0. `iam-api-key` takes this module's `rotation_days`, at the same resource addresses.

A spoke's Terraform deployer identity in one call: a `scaleway_iam_application`, its `scaleway_iam_policy`, and a `scaleway_iam_api_key` for it (LIB-0014). It rolls up `iam-application`, `iam-policy` and `iam-api-key` with the same inputs, inlined rather than nested so the resource addresses are fixed and a short URL can't break underneath it.

The leaf that calls it manages the key every other leaf deploys with, so it must not authenticate with that key itself. Allowlist the leaf for the spoke's Scaleway breakglass credential in `spoke.hcl` (`providers.scaleway.breakglass.leaves`, root.hcl v4.1.0+).

`policy_name` is used exactly as given (unlike `iam-policy`, which appends `-policy`), so an existing policy can be adopted under its current name. The API key's `expires_at` defaults to 30 days after first creation, anchored by `time_static`, as in `iam-api-key`.

With `rotation_days`, the key is instead replaced every `rotation_days`, by a `time_rotating` resource, and expires a week after each scheduled rotation (LIB-0024 §4). It's created before the old one is destroyed. That suits a key Terraform hands to other leaves, such as a LIB-0024 workload deployer, where the next plan after a rotation picks up the new key. It doesn't suit a key that is hand-copied into a secrets file, like a spoke's own deployer.

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
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_key_description"></a> [api\_key\_description](#input\_api\_key\_description) | IAM API key description | `string` | `null` | no |
| <a name="input_default_project_id"></a> [default\_project\_id](#input\_default\_project\_id) | Default project ID to use for Object Storage operations with the API key (defaults to the provider's own project when unset) | `string` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | Description for the IAM application and its policy | `string` | `null` | no |
| <a name="input_expires_at"></a> [expires\_at](#input\_expires\_at) | API key expiration timestamp (i.e. 2027-09-25T22:32:12Z). Defaults to 30 days after the key is first created. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | IAM application name | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Organization id | `string` | `null` | no |
| <a name="input_organization_permission_sets"></a> [organization\_permission\_sets](#input\_organization\_permission\_sets) | Organization permission set grants | `list(string)` | `null` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | IAM policy name, used exactly as given (defaults to "<name>-policy") | `string` | `null` | no |
| <a name="input_project_ids"></a> [project\_ids](#input\_project\_ids) | Project ids | `list(string)` | `null` | no |
| <a name="input_project_permission_sets"></a> [project\_permission\_sets](#input\_project\_permission\_sets) | Project permission set grants | `list(string)` | `null` | no |
| <a name="input_rotation_days"></a> [rotation\_days](#input\_rotation\_days) | Replace the API key every this many days, expiring it a week after each scheduled rotation (LIB-0024). Unset, the key expires 30 days after it was first created and is never replaced. | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_key"></a> [access\_key](#output\_access\_key) | IAM API key access key |
| <a name="output_application_id"></a> [application\_id](#output\_application\_id) | IAM application ID |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | IAM policy ID |
| <a name="output_secret_key"></a> [secret\_key](#output\_secret\_key) | IAM API key secret key |
<!-- END_TF_DOCS -->
