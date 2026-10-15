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

A spoke commits a `spoke.hcl` at its repo root:

```hcl
locals {
  # Template version to materialize: "X.Y.Z", or "main" for the working tree.
  root_hcl_version = "1.0.0"

  # secrets.enc key (or environment variable) naming the spoke's state bucket.
  state_bucket_secret = "PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME"
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

### Optional extensions (v1.1.0)

Both are off unless `spoke.hcl` sets them, and a spoke that sets neither renders
exactly as it did on `v1.0.x`.

```hcl
locals {
  # ...
  # Appended to the single required_providers block. A provider's own
  # configuration, if it needs one, lives in the leaf that uses it.
  extra_required_providers = {
    grafana = { source = "grafana/grafana", version = "~> 4.0" }
  }

  # DEV-0148's latent Backblaze B2 provider. Still inert for any leaf that does
  # not drop a sibling backblaze_config.hcl with `enabled = true`; those that do
  # get the b2 provider, configured from BACKBLAZE_APPLICATION_KEY{,_ID}.
  backblaze = true
}
```

`willowgraysen.com` uses both (RUN-0001).

## Two pins, deliberately

`/.lib-version` decides which *resolver* runs: `resolve-root-hcl.sh` is on the
`workflows/` track. `root_hcl_version` decides which *template* it writes. That
is the same split as the theme's `.lib-version` versus `theme_version`.
