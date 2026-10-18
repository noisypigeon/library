# LIB-0016: Terraform state bucket names follow the repo names

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-17.
- **Status**: Accepted.

## Context

Each spoke has been renamed so that its repo name says what it is: LIB-0013
renamed `willowgraysen` to `runway`, COM-0007 renamed the `noisypigeon.com`
repo to `blog`, DEV-0165 made `pigeon.dev` into `garden`, and LIB-0015
renamed the hub to `library`. The state buckets kept the prefixes they were
created with, which come from the old domains:

| Spoke | Leaf | Bucket today |
| --- | --- | --- |
| garden | `terraform/cloudflare/bucket/terraform-state` | `dev-<code>-terraform-state` (R2) |
| garden | `terraform/backblaze/bucket/terraform-state-backup` | `dev-<code>-terraform-state-backup` (B2) |
| blog | `terraform/cloudflare/bucket/terraform-state` | `com-<code>-terraform-state` (R2) |
| blog | `terraform/backblaze/bucket/terraform-state-backup` | `com-<code>-terraform-state-backup` (B2) |
| runway | `terraform/scaleway/object-bucket/terraform-state` | `willowgraysen-com-<code>-terraform-state` (Scaleway) |

`<code>` is the six-character random suffix each bucket module draws. The B2
backup draws its own, so nothing in its name ties it to the R2 bucket it
copies (LIB-0007 §4). Today the only link is the leaf's `description`.

None of R2, B2 or Scaleway can rename a bucket. A new name means a new bucket
and a copy of every object. The state-bucket leaf is also the awkward case: its
own state lives in the bucket it manages. Changing its `name_prefix` would plan
a replacement, and the destroy half would fail on a non-empty bucket, or
succeed and take every leaf's state with it.

The state bucket's name reaches Terraform only through
`terraform/secrets/terraform.enc`'s `TERRAFORM_STATE_BUCKET_NAME`, and the
backup's through `TERRAFORM_STATE_BACKUP_BUCKET_NAME` (LIB-0010, LIB-0012).
Nothing else in a spoke or in this repo names either bucket.

## Decision

### 1. The names

- **A state bucket is `<repo>-<code>-terraform-state`,** where `<repo>` is the
  spoke's GitHub repo name: `garden-<code>-terraform-state`,
  `blog-<code>-terraform-state` and `runway-<code>-terraform-state`. `<code>`
  is drawn afresh: the new bucket doesn't keep the old one's suffix.
- **Its B2 backup, where `state_backup = true`, is exactly
  `<state bucket name>-backup`.** Either name then gives you the other, and the
  backup has no random code of its own.
- **The B2 backup key is `<repo>-terraform-state-backup`,** following the same
  rule as the bucket.

### 2. `backblaze/bucket` gains `exact_name`

`cloudflare/bucket` and `scaleway/object-bucket` already take an `exact_name`
that bypasses the prefix/random/suffix scheme. `backblaze/bucket` gets the
same input, with the same meaning, as a minor release. No `random_string` is
created when it's set.

The backup leaf sets `exact_name` to the R2 leaf's `name` output plus
`-backup`, through a Terragrunt `dependency` on
`../../../cloudflare/bucket/terraform-state`. The api-key leaf already reads
the bucket leaf the same way. So the backup's name follows the state bucket's
by construction, not because someone copied it by hand.

### 3. Leaf paths and state keys don't change

Each leaf keeps its directory. Only the bucket leaves' inputs change
(`name_prefix`, or `exact_name` for B2) and the api-key leaf's `key_name`. Every
leaf's key stays `<path_relative_to_include()>/terraform.tfstate`. The copy in
§4 moves objects key for key, so no leaf finds out that its state moved
(LIB-0001 invariant 4, LIB-0007 §2).

### 4. The cutover, one spoke at a time

Nothing may be applied in the spoke from step 3 until step 5 passes.

1. **Release the old bucket.** `terraform state rm` every resource in the
   state-bucket leaf, the `random_string` included. The old bucket becomes
   unmanaged and stays as it is. No destroy is ever planned against it.
2. **Create the new one.** Change the leaf's `name_prefix` and apply it. The
   apply draws a new code and creates the new bucket. The leaf's own state is
   still written to the old bucket, because the secret hasn't changed yet.
3. **Copy the state.** `rclone copy` every `terraform/**` object from the old
   bucket to the new one, as LIB-0007 §4 does, never `sync`. Each object is
   checked by SHA-256, `serial` and `lineage`, as in LIB-0004 §3's pull/push
   runbook.
4. **Point Terraform at it.** Hand-copy the new name into
   `TERRAFORM_STATE_BUCKET_NAME`.
   - **R2:** the R2 API token is made by hand and scoped to one bucket
     (LIB-0007 §3), so a new token scoped to the new bucket replaces it in
     `TERRAFORM_STATE_ACCESS_KEY_ID` and `TERRAFORM_STATE_ACCESS_KEY`. The old
     token is then revoked.
   - **Scaleway:** runway's deployer (LIB-0014 §4) holds
     `ObjectStorageFullAccess` on the project, not on one bucket, so its keys
     don't change.
5. **Prove nothing moved.** Every leaf runs `init -reconfigure` and plans
   `No changes.` A leaf that plans anything means the copy is incomplete, so
   the cutover stops there, and the secret goes back to the old name until
   it's fixed.
6. **Then the backup (garden and blog only).** Do the same `state rm` in the B2
   bucket leaf, then apply it with `exact_name`. The api-key leaf's
   `bucket_ids` and `key_name` both change, so it plans a replacement. Its new
   values go into `TERRAFORM_STATE_BACKUP_*`, along with the new bucket's
   name. Then dispatch `state-backup.yml` once, and check that it lists the
   same objects on both sides.

Until step 6, the scheduled backup keeps copying into the old B2 bucket. That's
harmless: the objects it copies are the same ones.

### 5. History stays where it was written

A copy carries current objects only. The new B2 bucket starts its version
history at the cutover. Every earlier version stays in the old B2 bucket, and
runway's in the old, versioned Scaleway bucket. The restore runbook reads
the backup bucket's name from `TERRAFORM_STATE_BACKUP_BUCKET_NAME`, so a
restore from before the cutover sets that variable to the old bucket's name
for the run.

## Consequences

- **Three hand-run migrations,** each with a short no-apply window (§4 steps
  3–5). Each is that spoke's own PR. Its plan must show the new bucket created
  and nothing destroyed.
- **Each spoke holds two sets of buckets** until the old ones are retired. That
  costs storage only, and these are a few small files.
- **Rollback history is split** across the old and new B2 buckets (and
  Scaleway buckets for runway) at the cutover date. A restore from before it
  reads the old bucket.
- **The backup's name is tied to the state bucket's.** A later state bucket
  rename renames its backup too, in the same cutover.
- **The hub's only change is `backblaze/bucket`'s minor release.** `root.hcl`,
  the secrets schema and `state-backup.yml` already take bucket names as
  secrets, so none of them changes.

## Out of scope

- **Retiring the old buckets.** They stay as frozen, unmanaged rollback copies,
  as LIB-0007 left the Scaleway buckets, until a later decision empties and
  deletes them. Genuinely deferred: a GitHub issue against
  `noisypigeon/noisypigeon`.
- **Renaming buckets that don't hold state,** such as runway's `pigeon-*`
  Object Storage buckets or its other B2 buckets. This record's rule covers
  state and its backup only.
- **Renaming leaf directories.** Permanent: a leaf's path is its state key
  (LIB-0001 invariant 4).
- **`noisypigeon/noisypigeon`'s state.** A permanent boundary, as in LIB-0014
  and LIB-0015.
- **State locking.** Still noisypigeon/noisypigeon#315, unchanged by a new
  bucket.
