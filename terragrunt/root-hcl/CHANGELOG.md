# Changelog

All notable changes to this template are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [3.0.0] - 2026-10-16

### Fixed secret names checked against a schema (root.hcl v3, workflows v2)

Every spoke secret now has one fixed name, the same in every spoke, and which names a spoke needs follows from its `spoke.hcl` (LIB-0010). This is a breaking release of both the `root.hcl` template and the reusable workflows. Spokes move one PR each, renaming their `secrets.enc` keys; values don't change, so every leaf should plan `No changes.`

**`root.hcl` v3.0.0**

- **Fixed names.** Secrets are read by fixed names with `get_env(NAME, secrets.enc[NAME])`.
  - State: `TERRAFORM_STATE_{BUCKET_NAME,ACCESS_KEY_ID,ACCESS_KEY}`, for both backends.
  - B2 backup: `TERRAFORM_STATE_BACKUP_*`.
  - Providers: `CLOUDFLARE_PROVIDER_{ACCOUNT_ID,TOKEN}`, `SCALEWAY_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY,ORGANIZATION_ID,PROJECT_ID}` and `BACKBLAZE_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY}`.
  - State never borrows a provider's key. A Scaleway-backed spoke holds its key under both names.
- **The schema.** `secrets-schema.json` lists the required keys per condition (`always`, `backend.cloudflare`, `provider.<name>`) and the allowed `^ENV_[A-Z0-9_]+$` pattern. The template reads it from beside itself. It fails the render, naming the key and never its value, when a required key is missing or empty, or when `secrets.enc` holds a key outside the schema.
- **`spoke.hcl` changes.** `state_bucket_secret` is gone, and the template fails if a spoke still sets it. `state_backend = "cloudflare"` now requires `providers.cloudflare`, because the R2 endpoint is built from `CLOUDFLARE_PROVIDER_ACCOUNT_ID`.
- **One `ENV_` prefix.** `ENV_<NAME>` becomes `local.<name>` in every leaf, whatever its providers, in `env_secrets_generated.tf`. It replaces `ENV_SW_`/`ENV_CF_`, and the locals keep their names. `env_scaleway_secrets_generated.tf` is still written, as a comment, so a stale copy can't define the same locals twice.
- **No zone IDs.** `ENV_CF_ZONE_ID_*`, `local.cloudflare_zone_id` and its guard are removed. Zone leaves keep `local.cloudflare_zone`, and `cloudflare/dns-record` v1 looks the zone up by apex (LIB-0011).
- **Unchanged locals.** `local.cloudflare_account_id`, `local.scaleway_organization_id` and `local.scaleway_project_id` are still generated.

**`workflows/` v2.0.0**

- **`state-backup.yml` takes no name inputs.** Its `state_bucket_secret`, `backup_bucket_secret`, `backup_key_id_secret` and `backup_key_secret` inputs are gone. It reads `TERRAFORM_STATE_*` and `TERRAFORM_STATE_BACKUP_*`, and builds the R2 endpoint from `CLOUDFLARE_PROVIDER_ACCOUNT_ID`. Delete those inputs from its callers. `terragrunt-run.yml` never had them, so it's unchanged.
- **`resolve-root-hcl.sh` copies the schema too.** It writes `secrets-schema.json` beside `root.hcl` at the pinned version, and `--check` verifies both files. For a version before v3.0.0 it removes a stale copy.
- **New `check-secrets.sh`.** It reads the key names from `terraform/secrets.enc` without decrypting (sops dotenv keeps them in plaintext), and `state_backend` and `providers` from `spoke.hcl`. It exits 1 listing missing and unknown keys. It needs no `SOPS_AGE_KEY`. Spokes append it to `prepare_cmd`: `… resolve-root-hcl.sh --check && .lib-src/.github/scripts/check-secrets.sh`.
- **Wider release predicate.** A change to `terragrunt/root-hcl/secrets-schema.json` now releases the template, in `template-release.yml` and its twin in `root-changelog.yml`.

**Migrating a spoke.** `terragrunt/root-hcl/README.md` has the old-to-new key map and the steps:

1. Rename the keys.
2. Delete `state_bucket_secret`.
3. Set `root_hcl_version = "3.0.0"`, with `/.lib-version` at `workflows/v2.0.0` or later, and commit both generated files.
4. Pin `@workflows/v2.0.0` and add `check-secrets.sh` to `prepare_cmd`.

The B2 restore runbook uses the new names.

**Verified against all three spokes.** garden, blog and willowgraysen were copied to a scratch dir, with fake values under the real key names.

- **Parity.** All 34 leaves rendered under v2.2.1 (old names) and v3 (new names). `remote_state`, inputs and every provider file are byte-identical. The only differences are the dropped zone-ID locals, the `env_scaleway_secrets` comment, and the new `env_secrets_generated.tf`, whose locals match v2's `ENV_SW_` set exactly.
- **Guards.** Each fires on its case: a missing key, an empty key, unknown keys (`CLOUDFLARE_TOKEN`, `ENV_lower`), R2 without the Cloudflare provider, and a leftover `state_bucket_secret`. A missing key supplied through the environment passes.
- **`check-secrets.sh`.** It passes on each renamed copy and fails on each real `secrets.enc` as it stands today. It ran with no age key and no sops on `PATH`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#59](https://github.com/noisypigeon/pigeon-lib/pull/59)

## [2.2.1] - 2026-10-16

### Drop pigeon.dev from comments and docs

Comments and docs across the hub now describe the current architecture only. `pigeon.dev` is gone from them: the site repo is `noisypigeon/garden`, and module sources are `https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z`.

- **`terragrunt/root-hcl`:** the template's header drops how it was generalized from the monorepo's per-domain roots, and its example secret is a real current one. Only comments change, so every leaf renders exactly as it did under v2.2.0, and a spoke can take this version as a no-op.
- **`scaleway/project`:** the header comment drops the module's relocation history. No inputs, outputs or resources change.
- **`generate-module-redirects.sh`:** a comment change only.
- **Docs:** `CLAUDE.md`, `terraform/README.md`, `terragrunt/root-hcl/README.md`, `zola-site/README.md` and the `release-pr` skill name `noisypigeon/garden` and the current host, without the pigeon.dev history.
- **LIB-0009** gets an amendment line. `pigeon.dev` redirects to `https://noisypigeon.com`, not the garden (noisypigeon/noisypigeon.com#33).

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#55](https://github.com/noisypigeon/pigeon-lib/pull/55)

## [2.2.0] - 2026-10-16

### Zone leaves at terraform/cloudflare/<zone>/<module>/<instance>/, with their zone ID from the template (LIB-0008)

A spoke's Cloudflare leaves that write to a zone can now say which zone in their path, and `root.hcl` hands them that zone's ID ([LIB-0008](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0008-cloudflare-zone-leaves.md)).

### The layout

A leaf calling a zone-scoped Cloudflare module (`cloudflare/dns-record` or `cloudflare/ruleset`) lives at `terraform/cloudflare/<zone>/<module>/<instance>/`, for example `terraform/cloudflare/noisypigeon.com/dns-record/proton`. `<zone>` is the zone's apex domain.

- The module's short URL doesn't change.
- Account-level modules such as `cloudflare/bucket` keep `terraform/cloudflare/<module>/<instance>/`.
- This is the one exception to LIB-0004's three segments, and LIB-0004 carries an amendment line saying so.

### What the template adds

A zone leaf now gets two locals:
- `local.cloudflare_zone`, the zone's apex domain;
- `local.cloudflare_zone_id`, read from `ENV_CF_ZONE_ID_<ZONE>` in `secrets.enc` (`noisypigeon.com` → `ENV_CF_ZONE_ID_NOISYPIGEON_COM`).

Write `zone_id = local.cloudflare_zone_id` in the leaf. If the secret is missing, the run fails with a message naming the expected key, instead of planning records into the wrong zone.

**Nothing changes until a leaf moves.** The existing `local.zone_id_<zone>` locals still render, and every non-zone leaf's generated files are byte-identical to v2.1.0's.

### Moving a leaf on R2

LIB-0008 §3 updates LIB-0004's state-move runbook for the R2 backend: copy the state object to the new key byte for byte, check serial and lineage, plan, then `state rm` the old key. `terraform state push` into an empty R2 key adopts a new lineage (COM-0004).

The module READMEs now say which modules are zone-scoped (`dns-record`, `ruleset`) and which are account-level (`bucket`). noisypigeon.com adopts first. The redirector moves and noisypigeon.garden are tracked in noisypigeon/noisypigeon#320, #321 and #322.

Verified by rendering all 32 leaves across the three spokes under v2.1.0 and this template: everything apart from `locals` hashed identically. A zone leaf rendered the right zone and ID, and a zone with no secret failed with the expected message.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#47](https://github.com/noisypigeon/pigeon-lib/pull/47)

## [2.1.0] - 2026-10-15

### State backend selectable in spoke.hcl: Scaleway or Cloudflare R2 (LIB-0007)

`root.hcl` can now keep a spoke's Terraform state in Cloudflare R2 as well as in Scaleway Object Storage. [LIB-0007](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0007-terraform-state-on-r2-with-offsite-backup.md) records why and how.

### `state_backend` in `spoke.hcl`

```hcl
locals {
  root_hcl_version    = "2.1.0"
  state_bucket_secret = "NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME"
  state_backend       = "cloudflare"   # or "scaleway", the default
}
```

- **Leave it out and nothing changes.** `"scaleway"` is the default, and a spoke that doesn't set it renders exactly what v2.0.0 rendered.
- **`"cloudflare"`** points the S3 backend at the account's EU-jurisdiction R2 endpoint, `https://<account_id>.eu.r2.cloudflarestorage.com` (LIB-0006), with `region = "auto"`, path-style addressing and `skip_s3_checksum`. It also tells Terragrunt not to enable versioning on, or otherwise update, the bucket: R2 has no object versioning.
- **Any other value fails the run** with a message naming the known ones.

The state key is `terraform/<leaf>/terraform.tfstate` on either backend. Moving a spoke between them copies objects; it changes no keys.

### R2 credentials

Cloudflare has no Terraform resource for R2's S3 keys. Create an R2 API token with *Object Read & Write*, scoped to the state bucket, in the dashboard. Store its keys in the spoke's `secrets.enc` as `CLOUDFLARE_R2_ACCESS_KEY_ID` and `CLOUDFLARE_R2_SECRET_ACCESS_KEY`. The account ID is the existing `CLOUDFLARE_ACCOUNT_ID`.

### Offsite backup

Because R2 can't version, LIB-0007 also pairs an R2 state bucket with a versioned Backblaze B2 copy, made by the reusable `state-backup.yml` workflow. That ships in its own PR as `workflows/v1.4.0`.

Verified by rendering every `pigeon.dev` leaf under v2.0.0 and under this template. With no `state_backend`, everything apart from `locals` hashed identically. The `"cloudflare"` render and the guard were checked too.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#39](https://github.com/noisypigeon/pigeon-lib/pull/39)

## [2.0.0] - 2026-10-15

### Providers enabled and configured in spoke.hcl (LIB-0005)

`terragrunt/root-hcl` v2.0.0 makes a spoke's `spoke.hcl` the one place that turns providers on and configures them. Recorded in [LIB-0005](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0005-providers-configured-in-spoke-hcl.md).

### The `providers` map

```hcl
providers = {
  cloudflare = {}
  scaleway   = { region = "fr-par", zone = "fr-par-1" }
  backblaze  = { leaves = ["terraform/backblaze/bucket/"] }
  grafana    = { leaves = ["terraform/grafana/dashboard/"] }
}
```

- **Required.** A provider not in the map is off for every leaf.
- **`leaves` is optional.** It takes path prefixes, each ending in `/`, and limits the provider to leaves under them. Under LIB-0004's layout that's usually `terraform/<provider>/<module>/`.
- **Scaleway's `region`/`zone`** move here from the old per-leaf `scaleway_config.hcl`. The defaults are unchanged.
- **Grafana keeps its contract.** An enabled leaf defines `local.grafana_auth_token`. It needs Scaleway on for the same leaf.

### Breaking changes

- **`backblaze = true` and `grafana = true` in `spoke.hcl` are now an error.**
- **`scaleway_config.hcl`, `backblaze_config.hcl` and `grafana_config.hcl` are no longer read.**
- **Each provider gets its own `provider_<name>_generated.tf`.** The one `required_providers` block stays in `provider_generated.tf` and lists only the providers the leaf gets. A provider that's off for a leaf leaves a one-line comment file, so it overwrites any stale v1 file in `.terragrunt-cache`.

The template also fails loudly on:

- an unknown provider key;
- a prefix without its trailing slash;
- Grafana without Scaleway.

The state backend and state keys don't change.

### Migrating a spoke

1. Add `providers`, with `cloudflare = {}` and `scaleway = {}` for v1's defaults.
2. Turn any `backblaze`/`grafana` bool into an entry whose `leaves` covers the leaves that had a `*_config.hcl`.
3. Delete those files.
4. Bump `root_hcl_version` to `"2.0.0"` and regenerate `root.hcl`.

### Verified against all three spokes

All 30 leaves (`pigeon.dev` 4, `noisypigeon.com` 6, `willowgraysen.com` 20) were checked with exactly that migration applied temporarily:

- **Renders:** identical to their current `root.hcl` (v1.0.1, v1.0.1, v1.2.0) in every key and in every non-comment generated line, state keys included.
- **Plans:** `No changes.` on every leaf.

Each new guard was also checked: it fails the render with its own message.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#36](https://github.com/noisypigeon/pigeon-lib/pull/36)

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
