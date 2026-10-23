# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-23

### Workloads sign in to Cloudflare with their own token; bootstrap keys only mint (LIB-0033)

Builds [LIB-0033](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0033-self-bootstrapped-cloudflare-and-backblaze-keys.md) (#155).

**`cloudflare/api-token` v0.1.0 (new).** One account-owned token (`cloudflare_account_token`).
- Policies name their permission groups (such as `"DNS Write"`), resolved through the account's permission-groups list.
- Each policy is scoped to `zones` by apex, `all_zones` or the `account`, exactly one.
- An unknown group, or one the signing-in token may not grant (`is_selectable`), fails the plan by name.
- `rotation_days` replaces the token create-before-destroy, as `scaleway/terraform-deployer-iam` does. Otherwise it expires after `expires_on`, or 365 days.
- It outputs `id` and a sensitive `token`.

**`terragrunt/root-hcl`**
- `secrets-schema.json` gains `cloudflare_breakglass` (`CLOUDFLARE_BREAKGLASS_TOKEN`) and `backblaze_breakglass`. They're for hand-made keys that can only mint keys, read only by the leaves `spoke.hcl`'s `breakglass.leaves` allowlists (LIB-0014 §2).
- A workload that owns a zone in `zones.yaml`, or declares a `cloudflare.bucket`, gets `workloads/<w>/cloudflare/api-token/deployer`, minted with the spoke's token. By default it has *Zone Read*, *DNS Write* and *Dynamic URL Redirects Write* on exactly its zones, plus *Workers R2 Storage Write* if it has buckets, and rotates every 30 days. `cloudflare.deployer` overrides any input.
- The four Cloudflare kinds now sign in with that token: `provider "cloudflare"` reads `var.cloudflare_api_token`.
- Every other leaf renders identically to v5.2.0, Scaleway workload credentials included.

**`workflows/`**
- `resolve-workloads.sh` generates the token stub and wires Cloudflare stubs to it. Workload credentials are now per provider, so a Cloudflare leaf never gets Scaleway's variables.
- `generate-module-redirects.sh` publishes the token's schema, without `account_id`, and adds `cloudflare.deployer` to `v1.json`.

LIB-0033 gains an amendment:
- the token is keyed on zone ownership, so it exists before LIB-0032's import;
- the first `cloudflare.enc` holds the bootstrap token as a placeholder;
- the API-token permission group names are confirmed only by the first real plan.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#159](https://github.com/noisypigeon/library/pull/159)
