# LIB-0012: spoke secrets are one sops file per concern

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-17.
- **Status**: Accepted.

## Context

LIB-0010 gave every spoke secret one fixed name, required according to
`spoke.hcl`, and enforced by `secrets-schema.json` in `root.hcl` and in
`check-secrets.sh`. Every spoke still keeps all of them in one
`terraform/secrets.enc`, though, and three things follow:

- **Every leaf decrypts every secret.** A Grafana dashboard leaf decrypts the
  Backblaze keys, and every leaf decrypts the state backup's key, which only
  `state-backup.yml` uses.
- **One file blurs which concern a key belongs to.** The schema allows any key it
  lists anywhere. willowgraysen's state values went under
  `TERRAFORM_STATE_BACKUP_*`, which a Scaleway backend doesn't use, and
  `check-secrets.sh` passed. Only the render guard's "empty value" check caught
  the empty `TERRAFORM_STATE_*` keys (LIB-0010 Verification 5).
- **Editing one provider's key means opening all of them.** `mise run
  secrets-edit` decrypts the whole file.

## Decision

### 1. The files, and exactly what each holds

Each is a sops dotenv file under `terraform/secrets/`:

| File | Required when | Keys, exactly |
| --- | --- | --- |
| `terraform.enc` | always | `TERRAFORM_STATE_BUCKET_NAME`, `TERRAFORM_STATE_ACCESS_KEY_ID`, `TERRAFORM_STATE_ACCESS_KEY`; and `TERRAFORM_STATE_BACKUP_{BUCKET_NAME,ACCESS_KEY_ID,ACCESS_KEY}` if and only if `state_backup = true` |
| `cloudflare.enc` | `providers.cloudflare` is set | `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, `CLOUDFLARE_PROVIDER_TOKEN` |
| `scaleway.enc` | `providers.scaleway` is set | `SCALEWAY_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY,ORGANIZATION_ID,PROJECT_ID}` |
| `backblaze.enc` | `providers.backblaze` is set | `BACKBLAZE_PROVIDER_ACCESS_KEY_ID`, `BACKBLAZE_PROVIDER_ACCESS_KEY` |
| `env.enc` | optional | any key matching `^[A-Z][A-Z0-9_]*$` |

- **A required file must exist, and hold exactly its keys, each non-empty.** A key
  that isn't its file's own is an error. That covers a backup key in
  `terraform.enc` while `state_backup` is off, and a Cloudflare key in
  `scaleway.enc`.
- **A file whose condition doesn't hold is ignored.** It's neither required nor
  decrypted, so a spoke can keep a disabled provider's file without it being read.
- **`env.enc` is open-ended.** Each key `FOO_BAR` becomes `local.foo_bar` in every
  leaf. The file is the namespace, so LIB-0010 §3's `ENV_` prefix goes. A key
  whose local would shadow a generated one is an error: `cloudflare_zone`,
  `cloudflare_account_id`, `scaleway_organization_id`, `scaleway_project_id` and
  `grafana_auth_token`.
- **Grafana has no file.** Its token is a leaf local (ADR-0135).

### 2. `spoke.hcl` says whether the state is backed up

`state_backup = true` turns on the B2 copy. It requires the backup keys in
`terraform.enc`, and it's what `state-backup.yml` checks before it runs. It
defaults to `false`.

The template's guards:
- **`state_backend = "cloudflare"` requires `state_backup = true`,** because R2
  can't version objects (LIB-0007).
- **It still requires `providers.cloudflare`,** because the R2 endpoint is built
  from `CLOUDFLARE_PROVIDER_ACCOUNT_ID` in `cloudflare.enc` (LIB-0010 §1). The
  state backend is the one place that reads a provider's file.

garden and blog set it, and willowgraysen's Scaleway state, versioned in place,
doesn't.

### 3. A leaf decrypts only what it needs

`root.hcl` decrypts in memory, with `run_cmd sops` as before:

- `terraform.enc`, always;
- `cloudflare.enc`, when the backend is `cloudflare`;
- each provider's file, when that provider is on **for this leaf**, honouring
  `leaves` scoping (LIB-0005);
- `env.enc`, when it exists.

So willowgraysen's Grafana leaf reads `terraform.enc`, `scaleway.enc` and
`env.enc`, never `backblaze.enc`. An environment variable still overrides any key
(`get_env`), as LIB-0010 §1 kept.

### 4. One schema, enforced twice

- **`secrets-schema.json` is organised by file:** each file's condition, its keys,
  and its conditional keys, plus `env`'s pattern and reserved names.
  `resolve-root-hcl.sh` still copies it beside `root.hcl`, and `--check` still
  covers it.
- **`root.hcl` enforces it per leaf,** for the files it decrypts. A missing file, a
  missing or empty key, a key outside its file, or a reserved env name fails the
  render, naming the file and key and never a value.
- **`check-secrets.sh` enforces it spoke-wide,** from plaintext key names and with
  no age key. Every required file must be present, and each file present must
  hold exactly its own keys. An ignored file is reported, not failed. It runs in
  `prepare_cmd`, as LIB-0010 §4 set up.

### 5. Tooling

- **`.sops.yaml`** has one rule, `path_regex: ^terraform/secrets/[a-z]+\.enc$`,
  with the spoke's existing recipient.
- **`mise run secrets-edit <file>`** edits one file, for example
  `mise run secrets-edit cloudflare`.
- **`.github/scripts/split-secrets.sh`** is a one-time migration helper that each
  spoke's owner runs. It turns a v3 `terraform/secrets.enc` into the v4 files:
  - it pipes `sops -d` through a filter into `sops -e`, so it writes only
    ciphertext and never prints a value;
  - it strips `ENV_` for `env.enc`;
  - it finishes by running `check-secrets.sh`.

  It ships in the hub so every spoke migrates the same way.
- **`terragrunt-run.yml` and `state-backup.yml`** default `secrets_files` to the
  `terraform/secrets/*.enc` that exist, for masking in CI. `state-backup.yml`
  reads `terraform.enc` and `cloudflare.enc` only, and does nothing unless
  `state_backup = true`. `terragrunt-detect.yml`'s leaf pattern covers
  `terraform/secrets/`.

### 6. Release and migration

`terragrunt/root-hcl/v4.0.0` and `workflows/v3.0.0`, both breaking. Each spoke
then moves in one PR, garden first, then blog, then willowgraysen:

1. **The owner** runs `split-secrets.sh`.
2. **The PR:**
   - deletes `terraform/secrets.enc` and adds `terraform/secrets/*.enc`;
   - updates `.sops.yaml` and the mise task;
   - sets `root_hcl_version = "4.0.0"`, plus `state_backup = true` where the
     backend is R2;
   - moves the pins.

No value changes, so every leaf must plan `No changes.`

This supersedes LIB-0010 §4's single-file schema and §3's `ENV_` prefix.
LIB-0010's names are unchanged.

## Consequences

- **A leaf holds only the secrets it uses,** and an editor opens only the concern
  being changed.
- **A value can't sit in the wrong place unnoticed.** Each file has a closed set of
  keys, so willowgraysen's mistake now fails the CI key check before any render.
- **Adding a provider means a file,** and the contract says which keys it holds.
- **A spoke has up to five secrets files** instead of one. They're small, and each
  one is about a single thing.

## Out of scope

Permanent boundaries, with no issue:

- **Different sops recipients or age keys per file.** The layout allows them, so a
  provider's file could be readable by fewer people than the state's. This record
  keeps one recipient for all of them.
- **Validating values,** beyond the render guard's check that they aren't empty. A
  key's format is the provider's business.

## Verification

Recorded as §6 lands.
