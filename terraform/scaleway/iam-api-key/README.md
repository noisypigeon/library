# iam-api-key

A thin wrapper around `scaleway_iam_api_key`. Split out of `iam-policy` (ADR-0119) so a credential's lifecycle is independent of the application/policy it authenticates for. Defaults `expires_at` to 30 days after the key is first created, anchored via a `time_static` resource so the default doesn't drift on every `plan`.

## Usage

```hcl
module "iam_api_key" {
  source         = "https://pigeon.dev/modules/scaleway/iam-api-key/v0.1.0"
  application_id = module.iam_application.id
}
```

Pass an explicit `expires_at` for any credential that needs to outlive the 30-day default (e.g. a deployer identity, or a long-running job).

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_application_id"></a> [application\_id](#input\_application\_id) | IAM application ID this key authenticates as | `string` | n/a | yes |
| <a name="input_description"></a> [description](#input\_description) | IAM API key description | `string` | `null` | no |
| <a name="input_expires_at"></a> [expires\_at](#input\_expires\_at) | API key expiration timestamp (i.e. 2027-09-25T22:32:12Z). Defaults to 30 days after the key is first created. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_key"></a> [access\_key](#output\_access\_key) | IAM API key access key |
| <a name="output_secret_key"></a> [secret\_key](#output\_secret\_key) | IAM API key secret key |
<!-- END_TF_DOCS -->
