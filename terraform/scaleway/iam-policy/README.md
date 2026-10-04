# iam-policy

A Scaleway `scaleway_iam_policy` wrapper granting organization/project permission-set rules to an existing IAM application. Split from a formerly application+policy+API-key bundle (ADR-0119) — pair with `iam-application` (to create the application) and `iam-api-key` (to mint a credential for it).

## Usage

```hcl
module "iam_application" {
  source = "https://noisypigeon.com/modules/scaleway/iam-application/v0.1.0"
  name   = "pigeon-cli"
}

module "iam_policy" {
  source = "https://noisypigeon.com/modules/scaleway/iam-policy/v4.0.0"
  name   = "pigeon-cli"

  application_id = module.iam_application.id

  project_ids              = [local.scaleway_project_id]
  project_permission_sets  = ["ObjectStorageFullAccess"]
}

module "iam_api_key" {
  source         = "https://noisypigeon.com/modules/scaleway/iam-api-key/v0.1.0"
  application_id = module.iam_application.id
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_application_id"></a> [application\_id](#input\_application\_id) | IAM application ID this policy is attached to | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | IAM policy description | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | IAM policy name | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Organization id | `string` | `null` | no |
| <a name="input_organization_permission_sets"></a> [organization\_permission\_sets](#input\_organization\_permission\_sets) | Organization permission set grants | `list(string)` | `null` | no |
| <a name="input_project_ids"></a> [project\_ids](#input\_project\_ids) | Project ids | `list(string)` | `null` | no |
| <a name="input_project_permission_sets"></a> [project\_permission\_sets](#input\_project\_permission\_sets) | Project permission set grants | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | IAM policy ID |
<!-- END_TF_DOCS -->
