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

## Outputs

| Name | Description |
|------|-------------|
<!-- END_TF_DOCS -->
