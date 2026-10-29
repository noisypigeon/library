# iam-api-key

A thin wrapper around `scaleway_iam_api_key`. Split out of `iam-policy` (ADR-0119) so a credential's lifecycle is independent of the application/policy it authenticates for. Defaults `expires_at` to 30 days after the key is first created, anchored via a `time_static` resource so the default doesn't drift on every `plan`.

## Usage

```hcl
module "iam_api_key" {
  source         = "https://noisypigeon.garden/terraform/scaleway/iam-api-key/v0.1.0"
  application_id = module.iam_application.id
}
```

Pass an explicit `expires_at` for any credential that needs to outlive the 30-day default (e.g. a deployer identity, or a long-running job), or `rotation_days` to have Terraform replace the key on a schedule (LIB-0038 §2). A rotated key is created before the old one is destroyed, and expires a week after each scheduled rotation.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_application_id"></a> [application\_id](#input\_application\_id) | IAM application ID this key authenticates as | `string` | n/a | yes |
| <a name="input_default_project_id"></a> [default\_project\_id](#input\_default\_project\_id) | Default project ID to use for Object Storage operations with this key (defaults to the provider's own project when unset) | `string` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | IAM API key description | `string` | `null` | no |
| <a name="input_expires_at"></a> [expires\_at](#input\_expires\_at) | API key expiration timestamp (i.e. 2027-09-25T22:32:12Z). Defaults to 30 days after the key is first created. | `string` | `null` | no |
| <a name="input_rotation_days"></a> [rotation\_days](#input\_rotation\_days) | Replace the API key every this many days, expiring it a week after each scheduled rotation (LIB-0038). Unset, the key expires 30 days after it was first created and is never replaced. | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_key"></a> [access\_key](#output\_access\_key) | IAM API key access key |
| <a name="output_secret_key"></a> [secret\_key](#output\_secret\_key) | IAM API key secret key |
<!-- END_TF_DOCS -->
