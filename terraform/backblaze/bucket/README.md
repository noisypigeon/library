# bucket

A private Backblaze B2 bucket (`b2_bucket`) with a randomized name suffix (B2 bucket names are globally unique across all accounts, like S3), or exactly `exact_name` when the name must match something external, such as a backup bucket named after the R2 bucket it mirrors (LIB-0016 §2). Set either `exact_name`, or both `name_prefix` and `name_suffix`. Always `bucket_type = "allPrivate"` — no public-bucket override. An optional `description` is stored in the bucket's `bucket_info` metadata.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_description"></a> [description](#input\_description) | Free-form description, stored in the bucket's bucket\_info metadata | `string` | `null` | no |
| <a name="input_exact_name"></a> [exact\_name](#input\_exact\_name) | Exact bucket name, bypassing the name\_prefix/random-suffix/name\_suffix scheme entirely — for buckets whose name must match something external | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Bucket name prefix (ignored if exact\_name is set) | `string` | `null` | no |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Bucket name suffix (ignored if exact\_name is set) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | B2 bucket ID |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Computed bucket name |
<!-- END_TF_DOCS -->
