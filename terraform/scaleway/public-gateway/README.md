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
<!-- END_TF_DOCS -->
