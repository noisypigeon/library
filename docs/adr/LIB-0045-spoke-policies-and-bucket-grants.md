# LIB-0045: spoke policies, and owner-granted Backblaze keys

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed. Amends LIB-0029 §3, which let a key reach only its own
  workload's buckets.

## Context

LIB-0040 and LIB-0044 put runway's Backblaze buckets in two private
workloads, so that no other deployer can reach their state. Nothing keeps
them there:

- the next PR can declare `backblaze.bucket` in any workload;
- a hand-written leaf can hold a `b2_bucket`.

Either would plan and apply. The isolation holds only by convention.

There's no general way to say a rule like that. Every check this family has
is a schema check: `resolve-workloads.sh --check`, `check-secrets.sh` and
root.hcl's guards. Each says what a file may hold. None says where a resource
may live in a particular spoke, and the workload names are the spoke's, not
the hub's.

Other workloads also need to read those buckets. pigeon-cli, for one, reads
the snapshots. LIB-0029 §3 lets a key name only its own workload's buckets.
So a consumer today needs either a bucket of its own, which is the copy this
record exists to prevent, or a hand-written account-wide key.

## Decision

### 1. `check-policies.sh` runs a spoke's policies before every plan

`.github/scripts/check-policies.sh` is a runner on the `workflows/` track,
beside `check-secrets.sh`.

- **A spoke runs it in `prepare_cmd`,** after `resolve-workloads.sh --check`,
  so it runs before every plan and every apply.
- **It's static.** It needs no credentials and no network, only `yq` and
  `jq`. It decrypts nothing.
- **It reports with `::error file=…,line=…::`,** like its neighbours, then
  prints a summary. It exits 1 on any error.

It doesn't live in root.hcl, because a leaf there sees only itself, and
every new rule would need a template release. It doesn't read plan JSON,
because that needs a credentialed plan of every leaf before anything can
fail. It isn't OPA or conftest, which would add a tool and a language to a
family that checks with bash and jq.

### 2. One inventory, built once

The runner builds one record per leaf:

```json
{ "path": "workloads/private/personal-cold-storage/backblaze/bucket/snapshot-2026-10-17",
  "file": "workloads/private/personal-cold-storage/workload.yaml", "line": 31,
  "unit": { "type": "workload", "id": "private/personal-cold-storage" },
  "provider": "backblaze", "module": "backblaze/bucket",
  "instance": "snapshot-2026-10-17", "resources": [] }
```

- **Unit leaves come from `resolve-workloads.sh --list`.** That's every leaf a
  `workload.yaml` or `zone.yaml` implies, implied ones included, such as a
  workload's own B2 key (LIB-0041). A kind added later shows up without the
  runner changing.
  - A workload's `unit.id` is `<parent>/<workload>`, its path under
    `workloads/`.
  - A zone's is its apex.
- **Hand-written leaves are every tracked `terraform/**/terragrunt.hcl`.**
  - `unit` is `{spoke, <leaf dir>}`.
  - `module` is the library module its `source` names, or else the module
    its LIB-0004 path names.
  - `resources` lists every `resource "<type>"` in the leaf's own `*.tf`.
    That's how a raw `b2_bucket` is caught.
- **`line` is best-effort.** It points at the entry in the unit file. It's
  absent for an implied leaf.

`check-policies.sh --inventory` prints the inventory and checks nothing.

### 3. A policy is a jq filter and a params schema

Each policy is two files under `.github/scripts/policies/`:

- **`<id>.jq`:**
  - Its input is the inventory, and `$params` is the spoke's settings for
    it.
  - It emits one `{path, file, line?, message}` per violation.
  - It calls `error(…)` when its params are wrong.
  - It writes no annotation, never exits and handles no exemptions. The
    runner does all three.
- **`<id>.schema.json`:** the JSON Schema of its params.

So a new policy costs those two files, a test case and the record that
decides it. When a policy needs a fact the inventory doesn't have, the
inventory grows, and policies stay filters.

### 4. A spoke turns policies on in `policies.yaml`

The spoke commits `policies.yaml` at its root. The hub ships the logic, and
the spoke supplies the names:

```yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/policies/v1.json
policies:
  backblaze-bucket-owners:
    workloads:
      - private/personal-cold-storage
      - private/custodial-cold-storage
    exempt:                       # optional
      - path: terraform/backblaze/bucket/legacy
        reason: "…"
```

- **Without the file, the runner prints a notice and passes.** Policies are
  opt-in per spoke, like providers (LIB-0005).
- **A policy runs when its key is present.** A key that names no policy is
  an error.
- **`exempt` drops one violation by `path`.** Every entry needs a `reason`,
  which the runner prints as a notice. **An exemption that matches no
  violation is an error,** so a stale one can't outlive what it excused.
- **It isn't in `spoke.hcl`.** The scripts read that file with sed and awk,
  which can't read nested lists, and `yq` already reads every unit file.
- **Turning a policy off** means deleting its key, which shows up in review.

`generate-module-redirects.sh` publishes `schemas/policies/v1.json`. It's
assembled from every `<id>.schema.json`, plus `exempt`, with
`additionalProperties: false`. A new policy adds an optional property to v1
in place. The version bumps only when an existing policy's params change
incompatibly.

### 5. `backblaze-bucket-owners`

Its one param is `workloads` (required): the workload IDs that may own a
Backblaze bucket.

It fails:

1. **A bucket outside those workloads.** That's a leaf whose `module` is
   `backblaze/bucket`, or whose `resources` hold `b2_bucket`, when its unit
   isn't one of those workloads. A zone or a hand-written leaf is never one
   of them.
2. **A B2 key in a hand-written leaf.** That's `module` `backblaze/api-key`,
   or a `b2_application_key` resource. No grant (§6) covers it, so nothing
   can check what it reaches.

A key a workload declares passes, wherever the workload is, and so does its
implied deployer key. §6 already holds a workload's keys to its own buckets
and to buckets granted to it.

**The `state_backup` bucket is outside this policy, permanently.** No
Terraform makes it. root.hcl only names its keys in the secrets schema, and
`state-backup.yml` copies into a bucket made by hand, with
`--s3-no-check-bucket` (LIB-0007 §4). No inventory can see it.

### 6. An owner grants its buckets, with a ceiling

A bucket entry may hold `grants`, a map from a workload ID to the most a key
of that workload may do in the bucket:

```yaml
# workloads/private/personal-cold-storage/workload.yaml
backblaze:
  bucket:
    snapshot-2026-10-17:
      name_prefix: wg
      name_suffix: snapshot-2026-10-17
      grants:
        private/pigeon-cli: [listBuckets, listFiles, readFiles]
```

- **`grants` is the workload's own field, not a module input,** like a key's
  `buckets`. `resolve-workloads.sh` and root.hcl drop it before the module
  sees the entry.
- **Each key is a workload ID, `<parent>/<workload>`.** It needn't exist yet,
  so an owner can grant before its consumer lands. A bucket's own workload
  can't be granted.
- **Every grant has a ceiling,** a non-empty list of capabilities. There's
  no uncapped grant, for the same reason `capabilities` has no default
  (LIB-0029 §2): what another workload may do to a bucket is always written
  down.

### 7. The consumer declares the key

This amends LIB-0029 §3. A `backblaze.apiKey.<key>.buckets` entry is one of
two things:

- **`<bucket>`** is one of the workload's own buckets, as before.
- **`<parent>/<workload>/<bucket>`** is a bucket of another workload. A
  workload ID always has two segments, so a three-segment entry can't be
  misread.

For each foreign entry, the key's stub gets a dependency,
`dependency "xbucket_<n>"`, on the owner's bucket leaf. Its ID joins
`bucket_ids`. Dependencies across units already exist: a zoned workload's
project depends on its zone's (LIB-0037 §2).

Refused, by `resolve-workloads.sh --check` across every unit and by a root.hcl
guard on the key's leaf:

- a foreign entry whose owner has no such bucket;
- a foreign entry whose bucket doesn't grant this workload;
- a key whose `capabilities` exceed the ceiling of any foreign bucket it
  names. A B2 key's capabilities hold for every bucket it reaches, so the key
  must fit within each ceiling. Its own buckets set no ceiling.
- a malformed `grants`.

**Revoking a grant fails the consumer's key,** so revocation and the key's
change land in one PR.

### 8. Workload schema v6

`generate-module-redirects.sh` publishes `schemas/workload/v6.json`, made
from v5 the way v5 was made from v4. It adds `grants` and the
`<parent>/<workload>/<bucket>` form. v5 stays published, unchanged.

### 9. Releases

| PR | Unit | Label |
| --- | --- | --- |
| `check-policies.sh`, the first policy, the policies schema | `workflows/` | `release:minor` |
| grants and foreign buckets in `resolve-workloads.sh`, workload schema v6 | `workflows/` | `release:minor` |
| the grant guard and the `grants` strip | `terragrunt/root-hcl/` | `release:minor` |

Each is additive. A spoke that doesn't call `check-policies.sh`, write
`grants` or name a foreign bucket sees no change.

runway then takes both and commits its `policies.yaml`, once the custodial
workload's rename to `private/custodial-cold-storage` has landed. Its first
consumer, with its grant and its key, is a PR of its own after that.

## Consequences

- **A bucket outside the cold-storage workloads fails CI before any plan,**
  and so does a hand-written B2 key.
- **A workload can read another's bucket without owning a copy,** and only
  as far as the owner allows.
- **Grants limit the minted key, not the consumer's deployer.** A workload
  that declares a B2 key gets its own account-wide B2 key (LIB-0041),
  because only an unrestricted key can mint keys. That deployer could reach
  any bucket. What stops it is review, plus this policy on what may be
  declared. A narrower deployer is #109.
- **A consumer's key depends on the owner's bucket leaf.** Planning it reads
  that leaf's outputs, through the owner's own state bucket.
- **The policy engine is the place for spoke-specific rules.** A schema rule
  that holds in every spoke still goes in `resolve-workloads.sh` and root.hcl.

## Out of scope

- **A policy check on plan JSON,** which would catch what a static
  inventory can't, such as a resource a module creates without its name
  saying so. It isn't needed while every Backblaze resource comes from a
  library module or a resource in a leaf's own `.tf`. That's
  [#230](https://github.com/noisypigeon/library/issues/230).
- **A B2 deployer narrower than the account.** That's
  [#109](https://github.com/noisypigeon/library/issues/109).
- **Reaching a bucket without a key,** for example through rclone config or
  an endpoint in a comment. A policy sees declarations, not data paths. This
  is a permanent boundary.

## Verification

1. **The hub's tests pass.** That's `node --test .github/scripts/*.test.js`,
   with cases for every violation, exemption, config error, grant and
   ceiling.
2. **runway's inventory is complete.** `check-policies.sh --inventory` on
   runway lists every unit and hand-written leaf. Before the rename, the
   check fails only on the custodial bucket. After it, the check passes.
3. **runway's wiring PR plans no change** and runs the check in its prepare
   step.
4. **The negative cases fail where they should.** A draft PR adding a bucket
   to `blog` fails `check-policies.sh`. A key in `blog` naming an ungranted
   cold-storage bucket fails `resolve-workloads.sh --check`.
