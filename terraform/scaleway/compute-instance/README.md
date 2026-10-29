# compute-instance

A Scaleway compute Instance (`scaleway_instance_server`) with a randomized name suffix. It takes an already-rendered `cloud_init` document, normally `compute-instance-config`'s, and block volumes the caller creates. Since v8.0.0 (LIB-0043) it also creates the instance's own routed public IPv4 (`public_ipv4`) and attaches it to a Private Network (`enable_private_network`, `private_network_id`), with a standalone NIC so that attaching or detaching never replaces the server. `project_id` is required.

## Usage

```hcl
module "instance" {
  source      = "https://noisypigeon.garden/terraform/scaleway/compute-instance/v8.0.0"
  name_prefix = "pigeon-cli"
  name_suffix = "worker"
  project_id  = local.project_id

  type                  = "COMPUTE3-X8C-16G"
  cloud_init            = module.config.cloud_init
  additional_volume_ids = [module.volume.id]

  public_ipv4            = false
  enable_private_network = true
  private_network_id     = module.private_network.id
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_volume_ids"></a> [additional\_volume\_ids](#input\_additional\_volume\_ids) | IDs of block volumes to attach. Created by the caller (ADR-0153, reversing ADR-0120's internal block-volume composition). Note the instance only mounts /dev/sdb if its cloud-init was rendered with has\_attached\_volume = true. | `list(string)` | `[]` | no |
| <a name="input_cloud_init"></a> [cloud\_init](#input\_cloud\_init) | Rendered cloud-init document for user\_data["cloud-init"], normally compute-instance-config's cloud\_init output. null attaches no user\_data at all. Changing it replaces the instance. | `string` | `null` | no |
| <a name="input_enable_private_network"></a> [enable\_private\_network](#input\_enable\_private\_network) | Attach the instance to private\_network\_id with a standalone scaleway\_instance\_private\_nic, so attaching or detaching never replaces the server (ADR-0145). An explicit bool rather than private\_network\_id != null, since count can't depend on an apply-time-unknown ID (compute-instance v5.6.0). | `bool` | `false` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether to create the instance. false destroys the server only; any IP, volume or IAM the caller created for it is untouched. | `bool` | `true` | no |
| <a name="input_image"></a> [image](#input\_image) | Instance image label (e.g. ubuntu\_jammy, ubuntu\_noble, ubuntu\_resolute) | `string` | `"ubuntu_jammy"` | no |
| <a name="input_ip_ids"></a> [ip\_ids](#input\_ip\_ids) | IDs of scaleway\_instance\_ip resources to attach. Created by the caller (ADR-0153) -- an IP must exist before the server that references it, so this module cannot create one and attach it in the same step. | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Instance name prefix | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Instance name suffix | `string` | n/a | yes |
| <a name="input_private_network_id"></a> [private\_network\_id](#input\_private\_network\_id) | ID of the Private Network to attach to when enable\_private\_network is true (LIB-0043). | `string` | `null` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project the instance, and the IP public\_ipv4 creates, live in (LIB-0043). Required since v8.0.0: the provider's own default project is rarely the one a caller means. | `string` | n/a | yes |
| <a name="input_public_ipv4"></a> [public\_ipv4](#input\_public\_ipv4) | Create a routed public IPv4 for the instance and attach it, beside any ip\_ids (LIB-0043). The IP isn't gated by enabled, so it keeps its address across an enabled = false cycle. While a Public Gateway pushes its default route on the instance's Private Network, the IP works outbound only (ADR-0146). | `bool` | `false` | no |
| <a name="input_ssh_key"></a> [ssh\_key](#input\_ssh\_key) | Public SSH key to authorize on the instance, passed through as an AUTHORIZED\_KEY tag. Exactly one key, not a list (ADR-0118). | `string` | `null` | no |
| <a name="input_type"></a> [type](#input\_type) | Instance commercial type | `string` | `"STARDUST1-S"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Instance ID (null if enabled = false) |
| <a name="output_name"></a> [name](#output\_name) | Computed instance name (null if enabled = false) |
| <a name="output_private_ipv4"></a> [private\_ipv4](#output\_private\_ipv4) | The instance's IPv4 address on its Private Network (null without one, or if enabled = false). private\_ips is dual-stack, so the IPv6 one is filtered out. |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Public IPs attached to the instance (null if enabled = false) |
<!-- END_TF_DOCS -->
