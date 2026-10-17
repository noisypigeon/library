# LIB-0010: spoke secrets have one name each, checked against a schema

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted.
- **Amended 2026-10-17**: LIB-0012 splits the single `secrets.enc` into one
  file per concern under `terraform/secrets/`, superseding §4's single-file
  schema and §3's `ENV_` prefix. §1's names are unchanged.

## Context

Every spoke's `terraform/secrets.enc` holds the same few kinds of value under
different names, and the `root.hcl` template hard-codes whichever name each one
had historically:

- **Provider credentials** are named after the provider's own vocabulary:
  `CLOUDFLARE_TOKEN`, `BACKBLAZE_APPLICATION_KEY_ID`, `SCALEWAY_SECRET_KEY`.
- **State credentials** borrow a provider's name where they happen to be the
  same key. A Scaleway backend reads `SCALEWAY_ACCESS_KEY`, and an R2 backend
  reads `CLOUDFLARE_R2_ACCESS_KEY_ID`.
- **The state bucket's name** has a different key in every spoke:
  `PIGEON_DEV_R2_TERRAFORM_STATE_BUCKET_NAME`,
  `NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME` and
  `WILLOWGRAYSEN_COM_TERRAFORM_STATE_BUCKET_NAME`. `spoke.hcl`'s
  `state_bucket_secret` and two workflow inputs thread that name through.
- **The B2 backup** uses a third style, `TERRAFORM_STATE_BACKUP_B2_KEY_ID`, read
  by `state-backup.yml` through three more inputs.
- **Leaf values** pass through provider-scoped prefixes, `ENV_SW_` and
  `ENV_CF_`. So a leaf's value appears only if its provider happens to be on.

Nothing checks any of this until a leaf plans. A typo, or a key left behind by a
rename, is silent unless it's one of the few the template guards. And sops
itself has no notion of a schema.

## Decision

### 1. One name per value

Each value is read as `get_env(NAME, secrets.enc[NAME])`, as today, so an
environment variable still overrides the file.

| Name | Required when |
| --- | --- |
| `TERRAFORM_STATE_BUCKET_NAME`, `TERRAFORM_STATE_ACCESS_KEY_ID`, `TERRAFORM_STATE_ACCESS_KEY` | always |
| `TERRAFORM_STATE_BACKUP_BUCKET_NAME`, `TERRAFORM_STATE_BACKUP_ACCESS_KEY_ID`, `TERRAFORM_STATE_BACKUP_ACCESS_KEY` | `state_backend = "cloudflare"`; LIB-0007 pairs every R2 bucket with a B2 copy |
| `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, `CLOUDFLARE_PROVIDER_TOKEN` | `providers.cloudflare` is set |
| `SCALEWAY_PROVIDER_ACCESS_KEY_ID`, `SCALEWAY_PROVIDER_ACCESS_KEY`, `SCALEWAY_PROVIDER_ORGANIZATION_ID`, `SCALEWAY_PROVIDER_PROJECT_ID` | `providers.scaleway` is set |
| `BACKBLAZE_PROVIDER_ACCESS_KEY_ID`, `BACKBLAZE_PROVIDER_ACCESS_KEY` | `providers.backblaze` is set |
| `ENV_<NAME>` | optional; see §3 |

- **The state reads only `TERRAFORM_STATE_*`, and providers read only their own
  `<PROVIDER>_PROVIDER_*`.** A Scaleway-backed spoke whose state key is also its
  provider key holds the value twice, once under each name. That's
  willowgraysen's case.
- **The one deliberate overlap:** an R2 backend's endpoint is
  `<account>.eu.r2.cloudflarestorage.com`, built from
  `CLOUDFLARE_PROVIDER_ACCOUNT_ID`. So `state_backend = "cloudflare"` is allowed
  only on a spoke whose `providers` map sets `cloudflare`, and the template
  fails the render otherwise. Only a spoke that runs Cloudflare can keep its
  state there.
- `local.cloudflare_account_id`, `local.scaleway_organization_id` and
  `local.scaleway_project_id` are still generated for the leaves that use them.

### 2. No per-spoke names

`spoke.hcl` loses `state_bucket_secret`, and the template fails the render if a
spoke still sets it. `state-backup.yml` and `terragrunt-run.yml` lose their
`state_bucket_secret` and `backup_*_secret` inputs and read the fixed names.
That breaks their callers, so it's `workflows/v2.0.0`.

### 3. One `ENV_` prefix for leaf values

Any key `ENV_<NAME>` becomes `local.<name>` (lowercased) in every leaf, whatever
its providers, in one generated file. It replaces `ENV_SW_` and `ENV_CF_`. The
local's name doesn't change: `ENV_SW_COCKPIT_LOGS_URL` was `local.cockpit_logs_url`,
and so is `ENV_COCKPIT_LOGS_URL`. Renaming the key needs no leaf change.
`ENV_CF_ZONE_ID_*` goes away altogether (LIB-0011).

### 4. A schema, enforced twice

sops has no schema feature. A sops **dotenv** file does keep its key names in
plaintext, though, and encrypts only values. So the set of keys can be checked
without the age key.

- **The schema is one file,** `terragrunt/root-hcl/secrets-schema.json`. It lists
  the required keys per condition (`always`, `backend.cloudflare` and
  `provider.<name>`) and the pattern every other key must match (`^ENV_[A-Z0-9_]+$`).
  `resolve-root-hcl.sh` copies it beside `root.hcl` as `/secrets-schema.json` at
  the version `spoke.hcl` pins, and the spoke commits both. `--check` fails if
  either drifts.
- **`root.hcl` enforces it at render time.** It decodes the schema and fails, naming
  the key, when a key required by the spoke's backend or providers is missing or
  empty, or when a key matches neither the schema nor the `ENV_` pattern.
  Messages name keys and never print a value.
- **`.github/scripts/check-secrets.sh` enforces it before anything decrypts.** It
  reads the key names out of `terraform/secrets.enc` and the backend and
  providers out of `spoke.hcl`, then checks them against the same JSON. It needs
  no `SOPS_AGE_KEY`, and it runs in each spoke's `prepare_cmd`, after
  `resolve-root-hcl.sh --check`. Locally it's `mise run secrets-check`. A
  leftover old name fails the PR before the first plan.

### 5. Releases and migration

- `terragrunt/root-hcl/v3.0.0` (breaking) carries §1–§4, together with LIB-0011's
  removal of `ENV_CF_ZONE_ID_*`.
- `workflows/v2.0.0` carries §2.
- The restore runbook uses the new names.
- Each spoke then moves in one PR. Its keys are renamed in `secrets.enc` first,
  by hand with `mise run secrets-edit`, and the PR bumps `root_hcl_version`,
  the workflow pins and `prepare_cmd`. Values don't change, so every leaf must
  plan `No changes.`

## Consequences

- **Any spoke's `secrets.enc` reads the same,** and what a spoke needs follows
  from its `spoke.hcl`.
- **A rename can't leave a key behind silently.** The unknown-key check catches it
  in CI, and again at render time.
- **willowgraysen holds its Scaleway key twice,** once for state and once for the
  provider. That's the price of never borrowing.
- **R2 state needs the Cloudflare provider on.** No spoke wants one without the
  other today.

## Out of scope

Permanent boundaries, with no issue:

- **Schema enforcement inside sops itself.** sops can't do it. The plaintext key
  names make the CI check enough.
- **Secrets that leaves define for themselves,** such as `local.grafana_auth_token`
  (ADR-0135). They're leaf code, not spoke configuration.

## Verification

1. **The release** (#59) cut `terragrunt/root-hcl/v3.0.0` and `workflows/v2.0.0`.
   Before merging, all 34 leaves in the three spokes were rendered under v2.2.1
   and v3.0.0, using fake values under the new names, encrypted to a throwaway
   age key. The backend config, inputs and provider files were byte-identical.
   The only differences were the dropped zone-ID locals and the `ENV_` locals'
   new file, whose contents matched v2's `ENV_SW_` set exactly.
2. **The guards.** Each one fired on its case: a missing key, an unknown key, a
   leftover `state_bucket_secret`, and a `cloudflare` backend without the
   provider. Each message named the key and no value. `check-secrets.sh` passed
   on the renamed copies and failed on all three spokes' unrenamed files, with no
   `SOPS_AGE_KEY` and no sops installed.
3. **garden** (noisypigeon/garden#47). `check-secrets.sh` passed on 10 keys, and
   CI planned and applied `No changes.` on 4/4 leaves. The post-apply backup
   copied to B2 under the new names.
4. **blog** (noisypigeon/blog#38, with LIB-0011 §4). `check-secrets.sh` passed on
   10 keys, and CI planned `No changes.` on 14 units, the removed redirect leaves
   included. The apply was a no-op, and the backup succeeded.
5. **willowgraysen** (noisypigeon/willowgraysen#16) passed `check-secrets.sh` on
   27 keys, and its 18 `ENV_SW_` keys became `ENV_` with no leaf change.
   - The first plan failed on every leaf, correctly. The bucket name and state
     keys had gone into `TERRAFORM_STATE_BACKUP_*`, leaving `TERRAFORM_STATE_*`
     empty. The render guard named the three empty keys and printed no value.
   - Once the values were moved, CI ran 18/18 units `No changes.`, and the apply
     was a no-op.
   - That mistake shows a gap in `check-secrets.sh`. It can't see an empty value,
     and it allows a schema key whose condition doesn't apply. Here that was
     `TERRAFORM_STATE_BACKUP_*` on a Scaleway backend. The render guard caught
     the first, and nothing flags the second.
6. **The sweep.** Afterwards, no spoke's `secrets.enc` key names, `spoke.hcl` or
   workflows used an old name. noisypigeon/garden#48 and noisypigeon/blog#39
   updated the output descriptions that still named the old keys.
