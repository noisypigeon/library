# public-gateway

A Scaleway Public Gateway attached to one Private Network: its public IP
(`scaleway_vpc_public_gateway_ip`), the gateway (`scaleway_vpc_public_gateway`)
and the attachment (`scaleway_vpc_gateway_network`), with masquerade and the
default route on by default. It's a workload's `scaleway.publicGateway` kind
(LIB-0043), and is the shared gateway `compute-cluster` creates for its jobs.

While the gateway pushes its default route, an instance on the network that
also has its own public IP can use it outbound only (ADR-0146). Its `type` can
be upgraded in place but never downgraded.

## Usage

```hcl
module "public_gateway" {
  source = "https://noisypigeon.garden/terraform/scaleway/public-gateway/v0.1.0"

  name               = "pigeon-cli"
  project_id         = local.project_id
  private_network_id = module.private_network.id
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_masquerade"></a> [enable\_masquerade](#input\_enable\_masquerade) | NAT the Private Network's outbound traffic through the gateway's IP | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Public Gateway name | `string` | n/a | yes |
| <a name="input_private_network_id"></a> [private\_network\_id](#input\_private\_network\_id) | ID of the Private Network the gateway attaches to, and routes out of | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID | `string` | n/a | yes |
| <a name="input_push_default_route"></a> [push\_default\_route](#input\_push\_default\_route) | Advertise the gateway as the Private Network's default route. While it does, an attached instance's own public IP is reachable outbound only (ADR-0146). | `bool` | `true` | no |
| <a name="input_type"></a> [type](#input\_type) | Gateway offer type. Changing it upgrades the gateway in place, keeping its ID and IP; Scaleway can't downgrade one. | `string` | `"VPC-GW-S"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_gateway_network_id"></a> [gateway\_network\_id](#output\_gateway\_network\_id) | ID of the gateway's attachment to the Private Network |
| <a name="output_id"></a> [id](#output\_id) | Public Gateway ID |
| <a name="output_ip_address"></a> [ip\_address](#output\_ip\_address) | The gateway's public IPv4 address |
<!-- END_TF_DOCS -->
