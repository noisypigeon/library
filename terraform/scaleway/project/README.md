# project

A thin wrapper around `scaleway_account_project`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_description"></a> [description](#input\_description) | Project description | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Project name | `string` | `null` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Organization ID for the project — defaults to the provider's own; changing this recreates the resource | `string` | `null` | no |
| <a name="input_ssh_key"></a> [ssh\_key](#input\_ssh\_key) | SSH key to register for instance access in this project — omit to skip creating one | <pre>object({<br/>    alias      = string<br/>    public_key = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Project ID |
| <a name="output_name"></a> [name](#output\_name) | Project name |
| <a name="output_ssh_key_id"></a> [ssh\_key\_id](#output\_ssh\_key\_id) | ID of the created SSH key, if ssh\_key was provided |
<!-- END_TF_DOCS -->
