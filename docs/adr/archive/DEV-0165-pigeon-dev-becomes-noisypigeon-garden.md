# DEV-0165: `pigeon.dev` becomes `noisypigeon.garden`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted.
- **Amended 2026-10-16**: §4's redirect target was wrong. `pigeon.dev`
  redirects to `https://noisypigeon.com`, because it was the blog's home
  before noisypigeon.com and it's an alias of the identity. Only the site and
  the module short URLs moved here (noisypigeon/noisypigeon.com#33).

## Context

This repo serves the `pigeon.dev` site from GitHub Pages: the wiki, the module
overview pages, the release posts, and the `terraform-get` redirect pages behind
every module short URL (DEV-0136, DEV-0141, DEV-0156). It also holds the
`pigeon.dev` zone's two DNS leaves, plus its own R2 state bucket and its B2
backup (DEV-0164).

[LIB-0009](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0009-terraform-short-urls-move-to-noisypigeon-garden.md)
moves the short URLs to `https://noisypigeon.garden/terraform/…`, a domain
bought to be this site's new home, and retires `pigeon.dev`'s with no redirect.
LIB-0008 puts a redirect-only domain in the `noisypigeon.com` repo. This record
is this repo's side of both.

## Decision

### 1. The repo is `noisypigeon/garden`

The repo is renamed from `noisypigeon/pigeon.dev`, and
`.github/workflows/pigeon-dev-pages.yml` becomes `garden-pages.yml`. The hub's
dispatch follows (LIB-0009 §4). The repo ID carries the Pages site, the
secrets, the ruleset and the bot token's grant.

### 2. Zone leaves, by LIB-0008

`spoke.hcl` takes `root.hcl` v2.2.0. Each leaf below writes
`zone_id = local.cloudflare_zone_id`.

| Today | Becomes |
| --- | --- |
| `terraform/cloudflare/dns-record/fastmail` | `terraform/cloudflare/pigeon.dev/dns-record/fastmail` |
| `terraform/cloudflare/dns-record/github-pages` | `terraform/cloudflare/pigeon.dev/dns-record/github-pages` |
| — | `terraform/cloudflare/noisypigeon.garden/dns-record/github-pages` |

The two moves are LIB-0008 §3 within this repo's own R2 bucket. The new leaf
holds DNS-only CNAMEs for `@` and `www` pointing at `noisypigeon.github.io`,
the same shape as `pigeon.dev`'s. Once the domain is verified for Pages in the
account's settings, the leaf also holds that verification TXT record. `terraform/cloudflare/bucket/terraform-state` is account-level, so it
stays where it is. `terraform/secrets.enc` gains
`ENV_CF_ZONE_ID_NOISYPIGEON_GARDEN`.

### 3. The site moves to `noisypigeon.garden`

- **The custom domain** changes from `pigeon.dev` to `noisypigeon.garden`, with
  HTTPS enforced.
- **`web/config.toml`** gets `base_url = "https://noisypigeon.garden"`, and the
  title becomes "noisypigeon.garden".
- **`web/content/modules/` becomes `web/content/terraform/`,** to match the
  generator (LIB-0009 §3), along with its `_index.md` and `.gitignore`'s globs
  for the generated pages.

### 4. The `pigeon.dev` zone leaves for `noisypigeon.com`

- **`fastmail` moves** with its state, from this repo's R2 bucket to
  `noisypigeon.com`'s, by COM-0006's pattern. pigeon.dev's email doesn't change.
- **`github-pages` is destroyed,** because nothing serves `pigeon.dev` any more.
  Removing the leaf here destroys its two CNAMEs. That frees the apex for the
  proxied placeholder records `noisypigeon.com` creates next.
- **`noisypigeon.com` adds the redirect:** a ruleset sending `pigeon.dev` and
  `www` to `https://noisypigeon.garden` with a 301.
- **`ENV_CF_ZONE_ID_PIGEON_DEV` leaves** this repo's `secrets.enc`. The
  Cloudflare provider stays on, for the bucket and the garden zone.

## Consequences

- **This repo has one zone,** `noisypigeon.garden`, plus account-level leaves.
- **A failed site deploy now breaks every module consumer's `terraform init`,**
  as before. The URL is different and the stakes are the same.
- **The emptied state objects** from §2 and §4 are deleted from R2. B2 keeps
  their versions.

## Out of scope

- **Renaming the `DEV-` prefix, the `PIGEON_DEV_*` secrets or the state bucket.**
  This is a permanent boundary, as in LIB-0009.
- **Any `pigeon.dev` compatibility path.** There isn't one, per LIB-0009 §2.

## Verification

1. **§1.** `gh repo rename` kept the repository's ID, the `main` ruleset, both
   Actions secrets and the Pages settings. #39 renamed the workflow, and a
   manual `garden-pages.yml` dispatch deployed cleanly. The first module
   release afterwards (pigeon-lib#53) dispatched it from the hub.
2. **§2** (#40). Both moved state objects matched their old keys by SHA-256, and
   in serial, lineage and resource count (8 instances). They planned
   `No changes.`, and `state rm` emptied the old keys. The apply created the
   `noisypigeon.garden` leaf's 2 CNAMEs, and both resolved to GitHub Pages.
3. **§3** (#41).
   - `mise run garden-build` produced 170 pages, with no path left under
     `/modules/`.
   - After the custom domain moved and its certificate was approved, the deploy
     served `https://noisypigeon.garden`, with canonical URLs on that host.
   - `/terraform/cloudflare/dns-record/v0.1.0` carried the `terraform-get` meta,
     and `terraform init` resolved it.
   - #42 then moved this repo's own sources to the new URLs, with `No changes.`
     on 6/6 leaves.
4. **§4.**
   - `fastmail`'s state was copied to noisypigeon.com's R2 bucket. It matched in
     hash, serial, lineage and count (6 instances), and planned `No changes.`
     there (noisypigeon/noisypigeon.com#32). `state rm` then emptied this repo's
     key.
   - #43 destroyed only the 2 github-pages CNAMEs, and noisypigeon.com#32
     created the placeholders and the ruleset.
   - `pigeon.dev` and `www.pigeon.dev` then returned `301` to
     `https://noisypigeon.garden/`. The Fastmail MX and DKIM records still
     resolved.
   - The four emptied state objects were deleted from this repo's R2 bucket.
     Earlier versions of each remain in B2.
