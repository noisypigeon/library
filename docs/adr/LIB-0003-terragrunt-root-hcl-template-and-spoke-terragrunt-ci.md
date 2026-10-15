# LIB-0003: a versioned `root.hcl` template, and Terragrunt CI a spoke can call

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted.

## Context

LIB-0001 §6 said `root.hcl` should become a versioned template, with a spoke's
copy reduced to the values that genuinely vary. LIB-0002 deferred it because it
only served the Terraform hoist (LIB-0001 §7 step 3), which was blocked on §8.
For `pigeon.dev`, DEV-0163 now unblocks that step by leaving `state/iam` in
`noisypigeon`. So the template is needed now, not eventually.

Checked against `noisypigeon@origin/main`, the three per-domain roots are 5857,
5877 and 8080 bytes.

- **`pigeon.dev/root.hcl` and `noisypigeon.com/root.hcl` differ only in the name
  of the state-bucket secret.** That is
  `PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME` against
  `NOISYPIGEON_COM_TERRAFORM_STATE_BUCKET_NAME`, plus the ADR cited in one
  comment.
- **`willowgraysen.com/root.hcl` adds two things.** A latent Backblaze provider
  that a leaf opts into through `backblaze_config.hcl` (DEV-0148), and a
  `grafana/grafana` provider requirement.

Of the six differences LIB-0001 §3 counted, the other three belonged to the
monorepo's shared `root.hcl`, which no spoke inherits. Those were the `.env.enc`
path, the two-segment leaf check, and the `workloads/` key prefix. In a spoke,
one value varies today.

The hub's Terragrunt CI also could not serve a spoke. `terragrunt-run.yml` masked
secrets by decrypting a hardcoded `.env.enc`, and it had no step to fetch the
library or produce a `root.hcl` before running.

## Decision

### 1. `terragrunt/root-hcl/root.hcl`, tagged `terragrunt/root-hcl/vX.Y.Z`

This is the fourth release track. The template is `pigeon.dev/root.hcl` with
one change: the state-bucket secret name is read from the spoke's `spoke.hcl`
through `read_terragrunt_config("${get_parent_terragrunt_dir()}/spoke.hcl")`.
A missing `spoke.hcl`, or one without `state_bucket_secret`, is a hard error.
Guessing a bucket is how a plan lands in the wrong one.

`template-release.yml` cuts the track when `terragrunt/root-hcl/root.hcl` changes.
The first version is `1.0.0`. It writes the unit's `CHANGELOG.md` and a
`[terragrunt/root-hcl]` root line. The hub's `root-changelog.yml` gained the
matching stand-down arm in the same PR (pigeon-lib#15), so there are now four
duplicated predicates. That is #301's risk, carried forward deliberately.

### 2. Materialized, never included or symlinked

`.github/scripts/resolve-root-hcl.sh` runs from a spoke's root. It reads
`root_hcl_version` from `spoke.hcl` and copies the template to `./root.hcl`,
either at the tag or from the working tree for `"main"`. The spoke gitignores
`/root.hcl`. This is the shape `resolve-theme.sh` already has, and LIB-0001 §6
named it for this reason. Three constraints force it:

- **Terragrunt does not support nested includes (DEV-0059).** A spoke-owned
  `root.hcl` cannot `include` the template on a leaf's behalf.
- **The state key would change.** `path_relative_to_include()` is relative to the
  included file's directory. A `root.hcl` anywhere but the spoke's root would
  shorten every key, which is DEV-0059's "Backend configuration changed".
- **A symlink would point at the wrong repo.** `get_parent_terragrunt_dir()`
  would resolve into the library clone and look for `spoke.hcl` there.

The script lives under `.github/scripts/`, not `terragrunt/root-hcl/`, so the
`workflows/` track versions it. `resolve-theme.sh` sits under `zola-site/`, where
no release predicate covers it, and that gap is not repeated here.

### 3. Spoke-callable Terragrunt CI (`workflows/v1.3.0`)

`terragrunt-run.yml` gained two inputs, and both defaults reproduce its old
behaviour exactly:

- `secrets_files`: the sops files to mask, defaulting to `.env.enc`.
- `prepare_cmd`: a command run before Terragrunt, defaulting to none. A spoke
  passes `./fetch-lib.sh && .lib-src/.github/scripts/resolve-root-hcl.sh`.

`terragrunt-detect.yml` already took `leaf_pattern`.

## Consequences

- **A broken template breaks every spoke that bumps to it, at once.** LIB-0001
  predicted this. The mitigation is invariant 2: each spoke opts in by changing
  `root_hcl_version`, and that bump is a PR whose plan shows the consequence.
- **Two pins govern a spoke's Terraform.** `/.lib-version` picks the resolver and
  `root_hcl_version` picks the template. A template change needs only the
  second; a resolver change needs only the first.
- **Local Terraform work in a spoke needs the library first.** `mise run plan`
  fetches it and resolves `root.hcl` before Terragrunt runs. A fresh clone with
  neither has no `root.hcl` at all, and Terragrunt fails loudly rather than
  finding some other root.
- **The release predicates now live in four places in two files.** #301 is
  unchanged, and this makes it worse by one.

## Out of scope

- **`willowgraysen.com`'s providers.** Genuinely deferred to that spoke's hoist.
  The extension point is additive, so it is a minor bump: an optional
  `extra_required_providers` in `spoke.hcl`, and the latent per-leaf
  `backblaze_config.hcl` lifted from `willowgraysen.com/root.hcl`. It is not
  shipped now because nothing here can plan-verify it.
- **`noisypigeon.com`'s hoist.** Template `v1.0.0` already serves it unchanged;
  the hoist is that spoke's own step.
- **Templating the monorepo's shared `root.hcl`.** Permanent boundary. It serves
  only the `state/iam` leaves left behind under LIB-0001 §8, and it is not a spoke.
- **Fixing #301.** Genuinely deferred; tracked.

## Verification

1. **The resolver, against a scratch library repo.**
   - A pinned version writes the tagged file, and `"main"` writes the working
     tree as a regular file, not a symlink.
   - An unknown version exits 1 with `Unknown tag terragrunt/root-hcl/v9.9.9`.
   - A missing `spoke.hcl` exits 1, and so does running inside the library.
2. **The template, against the root it replaces.**
   - For `pigeon.dev`'s four hoisted leaves (`fastmail/dns`, `project`,
     `state/bucket`, `wiki/dns`), `terragrunt render --format=json` was run under
     the monorepo's `pigeon.dev/root.hcl` and under this template with
     `spoke.hcl`.
   - After normalizing the two trees' absolute paths, the renders have **zero**
     differing keys.
   - The state keys are literally `terraform/<leaf>/terraform.tfstate` in both.
     The renders contain decrypted secrets, so they were compared structurally
     and deleted.
3. **The release.**
   - pigeon-lib#15 cut `workflows/v1.3.0`.
   - This record's PR changes `terragrunt/root-hcl/root.hcl`, so its merge should
     cut `terragrunt/root-hcl/v1.0.0` and write one `[terragrunt/root-hcl]` root
     line, with no second line from `root-changelog.yml`.
