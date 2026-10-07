# iam-application

A thin wrapper around `scaleway_iam_application`. Split out of `iam-policy` (ADR-0119) so one application can be shared across several `iam-policy` calls instead of each policy minting its own.

## Usage

```hcl
module "iam_application" {
  source = "https://pigeon.dev/modules/scaleway/iam-application/v0.1.0"
  name   = "pigeon-cli"
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_description"></a> [description](#input\_description) | IAM application description | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | IAM application name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | IAM application ID |
| <a name="output_name"></a> [name](#output\_name) | IAM application name |
<!-- END_TF_DOCS -->
