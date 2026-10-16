# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-15

### Add cloudflare/ruleset, a thin wrapper over cloudflare_ruleset

A new module, `cloudflare/ruleset`: a thin wrapper around a single `cloudflare_ruleset`. A leaf that manages a ruleset can then call a pigeon-lib module and live at `terraform/cloudflare/ruleset/<instance>/`, the layout [LIB-0004](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0004-normalized-terraform-leaf-layout.md) sets. Its first user is `willowgraysen.com`'s redirect to `noisypigeon.com`.

It adds no behaviour:

- **Required:** `zone_id`, `name`, `kind`, `phase`.
- **`rules`:** passed to the provider exactly as given.
- **`description`:** defaults to `null`, so it stays unset.
- **Output:** `id`.

Moving an existing raw `cloudflare_ruleset` under it is an address change only, done with one `moved` block. The README has the pattern.

Requires `cloudflare/cloudflare` `~> 5`, matching the `terragrunt/root-hcl` template.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#30](https://github.com/noisypigeon/pigeon-lib/pull/30)
