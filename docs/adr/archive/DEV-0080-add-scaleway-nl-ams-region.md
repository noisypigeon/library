# DEV-0080: support a second Scaleway region (`nl-ams`)

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-30.
- **Status**: Accepted.

## Context

`terraform/infrastructure/scaleway/` has only ever targeted one region.
ADR-0060 added the Scaleway provider deliberately without pinning
`region`/`zone`, relying on Scaleway's own default (`fr-par`/`fr-par-1`),
reasoning that pinning could wait "until a region-specific resource
actually needs pinning." That default is now a hardcoded literal in
`terraform/infrastructure/scaleway/root.hcl`'s generated `provider
"scaleway"` block (`zone = "fr-par-1"`, `region = "fr-par"`), applied
identically to *every* leaf under `scaleway/` — `fr-par/*` and `global/*`
alike, since it's the only provider block available (there is no top-level
`terraform/infrastructure/root.hcl`; each provider — `digitalocean`,
`cloudflare`, `scaleway` — has its own independent `root.hcl` per
ADR-0061).

`terraform/infrastructure/scaleway/nl-ams/` doesn't exist yet, and
critically, nothing today would make it work correctly even if someone
hand-created a mirror of `fr-par/`'s structure under it: the state *key*
would look right (`scaleway/nl-ams/.../terraform.tfstate`, since
`path_relative_to_include()` already embeds the full leaf path — no
collision risk there), but the generated provider block would still
silently emit `zone = "fr-par-1"` / `region = "fr-par"`, so resources
would actually provision into `fr-par`, not `nl-ams`. This ADR fixes that
mismatch and makes `nl-ams` a real, selectable second region. This is
plumbing only: no nl-ams leaf or resource is added as part of it.

## Decision

### Region selection by leaf path, inside the existing `scaleway/root.hcl`

Keep a single `terraform/infrastructure/scaleway/root.hcl` — adding a
second, per-region root file would deviate from ADR-0061's one-root-per-
*provider* convention for no benefit here. Instead, add a path-keyed
region/zone lookup, mirroring the path-based-branching pattern ADR-0064
already established for Cloudflare's per-domain credential selection:

```hcl
locals {
  # ... existing secrets-loading locals unchanged ...

  leaf_path = path_relative_to_include()

  scaleway_region_zone = {
    "fr-par" = { region = "fr-par", zone = "fr-par-1" }
    "nl-ams" = { region = "nl-ams", zone = "nl-ams-1" }
  }
  leaf_region_segment = element(split("/", local.leaf_path), 0)
  scaleway_region = lookup(local.scaleway_region_zone, local.leaf_region_segment, local.scaleway_region_zone["fr-par"]).region
  scaleway_zone   = lookup(local.scaleway_region_zone, local.leaf_region_segment, local.scaleway_region_zone["fr-par"]).zone
}
```

The generated `provider "scaleway"` block's `zone`/`region` switch from
the current hardcoded strings to `"${local.scaleway_zone}"` /
`"${local.scaleway_region}"`.

Any leaf whose first path segment isn't `"nl-ams"` — every existing
`fr-par/*` leaf, plus the region-agnostic `global/*` leaf — falls through
to the `fr-par` default via the `lookup(...)` fallback, so **no existing
leaf's behavior changes**. This is the same accepted risk ADR-0064 already
named for its own path-based branching: a leaf placed outside the expected
directory convention silently resolves to the default region rather than
erroring. No code-level guard is added against it here either, consistent
with that precedent.

### Remote state is untouched

The state *bucket*'s own location (`endpoints.s3 =
"https://s3.fr-par.scw.cloud"`, `region = "fr-par"` in the `remote_state`
block) is where state is *stored*, not where resources are *provisioned*
— there's no reason to move it just because a second resource-region
exists. State keys already avoid collision with no change needed: `key =
"scaleway/${path_relative_to_include()}/terraform.tfstate"` already embeds
the full leaf path, so `scaleway/nl-ams/<domain>/<leaf>/terraform.tfstate`
and `scaleway/fr-par/<domain>/<leaf>/terraform.tfstate` are naturally
distinct keys in the same shared bucket.

### No new secrets

`SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`/`SCALEWAY_ORGANIZATION_ID`/
`SCALEWAY_PROJECT_ID_NOISYPIGEON` are org/project-scoped, not
region-scoped — a Scaleway Project spans regions, so the same project ID
and API credentials apply to resources in `nl-ams` as in `fr-par`. Nothing
new is needed in `.env`/`.env.example`.

## Consequences

- `nl-ams` becomes a usable region the moment a leaf is placed at
  `terraform/infrastructure/scaleway/nl-ams/<domain>/<leaf>/` with the
  same boilerplate `terragrunt.hcl` every other leaf uses (`include "root"
  { path = find_in_parent_folders("root.hcl") }` + `terraform { source =
  get_terragrunt_dir() }`) — no further `root.hcl` change needed per
  future leaf.
- `scaleway/root.hcl` now carries a small branching table instead of two
  flat literals — a real complexity increase in the one file every
  Scaleway leaf depends on, accepted in exchange for not duplicating the
  secrets/provider/remote_state boilerplate ADR-0061 consolidated into one
  file per provider.
- Nothing under `fr-par/` or `global/` changes behavior — both fall
  through to the same `fr-par` default they already resolve to today,
  unconditionally.
- No nl-ams leaves are added by this ADR. The first real nl-ams resource
  is a follow-up decision (its own ADR if it's architecturally
  significant, or a direct PR if it's routine — matching how `fr-par`'s
  own leaves after ADR-0060 didn't each get a fresh ADR).

## Out of scope

- Implementing the `root.hcl` diff itself — this ADR is a decision
  record; the snippet above is written to be applied directly as a small,
  mechanical follow-up.
- Any actual resource under `terraform/infrastructure/scaleway/nl-ams/` —
  no bucket, project, or compute instance is created here.
- A third region, or a general N-region abstraction beyond the two-entry
  lookup table above — extend the table if/when a third region is
  actually needed, per this repo's usual backfill-not-speculate
  convention (ADR-0060, ADR-0079).
- Guarding against a leaf being accidentally placed outside the
  `fr-par/`/`nl-ams/`/`global/` convention and silently defaulting to
  `fr-par` — same accepted risk ADR-0064 already carries for Cloudflare
  domain selection.
