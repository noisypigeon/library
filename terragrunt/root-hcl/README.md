# `terragrunt/root-hcl`

The Terragrunt `root.hcl` every spoke in this family shares, versioned as
`terragrunt/root-hcl/vX.Y.Z` (LIB-0001 §6, LIB-0003). Before it existed, the
three per-domain roots in `noisypigeon/noisypigeon` were near-copies of one another.
`pigeon.dev`'s and `noisypigeon.com`'s differed only in the name of their
state-bucket secret.

## What it does

For every leaf under a spoke's `terraform/`:

- decrypts the spoke's `terraform/secrets.enc` in memory with sops/age (no
  plaintext on disk) and exposes `ENV_SW_*`/`ENV_CF_*` keys as locals;
- generates the Cloudflare and Scaleway providers, honouring a leaf's optional
  `scaleway_config.hcl` region/zone override (default `fr-par`/`fr-par-1`);
- excludes anything not under `terraform/`;
- keeps state in the spoke's own Scaleway bucket, at
  `terraform/<leaf>/terraform.tfstate`.

That key carries no prefix, so it is byte-identical to what the per-domain roots
in `noisypigeon/noisypigeon` produced. Hoisting a leaf into a spoke therefore
moves no state (LIB-0001 invariant 4).

## Consuming it

A spoke never commits `root.hcl`. It commits a `spoke.hcl` at its repo root:

```hcl
locals {
  # Template version to materialize: "X.Y.Z", or "main" for the working tree.
  root_hcl_version = "1.0.0"

  # secrets.enc key (or environment variable) naming the spoke's state bucket.
  state_bucket_secret = "PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME"
}
```

…gitignores `/root.hcl`, and runs this before any `terragrunt` command, from its
repo root:

```sh
./fetch-lib.sh                                   # pigeon-lib at /.lib-version
.lib-src/.github/scripts/resolve-root-hcl.sh     # writes ./root.hcl
```

Leaves include it the usual way:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}
```

In CI, the reusable `terragrunt-run.yml` does the same through its `prepare_cmd`
input, with `secrets_files: terraform/secrets.enc`.

### Why copied, not included or symlinked

- Terragrunt does not support nested includes (DEV-0059), so a spoke file
  cannot `include` this one on a leaf's behalf.
- A leaf's `path_relative_to_include()`, and so its state key, is relative to
  the included file's own directory. A `root.hcl` anywhere but the spoke's root
  would silently shorten every key. DEV-0059 hit exactly that failure.
- The template finds `spoke.hcl` through `get_parent_terragrunt_dir()`, which a
  symlink into the library clone would point at the wrong repo.

## Two pins, deliberately

`/.lib-version` decides which *resolver* runs: `resolve-root-hcl.sh` is on the
`workflows/` track. `root_hcl_version` decides which *template* it writes. That
is the same split as the theme's `.lib-version` versus `theme_version`.
