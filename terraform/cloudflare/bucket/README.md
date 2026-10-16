# bucket

A Cloudflare R2 bucket (`cloudflare_r2_bucket`), named the way
`backblaze/bucket` and `scaleway/object-bucket` name theirs:
`{name_prefix}-{random_code}-{name_suffix}`, or exactly `exact_name`.

- **Every bucket is in R2's `eu` jurisdiction.** Cloudflare enforces it, and
  there's no input to change it. There is no location hint either, since R2 doesn't
  always respect one (LIB-0006).
- **`storage_class` defaults to `Standard`.** `InfrequentAccess` is the
  alternative.

It exists so that a leaf managing an R2 bucket calls a pigeon-lib module and can
live at `terraform/cloudflare/bucket/<instance>/`, like every other leaf
(LIB-0004).

## Usage

```hcl
module "bucket" {
  source = "https://pigeon.dev/modules/cloudflare/bucket/v1.0.0"

  account_id  = local.cloudflare_account_id
  name_prefix = "example-com"
  name_suffix = "assets"
}
```

`local.cloudflare_account_id` is generated into every spoke leaf by the
`terragrunt/root-hcl` template. The `endpoint` output is the bucket's EU S3 API
endpoint, for clients such as rclone that talk to R2 over S3. An EU bucket isn't
reachable through the default endpoint.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account ID the bucket belongs to (in a spoke leaf, local.cloudflare\_account\_id) | `string` | n/a | yes |
| <a name="input_exact_name"></a> [exact\_name](#input\_exact\_name) | Exact bucket name, bypassing the name\_prefix/random-suffix/name\_suffix scheme entirely — for buckets whose name must match something external | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Bucket name prefix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Bucket name suffix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Default storage class for new objects (Standard, InfrequentAccess) | `string` | `"Standard"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Bucket S3 API endpoint URL (EU jurisdiction) |
| <a name="output_id"></a> [id](#output\_id) | Bucket ID |
| <a name="output_name"></a> [name](#output\_name) | Computed bucket name |
<!-- END_TF_DOCS -->
