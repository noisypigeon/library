# LIB-0029: Backblaze kinds in a workload's `values.yaml`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-22.
- **Status**: Proposed. Amends LIB-0023, whose §2 kind table gains its first
  rows for another provider and whose §4 gains their defaults, and LIB-0028,
  whose §4 table gains the same rows.

## Context

A LIB-0023 workload can declare only Scaleway modules. Every other provider's
resources stay in hand-written leaves, which is #96. runway's Backblaze buckets
and keys are such leaves, under `terraform/backblaze/{bucket,api-key}/`, so a
workload that needs a B2 bucket has to reach outside its own `values.yaml`.

Backblaze differs from Scaleway in the two ways that shaped LIB-0024 and
LIB-0028.

- **There are no projects.** A B2 account is one namespace. The provider signs
  in with the spoke's one account-wide key, from `terraform/secrets/backblaze.enc`
  (LIB-0012). There's no unit LIB-0024 could scope a workload's own credential
  to, so a workload deployer for Backblaze would buy no isolation. What a
  workload can scope is the keys it *creates*: B2 application keys can be
  restricted to a list of buckets.
- **State has nowhere of its own to go.** Backblaze could hold a state bucket,
  but LIB-0028 already gives every workload one, in its Scaleway project. A
  workload with Backblaze kinds keeps them there too.

One thing in the template is in the way.

- **`spoke.hcl` scopes providers by leaf prefix** (LIB-0005). runway turns
  Backblaze on for `terraform/backblaze/` only. A prefix can't name
  `workloads/*/backblaze/`, and widening it to `workloads/` would turn
  Backblaze on, and decrypt `backblaze.enc`, in every Scaleway workload leaf
  too.

## Decision

### 1. Two Backblaze kinds

| YAML key | Module | Shape | `<instance>` | Credentials | State |
| --- | --- | --- | --- | --- | --- |
| `backblaze.bucket.<key>` | `backblaze/bucket` | map | `<key>` | spoke | workload |
| `backblaze.apiKey.<key>` | `backblaze/api-key` | map | `<key>` | spoke | workload |

- **Their leaves are `workloads/<workload>/backblaze/{bucket,api-key}/<key>/`.**
  That's LIB-0023 §1's shape, with `backblaze` as the provider segment.
- **"Spoke" credentials** means `backblaze.enc`'s account-wide key. There's no
  workload credential for Backblaze (Context).
- **"Workload" state** means LIB-0028's bucket. Both kinds depend on
  `scaleway/bucket/state` and the deployer, and their stubs carry LIB-0028
  §5's `remote_state`.
- **Every workload still gets its implicit Scaleway project, deployer and state
  bucket** (LIB-0028 §1), even one that declares only Backblaze kinds. They're
  where its state lives.
- **The kind table gains these rows** in all three copies: root.hcl,
  `resolve-workloads.sh` and `generate-module-redirects.sh`.

The file:

```yaml
prefix: pigeon-cli
suffix: email
backblaze:
  bucket:
    archive:
      description: pigeon-cli email archive
  apiKey:
    archive-writer:
      buckets: [archive]
      capabilities: [listBuckets, listFiles, readFiles, writeFiles]
```

### 2. Names default from the workload; grants don't

Each default applies only when the input is absent, as LIB-0023 §4's do.

- **`backblaze.bucket.<key>`:** `name_prefix` = `<prefix>-<key>` and
  `name_suffix` = `<suffix>`, as for a Scaleway bucket. The module's random
  segment sits between them.
- **`backblaze.apiKey.<key>`:** `key_name` = `<prefix>-<key>-<suffix>`.
- **`capabilities` has no default.** It must be written, so what a key may do
  is always a decision in the file.

### 3. A key reaches only buckets of its own workload

- **`backblaze.apiKey.<key>.buckets`** is a required, non-empty list of this
  workload's `backblaze.bucket` keys. Like `scaleway.state.prefix` (LIB-0028
  §3), it's the workload's own field, not a module input.
- **Its stub declares one `dependency "bucket_<b>"` per listed bucket** and
  wires `bucket_ids = [dependency.bucket_<b>.outputs.module.bucket_id, ...]`.
  The wiring type is `list(string)`, which Terraform converts to the module's
  `set(string)`.
- **`bucket_ids` can't be written directly.** The module's own default, null,
  makes an account-wide key. A workload key that could reach every bucket in
  the account would undo the scoping this record relies on.
- **Refused**, by `resolve-workloads.sh` and the template:
  - a missing or empty `buckets`;
  - a `buckets` entry that isn't one of the workload's `backblaze.bucket` keys;
  - `bucket_ids` in `values.yaml` or `secrets.yaml`.

### 4. A workload leaf gets the provider its path names

- **For a workload leaf, root.hcl's `provider_on.<name>`** is
  `name == <the path's provider segment>`, and `name` is in `spoke.hcl`'s
  `providers` map. A `scaleway` leaf gets Scaleway, a `backblaze` leaf gets
  Backblaze, and nothing else.
- **`leaves` and `breakglass.leaves` govern hand-written leaves only.** A spoke
  adds no prefix for workloads.
- **A Scaleway workload leaf stops getting other unscoped providers.** In a
  spoke whose map turns, say, Cloudflare on for every leaf, those leaves lose a
  provider block they never used. Only generated provider files change, never
  a resource.
- **A guard fails a Backblaze workload leaf whose spoke has no `backblaze`
  entry**, naming `spoke.hcl`.
- **Secrets follow.** `secrets-schema.json` already requires `backblaze.enc`
  under `provider.backblaze`, so a Backblaze workload leaf decrypts it and a
  Scaleway one doesn't.

### 5. A bucket name that B2 would reject is refused before planning

B2 bucket names are 6 to 50 characters. `<prefix>-<key>-<code>-<suffix>`, with
a six-character code, can pass a plan and fail the apply.

- **`resolve-workloads.sh` refuses a `backblaze.bucket` entry** whose generated
  name would be longer than 50 characters, unless it sets `exact_name`.

### 6. The schema

- **The workload schema gains a top-level `backblaze`**, with `bucket` and
  `apiKey` as maps of kebab-case keys.
- **`backblaze.bucket.<key>`** validates against `backblaze/bucket`'s
  `inputs.schema.json`, by version, as LIB-0023 §6 does.
- **`backblaze.apiKey.<key>`** validates against a `workload.schema.json`,
  which every `backblaze/api-key` version publishes beside its
  `inputs.schema.json`. It holds the module's inputs, without `bucket_ids` and
  with `buckets`. That's LIB-0028's `state.schema.json` approach, generalised:
  a kind whose fields differ from its module's gets its own schema file.

### 7. Stages

Nothing new. Backblaze leaves depend on the state bucket, so they plan in
LIB-0028 §6's last stage, and a key plans in the stage after its buckets.

### 8. Release impact

- **`terragrunt/root-hcl` takes a minor version**, for the kinds, §4's rule
  and its guard. A spoke with no Backblaze kinds plans `No changes.` A
  Scaleway workload leaf's provider files change only where §4 says.
- **`workflows/` takes a minor version**, for the stubs, `--check`'s refusals
  and the schema.
- **Neither has to be taken alone first.** Selection doesn't change, so
  LIB-0024 §5 doesn't apply.

### 9. runway adopts on `poc`

- **`workloads/poc/values.yaml` gains one bucket and one key:**
  - `backblaze.bucket.b2`, short enough for §5;
  - `backblaze.apiKey.b2-reader`, with `buckets: [b2]` and read-only
    capabilities.
- **runway's hand-written Backblaze leaves stay as they are.** Moving them is
  #98's import.

## Consequences

- **A workload can hold its Backblaze buckets and keys**, in the same file as
  its Scaleway ones, with state in the same bucket.
- **Isolation on Backblaze is by key scope only.** Every Backblaze workload
  leaf signs in with the spoke's account-wide key. What a workload hands out
  reaches only its own buckets.
- **The kind table has its first non-Scaleway rows.** Its three copies now
  span two providers.
- **Provider files change on existing workload leaves** in a spoke with an
  unscoped non-Scaleway provider.
- **A key needs one dependency per bucket**, so a key over many buckets waits
  for all of them.

## Out of scope

- **A per-workload Backblaze credential**, for creating a workload's buckets
  and keys with something narrower than the account key. Extends
  [#109](https://github.com/noisypigeon/library/issues/109).
- **Cloudflare and Grafana kinds.**
  [#96](https://github.com/noisypigeon/library/issues/96) stays open for them.
- **Importing runway's hand-written Backblaze leaves into workloads.** Extends
  [#98](https://github.com/noisypigeon/library/issues/98).

## Verification

1. **`poc`'s Backblaze leaves land.** The bucket plans once the state bucket
   exists, and the key in the stage after it. Their state is under
   `workloads/poc/backblaze/` in `poc`'s own bucket.
2. **The key reaches exactly its bucket.** Its plan shows `bucket_ids` holding
   one ID, the `poc` bucket's.
3. **Scaleway workload leaves don't change.** In runway, their generated
   provider files and plans are the same before and after.
4. **The refusals hold**, each before any plan runs:
   - an empty `buckets`;
   - a `buckets` entry that isn't a bucket key;
   - `bucket_ids` written directly;
   - an overlong bucket name;
   - a key without `capabilities`;
   - a Backblaze kind in a spoke with no `backblaze` provider.
5. **It converges.** After the last stage, a re-plan of every leaf in runway
   shows `No changes.`

## Amendments

### 2026-10-22: what building it changed

§§1–8 shipped with this record, in `workflows/v4.10.0` and
`terragrunt/root-hcl` v5.1.0. Building them found two things it didn't say.

1. **A stub's dependency paths are relative to its workload, not its
   provider.** They were `../../<module>/<instance>`, which only reaches
   stubs under the same provider. A Backblaze stub couldn't have reached the
   Scaleway state bucket. They're now `../../../<provider>/<module>/<instance>`
   for every stub. They resolve to the same leaves, and stubs are generated,
   so nothing committed changes.
2. **A spoke can't adopt before garden publishes the schemas.**
   `resolve-workloads.sh --check` fetches each kind's `inputs.schema.json`
   from `noisypigeon.garden`. The Backblaze modules' schemas appear there only
   once garden builds with `workflows/v4.10.0` or later. Until then, `--check`
   fails on a Backblaze kind. So §9 waits on garden's bump.

