# LIB-0044: the custodial bucket gets its own workload, and cold-storage becomes `personal-cold-storage`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed; amended twice on 2026-10-28 (see `## Amendments`). Applies
  LIB-0037 and LIB-0040 to runway.

## Context

LIB-0040 made runway's five Backblaze buckets one workload,
`workloads/private/cold-storage/`, in the project `wg-cold-storage`. Four of
them are personal backups and pigeon-cli's deduplicated snapshots. The
fifth, the custodial bucket, holds files kept for someone else.

Sharing a workload means sharing a state bucket and a deployer. The
deployer that writes the personal backups' state can rewrite the custodial
bucket's too, and one bad apply in the workload can reach both.

The workload's name also stopped saying what it holds. Once the custodial
bucket leaves, everything in it is personal.

## Decision

### 1. `private/custodial-storage`

A second private workload holds the custodial bucket:

```yaml
workload:
  name: custodial-storage
  deployments:
    scaleway:
      project:
        name: custodial-storage
        prefix: cus
        suffix: custodial-storage
  backblaze:
    bucket:
      <the custodial bucket's key>:
        # its old entry, every input copied
```

- **Its project is named `custodial-storage`**, through
  `deployments.scaleway.project.name`, which overrides the
  `<prefix>-<suffix>` default. Its deployer and Backblaze key are
  `cus-custodial-storage-…`, and its state bucket is
  `cus-<code>-terraform-state` (LIB-0040's 2026-10-27 amendment).
- **It needs no new secret.** The spoke's Scaleway key makes its project and
  deployer, and the spoke's Backblaze breakglass key mints its own key
  (LIB-0041).
- **The bucket keeps its name and its ID.** Only its state moves (§3).

### 2. `cold-storage` becomes `personal-cold-storage`

The workload moves to `workloads/private/personal-cold-storage/`, with
`suffix: personal-cold-storage`. Its prefix stays `wg`.

| Leaf | Before | After |
| --- | --- | --- |
| `scaleway/project/main` | `wg-cold-storage` | `wg-personal-cold-storage`, renamed in place |
| `scaleway/{iam-application,iam-policy}/deployer` | `wg-cold-storage-deployer` | `wg-personal-cold-storage-deployer`, renamed in place |
| `scaleway/iam-api-key/deployer` | — | unchanged |
| `scaleway/bucket/state` | `wg-<code>-terraform-state` | unchanged: its name carries no suffix |
| `backblaze/api-key/deployer` | `wg-cold-storage-backblaze-deployer` | `wg-personal-cold-storage-backblaze-deployer`, replaced |
| the four buckets | their own `wg` names | unchanged: each entry writes its name |

Nothing that holds data is recreated. The Backblaze key is replaced, since
B2 can't rename one. It's created before the old one goes, and it's a minted
key that already rotates every 30 days.

### 3. State moves by copy, not import

The custodial bucket's leaf is the same module at the same addresses in both
workloads, `module.this.b2_bucket.bucket` and
`module.this.random_string.suffix[0]`. So its state is pulled from the old
leaf and pushed into the new one, as LIB-0040 §4 did.

`import-a-leaf-into-a-workload.md` imports instead, and that doesn't work
here. An imported `random_string` takes the provider's default character
flags. The module sets `upper` and `special` to false, so the plan replaces
it, and with it the bucket's name and the bucket. `moved` and `removed`
blocks can't cross states.

### 4. Renaming a workload moves every key

A leaf's state key follows its path, so every one of the workload's leaves
moves:

- `root.hcl`'s `state_key` in the spoke's bucket, for the project, the
  deployer and the state bucket;
- `workload_state_key` in the workload's own bucket, for the rest.

The rename runs, with runway frozen:

1. Pull each old leaf's state, twice, into a backup outside every checkout.
2. Push each into its new leaf, in dependency order: project, deployer,
   state bucket, Backblaze key, buckets. Then plan each locally: renames in
   place, the one key replace, and nothing destroyed.
3. Empty each old leaf with `state rm`, in reverse order. Their outputs
   stay, so CI can still resolve the removed leaves' backends when it plans
   their removal.
4. Open the PR. It must plan only the outputs-only removals, the renames and
   the key replace.

### 5. Order

The custodial bucket moves first, so its state moves once. Three runway
PRs:

1. **Bootstrap `custodial-storage`**: its project, deployer and state
   bucket, nothing else.
2. **Move the custodial bucket.** Empty the old leaf, then apply the first
   stage, which mints the workload's key. Push the state, re-plan, and
   apply the rest, which changes nothing.
3. **Rename `cold-storage`** (§4).

## Consequences

- **The custodial bucket's state is out of the personal deployer's reach,**
  and the reverse is true too.
- **On B2, isolation is still by state only.** Both workloads' keys are
  account-wide, since B2 needs an unrestricted key to make a bucket
  (LIB-0033 §5).
- **The project, IAM and key names say what each workload holds.**
- **runway has two private workloads.** The `name:` override is now in use.

## Out of scope

- **A Backblaze key narrower than the account,** for either workload. That's
  [#109](https://github.com/noisypigeon/library/issues/109).
- **Renaming the B2 buckets.** B2 can't rename a bucket, and copying custodial
  or archival data to change a name isn't worth the risk. This is a
  permanent boundary.

## Verification

1. **The bootstrap creates only the new workload's own leaves.**
2. **The custodial bucket moved, not recreated.** Its new leaf plans
   `No changes.` before the PR's last stage, and B2 still holds it under the
   same name and ID.
3. **The rename destroys nothing.** Its only changes are the in-place
   renames, the key replace and the old leaves' outputs.
4. **It converges.** After the last PR, a re-plan of every runway leaf shows
   `No changes.`

## Amendments

### 2026-10-28: results

noisypigeon/runway#93, noisypigeon/runway#94 and noisypigeon/runway#95 each
applied and merged. All four Verification items hold:

1. **The bootstrap created only the new workload's own leaves:** its
   project, its deployer's three leaves and its state bucket, in three stages,
   with nothing destroyed.
2. **The custodial bucket moved, not recreated.** Its new leaf planned
   `No changes.` locally after the push, and so did CI's fresh plan before
   the last stage. Its bucket ID is the one in the backup.
3. **The rename destroyed nothing.** Its plan held the ten old leaves'
   outputs, the in-place renames of the project, application and policy,
   and the Backblaze key's replace. Nothing else changed.
4. **It converges.** From `main` after runway#95, all 17 leaves of both
   workloads plan `No changes.` with refresh. Every bucket, the state bucket
   and the project keep the IDs in their backups.

Three things went differently from §§4–5:

1. **A stage's replan reports an already-applied destroy as a failure.**
   Stage 1 applies the removed leaves' outputs-only destroys. Each later
   stage's replan still lists them, finds no result, and counts them as
   `failed to plan` (or `failed to apply`). That's one row per removed leaf:
   one on runway#94 and ten on runway#95. Each old leaf was checked empty,
   with no resources and no outputs, before going on. The runs succeeded and
   the PRs merged, so it's only noise, but it reads like a failure.
2. **The second PR's automatic replan ran before the state push.** It
   planned the custodial bucket as a create, as §5 expected. It was never
   applied: after the push, a `terragrunt plan` comment replaced it with a
   `No changes.` plan, and that's the one that was applied. Any move that
   pushes state between stages must replan before applying.
3. **Two pulls of one state can differ in `check_results` order** alone.
   Compare backups with that list sorted.

### 2026-10-28: `custodial-storage` becomes `custodial-cold-storage`

The custodial workload is renamed so that both private workloads name what
they hold the same way: `personal-cold-storage` and `custodial-cold-storage`.

1. **It moves to `workloads/private/custodial-cold-storage/`.** Its `name`,
   `suffix` and project `name:` become `custodial-cold-storage`, and its
   prefix stays `cus`.

   | Leaf | After |
   | --- | --- |
   | `scaleway/project/main` | `custodial-cold-storage`, renamed in place |
   | `scaleway/{iam-application,iam-policy}/deployer` | `cus-custodial-cold-storage-deployer`, renamed in place |
   | `scaleway/iam-api-key/deployer` | unchanged |
   | `scaleway/bucket/state` | unchanged: its name carries no suffix |
   | `backblaze/api-key/deployer` | `cus-custodial-cold-storage-backblaze-deployer`, replaced |
   | the custodial bucket | unchanged |

2. **It moved as §4 describes.** All seven keys were pushed to their new
   paths and the old leaves emptied before the PR planned.
   noisypigeon/runway#96 applied in three stages and merged. Its only
   changes were the in-place renames, the key's replace and the old leaves'
   outputs.
3. **It converges.** From `main` after runway#96, all 17 leaves of both
   workloads plan `No changes.` with refresh. The custodial bucket, the
   state bucket and the project keep the IDs in their backups.
4. **The results amendment's item 1 recurred.** runway is still on
   `workflows/v8.2.0`, so the seven removed leaves showed as
   `failed to plan` in each later stage. `workflows/v9.0.2` stops that
   (noisypigeon/library#229).
