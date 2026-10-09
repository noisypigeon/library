# bucket

A private Backblaze B2 bucket (`b2_bucket`) with a randomized name suffix (B2 bucket names are globally unique across all accounts, like S3). Always `bucket_type = "allPrivate"` — no public-bucket override. An optional `description` is stored in the bucket's `bucket_info` metadata.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|

## Outputs

| Name | Description |
|------|-------------|
<!-- END_TF_DOCS -->
