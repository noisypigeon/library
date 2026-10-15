# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-15

### Add cloudflare/dns-record, a thin wrapper over cloudflare_dns_record

A new module, `cloudflare/dns-record`: a thin wrapper around a single `cloudflare_dns_record`. It exists so that a leaf managing DNS records calls a pigeon-lib module and can live at `terraform/cloudflare/dns-record/<instance>/`, the layout [LIB-0004](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0004-normalized-terraform-leaf-layout.md) sets for every spoke.

It adds no behaviour. Every argument passes straight through to the provider:

- **Required:** `zone_id`, `name`, `type`, `content`.
- **Optional:** `ttl` defaults to `1` (automatic). `proxied`, `priority` and `comment` default to `null`, which leaves them unset. Many existing MX and TXT records never set `proxied`, and a wrapper that quietly sent `false` would turn adopting it into a change.
- **Output:** `id`.

Callers use `for_each` for several records. Moving an existing raw `cloudflare_dns_record` under this module is an address change only: add one `moved` block per record, and the plan shows moves and no changes. The README has both patterns.

Requires `cloudflare/cloudflare` `~> 5`, matching the `terragrunt/root-hcl` template's provider block.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#24](https://github.com/noisypigeon/pigeon-lib/pull/24)
