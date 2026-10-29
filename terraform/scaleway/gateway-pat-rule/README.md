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
<!-- END_TF_DOCS -->
