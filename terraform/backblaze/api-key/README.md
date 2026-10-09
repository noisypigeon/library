# api-key

A thin wrapper around `b2_application_key`. Takes a required `capabilities` set and an optional `bucket_ids` set to scope the key to specific buckets (composes naturally with `backblaze/bucket`'s own `bucket_id` output). Defaults `valid_duration_in_seconds` to 30 days, mirroring `scaleway/iam-api-key`'s own default-expiry policy for new credentials.

## Usage

```hcl
module "backup_key" {
  source       = "https://pigeon.dev/modules/backblaze/api-key/v0.1.0"
  key_name     = "backup-writer"
  capabilities = ["listFiles", "readFiles", "writeFiles"]
  bucket_ids   = [module.backup_bucket.bucket_id]
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bucket_ids"></a> [bucket\_ids](#input\_bucket\_ids) | Bucket IDs this key is restricted to (unset = account-wide access) | `set(string)` | `null` | no |
| <a name="input_capabilities"></a> [capabilities](#input\_capabilities) | Capability strings the key grants (e.g. ["listBuckets", "readFiles", "writeFiles"]) -- see Backblaze's own capability catalog, not validated locally since it's provider-defined and subject to change | `set(string)` | n/a | yes |
| <a name="input_key_name"></a> [key\_name](#input\_key\_name) | Application key name | `string` | n/a | yes |
| <a name="input_valid_duration_in_seconds"></a> [valid\_duration\_in\_seconds](#input\_valid\_duration\_in\_seconds) | Key validity duration in seconds, counted from creation. Defaults to 30 days (2592000 seconds); pass null for a key that never expires. | `number` | `2592000` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_key"></a> [application\_key](#output\_application\_key) | Application key secret value |
| <a name="output_application_key_id"></a> [application\_key\_id](#output\_application\_key\_id) | Application key ID |
<!-- END_TF_DOCS -->
