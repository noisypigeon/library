# Changelog

All notable changes to this template are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] - 2026-10-15

### A latent Scaleway Cockpit Grafana provider in the root.hcl template

`terragrunt/root-hcl` gains a latent Grafana provider, shaped like the Backblaze one. A leaf that manages Grafana dashboards then needs no provider block or data source of its own, and can be a single module call, as [LIB-0004](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0004-normalized-terraform-leaf-layout.md) requires.

### How a leaf opts in

1. `grafana = true` in the spoke's `spoke.hcl`.
2. A sibling `grafana_config.hcl` with `enabled = true` in each leaf that uses it.

### What an enabled leaf gets

- **`grafana/grafana ~> 4.0`** in its `required_providers`.
- **A generated `data "scaleway_cockpit_grafana" "grafana"`** for the project's Grafana URL.
- **A generated `provider "grafana"`**, authenticated with **`local.grafana_auth_token`**. The leaf must define that local: the IAM API key secret, usually passed in from another leaf's output.

A leaf in a Grafana-enabled spoke that hasn't opted in gets a comment-only file. A spoke without `grafana = true` gets nothing.

### Verified

I rendered every leaf of all three spokes (24 leaves) under its current `root.hcl` and under this template. The only differences are added generate entries with `disable: true`, which write no file. State keys are unchanged everywhere. LIB-0003 records this as its third amendment.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#32](https://github.com/noisypigeon/pigeon-lib/pull/32)

## [1.1.0] - 2026-10-15

### Optional extra providers and Backblaze support in the root.hcl template

The `root.hcl` template gains two optional `spoke.hcl` settings, which `willowgraysen.com` needs before its Terraform can move into its own repo. Both are off by default, and a spoke that sets neither gets no new file.

### `extra_required_providers`

A map of `{ source, version }` entries, appended to the one `required_providers` block:

```hcl
extra_required_providers = {
  grafana = { source = "grafana/grafana", version = "~> 4.0" }
}
```

A provider's own configuration, if it needs one, still lives in the leaf that uses it.

### `backblaze = true`

This turns on the latent Backblaze B2 provider from DEV-0148, unchanged in behaviour:

- A leaf opts in by dropping a sibling `backblaze_config.hcl` with `enabled = true`. It then gets the `b2` required-provider entry and a `provider "b2"` block configured from `BACKBLAZE_APPLICATION_KEY_ID` and `BACKBLAZE_APPLICATION_KEY`.
- Other leaves in that spoke get a comment-only `provider_backblaze_generated.tf`.
- In a spoke without `backblaze = true`, that generate block is disabled, so the file is never written.

### Verified with `terragrunt render --format=json`

- **`willowgraysen.com`'s 14 hoistable leaves:** compared against their current root, each differs in one key, the generated provider file, and only in whitespace. The original root left a blank indented line where the Backblaze entry would go. State keys are equal.
- **`pigeon.dev`'s 4 leaves and `noisypigeon.com`'s 6:** compared against `v1.0.1`, each differs only by the disabled Backblaze generate block (`disable: true`, `if_disabled: skip`), which writes nothing.

[LIB-0003](docs/adr/LIB-0003-terragrunt-root-hcl-template-and-spoke-terragrunt-ci.md) records this as its second amendment.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#21](https://github.com/noisypigeon/pigeon-lib/pull/21)

## [1.0.1] - 2026-10-15

### Mark the root.hcl template as generated and committed in spokes

Only the template's header comment changes. The configuration it produces is identical to `v1.0.0`.

The header used to say a spoke never commits `root.hcl`. Spokes now must commit it. Terragrunt's `[main...HEAD]` git filter plans inside git worktrees that contain only tracked files, so a gitignored copy made every leaf fail with `Could not find a root.hcl`. The header is what a spoke commits, so it now reads "GENERATED in a spoke -- do not edit there". It says how to change the template (change it in `pigeon-lib`, then bump `root_hcl_version`), and that CI runs `resolve-root-hcl.sh --check` against it. The `--check` mode shipped in `workflows/v1.3.1`.

Also updated:

- the template's `README.md`: consumption steps and the reasons for committing;
- the hub's `CLAUDE.md`;
- the root `CHANGELOG.md` header, which now lists the `terragrunt/root-hcl` and `terragrunt` tags;
- [LIB-0003](docs/adr/LIB-0003-terragrunt-root-hcl-template-and-spoke-terragrunt-ci.md): a dated `## Amendments` section recording the dry run that failed and the one that passed. Its date is also corrected to 2026-10-15.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#18](https://github.com/noisypigeon/pigeon-lib/pull/18)

## [1.0.0] - 2026-10-15

### Add the spokes' Terragrunt root.hcl template

The first version of `terragrunt/root-hcl/root.hcl`: the Terragrunt root every spoke in this family will share, replacing the per-domain `root.hcl` copies in `noisypigeon/noisypigeon`. Recorded in [LIB-0003](docs/adr/LIB-0003-terragrunt-root-hcl-template-and-spoke-terragrunt-ci.md).

### What it does

For every leaf under a spoke's `terraform/`, it:

- decrypts `terraform/secrets.enc` in memory with sops/age, and exposes `ENV_SW_*`/`ENV_CF_*` keys as locals;
- generates the Cloudflare and Scaleway providers, honouring a leaf's optional `scaleway_config.hcl`;
- excludes anything outside `terraform/`;
- keeps state in the spoke's own bucket at `terraform/<leaf>/terraform.tfstate`. That is byte-identical to the per-domain roots, so adopting the template moves no state.

### Consuming it

A spoke never commits `root.hcl`. It commits a `spoke.hcl`:

```hcl
locals {
  root_hcl_version    = "1.0.0"
  state_bucket_secret = "PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME"
}
```

It gitignores `/root.hcl` and runs `.lib-src/.github/scripts/resolve-root-hcl.sh` (shipped in `workflows/v1.3.0`) from its repo root before Terragrunt. The script copies the template at the pinned version. A missing `spoke.hcl`, or a missing `state_bucket_secret`, stops the run instead of guessing a bucket. See [`terragrunt/root-hcl/README.md`](terragrunt/root-hcl/README.md) for why the template is copied rather than included or symlinked.

### Verified against the root it replaces

I rendered `pigeon.dev`'s four hoistable leaves with `terragrunt render --format=json`, once under the monorepo's `pigeon.dev/root.hcl` and once under this template. After normalizing the two trees' absolute paths, the renders differ in **zero** keys, including all four `generate` blocks and the backend. The state keys are literally the same in both.

The hub's `CLAUDE.md`, `README.md` and `release-pr` skill now list four release tracks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#16](https://github.com/noisypigeon/pigeon-lib/pull/16)
