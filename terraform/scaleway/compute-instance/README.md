# compute-instance

A Scaleway compute Instance (`scaleway_instance_server`) with a randomized name suffix, provisioned unconditionally for `pigeon-cli` (ADR-0118): rclone/neovim, a `keyring.toml` + `rclone.conf` rendered from one `keyring` list, and optional Cockpit/Alloy wiring — all grouped under `user_config`/`instance_config`.

## Usage

```hcl
module "compute" {
  source                = "https://pigeon.dev/modules/scaleway/compute-instance/v4.0.0"
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
| <a name="input_additional_volume_ids"></a> [additional\_volume\_ids](#input\_additional\_volume\_ids) | IDs of block volumes to attach. Created by the caller (ADR-0153, reversing ADR-0120's internal block-volume composition). Note the instance only mounts /dev/sdb if its cloud-init was rendered with has\_attached\_volume = true. | `list(string)` | `[]` | no |
| <a name="input_cloud_init"></a> [cloud\_init](#input\_cloud\_init) | Rendered cloud-init document for user\_data["cloud-init"], normally compute-instance-config's cloud\_init output. null attaches no user\_data at all. Changing it replaces the instance. | `string` | `null` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether to create the instance. false destroys the server only; any IP, volume or IAM the caller created for it is untouched. | `bool` | `true` | no |
| <a name="input_image"></a> [image](#input\_image) | Instance image label (e.g. ubuntu\_jammy, ubuntu\_noble, ubuntu\_resolute) | `string` | `"ubuntu_jammy"` | no |
| <a name="input_ip_ids"></a> [ip\_ids](#input\_ip\_ids) | IDs of scaleway\_instance\_ip resources to attach. Created by the caller (ADR-0153) -- an IP must exist before the server that references it, so this module cannot create one and attach it in the same step. | `list(string)` | `[]` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Instance name prefix | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Instance name suffix | `string` | n/a | yes |
| <a name="input_ssh_key"></a> [ssh\_key](#input\_ssh\_key) | Public SSH key to authorize on the instance, passed through as an AUTHORIZED\_KEY tag. Exactly one key, not a list (ADR-0118). | `string` | `null` | no |
| <a name="input_type"></a> [type](#input\_type) | Instance commercial type | `string` | `"STARDUST1-S"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Instance ID (null if enabled = false) |
| <a name="output_name"></a> [name](#output\_name) | Computed instance name (null if enabled = false) |
| <a name="output_public_ips"></a> [public\_ips](#output\_public\_ips) | Public IPs attached to the instance (null if enabled = false) |
<!-- END_TF_DOCS -->
