# LIB-0040: runway's cold-storage buckets become the `private/cold-storage` workload

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-27.
- **Status**: Proposed; amended 2026-10-27 (see `## Amendments`). Applies
  LIB-0029 and LIB-0037 to runway. The amendment refines LIB-0037 §2's names
  for a workload in its own project.

## Context

runway's five Backblaze buckets are still hand-written leaves, under
`terraform/backblaze/bucket/`:

- `custodial-duck-jellyfish`;
- `deduplicated-misc`;
- `original-2026-06-01`;
- `snapshot-2026-10-09`;
- `snapshot-2026-10-17`.

They're the data-ops cold storage: backups and pigeon-cli's deduplicated
snapshots. Their state sits in the spoke's one state bucket in the `runway`
project, beside pigeon-cli's.

The library already has everything these buckets need:

- **Backblaze kinds.** LIB-0029 gave workloads `backblaze.bucket`.
- **A home without a zone.** LIB-0037 §1 gave a zoneless workload
  `workloads/private/<workload>/`, with a project of its own.

Nothing has used either for runway's buckets. Moving them is the Backblaze
part of [#98](https://github.com/noisypigeon/library/issues/98) and
[#137](https://github.com/noisypigeon/library/issues/137).

Two more things are in that tree:

- **`terraform/backblaze/api-key/original-2026-06-01` is dead.** It reads
  `local.backblaze_original_bucket_id` and `_name`, which nothing defines, so
  it can't plan. It holds no key.
- **Two bucket leaves carry dormant keys.** Each has a commented-out
  `key.tf` and the `key_definition.tf` it would read.

## Decision

### 1. The workload

`workloads/private/cold-storage/workload.yaml` holds runway's buckets:

```yaml
workload:
  name: cold-storage
  deployments:
    scaleway:
      project:
        prefix: wg
        suffix: cold-storage
  backblaze:
    bucket:
      snapshot-2026-10-17:
        name_prefix: wg
        name_suffix: snapshot-2026-10-17
        description: Unique documents and media files from pigeon-cli transform (Snapshot: October 17th, 2026)
      # ...one entry per leaf
```

- **There's one `backblaze.bucket` entry per leaf, keyed by the leaf's name.**
  The leaf is then `workloads/private/cold-storage/backblaze/bucket/<key>/`.
- **Each entry writes its leaf's own `name_prefix`, `name_suffix` and
  `description`.** An explicit input overrides LIB-0029 §2's default.
  `custodial-duck-jellyfish` keeps its `custodial` prefix, and every other
  bucket keeps `wg`.
- **Each bucket keeps its name.** The random segment lives in the state that
  moves (§4). The stub takes the newest `backblaze/bucket`, v0.2.0, whose
  `moved` block carries that segment to `random_string.suffix[0]`.
- **The workload declares no `apiKey` and no Cloudflare entries.** A key, when
  one is needed, is a `backblaze.apiKey` entry scoped to its buckets
  (LIB-0029 §3), not a dormant file.

### 2. Its own project holds the buckets' state

A private workload always has its own project (LIB-0037 §§1–2).
cold-storage's does one thing: it holds the buckets' state.

| Leaf | Name |
| --- | --- |
| `scaleway/project/main` | `wg-cold-storage` |
| `scaleway/{iam-application,iam-policy,iam-api-key}/deployer` | `wg-cold-storage-cold-storage-deployer` |
| `scaleway/bucket/state` | `wg-<code>-cold-storage-terraform-state` |

- **The name repeats in the deployer.** `<prefix>-<suffix>-<name>` (LIB-0037
  §2) gives `cold-storage` twice. Since the suffix names the project after
  its one workload, this is what the rule produces, and it's left as is.
- **The buckets still sign in with the spoke's account-wide B2 key**
  (LIB-0029 §4). Only their state moves.
- **The deployer reaches only this project's state.** Cold storage stops
  sharing a state bucket with pigeon-cli, and no zone's deployer can reach it.

### 3. The legacy leaves are deleted

- **The five `terraform/backblaze/bucket/*` leaves go,** once their state has
  moved (§4). Their dormant `key.tf` and `key_definition.tf` go with them.
- **`terraform/backblaze/api-key/original-2026-06-01` goes.** It holds no
  state, so deleting it plans nothing.
- **`terraform/backblaze/api-key/terraform-deployer` stays.** It's the spoke's
  minted key (LIB-0033 §2), and `spoke.hcl`'s
  `backblaze.leaves = ["terraform/backblaze/"]` still covers it.

### 4. State moves; no bucket is recreated

Each bucket's state moves by LIB-0038 §5 and its 2026-10-26 amendment, with
runway frozen from the first push until the PR that commits the move merges.

For each bucket:

1. **Pull a backup** of the old leaf's state into a private directory outside
   every checkout.
2. **Rename its addresses in the backup:** `module.bucket.*` becomes
   `module.this.*`, the stub's module block.
3. **Check the new leaf's backend is empty**, from a scratch copy whose stub
   carries no `dependency` blocks.
4. **Push the backup**, then rewrite its outputs to the stub's `module`
   output, from a `-refresh=false` plan's `planned_values`.
5. **Plan with `-detailed-exitcode`,** which must exit 0. The `moved` block's
   note is not a change.
6. **Empty the old leaf** with `state rm`.

| Old address | New address |
| --- | --- |
| `module.bucket.random_string.suffix` | `module.this.random_string.suffix` (v0.2.0's `moved` takes it to `[0]`) |
| `module.bucket.b2_bucket.bucket` | `module.this.b2_bucket.bucket` |

### 5. Two runway PRs

State can't be pushed into a bucket that doesn't exist yet. So:

1. **The first PR adds the workload with only its project.** It creates the
   project, the deployer's three leaves and the state bucket, and is applied.
2. **The move runs** (§4).
3. **The second PR commits the move.** It adds the five `backblaze.bucket`
   entries and deletes the six legacy leaves. Its plan creates, destroys and
   replaces nothing.

## Consequences

- **runway's cold storage is declared in one file.** A new bucket is one more
  entry there, with its name defaulted or written.
- **runway's `terraform/` tree loses its Backblaze buckets.** Only the
  Backblaze deployer key stays there.
- **Cold storage's state is in a project of its own.** A pigeon-cli or zone
  deployer can't reach it.
- **B2 itself is still managed with one account-wide key.** Isolation on
  Backblaze is by key scope only (LIB-0029).

## Out of scope

- **runway's other hand-written leaves,** pigeon-cli's Scaleway buckets,
  cluster, IAM and Grafana. They stay under
  [#98](https://github.com/noisypigeon/library/issues/98).
- **A Backblaze credential narrower than the account key** for the workload.
  That's [#109](https://github.com/noisypigeon/library/issues/109).

## Verification

1. **The first PR creates only the workload's own leaves:** the project,
   three deployer leaves and the state bucket.
2. **State moved, not recreated.** Each of the five bucket leaves plans
   `No changes.` at its workload key before its old leaf is emptied.
3. **The deleted leaves plan nothing.** The old leaves are empty, and the
   original key's leaf never had state.
4. **It converges.** After the second PR's apply, a re-plan of every leaf
   shows `No changes.`
5. **B2 still holds all five buckets under the same names,** checked out of
   band with the spoke's key.

## Amendments

### 2026-10-27: a workload in its own project doesn't repeat its name

§2 took the doubled name as what the rule produces. noisypigeon/runway#87's
first stage then created the deployer's IAM application as
`wg-cold-storage-cold-storage-deployer`, which showed the name was worth
fixing before the rest landed.

1. **A workload in a project of its own carries no name tag.** LIB-0037 §2's
   `<name>` keeps sibling workloads apart in their zone's project. A private
   workload, or a zoned one that sets its own project, has no siblings in it,
   and the project's suffix already names it. Its implicit resources are named
   as a top-level LIB-0028 workload's are.
2. **cold-storage's names become:**

   | Leaf | Name |
   | --- | --- |
   | `scaleway/project/main` | `wg-cold-storage` (unchanged) |
   | `scaleway/{iam-application,iam-policy,iam-api-key}/deployer` | `wg-cold-storage-deployer` |
   | `scaleway/bucket/state` | `wg-<code>-terraform-state` |

3. **Both twins change:** root.hcl's `workload_name_tag` and
   `resolve-workloads.sh`'s `tag`, in `terragrunt/root-hcl` v8.0.1 and
   `workflows/v8.0.1`. A workload in its zone's project keeps its tag, so
   blog's and garden's names don't change.
4. **runway#87 takes 8.0.1 before its second stage.** The IAM application is
   renamed in place. The policy, key and state bucket don't exist yet, so
   they're created under the new names.
