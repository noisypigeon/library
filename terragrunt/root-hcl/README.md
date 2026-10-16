# `terragrunt/root-hcl`

The Terragrunt `root.hcl` every spoke in this family shares, versioned as
`terragrunt/root-hcl/vX.Y.Z` (LIB-0001 §6, LIB-0003). Everything a spoke varies
lives in its `spoke.hcl`; everything else is this one template.

## What it does

For every leaf under a spoke's `terraform/`:

- decrypts the spoke's `terraform/secrets.enc` in memory with sops/age (no
  plaintext on disk) and exposes `ENV_SW_*`/`ENV_CF_*` keys as locals;
- generates the providers `spoke.hcl`'s `providers` map turns on for that leaf
  (Cloudflare, Scaleway, Backblaze B2, Scaleway Cockpit Grafana; LIB-0005);
- excludes anything not under `terraform/`;
- keeps state in the spoke's own Scaleway bucket, at
  `terraform/<leaf>/terraform.tfstate`.

That key carries no prefix, so it is byte-identical to what the per-domain roots
in `noisypigeon/noisypigeon` produced. Hoisting a leaf into a spoke therefore
moves no state (LIB-0001 invariant 4).

## Consuming it

A spoke commits a `spoke.hcl` at its repo root:

```hcl
locals {
  # Template version to materialize: "X.Y.Z", or "main" for the working tree.
  root_hcl_version = "2.0.0"

  # secrets.enc key (or environment variable) naming the spoke's state bucket.
  state_bucket_secret = "NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME"

  # Which providers this spoke's leaves get (v2.0.0, LIB-0005). See below.
  providers = {
    cloudflare = {}
    scaleway   = {}
  }
}
```

…runs this from its repo root, and **commits the resulting `root.hcl`**:

```sh
./fetch-lib.sh                                   # pigeon-lib at /.lib-version
.lib-src/.github/scripts/resolve-root-hcl.sh     # writes ./root.hcl
```

The committed copy is generated output; never edit it in the spoke. To take a
template change, bump `root_hcl_version` and rerun the script. CI runs the same
script with `--check`, which writes nothing and fails unless `./root.hcl` is
byte-identical to the pinned template, so a hand edit or a forgotten re-run
cannot reach `main` unnoticed.

Leaves include it the usual way:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}
```

In CI, the reusable `terragrunt-run.yml` runs `./fetch-lib.sh &&
.lib-src/.github/scripts/resolve-root-hcl.sh --check` through its `prepare_cmd`
input, with `secrets_files: terraform/secrets.enc`.

### Why copied and committed, not included, symlinked or gitignored

- Terragrunt does not support nested includes (DEV-0059), so a spoke file
  cannot `include` this one on a leaf's behalf.
- A leaf's `path_relative_to_include()`, and so its state key, is relative to
  the included file's own directory. A `root.hcl` anywhere but the spoke's root
  would silently shorten every key. DEV-0059 hit exactly that failure.
- The template finds `spoke.hcl` through `get_parent_terragrunt_dir()`, which a
  symlink into the library clone would point at the wrong repo.
- Terragrunt's `[main...HEAD]` git filter, which `terragrunt-run.yml` uses,
  plans every unit inside temporary git worktrees of both refs. Only tracked
  files exist there, so a gitignored `root.hcl` makes every leaf fail with
  `Could not find a root.hcl`. Tracking it has a second benefit: the base ref's
  worktree has its own `root.hcl`, so a removed leaf can still plan its destroy.

### Providers (v2.0.0)

`providers` is required. Each key turns a provider on; a provider that isn't in
the map is off for every leaf:

```hcl
providers = {
  cloudflare = {}
  scaleway   = { region = "fr-par", zone = "fr-par-1" } # the defaults
  backblaze  = { leaves = ["terraform/backblaze/"] }
  grafana    = { leaves = ["terraform/grafana/dashboard/"] }
}
```

- **`leaves`** is an optional list of path prefixes, relative to the spoke's
  root and ending in `/`. With it, the provider is on only for leaves under one
  of them; without it, for every leaf. Under LIB-0004's
  `terraform/<provider>/<module>/<instance>/` layout, a prefix is usually
  `terraform/<provider>/` or `terraform/<provider>/<module>/`.
- **`cloudflare`** generates `provider "cloudflare"` from `CLOUDFLARE_TOKEN`, and
  `local.cloudflare_account_id` plus the `ENV_CF_*` locals.
- **`scaleway`** generates `provider "scaleway"` at `region`/`zone`, plus
  `local.scaleway_project_id` and friends and the `ENV_SW_*` locals. The state
  backend is always `fr-par`, whatever this says.
- **`backblaze`** generates `provider "b2"` from
  `BACKBLAZE_APPLICATION_KEY{,_ID}` (DEV-0148).
- **`grafana`** generates a `data "scaleway_cockpit_grafana" "grafana"` and a
  `provider "grafana"` that authenticates with **`local.grafana_auth_token`**,
  which the leaf must define (an IAM API key secret, usually a Terragrunt
  `dependency` output). It needs `scaleway` on for the same leaf.

Every leaf's single `required_providers` block lists exactly the providers it
gets. Each provider has its own `provider_<name>_generated.tf`; when that
provider is off for the leaf, the file holds one comment line.

The template fails the run, rather than silently dropping a provider, on an
unknown key, a prefix without its trailing `/`, Grafana without Scaleway, or a
leftover v1 `backblaze`/`grafana` bool.

`extra_required_providers` (v1.1.0) still appends `{ source, version }` entries
to `required_providers`, for a provider the leaf configures itself.

### Migrating from v1

v1 turned Backblaze and Grafana on with a bool in `spoke.hcl` and a sibling
`backblaze_config.hcl`/`grafana_config.hcl` in each leaf, and overrode Scaleway's
region with `scaleway_config.hcl`. v2 reads none of them. In one PR:

1. Add `providers`, with `cloudflare = {}` and `scaleway = {}` for v1's defaults.
2. For `backblaze = true` or `grafana = true`, delete the bool and add the
   provider with `leaves` covering the leaves that had a `*_config.hcl`.
3. Delete every `*_config.hcl` under `terraform/`.
4. Bump `root_hcl_version` to `"2.0.0"`, rerun `resolve-root-hcl.sh`, and check
   that every leaf plans `No changes.`

## Two pins, deliberately

`/.lib-version` decides which *resolver* runs: `resolve-root-hcl.sh` is on the
`workflows/` track. `root_hcl_version` decides which *template* it writes. That
is the same split as the theme's `.lib-version` versus `theme_version`.
