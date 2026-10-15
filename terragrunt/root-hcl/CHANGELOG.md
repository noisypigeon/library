# Changelog

All notable changes to this template are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
