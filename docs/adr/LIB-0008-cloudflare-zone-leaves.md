# LIB-0008: Cloudflare zone leaves live at `terraform/cloudflare/<zone>/<module>/<instance>/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted; amended 2026-10-17 (see `## Amendments`).

## Context

LIB-0004 put every leaf at `terraform/<provider>/<module>/<instance>/`, with
exactly three segments below `terraform/`. For Cloudflare's zone-scoped
resources, that leaves out the most important fact about a leaf: which zone it
writes to.

- **The path doesn't say.** noisypigeon.com's four DNS leaves are
  `terraform/cloudflare/dns-record/{bluesky,github-pages,google-search,proton}`.
  All four write to `noisypigeon.com`, but only the line
  `zone_id = local.zone_id_noisypigeon_com` inside each leaf says so.
- **The zone ID is wired by hand.** `root.hcl` turns every `ENV_CF_*` secret
  into a local, for example `ENV_CF_ZONE_ID_NOISYPIGEON_COM` into
  `local.zone_id_noisypigeon_com`, and each leaf picks the right one. In a repo
  with one zone, that's tolerable.

It won't stay one zone per repo. The direction is for **noisypigeon.com to be
the canonical identity and to own every domain that redirects to it**:

- willowgraysen.com's redirect moves into the noisypigeon.com repo;
- pigeon.dev's follows, once its content moves to **noisypigeon.garden**, which
  has been bought to be pigeon.dev's new home;
- any domain bought later to point at the identity is added the same way.

A repo holding many zones needs each zone's leaves grouped together, and wired
to that zone without anyone choosing an ID by hand. This record sets that layout
and its plumbing. The moves themselves are out of scope.

## Decision

### 1. A zone leaf adds the zone between the provider and the module

A leaf that calls a **zone-scoped** Cloudflare module lives at
`terraform/cloudflare/<zone>/<module>/<instance>/`.

- **`<zone>`** is the zone's apex domain, exactly as Cloudflare names it, for
  example `noisypigeon.com`.
- **The module's coordinate doesn't change.** The leaf still calls
  `pigeon.dev/modules/cloudflare/<module>/vX.Y.Z`. The zone segment exists only
  in the spoke's path.
- **Whether a module is zone-scoped is the module's own property,** stated in
  its README. Today `cloudflare/dns-record` and `cloudflare/ruleset` are
  zone-scoped. `cloudflare/bucket` is account-level and keeps LIB-0004's
  `terraform/cloudflare/bucket/<instance>/`.
- **This is the one exception to LIB-0004 §1's "exactly three segments".**
  Every other leaf keeps three. LIB-0004 §4's future enforcement has to accept
  four for these leaves.
- **The state key follows from the path,** as always:
  `terraform/cloudflare/<zone>/<module>/<instance>/terraform.tfstate`. A dot in
  a key is fine for S3 and R2.

`ls terraform/cloudflare/<zone>/` answers "what does this repo manage in that
zone".

### 2. `root.hcl` gives a zone leaf its zone (`terragrunt/root-hcl` v2.2.0)

- **Detection.** A leaf is a zone leaf when its path is
  `terraform/cloudflare/<x>/…` with at least five segments, and `<x>` contains a
  dot. A domain always has a dot and a module name never does, so no list of
  zone-scoped modules is needed in the template.
- **Lookup.** For a zone leaf, the template sets `cloudflare_zone = "<x>"`. It
  reads `ENV_CF_ZONE_ID_<X>` from `secrets.enc` or the environment, where `<X>`
  is the zone uppercased with `.` and `-` turned into `_`:
  `noisypigeon.com` becomes `ENV_CF_ZONE_ID_NOISYPIGEON_COM`.
  `cloudflare_ids_generated.tf` then defines `local.cloudflare_zone` and
  `local.cloudflare_zone_id`.
- **A missing ID is a hard error.** A zone leaf without its `ENV_CF_ZONE_ID_*`
  secret fails the render, and the message names the expected key. Before this,
  a typo in a hand-picked local would have planned a record into the wrong zone.
- **Nothing else changes.** The existing `local.zone_id_<zone>` locals still
  render, and every non-zone leaf's generated files are byte-identical to
  v2.1.0's. Taking v2.2.0 is a no-op until a leaf moves.

A zone leaf writes `zone_id = local.cloudflare_zone_id`.

### 3. On R2, moving a leaf copies its state object

LIB-0004 §3's runbook pulls the old key's state and pushes it to the new key.
COM-0004 found that on R2, `terraform state push` into an empty key adopts the
new remote's lineage instead of keeping the state's own. On the R2 backend
(LIB-0007), a leaf moves like this:

1. **Copy** the state object to the new key with
   `rclone copyto --s3-no-check-bucket`, in the same bucket, byte for byte.
2. **Check** that `terragrunt state pull` at the new path, on the branch,
   matches a pull at the old path, on a worktree of `main`, in serial, lineage
   and resource count.
3. **Plan** the new path, which must show `No changes`.
4. **Empty the old key** with `state rm` of every address it held, from the
   worktree of `main` (DEV-0130). The removed directory then plans nothing.

Terraform PRs in the spoke are frozen from step 1 until the move merges. The
B2 backup picks up the new keys on its next run.

### 4. noisypigeon.com adopts first

| Today | Becomes |
| --- | --- |
| `terraform/cloudflare/dns-record/bluesky` | `terraform/cloudflare/noisypigeon.com/dns-record/bluesky` |
| `terraform/cloudflare/dns-record/github-pages` | `terraform/cloudflare/noisypigeon.com/dns-record/github-pages` |
| `terraform/cloudflare/dns-record/google-search` | `terraform/cloudflare/noisypigeon.com/dns-record/google-search` |
| `terraform/cloudflare/dns-record/proton` | `terraform/cloudflare/noisypigeon.com/dns-record/proton` |

It takes v2.2.0 and moves the four leaves by §3, in one PR. Each leaf switches
to `local.cloudflare_zone_id`. It's a file move and a state move; no resource
changes. Its `cloudflare/bucket` and `backblaze/` leaves don't move.

`pigeon.dev` and `willowgraysen.com` adopt later, in their own PRs. For both,
the move may be folded into the redirector rollout below.

## Consequences

- **A zone's leaves sit together,** and the path says which zone a leaf writes.
- **A redirector repo can hold any number of zones.** Each new zone is a
  directory plus one `ENV_CF_ZONE_ID_*` secret, and no leaf picks an ID by hand.
- **Modules have to say whether they're zone-scoped.** That's a line in the
  README, and it decides where the leaves go.
- **Spoke paths have four segments under `terraform/cloudflare/<zone>/`.** Tools
  that assume three, such as LIB-0004 §4's eventual enforcement, must allow for it.
- **The hand-wired locals linger** until every zone leaf has moved. Removing
  them would be a later, breaking template change.

## Out of scope

Genuinely deferred, each with an issue:

- **noisypigeon.com owns willowgraysen.com's redirect** (noisypigeon/noisypigeon#320).
  Its `dns-record/redirect` and `ruleset/noisypigeon-com-redirect` leaves move
  into the noisypigeon.com repo under `terraform/cloudflare/willowgraysen.com/`.
  That's a state move across repos and buckets. *Done:* COM-0006, Verification 6.
- **pigeon.dev's redirect moves to the noisypigeon.com repo**
  (noisypigeon/noisypigeon#321). The constraint to respect:
  `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` is a public module-source
  interface (ADR-0109/0110). Any redirect has to keep go-getter discovery
  working, by preserving the path and serving the `terraform-get` meta at the
  target. Otherwise every consumer's `source =` breaks.
  *Superseded by LIB-0009:* every consumer moves to the new host first, and
  `pigeon.dev` short URLs are retired rather than preserved.
- **noisypigeon.garden becomes pigeon.dev's new home**
  (noisypigeon/noisypigeon#322): the site, the module short-URL host, and its
  zone as zone leaves. *Decided by LIB-0009.*

Permanent boundaries, with no issue:

- **Account-level Cloudflare modules have no zone segment.** A bucket isn't in a
  zone.
- **Zones are named by apex domain,** never by zone ID. IDs stay in `secrets.enc`.

## Verification

1. **Template parity.** Every leaf in all three spokes was rendered with
   `terragrunt render --json` under v2.1.0 and under this template: 5 in
   pigeon.dev, 7 in noisypigeon.com and 20 in willowgraysen.com. Everything
   apart from `locals`, generated files included, hashed identically for all 32.
2. **A zone leaf.** A copy of noisypigeon.com's `proton` leaf at
   `terraform/cloudflare/noisypigeon.com/dns-record/x` rendered
   `cloudflare_zone = "noisypigeon.com"` and a non-empty `cloudflare_zone_id`,
   equal to the existing `zone_id_noisypigeon_com`. A non-zone leaf's generated
   file had no zone lines.
3. **The guard.** A copy at `terraform/cloudflare/example.org/dns-record/x`
   failed the render with "is a zone leaf for example.org but
   ENV_CF_ZONE_ID_EXAMPLE_ORG is not set in secrets.enc or the environment".
4. **The release.** #47 cut `terragrunt/root-hcl/v2.2.0`. Its README-only
   module changes released no module.
5. **noisypigeon.com's adoption** (noisypigeon/noisypigeon.com#29), by §3:
   - the four state objects were copied to their new R2 keys, and each matched
     its old key in serial, lineage and resource count;
   - the branch planned `No changes.` on 7/7 leaves;
   - `state rm` then emptied the old keys (13 instances).

   CI planned `No changes.` on the four new paths and on the four removed ones,
   with no creates or destroys. The apply was a no-op on all 11. The post-apply
   backup held 13 files in both R2 and B2. Afterwards, `main` planned
   `No changes.` on 7/7 leaves.
6. **willowgraysen.com's redirect** (COM-0006, noisypigeon/noisypigeon.com#30,
   noisypigeon/willowgraysen#12) was the first move between backends: §3
   copied from the spoke's Scaleway bucket to noisypigeon.com's R2 bucket.
   - The repo was renamed `noisypigeon/willowgraysen` first. It kept its ID,
     ruleset and secrets, and no state key changed.
   - Both state objects matched their sources by SHA-256, and in serial,
     lineage and resource count (3 instances).
   - noisypigeon.com gained `ENV_CF_ZONE_ID_WILLOWGRAYSEN_COM`. Its CI planned
     `No changes.` on both new leaves, the apply was a no-op, and the
     post-apply backup copied both new keys to B2.
   - `state rm` then emptied the old keys (3 instances). willowgraysen#12
     removed the leaves, the `cloudflare` provider and its three Cloudflare
     secrets. It planned and applied `No changes.` on 20/20 leaves.
   - The two emptied objects were deleted from the versioned Scaleway bucket.
     `willowgraysen.com` and `www` still return `301` to `https://noisypigeon.com/`.
7. **pigeon.dev's zone** moved to noisypigeon.com by the same steps as item 6
   (LIB-0009 Verification 6). `fastmail` moved with its state, and
   `github-pages` was destroyed rather than moved. The redirect targets
   `https://noisypigeon.garden`. `noisypigeon.garden` adopted the layout in its
   own repo from its first leaf (garden#40).

## Amendments

### 2026-10-17: COM-0006, the blog repo owns the `willowgraysen.com` redirect (folded from `noisypigeon/blog`)

Filed 2026-10-16. This was the first domain to move into the canonical
identity's repo under this record's layout (noisypigeon/noisypigeon#320).
Accepted, and amended the same day when `pigeon.dev` followed the same
pattern (DEV-0165, LIB-0009).

**Decision.**

1. **Two leaves move under the zone.**
   - `cloudflare/dns-record/redirect` holds the proxied placeholder records
     for the apex and `www`, so Cloudflare intercepts the traffic.
   - `cloudflare/ruleset/noisypigeon-com-redirect` holds a 301 to
     `https://noisypigeon.com`.

   Both move to `terraform/cloudflare/willowgraysen.com/…`. They were copied,
   not imported with history, so the PR merges through the apply like any
   other. Each leaf's only change is `zone_id = local.cloudflare_zone_id`.
2. **State is copied across buckets and backends.** This is §3 between two
   repos: `rclone copyto` from the source spoke's Scaleway bucket to this
   spoke's R2 bucket, byte for byte. Both remotes are configured from each
   repo's secrets by environment variables. Nothing is pushed, so serial and
   lineage survive (COM-0004). After this spoke plans `No changes.`, the
   source empties its old keys with `state rm`, removes the leaves, and turns
   its Cloudflare provider off.
3. **One new secret,** `ENV_CF_ZONE_ID_WILLOWGRAYSEN_COM`, the same value the
   source held. Without it, the render of both leaves fails.

The repo holding the source leaves had just been renamed from
`willowgraysen.com` to `willowgraysen`, and later became `runway`
(LIB-0013). Nothing depended on the name: the repo ID carries the secrets and
the ruleset, and no state key contains a repo name.

**Still true.**

- The blog repo holds the identity's zone and every redirecting zone, so a bad
  Terraform merge there can break a redirect as well as the site.
- The B2 backup covers the moved keys.
- The redirects' behaviour moved unchanged, permanently for that record.

**Verification.** The rename kept the repo ID, ruleset and secrets. Each R2
object's SHA-256 matched its source. Pulls matched in serial, lineage and
resource count (3 instances). The new secret hashed equal to the old one, and
both leaves planned `No changes.`.

Original: [COM-0006](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0006-own-willowgraysen-com-redirect.md).
