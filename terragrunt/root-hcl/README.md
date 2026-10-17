# `terragrunt/root-hcl`

The Terragrunt `root.hcl` every spoke in this family shares, versioned as
`terragrunt/root-hcl/vX.Y.Z` (LIB-0001 §6, LIB-0003). Everything a spoke varies
lives in its `spoke.hcl`; everything else is this one template.

## What it does

For every leaf under a spoke's `terraform/`:

- decrypts the spoke's `terraform/secrets.enc` in memory with sops/age (no
  plaintext on disk), checks its keys against `secrets-schema.json`, and
  exposes every `ENV_*` key as a local (LIB-0010);
- generates the providers `spoke.hcl`'s `providers` map turns on for that leaf
  (Cloudflare, Scaleway, Backblaze B2, Scaleway Cockpit Grafana; LIB-0005);
- excludes anything not under `terraform/`;
- keeps state in the spoke's own bucket, on Scaleway or R2 (`state_backend`,
  LIB-0007), at `terraform/<leaf>/terraform.tfstate`.

That key carries no prefix, so it is byte-identical to what the per-domain roots
in `noisypigeon/noisypigeon` produced. Hoisting a leaf into a spoke therefore
moves no state (LIB-0001 invariant 4).

## Consuming it

A spoke commits a `spoke.hcl` at its repo root:

```hcl
locals {
  # Template version to materialize: "X.Y.Z", or "main" for the working tree.
  root_hcl_version = "3.0.0"

  # Where state lives (LIB-0007): "scaleway" (the default) or "cloudflare".
  state_backend = "cloudflare"

  # Which providers this spoke's leaves get (v2.0.0, LIB-0005). See below.
  providers = {
    cloudflare = {}
    scaleway   = {}
  }
}
```

…runs this from its repo root, and **commits the resulting `root.hcl` and
`secrets-schema.json`**:

```sh
./fetch-lib.sh                                   # pigeon-lib at /.lib-version
.lib-src/.github/scripts/resolve-root-hcl.sh     # writes ./root.hcl and ./secrets-schema.json
```

The committed copies are generated output; never edit them in the spoke. To
take a template change, bump `root_hcl_version` and rerun the script. CI runs
the same script with `--check`, which writes nothing and fails unless both files
are byte-identical to the pinned template's, so a hand edit or a forgotten
re-run cannot reach `main` unnoticed. A version before v3.0.0 has no schema, and
the script removes a stale one.

Leaves include it the usual way:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}
```

In CI, the reusable `terragrunt-run.yml` runs the resolver and the secrets
check through its `prepare_cmd` input, with `secrets_files:
terraform/secrets.enc`:

```yaml
prepare_cmd: ./fetch-lib.sh && .lib-src/.github/scripts/resolve-root-hcl.sh --check && .lib-src/.github/scripts/check-secrets.sh
```

Locally, the same check is a mise task:

```toml
[tasks.secrets-check]
run = ["./fetch-lib.sh", ".lib-src/.github/scripts/check-secrets.sh"]
```

## Secrets (v3.0.0, LIB-0010)

Every value has one fixed name, the same in every spoke. Each is read from the
environment first, then from `terraform/secrets.enc`, so an environment variable
still overrides the file. Which names are required follows from `spoke.hcl`:

| Name | Required when | Feeds |
| --- | --- | --- |
| `TERRAFORM_STATE_BUCKET_NAME`, `TERRAFORM_STATE_ACCESS_KEY_ID`, `TERRAFORM_STATE_ACCESS_KEY` | always | the state backend, either one |
| `TERRAFORM_STATE_BACKUP_BUCKET_NAME`, `TERRAFORM_STATE_BACKUP_ACCESS_KEY_ID`, `TERRAFORM_STATE_BACKUP_ACCESS_KEY` | `state_backend = "cloudflare"` | `state-backup.yml`'s B2 copy (LIB-0007) |
| `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, `CLOUDFLARE_PROVIDER_TOKEN` | `providers.cloudflare` is set | `provider "cloudflare"`, `local.cloudflare_account_id`, and the R2 endpoint |
| `SCALEWAY_PROVIDER_ACCESS_KEY_ID`, `SCALEWAY_PROVIDER_ACCESS_KEY`, `SCALEWAY_PROVIDER_ORGANIZATION_ID`, `SCALEWAY_PROVIDER_PROJECT_ID` | `providers.scaleway` is set | `provider "scaleway"`, `local.scaleway_organization_id` and `local.scaleway_project_id` |
| `BACKBLAZE_PROVIDER_ACCESS_KEY_ID`, `BACKBLAZE_PROVIDER_ACCESS_KEY` | `providers.backblaze` is set | `provider "b2"` |
| `ENV_<NAME>` | optional | `local.<name>` in every leaf |

A provider's keys are required as soon as it's in the `providers` map, however
its `leaves` scope it.

- **State never borrows a provider's key.** A Scaleway-backed spoke whose state
  key is also its provider key holds the value twice, under both names. The one
  overlap is deliberate: an R2 backend builds its endpoint from
  `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, so `state_backend = "cloudflare"` requires
  `providers.cloudflare`.
- **`ENV_<NAME>` becomes `local.<name>`**, lowercased, in every leaf whatever
  its providers, all in `env_secrets_generated.tf`. `ENV_COCKPIT_LOGS_URL` is
  `local.cockpit_logs_url`.
- **Zone IDs aren't secrets any more.** A zone leaf gets only
  `local.cloudflare_zone`, its apex, and `cloudflare/dns-record` v1 looks the
  zone up from it (LIB-0011).

### The schema

`secrets-schema.json` holds the table above as data: `required` maps each
condition (`always`, `backend.<state_backend>`, `provider.<name>`) to its keys,
and `allowed_patterns` lists what any other key must match (`^ENV_[A-Z0-9_]+$`).
It's enforced twice, and both name keys and never print a value:

- **At render time, by `root.hcl`.** It reads the schema from beside itself and
  fails when a required key is missing or empty in both the environment and
  `secrets.enc`, or when `secrets.enc` holds a key outside the schema.
- **Before anything decrypts, by `.github/scripts/check-secrets.sh`.** sops
  dotenv keeps key names in plaintext, so it reads them straight out of
  `terraform/secrets.enc`, reads `state_backend` and `providers` out of
  `spoke.hcl`, and exits 1 listing missing and unknown keys. It needs no
  `SOPS_AGE_KEY`. It can't see an empty value; the render check can.

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
- **`cloudflare`** generates `provider "cloudflare"` from
  `CLOUDFLARE_PROVIDER_TOKEN`, and `local.cloudflare_account_id`, plus
  `local.cloudflare_zone` in a zone leaf (LIB-0008).
- **`scaleway`** generates `provider "scaleway"` at `region`/`zone`, plus
  `local.scaleway_project_id` and `local.scaleway_organization_id`. The state
  backend is always `fr-par`, whatever this says.
- **`backblaze`** generates `provider "b2"` from
  `BACKBLAZE_PROVIDER_ACCESS_KEY{_ID,}` (DEV-0148).
- **`grafana`** generates a `data "scaleway_cockpit_grafana" "grafana"` and a
  `provider "grafana"` that authenticates with **`local.grafana_auth_token`**,
  which the leaf must define (an IAM API key secret, usually a Terragrunt
  `dependency` output). It needs `scaleway` on for the same leaf.

Every leaf's single `required_providers` block lists exactly the providers it
gets. Each provider has its own `provider_<name>_generated.tf`; when that
provider is off for the leaf, the file holds one comment line.

The template fails the run, rather than silently dropping a provider, on an
unknown key, a prefix without its trailing `/`, Grafana without Scaleway, a
`cloudflare` state backend without the Cloudflare provider, a leftover v1
`backblaze`/`grafana` bool, or a leftover v2 `state_bucket_secret`.

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

### Migrating from v2

v3 renames every secret, so a spoke moves in one PR whose every leaf plans
`No changes.` — the values don't change, only their names.

1. Rename the keys in `terraform/secrets.enc` with `sops`, by hand:

   | v2 name | v3 name |
   | --- | --- |
   | the bucket key `spoke.hcl`'s `state_bucket_secret` named | `TERRAFORM_STATE_BUCKET_NAME` |
   | `CLOUDFLARE_R2_ACCESS_KEY_ID`, `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | `TERRAFORM_STATE_ACCESS_KEY_ID`, `TERRAFORM_STATE_ACCESS_KEY` |
   | `TERRAFORM_STATE_BACKUP_B2_{BUCKET_NAME,KEY_ID,KEY}` | `TERRAFORM_STATE_BACKUP_{BUCKET_NAME,ACCESS_KEY_ID,ACCESS_KEY}` |
   | `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_TOKEN` | `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, `CLOUDFLARE_PROVIDER_TOKEN` |
   | `SCALEWAY_ACCESS_KEY`, `SCALEWAY_SECRET_KEY` | `SCALEWAY_PROVIDER_ACCESS_KEY_ID`, `SCALEWAY_PROVIDER_ACCESS_KEY` |
   | `SCALEWAY_ORGANIZATION_ID`, `SCALEWAY_PROJECT_ID` | `SCALEWAY_PROVIDER_ORGANIZATION_ID`, `SCALEWAY_PROVIDER_PROJECT_ID` |
   | `BACKBLAZE_APPLICATION_KEY_ID`, `BACKBLAZE_APPLICATION_KEY` | `BACKBLAZE_PROVIDER_ACCESS_KEY_ID`, `BACKBLAZE_PROVIDER_ACCESS_KEY` |
   | `ENV_SW_<X>`, `ENV_CF_<X>` | `ENV_<X>` |
   | `ENV_CF_ZONE_ID_*` | deleted; take `cloudflare/dns-record` v1 with `zone = local.cloudflare_zone` |

   On a Scaleway backend, also add `TERRAFORM_STATE_ACCESS_KEY_ID` and
   `TERRAFORM_STATE_ACCESS_KEY` with the Scaleway key's values. Check the result
   with `check-secrets.sh`. It catches an old name like `CLOUDFLARE_TOKEN`, but
   `ENV_SW_<X>` still matches the `ENV_` pattern, so grep for that one.
2. Delete `state_bucket_secret` from `spoke.hcl`, bump `root_hcl_version` to
   `"3.0.0"`, and rerun `resolve-root-hcl.sh`. It now writes
   `secrets-schema.json` too, so `/.lib-version` has to be at least
   `workflows/v2.0.0`; commit both files.
3. Pin the reusable workflows at `workflows/v2.0.0`. `state-backup.yml` lost its
   `state_bucket_secret` and `backup_*_secret` inputs, so delete them from its
   callers. Append `&& .lib-src/.github/scripts/check-secrets.sh` to
   `prepare_cmd`.
4. Check that every leaf plans `No changes.`

## Two pins, deliberately

`/.lib-version` decides which *resolver* runs: `resolve-root-hcl.sh` is on the
`workflows/` track. `root_hcl_version` decides which *template* it writes. That
is the same split as the theme's `.lib-version` versus `theme_version`.
