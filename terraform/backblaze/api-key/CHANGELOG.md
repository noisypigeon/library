# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-10-28

### A workload's own Backblaze key, and providers with no spoke-wide credentials

A workload with Backblaze buckets or keys now gets its own Backblaze key, and a spoke can keep no spoke-wide Backblaze key or Cloudflare token at all (LIB-0041).

**A workload's own Backblaze key.** Any workload that declares a `backblaze.bucket` or `backblaze.apiKey` gets an implicit leaf, `backblaze/api-key/deployer`, the Backblaze twin of its Cloudflare token.
- It's minted with the spoke's Backblaze breakglass key where the spoke has one, and with `backblaze.enc`'s key otherwise.
- It's account-wide, since B2 can't confine a key to buckets that don't exist yet.
- It rotates every 30 days, and each key expires a week after its rotation.
- It's named `<prefix>-<suffix><unit tag>-backblaze-deployer`. `backblaze.deployer` overrides any of its inputs, and `backblaze.apiKey.deployer` is reserved.

**The workload's Backblaze leaves sign in with it.** Each `backblaze/bucket` and `backblaze/api-key` stub now depends on the key and passes its ID and secret to `provider "b2"`. Taking the bump plans `+1` per such workload. Its Backblaze leaves are deferred until the key applies, then plan `No changes.`, since only their provider's credentials change.

**`workloads_only`.** A Cloudflare or Backblaze entry in `spoke.hcl`'s `providers` may set `workloads_only = true` with `breakglass = {}`.
- No hand-written leaf turns the provider on.
- `backblaze.enc`, and `cloudflare.enc`'s `CLOUDFLARE_PROVIDER_TOKEN`, are no longer required. Any that remain are refused.
- The breakglass key mints every unit's own key or token.

The secrets schema expresses this as a new condition, `spoke_credentials.<name>`. Both root.hcl and `check-secrets.sh` enforce it. root.hcl now checks a file's keys against the spoke-wide conditions, as `check-secrets.sh` does, so a leaf that reads `cloudflare.enc` only for the R2 backend no longer flags a key another leaf needs. A spoke that doesn't set `workloads_only` needs no changes.

**`terraform/backblaze/api-key`** gains `rotation_days`. It replaces the key create-before-destroy on that schedule, and each key expires a week later. It overrides `valid_duration_in_seconds`, and it defaults to null, so existing callers keep their fixed expiry. Each existing caller does plan one new `terraform_data.rotation` resource on upgrade, as `cloudflare/api-token` did.

**The published workload schema** gains `backblaze.deployer`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#208](https://github.com/noisypigeon/library/pull/208)

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
