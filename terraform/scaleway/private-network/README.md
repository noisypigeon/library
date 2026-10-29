# private-network

A thin wrapper around a single `scaleway_vpc_private_network`. It's a workload's
`scaleway.privateNetwork` kind (LIB-0043): the network a workload's instances
attach to, and its Public Gateway routes out of.

Enabling Object Storage's private endpoint (`s3-vpc.<region>.scw.eu`) for the
network is still a one-time manual step against the VPC API (ADR-0145).

## Usage

```hcl
module "private_network" {
  source = "https://noisypigeon.garden/terraform/scaleway/private-network/v0.1.0"

  name       = "pigeon-cli"
  project_id = local.project_id
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Private Network name | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Private Network ID |
| <a name="output_name"></a> [name](#output\_name) | Private Network name |
<!-- END_TF_DOCS -->
