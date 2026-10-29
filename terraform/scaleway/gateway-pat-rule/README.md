# gateway-pat-rule

A thin wrapper around a single `scaleway_vpc_public_gateway_pat_rule`: it
forwards `public_port` on a Public Gateway's IP to `private_ip:private_port`
on the gateway's Private Network. It's what a workload instance's
`network.sshViaGateway` implies (LIB-0043), and is the path ADR-0146 found is
the only working one into an instance behind a gateway that pushes its
default route.

## Usage

```hcl
module "ssh" {
  source = "https://noisypigeon.garden/terraform/scaleway/gateway-pat-rule/v0.1.0"

  gateway_id  = module.public_gateway.id
  private_ip  = module.instance.private_ipv4
  public_port = 2222
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_gateway_id"></a> [gateway\_id](#input\_gateway\_id) | ID of the Public Gateway whose IP the rule listens on | `string` | n/a | yes |
| <a name="input_private_ip"></a> [private\_ip](#input\_private\_ip) | The target's IPv4 address on the gateway's Private Network | `string` | n/a | yes |
| <a name="input_private_port"></a> [private\_port](#input\_private\_port) | Port on the target | `number` | `22` | no |
| <a name="input_protocol"></a> [protocol](#input\_protocol) | tcp, udp or both | `string` | `"tcp"` | no |
| <a name="input_public_port"></a> [public\_port](#input\_public\_port) | Port on the gateway's public IP | `number` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_connect_command"></a> [connect\_command](#output\_connect\_command) | SSH command that reaches the target through the rule, when it forwards to port 22 |
| <a name="output_id"></a> [id](#output\_id) | PAT rule ID |
<!-- END_TF_DOCS -->
