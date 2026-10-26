# `terragrunt/root-hcl`

The Terragrunt `root.hcl` every spoke in this family shares, versioned as
`terragrunt/root-hcl/vX.Y.Z` (LIB-0001 §6, LIB-0003). Everything a spoke varies
lives in its `spoke.hcl`; everything else is this one template.

## What it does

For every leaf under a spoke's `terraform/`, and every workload leaf under its
`workloads/` (v4.3.0, LIB-0023):

- decrypts, in memory with sops/age (no plaintext on disk), only the
  `terraform/secrets/<concern>.enc` files that leaf needs, checks their keys
  against `secrets-schema.json`, and exposes every `env.enc` key as a local
  (LIB-0010, LIB-0012);
- generates the providers `spoke.hcl`'s `providers` map turns on for that leaf
  (Cloudflare, Scaleway, Backblaze B2, Scaleway Cockpit Grafana; LIB-0005);
- excludes anything else;
- keeps state in the spoke's own bucket, on Scaleway or R2 (`state_backend`,
  LIB-0007), at `<leaf>/terraform.tfstate`.

That key carries no prefix, so it is byte-identical to what the per-domain roots
in `noisypigeon/noisypigeon` produced. Hoisting a leaf into a spoke therefore
moves no state (LIB-0001 invariant 4).

## Consuming it

A spoke commits a `spoke.hcl` at its repo root:

```hcl
locals {
  # Template version to materialize: "X.Y.Z", or "main" for the working tree.
  root_hcl_version = "4.0.0"

  # Where state lives (LIB-0007): "scaleway" (the default) or "cloudflare".
  state_backend = "cloudflare"

  # Whether state-backup.yml copies the state to B2 (v4.0.0, LIB-0012). The
  # default is false; a cloudflare backend requires true.
  state_backup = true

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
./fetch-lib.sh                                   # library at /.lib-version
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
check through its `prepare_cmd` input. From `workflows/v3.0.0` it masks every
`terraform/secrets/*.enc` by default, so a spoke passes no `secrets_files`:

```yaml
prepare_cmd: ./fetch-lib.sh && .lib-src/.github/scripts/resolve-root-hcl.sh --check && .lib-src/.github/scripts/check-secrets.sh
```

Locally, the same check is a mise task:

```toml
[tasks.secrets-check]
run = ["./fetch-lib.sh", ".lib-src/.github/scripts/check-secrets.sh"]
```

## Secrets (v4.0.0, LIB-0012)

Every value has one fixed name, the same in every spoke (LIB-0010), and lives in
the one sops dotenv file for its concern, under the spoke's
`terraform/secrets/`. Which files a spoke needs follows from `spoke.hcl`:

| File | Required when | Keys, exactly | Feeds |
| --- | --- | --- | --- |
| `terraform.enc` | always | `TERRAFORM_STATE_BUCKET_NAME`, `TERRAFORM_STATE_ACCESS_KEY_ID`, `TERRAFORM_STATE_ACCESS_KEY`; plus `TERRAFORM_STATE_BACKUP_BUCKET_NAME`, `TERRAFORM_STATE_BACKUP_ACCESS_KEY_ID`, `TERRAFORM_STATE_BACKUP_ACCESS_KEY` if and only if `state_backup = true` | the state backend, either one; `state-backup.yml`'s B2 copy (LIB-0007) |
| `cloudflare.enc` | `providers.cloudflare` is set | `CLOUDFLARE_PROVIDER_ACCOUNT_ID`, `CLOUDFLARE_PROVIDER_TOKEN` | `provider "cloudflare"`, `local.cloudflare_account_id`, and the R2 endpoint |
| `scaleway.enc` | `providers.scaleway` is set | `SCALEWAY_PROVIDER_ACCESS_KEY_ID`, `SCALEWAY_PROVIDER_ACCESS_KEY`, `SCALEWAY_PROVIDER_ORGANIZATION_ID`, `SCALEWAY_PROVIDER_PROJECT_ID` | `provider "scaleway"`, `local.scaleway_organization_id` and `local.scaleway_project_id` |
| `backblaze.enc` | `providers.backblaze` is set | `BACKBLAZE_PROVIDER_ACCESS_KEY_ID`, `BACKBLAZE_PROVIDER_ACCESS_KEY` | `provider "b2"` |
| `env.enc` | optional | any key matching `^[A-Z][A-Z0-9_]*$` | `local.<lowercased key>` in every leaf |

The contract:

- **A required file must exist, and hold exactly its keys, each non-empty.** A
  key that isn't its file's own is an error: a Cloudflare key in
  `scaleway.enc`, or a backup key in `terraform.enc` while `state_backup` is
  off. A provider's file is required as soon as the provider is in the
  `providers` map, however its `leaves` scope it.
- **A file whose condition doesn't hold is ignored.** It's neither required nor
  decrypted, so a spoke can keep a disabled provider's file.
- **`env.enc` is open-ended.** `COCKPIT_LOGS_URL` becomes
  `local.cockpit_logs_url`, in every leaf whatever its providers, all in
  `env_secrets_generated.tf`. The file is the namespace, so v3's `ENV_` prefix
  is gone. A key is an error if its local would shadow a generated one
  (`cloudflare_account_id`, `cloudflare_zone`, `scaleway_organization_id`,
  `scaleway_project_id`, `scaleway_s3_provider_name`, `grafana_auth_token`), or
  if another file owns that name, which would put a provider's value in the
  wrong file.
- **Grafana has no file.** Its token is a leaf local (ADR-0135).
- **The environment still wins.** Each value is read with `get_env(NAME, …)`,
  so an environment variable overrides the file's value, and fills an empty one.
  It can't stand in for a missing file or key: those still fail.

### A leaf decrypts only what it needs

Each leaf runs `sops` on:

- `terraform.enc`, always;
- `cloudflare.enc`, when the backend is `cloudflare`, because the R2 endpoint is
  built from `CLOUDFLARE_PROVIDER_ACCOUNT_ID`;
- each provider's file, when that provider is on **for this leaf**, honouring
  `leaves`;
- `env.enc`, when it exists.

So a Grafana leaf scoped away from Backblaze decrypts `terraform.enc`,
`scaleway.enc` and `env.enc`, never `backblaze.enc`.

### `spoke.hcl`'s `state_backup`

`state_backup = true` says the state is copied to B2. It makes the three backup
keys part of `terraform.enc`, and it's what `state-backup.yml` checks before it
does anything. It defaults to `false`. A `cloudflare` backend requires it,
because R2 can't version objects (LIB-0007), and still requires
`providers.cloudflare`, for the endpoint's account ID.

### The schema

`secrets-schema.json` holds the table above as data. `files.<name>` has
`required_when`, a list of conditions any one of which requires the file
(`always`, `backend.<state_backend>`, `provider.<name>`), `keys`, and
`keys_when`, extra keys under a condition (`state_backup`). `files.env` has no
`required_when`, which makes it optional, plus its `pattern` and `reserved`
local names. It's enforced twice, and both name the file and key, never a
value:

- **At render time, by `root.hcl`,** per leaf, for the files that leaf
  decrypts. A missing file, a missing or empty key, a key outside its file, or
  a reserved `env.enc` name fails the render.
- **Before anything decrypts, by `.github/scripts/check-secrets.sh`,**
  spoke-wide. sops dotenv keeps key names in plaintext, so it reads them
  straight out of each file, reads `state_backend`, `state_backup` and
  `providers` out of `spoke.hcl`, and exits 1 on a missing required file, a
  file that doesn't hold exactly its keys, a `.enc` the schema doesn't know, or
  a leftover v3 `terraform/secrets.enc`. It reports an ignored file without
  failing. It needs no `SOPS_AGE_KEY`, and can't see an empty value; the
  render check can.

### Editing

One `.sops.yaml` rule covers every file:

```yaml
creation_rules:
  - path_regex: ^terraform/secrets/[a-z]+\.enc$
    age: <the spoke's recipient>
```

and the mise task takes a file name, so an edit opens one concern:

```toml
[tasks.secrets-edit]
usage = 'arg "<file>" help="terraform, cloudflare, scaleway, backblaze or env"'
run = "sops --input-type dotenv --output-type dotenv terraform/secrets/{{arg(name=\"file\")}}.enc"
```

`mise run secrets-edit cloudflare` edits `terraform/secrets/cloudflare.enc`.

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
`cloudflare` state backend without the Cloudflare provider or without
`state_backup = true`, a leftover v1 `backblaze`/`grafana` bool, or a leftover
v2 `state_bucket_secret`.

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

### Migrating from v3

v4 moves every secret into the file for its concern, so a spoke moves in one PR
whose every leaf plans `No changes.` — the values don't change, and neither do
their names, apart from `env.enc` losing `ENV_`.

1. **The owner splits the file.** With the hub fetched at `workflows/v3.0.0` or
   later, from the spoke's root:

   ```sh
   .lib-src/.github/scripts/split-secrets.sh
   ```

   It writes each `terraform/secrets/<file>.enc` from `terraform/secrets.enc`,
   piping `sops -d` through a filter into `sops -e`, so only ciphertext lands on
   disk and no value is printed. Each file is encrypted to the old file's own
   age recipients, whatever `.sops.yaml` says. Every key goes to the file that
   owns it, `ENV_<NAME>` becomes `env.enc`'s `<NAME>`, and a key no file owns
   stops it before anything is written. It refuses to overwrite a file, and
   ends by running `check-secrets.sh`, which says what `spoke.hcl` still lacks
   — on an R2 spoke, `state_backup = true`, so it fails until step 2 sets it.
2. **The PR:**
   - `git rm terraform/secrets.enc`, and add `terraform/secrets/*.enc`;
   - set `.sops.yaml`'s rule to `path_regex: ^terraform/secrets/[a-z]+\.enc$`;
   - make `mise run secrets-edit` take a file name, as above;
   - on an R2 spoke, set `state_backup = true` in `spoke.hcl`;
   - set `root_hcl_version = "4.0.0"`, with `/.lib-version` at
     `workflows/v3.0.0`, rerun `resolve-root-hcl.sh`, and commit both
     generated files;
   - pin the reusable workflows at `workflows/v3.0.0`, and delete
     `secrets_files: terraform/secrets.enc` from every caller, since the
     default now finds the split files. `state-backup.yml`'s callers can stay:
     it does nothing without `state_backup = true`.
3. Check that every leaf plans `No changes.`

## Workloads (v4.3.0, LIB-0023)

A workload is one file, `workloads/<workload>/values.yaml` at the spoke's root,
declaring the Scaleway modules one thing needs:

```yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/workload/v1.json
prefix: pigeon-cli
suffix: email
scaleway:
  project: {}
  bucket:
    example:
      storage_class: standard
  iam:
    application: {}
    apiKey: {}
```

`.lib-src/.github/scripts/resolve-workloads.sh` turns it into one stub leaf per
module, at `workloads/<workload>/<provider>/<module>/<instance>/terragrunt.hcl`.
The stubs are generated, never committed: the spoke gitignores `/workloads/*/*/`,
`mise run terraform-prepare` generates them locally, and `terragrunt-run.yml`
(`workflows/v4.2.0`) generates them in CI, where deleting an instance from
`values.yaml` plans its destroy. CI also runs the script with `--check`. A stub
carries only the `dependency` blocks its kind implies. For a workload leaf, this
template:

- reads the leaf's entry in `values.yaml`, and marks the file read, so a PR that
  edits only `values.yaml` still plans every leaf that reads it;
- defaults the names from `prefix` and `suffix`: `project.name` and
  `iam.application.name` are `<prefix>-<suffix>`, and a bucket's `name_prefix`
  and `name_suffix` are `<prefix>-<key>` and `<suffix>`;
- resolves the module's version at every plan: `version: "X.Y.Z"` exactly,
  `"X.Y"` or `"X"` as the newest release within it, and no `version` as the
  newest release (`git ls-remote --sort=-v:refname` against the library);
- writes `workload_generated.tf`: a `module "this"` block at that version's
  short URL, with the entry's inputs as literals, the wiring inputs (a bucket's
  `project_id`, an API key's `default_project_id` and `application_id`) as
  variables the stub sets from its dependencies, and the whole module as
  `output "module"`.

A workload with a project also gets its own deployer (v4.4.0, LIB-0024), at
`workloads/<workload>/scaleway/terraform-deployer-iam/main`. It needs no entry
in `values.yaml`, and an optional `scaleway.deployer` overrides its inputs. It
is scoped to the workload's project, defaults to `ObjectStorageFullAccess`, and
rotates its key every 30 days. Projects, deployers and IAM objects sign in with
the spoke's key. Project-scoped kinds, buckets today, sign in with the
deployer's key instead. The stub passes it as `scaleway_access_key` and
`scaleway_secret_key`, and this template's `provider "scaleway"` reads them.
`terragrunt-run.yml` (`workflows/v4.3.0`) plans a workload's leaves one at a
time and defers those whose dependencies are new or changing, so a new
workload lands in a few staged applies.

Since v5.0.0 (LIB-0028), with `workflows/v4.9.0` or later, every workload has a
project, a deployer and a versioned state bucket, whatever `values.yaml`
declares. `scaleway.project`, `scaleway.deployer` and `scaleway.state` only
override their module's inputs. The state bucket is
`workloads/<workload>/scaleway/bucket/state`, a `scaleway/bucket` named
`<prefix>-<code>-terraform-state`, with versioning on and storage class
`standard` (v5.0.1), neither of which can be changed: state moved to `GLACIER`
can't be read without a restore. `state` is therefore no longer a valid `scaleway.bucket` key.

- **The project, deployer and state bucket keep their state in the spoke's
  bucket.** They create the workload's.
- **Every other workload leaf keeps its state in the workload's bucket.** The
  key is `<prefix><provider>/<module>/<instance>/terraform.tfstate`, where
  `<prefix>` is `scaleway.state.prefix`, by default `workloads/<workload>/`.
  So by default the key is the same one the spoke's bucket would hold.
- **Its stub declares that `remote_state` itself**, signed in with the
  deployer's key, since only the stub has the dependencies the bucket name
  and key come from. This template refuses a workload-state leaf whose stub
  has none, which is what an older `resolve-workloads.sh` generates.
- **A deployer override must keep `ObjectStorageFullAccess`.**
- **A new workload lands in four stages:** project, then deployer, then state
  bucket, then the rest.

Since v5.1.0 (LIB-0029), with `workflows/v4.10.0` or later, a workload may also
declare Backblaze buckets and API keys:

```yaml
backblaze:
  bucket:
    archive: {}
  apiKey:
    archive-reader:
      buckets: [archive]
      capabilities: [listBuckets, listFiles, readFiles]
```

- **They sign in with the spoke's Backblaze key**, from `backblaze.enc`, and
  keep their state in the workload's bucket.
- **An API key reaches only the buckets its `buckets` list names.** Each is
  one of the workload's `backblaze.bucket` keys, and its stub wires their IDs
  as `bucket_ids`. `bucket_ids` itself can't be set, and `capabilities` has
  no default.
- **A bucket's name** defaults like a Scaleway bucket's. A name longer than
  B2's 50 characters is refused before planning.
- **A workload leaf gets exactly the provider its path names**, when
  `spoke.hcl`'s `providers` map has it. `leaves` scopes hand-written leaves
  only, so a spoke adds nothing for workloads.

Since v5.2.0 (LIB-0030), with `workflows/v4.11.0` or later, a workload may also
declare Cloudflare resources, in zones a root `zones.yaml` gives it. v6.0.0
refuses `zones.yaml`, a workload's `ruleset` and `apexRedirect`, and
hand-written zone leaves, so this is history; zones now work as the v5.6.0
section below says:

```yaml
# zones.yaml
example.org:
  workload: site
example.net:
  workload: terraform   # hand-written terraform/cloudflare/example.net/ leaves
```

```yaml
# workloads/site/values.yaml
cloudflare:
  zone: example.org
  dnsRecord:
    www:
      type: CNAME
      content: example.github.io
  apexRedirect:
    to-www:
      target_url: https://www.example.org
```

- **Four kinds:** `bucket` (R2), `dnsRecord`, `ruleset` and `apexRedirect`.
  They sign in with the spoke's Cloudflare token and keep their state in the
  workload's bucket.
- **A zone has one owner.** A workload may act only on zones `zones.yaml`
  registers to it. A hand-written zone leaf may not use a zone a workload
  owns.
- **`cloudflare.zone`** fills `zone` for every entry that doesn't set its own.
- **Defaults and refusals:**
  - a record's `name` defaults to its key, and its `comment` to
    `workloads/<w>`;
  - `account_id` comes from `cloudflare.enc`, as a sensitive variable;
  - `account_id` and `zone_id` can't be written;
  - a zone gets one entrypoint ruleset per phase and one record per name and
    type, checked before planning.

Since v5.3.0 (LIB-0033), with `workflows/v4.13.0` or later, those Cloudflare
leaves sign in with the workload's own token, not the spoke's:

- **A workload that owns a zone, or declares an R2 bucket,** gets
  `workloads/<w>/cloudflare/api-token/deployer`. Since v5.4.0 it's minted
  with the spoke's Cloudflare breakglass token where it has one, since
  Cloudflare won't let a minted token mint. By default it has *Zone Read*, *DNS Write* and *Dynamic URL
  Redirects Write* on exactly the zones `zones.yaml` gives it, plus *Workers
  R2 Storage Write* on the account if it has buckets. It rotates every 30
  days. `cloudflare.deployer` overrides its inputs, `policies` included.
- **The spoke's own keys are minted too.** `cloudflare_breakglass.enc` and
  `backblaze_breakglass.enc` hold hand-made keys that can only mint keys, read
  only by the deployer leaves `spoke.hcl` allowlists under `breakglass`
  (LIB-0014 §2), and by every workload's Cloudflare token leaf. The spoke
  deployers' outputs are copied by hand into `cloudflare.enc` and
  `backblaze.enc`.

Since v5.5.0 (LIB-0034), with `workflows/v4.14.0` or later, a site workload
says which GitHub Pages shim deploys it, and gets its Pages DNS from that:

```yaml
# workloads/site/values.yaml
features:
  githubPages:
    pagesShim: example/example.org   # the shim repo, owner/name
    pagesBaseUrl: example.github.io  # the Pages host
cloudflare:
  zone: example.org
```

- **Two records are implied:** `cloudflare.dnsRecord.github-pages-root-cname`
  (`@`) and `github-pages-www-cname` (`www`), each a CNAME to `pagesBaseUrl`,
  `ttl: 1`, not proxied. They land in `cloudflare.zone`, which `githubPages`
  requires.
- **An entry under either key overrides its default field by field,** so
  `github-pages-www-cname: { comment: … }` changes only the comment.

Since v5.6.0 (LIB-0036), with `workflows/v5.2.0` or later, a zone is a unit
of its own. `zones/<zone>/zone.yaml`, named for the zone's apex, holds the
records and redirects that belong to the domain rather than to a site:

```yaml
# zones/example.org/zone.yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/zone/v1.json
name: example.org   # the Scaleway project; defaults to the directory
prefix: exo         # every other name; defaults to name, as example-org
suffix: example     # required
workload: site      # optional: the one workload that may write here too
cloudflare:
  dnsRecord:
    mx-primary:
      name: '@'
      type: MX
      content: mx1.example.net
      priority: 10
  apexRedirect:
    main:
      target_url: https://www.example.org
```

- **A zone gets what a workload gets,** with `zone-` in its names: a project
  named `name`, a deployer `<prefix>-<suffix>-zone-deployer`, a state bucket
  `<prefix>-<code>-zone-terraform-state`, and a token
  `<prefix>-<suffix>-zone-cloudflare-deployer` with *Zone Read*, *DNS Write*
  and *Dynamic URL Redirects Write* on its own zone only. Its leaves are
  generated at `zones/<zone>/<provider>/<module>/<instance>/` and keep their
  state under `zones/<zone>/`.
- **It takes zone kinds only:** `dnsRecord`, `ruleset` and `apexRedirect`,
  plus overrides for its `project`, `deployer`, `state` and Cloudflare
  `deployer`. Its entries never write `zone`, and it has no `secrets.yaml`. A
  record's `comment` defaults to `zones/<zone>`.
- **`workload` takes `zones.yaml`'s place.** A workload acts only on zones
  whose `zone.yaml` names it, or that `zones.yaml` still registers to it. A
  zone in both is refused. A workload's token has the redirect group only if
  it declares a `ruleset` or an `apexRedirect`.
- **Clashes are checked across the spoke,** so a zone's records and its
  workload's can't be one record.

Since v6.0.0 (LIB-0036), with `workflows/v6.0.0` or later, a `zone.yaml` is
the only way to register a zone. Each of these is refused before planning, by
`resolve-workloads.sh` and by this template:

- **a root `zones.yaml`.** Move each zone into `zones/<zone>/zone.yaml`, and
  name its workload there;
- **a workload's `ruleset` or `apexRedirect`.** They're a zone's alone, since a
  phase has one entrypoint per zone. A workload keeps `dnsRecord` and `bucket`,
  and its token loses *Dynamic URL Redirects Write*;
- **a hand-written `terraform/cloudflare/<zone>/` leaf.** Declare its entries
  in the zone's `zone.yaml`, and import them (below).

A spoke whose zones are all `zone.yaml`s, and whose workloads hold no redirect,
plans `No changes.` on the bump.

Since v6.1.0 (LIB-0037), with `workflows/v6.1.0` or later, a workload may live
in its zone, beside the old layout while a spoke moves:

```yaml
# workloads/example.org/site/workload.yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/workload/v2.json
name: site            # defaults to the directory; never `zone`
deployments:
  scaleway:
    project: {}       # the zone's project; name, prefix or suffix gives it its own
  githubPages: {}     # username, shim and url all default
```

```yaml
# zones/example.org/zone.yaml
hosts:
  '@': site           # the apex and www
  docs: handbook      # workloads/example.org/handbook/
```

- **The directory names the zone,** so a `workload.yaml` never writes `zone`,
  and `prefix` and `suffix` are the zone's unless
  `deployments.scaleway.project` sets them. A workload with no zone lives in
  `workloads/private/<workload>/`, in a project of its own, so it sets both.
  Its secrets are `secrets.workload.yaml` beside it.
- **It has no project leaf in its zone's project.** Its deployer and state
  bucket depend on `zones/<zone>/scaleway/project/main`, and its names carry
  `name`: `<prefix>-<suffix>-<name>-deployer`,
  `<prefix>-<code>-<name>-terraform-state`,
  `<prefix>-<suffix>-<name>-cloudflare-deployer`, and `<prefix>-<name>-<key>`
  for a bucket. Its leaves are generated at
  `workloads/<zone>/<workload>/<provider>/<module>/<instance>/` and keep their
  state under `workloads/<zone>/<workload>/`.
- **`hosts` says who serves what.** Each host names one workload in
  `workloads/<zone>/`, which writes records only at its host: `@`, `www` and
  `_` names under them for the apex, or the label and the names under it.
  Its token gets *Zone Read* and *DNS Write* on its zone only with a host. The
  zone keeps every other name, but not one under a subdomain host, nor `www`
  or an A, AAAA or CNAME at `@` beside an apex host, so its MX and TXT at `@`
  stay. `hosts.@` and an `apexRedirect` can't stand together. Beside `hosts`,
  `workload` still names an old-layout workload, so a spoke can create a
  workload's new deployer, state bucket and token before moving its records.
- **`deployments.githubPages` replaces `features.githubPages`.** `username`
  defaults to the spoke repo's owner (`GITHUB_REPOSITORY_OWNER`, else
  origin's URL), `shim` to the host as a domain, and `url` to
  `<username>.github.io`. An apex host gets LIB-0034's two CNAMEs, a subdomain
  one, `github-pages-cname`. It needs a host. `site-dispatch.yml` dispatches
  `<username>/<shim>`, and a shim passes `site-pages.yml` the workload as
  `<zone>/<workload>`.

A spoke gitignores each provider's stub directory, `/workloads/*/*/scaleway/`,
`/workloads/*/*/cloudflare/` and `/workloads/*/*/backblaze/`, never
`/workloads/*/*/*/`, which would also hide a site's `content/`, `static/` and
`templates/`. It adds
`^workloads/[^/]+/[^/]+/(workload|secrets\.workload)\.yaml$` to its
`leaf_pattern` if it overrides it, and
`^workloads/[^/]+/[^/]+/secrets\.workload\.yaml$` to its `.sops.yaml`.

Moving an existing record into a zone is an import, never a recreate:
`docs/runbooks/import-a-leaf-into-a-workload.md`. A spoke gitignores
`/zones/*/scaleway/` and `/zones/*/cloudflare/` beside its workload lines, and
adds `^zones/[^/]+/zone\.yaml$` to `terragrunt-detect.yml`'s `leaf_pattern`
if it overrides it.

Since v7.1.0 (LIB-0039), with `workflows/v7.1.0` or later, each unit file has
one root key, its records sit at `dnsRecords` directly under it, and a zone
names the mail and identity providers it uses:

```yaml
# zones/example.org/zone.yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/zone/v3.json
zone:
  suffix: example
  services:
    proton:
      enabled: true          # default false
      verification:
        pm: <token>
        protonmail: <token>
      # dmarc: true          # the default policy; a string, or false for none
    bluesky:
      enabled: true
      did: did:plc:<id>
  dnsRecords:
    proton-spf:
      comment: overridden    # an entry of an implied key overrides it field by field
    status:
      name: status
      type: CNAME
      content: status.example.net
```

- **`zone:` and `workload:`.** zone.yaml's content goes under `zone`,
  workload.yaml's and secrets.workload.yaml's under `workload`. A key beside
  the wrapper is refused, and so is `cloudflare.dnsRecord` inside it: it's
  `dnsRecords` now. The leaves are unchanged, `cloudflare/dns-record/<key>`.
- **`services`** is a zone's alone, and only in a wrapped file. Each of
  `proton` (Proton Pass aliases), `fastmail`, `googleSearch` and `bluesky`
  implies its records, keyed `<service>-<record>` with ttl 1 and a fixed
  comment, when `enabled: true`. Inputs are only what's the zone's own:
  `proton.verification.pm` and `.protonmail`, `googleSearch.verification` and
  `bluesky.did`. A mail service's `dmarc` is `true` by default
  (`v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s` at `_dmarc`), a policy
  string, or `false`.
- **Refused before planning, by name:** an unknown service or key, an
  enabled service missing an input, `proton` and `fastmail` both enabled, and
  two SPF or two DMARC policies at one name.
- **An unwrapped file still reads as before** until v8.0.0, which refuses it.

A workload may also have a `workloads/<workload>/secrets.yaml` (v4.5.0,
LIB-0025), encrypted with sops as YAML. Its rule in the spoke's `.sops.yaml` is
`^workloads/[^/]+/secrets\.yaml$`. It holds secret inputs under the same kind
paths as `values.yaml`, and an `env` map that any `values.yaml` input reaches
as `{ secretRef: NAME }`. This template decrypts it for that workload's leaves
only, and passes each secret as a sensitive variable. It never writes one
into a generated file. `resolve-workloads.sh --check` refuses a plaintext
`secrets.yaml`, and an input set in both files.

Every input written in `values.yaml` wins over a default or a dependency. A
dependency has no `mock_outputs`, since apply runs the saved plan (LIB-0022):
a dependent plans only once what it depends on is applied, so land a workload's
independent kinds first. Every other leaf gets a one-line comment in
`workload_generated.tf`, so a hand-written leaf plans `No changes.` on v4.3.0.

## Two pins, deliberately

`/.lib-version` decides which *resolver* runs: `resolve-root-hcl.sh` is on the
`workflows/` track. `root_hcl_version` decides which *template* it writes. That
is the same split as the theme's `.lib-version` versus `theme_version`.
