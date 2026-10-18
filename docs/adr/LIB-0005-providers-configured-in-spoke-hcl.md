# LIB-0005: providers are enabled and configured in `spoke.hcl`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted; amended 2026-10-17 (see `## Amendments`).

## Context

`terragrunt/root-hcl` v1.2.0 (LIB-0003 and its amendments) decides which
providers a leaf gets in three different ways:

- **Cloudflare and Scaleway are always on,** for every leaf of every spoke.
- **Backblaze and Grafana need two opt-ins.** A bool in `spoke.hcl`
  (`backblaze = true`, `grafana = true`) makes the provider available. A sibling
  `backblaze_config.hcl` or `grafana_config.hcl` with `enabled = true` then turns
  it on for that one leaf (DEV-0148's design, copied for Grafana in v1.2.0).
- **A leaf can override Scaleway's region and zone** with a sibling
  `scaleway_config.hcl` (ADR-0098).

Checked against all three spokes' `main`, the per-leaf files carry almost
nothing:

- There are four `*_config.hcl` files in total: three `backblaze_config.hcl`
  under `willowgraysen.com`'s `terraform/backblaze/bucket/`, and one
  `grafana_config.hcl` in its Grafana dashboard leaf.
- **Every one of them is `locals { enabled = true }`** and nothing else.
- **No spoke has a `scaleway_config.hcl`.** The region override has never been
  used since the hoist.

So the files cost something without buying anything:

- **A spoke's providers can't be read from one place.** Answering "which leaves
  get Backblaze?" means a `find` for sidecar files, and a leaf's own
  `terragrunt.hcl` says nothing about them.
- **Every opt-in takes two edits in two places,** and getting either one wrong
  silently leaves the provider out.
- **LIB-0004 already says what a leaf is from its path.** Under
  `terraform/<provider>/<module>/<instance>/`, the leaves that need Backblaze
  are exactly the ones under `terraform/backblaze/`. A per-leaf flag repeats
  what the path already states.

## Decision

### 1. One required `providers` map in `spoke.hcl`

```hcl
locals {
  root_hcl_version    = "2.0.0"
  state_bucket_secret = "WILLOWGRAYSEN_COM_TERRAFORM_STATE_BUCKET_NAME"

  providers = {
    cloudflare = {}
    scaleway   = { region = "fr-par", zone = "fr-par-1" }
    backblaze  = { leaves = ["terraform/backblaze/bucket/"] }
    grafana    = { leaves = ["terraform/grafana/dashboard/"] }
  }
}
```

- **A provider absent from the map is off** for every leaf in the spoke.
- **The map is required.** A `spoke.hcl` without it is a hard error, the same
  rule as `state_bucket_secret`. Defaulting to "Cloudflare and Scaleway" would
  keep an implicit provider set alive, which is what this record removes.
- **The known keys are `cloudflare`, `scaleway`, `backblaze` and `grafana`.**
  Any other key is a hard error, so a typo can't silently turn a provider off.

### 2. `leaves` scopes a provider to path prefixes

- **`leaves` is optional.** Without it, the provider is on for every leaf.
- **Each entry is a path prefix,** relative to the spoke's root (the same
  root `path_relative_to_include()` is relative to), and must end in `/`. A
  prefix without the slash would match siblings too: `terraform/scaleway` would
  match `terraform/scaleway-foo/`. That is a hard error.
- **A leaf matches** when `"<path_relative_to_include()>/"` starts with any
  entry.

Under LIB-0004 the natural prefix is `terraform/<provider>/<module>/`, or
`terraform/<provider>/` for a whole provider. One line in `spoke.hcl` covers
every current and future leaf of that module.

### 3. Each provider's settings live in its entry

- **`scaleway`** takes `region` and `zone`, defaulting to `fr-par` and
  `fr-par-1`, which v1 hardcoded as defaults.
- **`cloudflare` and `backblaze`** take no settings. Their credentials still
  come from `secrets.enc` or the environment, exactly as in v1.
- **`grafana` keeps v1.2.0's contract.** An enabled leaf gets the
  `grafana/grafana ~> 4.0` requirement, a `scaleway_cockpit_grafana` data source
  and the provider, and it must define `local.grafana_auth_token`. That data
  source needs the Scaleway provider, so Grafana on with Scaleway off for the
  same leaf is a hard error.

### 4. One generated file per provider, always written

The single `provider_generated.tf` becomes:

| File | Holds |
| --- | --- |
| `provider_generated.tf` | The one `required_providers` block, for every provider this leaf gets plus `extra_required_providers` |
| `provider_cloudflare_generated.tf` | `provider "cloudflare"` |
| `provider_scaleway_generated.tf` | `provider "scaleway"` |
| `provider_backblaze_generated.tf` | `provider "b2"` |
| `provider_grafana_generated.tf` | The Cockpit data source and `provider "grafana"` |

`cloudflare_ids_generated.tf` follows Cloudflare, and `scaleway_ids_generated.tf`
and `env_scaleway_secrets_generated.tf` follow Scaleway.

**A file whose provider is off for the leaf holds one comment line.** It is not
`disable`d, which would write nothing at all. A disabled generate block leaves
any file an earlier template version wrote in the leaf's `.terragrunt-cache`
where it is. A stale `provider_grafana_generated.tf` in a leaf that no longer
gets Grafana would go on declaring the provider. Overwriting it with a comment
avoids that.

`extra_required_providers` (LIB-0003 v1.1.0) stays as it was.

### 5. The `*_config.hcl` files and the v1 bools are gone

- **`scaleway_config.hcl`, `backblaze_config.hcl` and `grafana_config.hcl`**
  are no longer read. There is no per-leaf provider override. A leaf that
  needs another Scaleway region sets `region` on its module's resources,
  which every Scaleway resource accepts.
- **`backblaze = true` and `grafana = true` in `spoke.hcl` are a hard error**
  under v2. Ignoring them would silently drop a provider from a spoke that
  bumped `root_hcl_version` without migrating.

### 6. The state backend does not change

`remote_state` still authenticates with the Scaleway credentials and always
uses `fr-par`, whether or not the Scaleway provider is on for the leaf, and
whatever region `providers.scaleway` sets. The state key stays
`<path_relative_to_include()>/terraform.tfstate` (LIB-0001 invariant 4).

### 7. A major version: `terragrunt/root-hcl/v2.0.0`

Removing the bools and the sidecar files, and requiring `providers`, breaks every
v1 `spoke.hcl`. Each spoke takes v2 in one PR of its own (LIB-0001 invariant 2)
that:

1. adds the `providers` map;
2. removes `backblaze` and `grafana`, if set;
3. deletes its `*_config.hcl` files;
4. bumps `root_hcl_version` to `"2.0.0"` and regenerates `root.hcl`.

Its plan must show `No changes.` on every leaf.

## Consequences

- **One file answers "which providers does this leaf get".** It's `spoke.hcl`,
  read against the leaf's path.
- **Every spoke now names Cloudflare and Scaleway explicitly.** That's two
  lines each, and the price of having no implicit provider set.
- **A spoke can narrow Cloudflare or Scaleway too.** For example, it can keep
  the Cloudflare provider and its API token out of Scaleway-only leaves. No
  spoke does this yet. With both unscoped, v2 renders the same provider
  configuration v1 did (Verification 1).
- **Generated files per leaf go from four (six in a spoke with Backblaze and
  Grafana) to eight,** several of them a one-line comment in any given leaf.
  The cost is cosmetic: the files live in `.terragrunt-cache`, not in git.
- **A leaf outside a provider's prefixes doesn't require that provider,** so
  `init` doesn't download it and its lock file doesn't list it.
- **Scoping by prefix ties the provider set to LIB-0004's layout.** A leaf
  outside the layout needs its own explicit prefix, which is one more reason to
  conform.

## Out of scope

- **Per-leaf provider overrides, aliases, or several regions in one leaf.**
  This is a permanent boundary. A region that differs goes on the resources.
- **Credentials in `spoke.hcl`.** Also permanent: secrets stay in sops
  (ADR-0123, ADR-0131), and `spoke.hcl` is committed in plaintext.
- **Enforcing LIB-0004's three-segment layout** (LIB-0004 §4). This is
  genuinely deferred to its own record. v2 could have carried it, but one
  breaking change per major is easier to verify.
- **The three spoke migrations.** Each is that spoke's own PR (§7).
- **Moving `willowgraysen.com`'s Grafana leaf** to
  `terraform/grafana/dashboard/pigeon-cli`, now that the module lives at
  `grafana/dashboard`. That is a LIB-0004 §3 state move in that spoke. Until it
  happens, the spoke's `grafana` prefix is `terraform/scaleway/grafana-dashboard/`.

## Verification

1. **Render parity, all three spokes.** Every leaf (4 in `pigeon.dev`, 6 in
   `noisypigeon.com`, 20 in `willowgraysen.com`) was rendered with
   `terragrunt render --json`:
   - once under its committed `root.hcl` (v1.0.1, v1.0.1 and v1.2.0);
   - once under this template, with its sidecar files deleted and a
     `providers` map standing in for them. `pigeon.dev` and `noisypigeon.com`
     used `cloudflare = {}` and `scaleway = {}`. `willowgraysen.com` added
     `backblaze = { leaves = ["terraform/backblaze/bucket/"] }` and
     `grafana = { leaves = ["terraform/scaleway/grafana-dashboard/"] }`.

   For all 30 leaves, every top-level key other than `locals` and `generate`
   was identical, state keys included. The non-comment lines across all
   generated files were identical as multisets: the same provider blocks and
   requirements, only split across files. The b2 provider appeared on exactly
   the three bucket leaves, and Grafana on exactly the one dashboard leaf. The
   renders contain decrypted secrets, so they were compared structurally and
   deleted.
2. **Live plans.** With the same temporary changes, `terragrunt run --all plan`
   in each spoke showed `No changes.` on 4/4, 6/6 and 20/20 leaves. The spokes'
   working trees were then restored to `main`.
3. **The guards.** Against `pigeon.dev`'s `terraform/scaleway/project/dev`, each
   of these failed the render, and the four guards name their own cause:
   - a leftover `backblaze = true`;
   - an unknown key (`scaleaway`);
   - a prefix without a trailing slash;
   - Grafana on for a leaf whose Scaleway prefix excludes it;
   - no `providers` map at all. This one fails as an unsupported attribute, as a
     missing `state_bucket_secret` does.
4. **The release.** This record's PR changes `terragrunt/root-hcl/root.hcl` and
   carries `release:major`, so its merge should cut
   `terragrunt/root-hcl/v2.0.0` and write one `[terragrunt/root-hcl]` root
   line.

## Amendments

### 2026-10-17: COM-0005, retire `noisypigeon.com`'s Scaleway resources (folded from `noisypigeon/blog`)

Filed 2026-10-16. Accepted. This was the first spoke to turn a provider *off*
through this record's map. DEV-0164 then did the same for garden (see
LIB-0007's amendments).

**Context.** After COM-0004 moved the state to R2, the domain had three
Scaleway pieces left:

- the old state bucket, kept as a frozen rollback copy that nothing read;
- the project, whose Object Storage held nothing else across fr-par, nl-ams
  and pl-waw;
- `state/iam`'s deploy key, still in `noisypigeon`.

R2 had by then run cleanly through three applies, each followed by a
successful B2 backup (noisypigeon/noisypigeon#317).

**Decision.**

1. **Retire in dependency order, one PR per step.**
   1. Apply `force_destroy = true` to the bucket on its own first. A destroy
      only empties a versioned bucket if that setting is already in state.
   2. Remove the bucket leaf, and CI destroys the bucket with every version.
   3. Remove the project in a separate PR. A removed leaf can't declare a
      dependency, and the project can't go while it holds a bucket.
   4. Destroy the deploy key last, in `noisypigeon`, because every destroy
      above authenticated with it.
2. **The old bucket's version history is let go,** not exported. Current
   state lives in R2, and every write since COM-0004 is versioned in B2.
3. **Scaleway is off through this record's map.** `spoke.hcl` drops
   `scaleway` from `providers`, with no template change. Every leaf's Scaleway
   generated files become a one-line comment, and the template's Scaleway
   backend is built but never selected.
4. **The Scaleway secrets are removed,** along with the old bucket's name.

**Still true.**

- Recovering state means a restore from B2
  (`docs/runbooks/restore-terraform-state-from-b2.md`).
- `state/iam` was settled for this spoke by retirement: there is no deploy key
  left to bootstrap.
- Emptied state objects of removed leaves stay in R2 and B2, harmless.
- Re-adding Scaleway would be a new decision (a new key, the provider back in
  the map, new leaves), not a deferral.

**Verification.** The bucket apply destroyed two resources and a listing then
returned no buckets. The project apply destroyed one. With Scaleway off,
`mise run plan` showed `No changes.` on all seven remaining leaves.

Original: [COM-0005](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0005-retire-scaleway.md).
