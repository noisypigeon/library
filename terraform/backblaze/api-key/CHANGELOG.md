# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.1] - 2026-10-09

### Qualify backblaze/b2 provider source with an explicit registry host

Both \`templates/terraform/backblaze/bucket\` and \`templates/terraform/backblaze/api-key\` declared their \`b2\` provider requirement as a bare \`source = "Backblaze/b2"\`, leaving the registry host to whatever the running Terraform-compatible binary defaults an unqualified source to.

PR #252's CI run — the first time any leaf actually exercising this provider ran through \`terragrunt plan\` — failed trying to install the provider from \`registry.opentofu.org\`, hitting an "authentication signature from unknown issuer" error there. The provider itself is fine: reproducing the exact generated configuration with this repo's own pinned Terraform binary (\`1.16.3\`, real HashiCorp, not OpenTofu) installs \`backblaze/b2 v0.14.0\` cleanly from \`registry.terraform.io\`, "signed by a HashiCorp partner."

This makes the source fully host-qualified (\`registry.terraform.io/Backblaze/b2\`) in both modules, removing the ambiguity regardless of which binary ends up resolving it. A matching change already landed in \`workloads/willowgraysen.com/root.hcl\`'s own generated \`required_providers\` entry for the same provider.

[#255](https://github.com/noisypigeon/noisypigeon/pull/255)

## [0.1.0] - 2026-10-09

### Add backblaze/bucket and backblaze/api-key modules

Adds two new Terraform modules under a new `templates/terraform/backblaze/` provider root.

`backblaze/bucket` wraps `b2_bucket`: it names the bucket from `name_prefix`/`name_suffix` plus a random 6-character suffix (B2 bucket names are globally unique across every B2 account, like S3, so the random suffix matters here even more than for the Scaleway bucket modules), always creates the bucket as `allPrivate` (no public-bucket option), and stores an optional `description` in the bucket's `bucket_info` metadata. It outputs `bucket_id` and `bucket_name`.

`backblaze/api-key` wraps `b2_application_key`: it takes a required `key_name` and a required `capabilities` set (not validated locally, since Backblaze's capability catalog is provider-defined and changes independently of this repo), an optional `bucket_ids` set to scope the key to one or more buckets, and defaults `valid_duration_in_seconds` to 30 days (pass `null` for a key that never expires). It composes naturally with `backblaze/bucket`'s `bucket_id` output for per-bucket key scoping, and outputs `application_key_id`/`application_key` (sensitive).

See ADR-0147 for the full design rationale. No `workloads/*` consumer is wired up in this PR — that's left for a future change once a real B2 bucket/key is needed.

This also generalizes `template-release.yml`'s module-discovery `find`, which was hardcoded to `templates/terraform/scaleway` and would otherwise have silently skipped tagging/releasing these new modules, and appends both to `module-docs.yml`'s `working-dir` list so their README input/output tables get generated.

[#253](https://github.com/noisypigeon/noisypigeon/pull/253)
