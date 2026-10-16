# bucket

A thin wrapper around a single Cloudflare R2 bucket (`cloudflare_r2_bucket`).
It names the bucket the way `backblaze/bucket` and `scaleway/object-bucket` do,
`{name_prefix}-{random_code}-{name_suffix}`, or exactly `exact_name`, and adds
nothing else: `location`, `jurisdiction` and `storage_class` are passed through
as given, and left `null` they stay unset rather than picking up a default here.
It exists so that a leaf managing an R2 bucket calls a pigeon-lib module and can
live at `terraform/cloudflare/bucket/<instance>/`, like every other leaf
(LIB-0004).

## Usage

```hcl
module "bucket" {
  source = "https://pigeon.dev/modules/cloudflare/bucket/v0.1.0"

  account_id  = local.cloudflare_account_id
  name_prefix = "example-com"
  name_suffix = "assets"
  location    = "weur"
}
```

`local.cloudflare_account_id` is generated into every spoke leaf by the
`terragrunt/root-hcl` template. The `endpoint` output is the bucket's S3 API
endpoint, for clients such as rclone that talk to R2 over S3.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID the bucket belongs to (in a spoke leaf, local.cloudflare\_account\_id) | `string` | n/a | yes |
| <a name="input_exact_name"></a> [exact\_name](#input\_exact\_name) | Exact bucket name, bypassing the name\_prefix/random-suffix/name\_suffix scheme entirely — for buckets whose name must match something external | `string` | `null` | no |
| <a name="input_jurisdiction"></a> [jurisdiction](#input\_jurisdiction) | Jurisdiction the bucket's data is restricted to (default, eu, fedramp, us). Null leaves it unset | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Location hint for the bucket (apac, eeur, enam, weur, wnam, oc). Null leaves it to Cloudflare | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Bucket name prefix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Bucket name suffix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Default storage class for new objects (Standard, InfrequentAccess). Null leaves it unset | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Bucket S3 API endpoint URL (the eu and fedramp jurisdictions have their own) |
| <a name="output_id"></a> [id](#output\_id) | Bucket ID |
| <a name="output_name"></a> [name](#output\_name) | Computed bucket name |
<!-- END_TF_DOCS -->
