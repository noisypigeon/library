# LIB-0046: runway's Scaleway project and pigeon buckets become the `private/data-ops` workload

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed. Applies LIB-0037 to runway, with LIB-0040 §4's and
  LIB-0044 §3's state move. Progress on
  [#98](https://github.com/noisypigeon/library/issues/98).

## Context

runway's Scaleway project is a hand-written leaf,
`terraform/scaleway/project/runway`. It calls `scaleway/project` v2.0.0,
which holds the project `runway` and one SSH key, `noisypigeon`.

Everything else under runway's `terraform/scaleway/` lives in that project:
the spoke's state bucket, pigeon-cli's cluster, Cockpit and IAM, the spoke
deployer, and four buckets pigeon-cli writes:

| Leaf | Bucket |
| --- | --- |
| `bucket/pigeon-cli-email` | `pigeon-cli-rkinck-email` |
| `bucket/pigeon-cli-email-reports` | `pigeon-cli-p7xktm-email-reports` |
| `bucket/pigeon-cli-reports-transform` | `pigeon-cli-gkq3v5-reports` |
| `bucket/pigeon-transform` | `pigeon-spc6f1-transform` |

None of those leaves reads the project leaf. Each takes its project from
`SCALEWAY_PROVIDER_PROJECT_ID` in `terraform/secrets/scaleway.enc`, as a
`local.scaleway_project_id` input or as the provider's default. That secret
holds the project's ID.

So the project is owned by a leaf nothing depends on, under a name that
says which spoke made it rather than what it holds. #98 asks for runway's
hand-written leaves to move into workloads. The project and these four
buckets can move now. The rest can't move in the same step: the cluster,
Cockpit and IAM have no workload kind that matches them as written, and the
state bucket is the spoke's backend.

## Decision

### 1. `private/data-ops` owns the project

A private workload takes over the existing project:

```yaml
workload:
  name: data-ops
  deployments:
    scaleway:
      project:
        prefix: wg
        suffix: data-ops
        ssh_key:
          alias: noisypigeon
          public_key: <the old leaf's key>
```

- **The project is renamed in place, `runway` → `wg-data-ops`.** The name is
  the project kind's `<prefix>-<suffix>` default. Its ID doesn't change, so
  the secret and every leaf that reads it stay as they are.
- **The SSH key moves with it.** It's an input of the same module and sits in
  the same state. Its ID doesn't change.
- **Its deployer and state bucket are new:** `wg-data-ops-deployer`, and
  `wg-<code>-terraform-state`, with no suffix since the workload has its own
  project (LIB-0040's 2026-10-27 amendment).

### 2. The old project leaf becomes a lookup

`terraform/scaleway/project/runway` stays at its path and owns nothing:

```hcl
data "scaleway_account_project" "project" {
  project_id = local.scaleway_project_id
}
```

It outputs `id` and `name`. Keeping the path keeps its state key, so CI
doesn't plan a removed leaf. A later hand-written leaf can read the project
through it rather than through the secret.

### 3. The four pigeon buckets move into the workload

Each becomes a `scaleway.bucket` entry whose key is its old leaf's name. Each
entry writes its old leaf's `name_prefix` and `name_suffix`, and every other
input the old leaf set:

| Entry | `name_prefix` | `name_suffix` | Also |
| --- | --- | --- | --- |
| `pigeon-cli-email` | `pigeon-cli` | `email` | `storage_class: glacier` |
| `pigeon-cli-email-reports` | `pigeon-cli` | `email-reports` | `storage_class: standard` |
| `pigeon-cli-reports-transform` | `pigeon-cli` | `reports` | `storage_class: standard`, `expiration_days: 3` |
| `pigeon-transform` | `pigeon` | `transform` | none: the module's `glacier` default |

- **Names and IDs don't change.** The random code moves with the state.
- **`project_id` is wired from the workload's project.** It's the ID the
  provider default gave each bucket, so it plans no change.
- **`bucket/terraform-state` stays hand-written.** It's the spoke's backend,
  and the workload's own deployer and state bucket keep their state in it.

### 4. State moves by copy, not import

As LIB-0044 §3 found, an imported `random_string` plans a replace, and with
it the bucket. Every leaf here moves by LIB-0040 §4's copy instead, with
runway frozen from the first push until the PR that commits it merges:

1. Pull the old leaf's state twice into a backup outside every checkout.
2. Rename its addresses in the backup:

   | Old address | New address |
   | --- | --- |
   | `module.project.scaleway_account_project.project` | `module.this.scaleway_account_project.project` |
   | `module.project.scaleway_iam_ssh_key.key[0]` | `module.this.scaleway_iam_ssh_key.key[0]` |
   | `module.bucket.random_string.suffix[0]` | `module.this.random_string.suffix[0]` |
   | `module.bucket.scaleway_object_bucket.bucket` | `module.this.scaleway_object_bucket.bucket` |

   The buckets' state already holds `suffix[0]`, so no `moved` block runs
   (unlike LIB-0040's amendment 3).
3. Check the new leaf's backend is empty, push the backup, then rewrite its
   outputs from a `-refresh=false` plan.
4. Plan the new leaf. A bucket must exit 0. The project must show one
   in-place update, its name, and nothing else.
5. Empty the old leaf with `state rm`, and check it holds no resources and no
   outputs (LIB-0040's amendment 2).

### 5. Two runway PRs

The project exists already, so it can't be bootstrapped the way LIB-0040's
and LIB-0044's projects were. It moves in the bootstrap instead:

1. **Move the project.** Add `workload.yaml` with only its project, rewrite
   the old leaf as §2's lookup, and move the project's state (§4). The PR
   plans the rename, creates the deployer's three leaves and the state
   bucket, and destroys nothing. Replan after the push and before applying
   (LIB-0044's amendment, item 2).
2. **Move the buckets.** Once the workload's state bucket exists, move each
   bucket's state (§4), then add the four entries and delete the four old
   leaves. The PR creates, replaces and destroys nothing.

## Consequences

- **runway's project says what it holds,** and a workload owns it. The
  rename touches nothing that reads its ID.
- **pigeon-cli's buckets are declared in one file.** A new one is one more
  entry.
- **`data-ops` isn't isolated yet.** `wg-data-ops` still holds the spoke's
  state bucket and pigeon-cli's hand-written leaves. The workload's deployer
  must keep `ObjectStorageFullAccess` on the project (LIB-0028 §5), so it can
  reach every runway leaf's state. That's the isolation LIB-0044 gave the
  custodial bucket, and `data-ops` doesn't have it until the rest of the
  project's contents leave.
- **The bucket names keep their `pigeon` and `pigeon-cli` prefixes.** Only
  their state moves.

## Out of scope

- **runway's other hand-written Scaleway leaves:** pigeon-cli's cluster,
  Cockpit, IAM applications, policies and keys, and the spoke deployer. They
  stay in `wg-data-ops`, under
  [#98](https://github.com/noisypigeon/library/issues/98).
- **Moving `bucket/terraform-state` into any workload.** The spoke's backend
  holds the bootstrap state of every workload, this one's included. This is a
  permanent boundary.
- **A LIB-0045 policy that keeps Scaleway buckets in `data-ops`.** LIB-0045
  ships `backblaze-bucket-owners` only. A Scaleway twin waits until the
  remaining leaves have moved, since today it would need an exemption for
  each of them.

## Verification

1. **The project, the secret and the buckets agree before anything moves.**
   The project leaf's ID equals `SCALEWAY_PROVIDER_PROJECT_ID`, and each of
   the four buckets' `project_id` equals it too.
2. **The first PR renames and creates, and destroys nothing.** Its only
   change to existing infrastructure is the project's name. Afterwards the
   project and the SSH key keep the IDs in the backup.
3. **The buckets moved, not recreated.** Each new bucket leaf plans
   `No changes.` before its old leaf is emptied, and Scaleway still holds all
   four under the names and IDs in the backup.
4. **It converges.** After the second PR's apply, a re-plan of every runway
   leaf, the hand-written Scaleway ones included, shows `No changes.`
