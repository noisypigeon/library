# LIB-0011: zones are looked up by apex, and a redirect is one `apex-redirect` leaf

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted.

## Context

LIB-0008 put zone leaves at `terraform/cloudflare/<zone>/<module>/<instance>/`.
`root.hcl` gives each one its zone ID from an `ENV_CF_ZONE_ID_<ZONE>` key in
`secrets.enc`, and every leaf hands that ID to `cloudflare/dns-record` or
`cloudflare/ruleset`. Three things follow:

- **Every zone costs a secret,** though a zone ID isn't secret and Cloudflare will
  return it for the apex the path already names. noisypigeon/blog holds three.
  Adding a domain means a `secrets-edit` before the first leaf can plan.
- **Every redirect is two leaves and two modules:** `dns-record/redirect`, with
  proxied placeholder records, and `ruleset/noisypigeon-com-redirect`, with the
  301. They're one thing and always change together. Retargeting `pigeon.dev`
  touched both, and the ruleset's rename forced a replacement.
- **`cloudflare/ruleset` has no other use.** It's a pass-through over
  `cloudflare_ruleset`, and both of its consumers are redirects.

## Decision

### 1. `cloudflare/dns-record` v1.0.0 looks its zone up

- **The `zone_id` input is replaced by `zone`,** the zone's apex domain. It's
  resolved with `data "cloudflare_zone"` filtered by name, and the module outputs
  the `zone_id` it found.
- **A zone leaf passes `zone = local.cloudflare_zone`,** which `root.hcl` already
  derives from the path (LIB-0008 §2).
- **`root.hcl` v3.0.0 drops** `ENV_CF_ZONE_ID_*`, `local.cloudflare_zone_id` and
  its guard, and zone IDs leave every spoke's `secrets.enc` (LIB-0010 §5).
- **The record doesn't change:** the looked-up ID is the one that was configured,
  so moving a leaf to v1.0.0 plans `No changes.`
- **Costs:** each record instance does its own lookup, one read of the API. The
  token needs **Zone:Read** on the zone as well as DNS edit. The first plan
  proves both.

### 2. A new `cloudflare/apex-redirect` module

It's zone-scoped. Its inputs are `zone`, `target_url`, `status_code` (default
301), `include_www` (default true) and `preserve_query_string` (default false).
It manages:

- the zone lookup;
- proxied placeholder records: `A @ 192.0.2.1`, and `CNAME www → <zone>` unless
  `include_www` is false;
- one `http_request_dynamic_redirect` ruleset that sends the apex, and `www`, to
  `target_url`.

Two design rules:

- **Raw resources, not nested modules.** LIB-0009 showed that a module which
  sources another module by short URL breaks when the host moves. A module that
  owns its resources has no such dependency.
- **Names are generated in today's exact wording.** For example:
  - the ruleset name, "`<zone> to <host> redirect`";
  - the rule description, "`redirect <zone> and www to the <host> homepage`";
  - the record comments, "`placeholder so Cloudflare intercepts apex traffic for
    the <host> redirect`".

  Existing redirects can then be imported with no diff. That matters most for
  the ruleset, which Cloudflare replaces when its name changes.

### 3. `cloudflare/ruleset` is end-of-life

Its README says so and points to `apex-redirect`. It gets no further releases.
Its tags stay resolvable, but once §4 lands nothing consumes them.

### 4. Each redirect migrates to one leaf in its own repo

Both live in `noisypigeon/blog`:

| Today | Becomes |
| --- | --- |
| `cloudflare/willowgraysen.com/{dns-record/redirect,ruleset/noisypigeon-com-redirect}` | `cloudflare/willowgraysen.com/apex-redirect/noisypigeon-com` |
| `cloudflare/pigeon.dev/{dns-record/redirect,ruleset/noisypigeon-com-redirect}` | `cloudflare/pigeon.dev/apex-redirect/noisypigeon-com` |

Two state files merge into one, which LIB-0008 §3's object copy can't do. So
each migration imports instead:

1. **`terraform import`** puts the 3 existing resources into the new leaf's
   state: the apex record, the `www` record and the ruleset. It runs locally,
   with IDs read from the old states, so the IDs never enter git.
2. **The new leaf must plan `No changes.`**
3. **`state rm` empties the two old keys,** from a worktree of `main` (DEV-0130).
4. **The PR removes the two old directories,** which then plan nothing.

Terraform PRs in the repo are frozen from step 1 until the PR merges.

## Consequences

- **A new domain needs no secret.** A zone directory and its leaves are enough.
- **A redirect is one leaf, one module and one plan.** Retargeting it changes one
  input.
- **Every zone leaf takes dns-record v1.0.0** in the same spoke PR that takes
  `root.hcl` v3.0.0, because v3.0.0 no longer emits `local.cloudflare_zone_id`.
- **The token must be able to read zones.** That's a dashboard setting, outside
  Terraform.

## Out of scope

Permanent boundaries, with no issue:

- **Path-preserving or multi-rule redirects.** `apex-redirect` sends a host to
  one URL. Anything richer is a different module.
- **Non-zone uses of `cloudflare_ruleset`.** None exist. If one appears, it gets
  its own module, not a revived `ruleset`.

## Verification

1. **The release** (#58) cut `terraform/cloudflare/dns-record/v1.0.0` and
   `terraform/cloudflare/apex-redirect/v0.1.0`, and both short URLs served their
   `terraform-get` meta. `cloudflare/ruleset`'s README marks it end-of-life, a
   README-only change that released nothing.
2. **The zone lookup.** The first zone leaf to take dns-record v1.0.0 was garden's
   `noisypigeon.garden/dns-record/github-pages` (noisypigeon/garden#47). It
   planned `No changes.`, which also showed the token can read zones. blog's five
   DNS leaves did the same (noisypigeon/blog#38).
3. **The migration** (noisypigeon/blog#38), by §4:
   - for both `willowgraysen.com` and `pigeon.dev`, `terraform import` put the
     apex record, the `www` record and the ruleset into the new
     `apex-redirect/noisypigeon-com` leaf, 6 resources in all;
   - both new leaves planned `No changes.`, so every generated name, comment and
     rule matched the live resources;
   - `state rm` then emptied the four old keys (6 instances) from `main`.

   CI planned `No changes.` on all 14 units, and the apply was a no-op.
   Afterwards, `willowgraysen.com`, `pigeon.dev`, their `www` hosts and a deep
   `pigeon.dev` path all returned `301` to `https://noisypigeon.com/`, and
   `pigeon.dev`'s Fastmail MX was unchanged.
4. **Zone IDs left the secrets.** garden's one `ENV_CF_ZONE_ID_*` key and blog's
   three were deleted. No leaf in any spoke references `cloudflare/ruleset`,
   `local.cloudflare_zone_id` or a pre-v1 `dns-record`.
