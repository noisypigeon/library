# block-volume

A Scaleway Block Storage volume (`scaleway_block_volume`) with a randomized name suffix. Minimal interface — `size` (required, renamed from the resource's `size_in_gb`), `iops` (defaults to `15000`), `project_id` (required), no snapshots, tags, or zone overrides yet.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_iops"></a> [iops](#input\_iops) | Volume IOPS | `number` | `15000` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Volume name prefix | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Volume name suffix | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID | `string` | n/a | yes |
| <a name="input_size"></a> [size](#input\_size) | Volume size, in GB | `number` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Volume ID |
| <a name="output_name"></a> [name](#output\_name) | Computed volume name |
<!-- END_TF_DOCS -->
