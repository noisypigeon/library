# compute-instance

A Scaleway compute Instance (`scaleway_instance_server`) with a randomized name suffix, provisioned unconditionally for `pigeon-cli` (ADR-0118): rclone/neovim, a `keyring.toml` + `rclone.conf` rendered from one `keyring` list, and optional Cockpit/Alloy wiring — all grouped under `user_config`/`instance_config`.

## Usage

```hcl
module "compute" {
  source                = "https://noisypigeon.com/modules/scaleway/compute-instance/v4.0.0"
  name_prefix           = "job-example"
  name_suffix           = "worker"
  additional_volume_ids = [module.volume.id]

  user_config = {
    ssh_key = local.ssh_key_public_key
  }

  instance_config = {
    type    = "COMPUTE3-X8C-16G"
    cockpit = local.cockpit
    # image omitted -- defaults to "ubuntu_jammy"
  }

  keyring = [
    {
      kind          = "bucket"
      alias         = "source"
      endpoint      = module.bucket.endpoint
      bucket        = module.bucket.name
      access_key_id = module.iam.access_key
      secret_key    = module.iam.secret_key
      provider      = local.scaleway_s3_provider_name
    }
  ]
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_volume_ids"></a> [additional\_volume\_ids](#input\_additional\_volume\_ids) | IDs of pre-created block volumes (e.g. scaleway/block-volume's id output) to attach to the instance | `list(string)` | `[]` | no |
| <a name="input_enable_ipv4"></a> [enable\_ipv4](#input\_enable\_ipv4) | Create and attach a routed IPv4 address (true/false) | `bool` | `true` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Create and attach a routed IPv6 address (true/false) | `bool` | `false` | no |
| <a name="input_instance_config"></a> [instance\_config](#input\_instance\_config) | Instance-level configuration: image, commercial type, and Cockpit/Alloy wiring (ADR-0102). null cockpit disables Alloy entirely. | <pre>object({<br/>    image = optional(string, "ubuntu_jammy")<br/>    type  = optional(string, "STARDUST1-S")<br/>    cockpit = optional(object({<br/>      metrics_push_url = string<br/>      logs_push_url    = string<br/>      token_secret     = string<br/>      scrape_port      = optional(number, 9091)<br/>    }))<br/>  })</pre> | `{}` | no |
| <a name="input_keyring"></a> [keyring](#input\_keyring) | pigeon-cli keyring.toml entries. kind = "bucket" entries also generate an rclone.conf remote; any entry with secret\_key set also exports PIGEON\_SECRET\_<ALIAS> on the instance. secret\_key is never written into keyring.toml itself. | <pre>list(object({<br/>    kind  = string<br/>    alias = string<br/><br/>    # kind = "email"<br/>    email                = optional(string)<br/>    provider             = optional(string)<br/>    host                 = optional(string)<br/>    port                 = optional(number)<br/>    max_imap_connections = optional(number)<br/><br/>    # kind = "bucket" -- also generates an rclone.conf remote<br/>    endpoint             = optional(string)<br/>    bucket               = optional(string)<br/>    access_key_id        = optional(string)<br/>    secret_key           = optional(string)<br/>    encryption_key_alias = optional(string)<br/><br/>    # kind = "encryption-key"<br/>    created_at = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Instance name prefix | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Instance name suffix | `string` | n/a | yes |
| <a name="input_user_config"></a> [user\_config](#input\_user\_config) | Per-instance user/access configuration | <pre>object({<br/>    ssh_key = optional(string)<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Instance ID |
| <a name="output_ipv4_address"></a> [ipv4\_address](#output\_ipv4\_address) | The instance's routed IPv4 address (null if enable\_ipv4 = false) |
| <a name="output_name"></a> [name](#output\_name) | Computed instance name |
| <a name="output_private_ips"></a> [private\_ips](#output\_private\_ips) | Private IPs attached to the instance |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Public IPs attached to the instance |
<!-- END_TF_DOCS -->
