# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-15

### Add cloudflare/bucket, a thin R2 bucket wrapper

A new module, `cloudflare/bucket`: a thin wrapper around a single Cloudflare R2 bucket (`cloudflare_r2_bucket`).

### Naming, the same as the other bucket modules

The bucket is named the way `backblaze/bucket` and `scaleway/object-bucket` name theirs:

- `{name_prefix}-{random_code}-{name_suffix}`, where the code is a 6-character lowercase random suffix;
- or exactly `exact_name`, with the same validation as `scaleway/object-bucket`: one scheme or the other, never a mix.

### Everything else passes through

- `account_id` is required. In a spoke leaf it's `local.cloudflare_account_id`, which `terragrunt/root-hcl` already generates.
- `location`, `jurisdiction` and `storage_class` go to the provider as given, validated against the provider's documented values. Left `null`, they stay unset.

### Outputs

- `id`
- `name`
- `endpoint`, the S3 API URL (`https://<account_id>.r2.cloudflarestorage.com`, with the `eu` or `fedramp` segment for those jurisdictions).

It exists so a leaf that manages an R2 bucket can live at `terraform/cloudflare/bucket/<instance>/` and call one pigeon-lib module, as LIB-0004 requires.

```hcl
module "bucket" {
  source = "https://pigeon.dev/modules/cloudflare/bucket/v0.1.0"

  account_id  = local.cloudflare_account_id
  name_prefix = "example-com"
  name_suffix = "assets"
}
```

Verified with `terraform validate`, and with a plan against a scratch root using both naming schemes and the `eu` jurisdiction (`cloudflare/cloudflare` 5.28.0).

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#34](https://github.com/noisypigeon/pigeon-lib/pull/34)
