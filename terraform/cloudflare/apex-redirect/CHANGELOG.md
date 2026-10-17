# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-16

### Look Cloudflare zones up by apex in dns-record and add apex-redirect

Cloudflare zones are now looked up by their apex domain instead of being passed in by ID, and a redirect is one module instead of two ([LIB-0011](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0011-zone-lookup-and-apex-redirect.md)). This release is breaking for `cloudflare/dns-record` and introduces `cloudflare/apex-redirect`.

### `cloudflare/dns-record` v1.0.0: `zone` replaces `zone_id` (breaking)

- **The `zone_id` input is gone.** Pass `zone`, the zone's apex domain (e.g. `"example.com"`), instead. The module resolves it with `data "cloudflare_zone"` filtered by name and gives the record that zone's ID.
- **A new `zone_id` output** returns the ID it found.
- **Nothing else changes.** Every other argument still passes straight through, and `null` still means unset.

To upgrade a zone leaf, replace `zone_id = local.cloudflare_zone_id` with `zone = local.cloudflare_zone`, which `terragrunt/root-hcl` derives from the leaf's path (LIB-0008). Because the looked-up ID is the one you were passing, the plan shows `No changes.` A zone ID then no longer needs to sit in `secrets.enc`.

**Token permissions:** your Cloudflare API token now needs **Zone:Read** on the zone as well as DNS edit. The first plan after upgrading proves it does. Each record instance does its own lookup, which is one API read per record.

### `cloudflare/apex-redirect` v0.1.0 (new)

This module redirects a zone's apex, and `www` with it, to a single URL. Today that takes two leaves, a `dns-record` leaf for the placeholders and a `ruleset` leaf for the 301. This module manages all three resources itself:

- a proxied placeholder `A @ 192.0.2.1` record;
- a proxied placeholder `CNAME www → <zone>` record, which `include_www = false` turns off;
- one `http_request_dynamic_redirect` ruleset that sends those hosts to `target_url`.

Inputs:

- **Required:** `zone` and `target_url`.
- **Optional:** `status_code` (default `301`), `include_www` (default `true`) and `preserve_query_string` (default `false`).

Outputs are `zone_id`, `ruleset_id`, `apex_record_id` and `www_record_id` (null without `www`). Every request goes to `target_url` itself; the path is not kept.

The ruleset's name, the rule's description and the records' comments are generated in exactly the wording the hand-written redirect leaves used: for example, the ruleset is `"<zone> to <host> redirect"`, where `<host>` is `target_url` without its scheme or trailing slash. That means an existing redirect can be `import`ed into a new `apex-redirect` leaf with no diff. That matters most for the ruleset, which Cloudflare replaces when its name changes. The README lists every generated string and the three `import` blocks.

The module declares its resources directly rather than calling `dns-record` and `ruleset`, because a module that sources another by short URL breaks when that host moves (LIB-0009). It needs the same Zone:Read permission as `dns-record`, plus ruleset edit.

### `cloudflare/ruleset` is end-of-life

`cloudflare/ruleset` gets no further releases. Its README now says so. Existing tags stay resolvable, so a leaf pinned to `v0.1.0` keeps working until it moves to `apex-redirect`.

Both modules require `cloudflare/cloudflare` `~> 5`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#58](https://github.com/noisypigeon/pigeon-lib/pull/58)
