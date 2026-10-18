# LIB-0007: Terraform state on Cloudflare R2, with an offsite copy in Backblaze B2

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted; amended 2026-10-17 (see `## Amendments`).
- **Amended 2026-10-16**: §4 now describes the copy as it ships since
  `workflows/v1.5.2` and `v1.5.3` (#44, #45), over B2's S3-compatible API. It
  also links the restore runbook, and Out of scope links its issues.

## Context

`terragrunt/root-hcl` v2.0.0 has one state backend, hardcoded. Every spoke
keeps its state in its own Scaleway Object Storage bucket
(`s3.fr-par.scw.cloud`), authenticated with the Scaleway keys, and each bucket
has object versioning on (ADR-0130/0132/0133).

Cloudflare R2 is a better fit for state:

- **It's free at this size.** The free tier covers a few dozen small state
  files many times over.
- **Egress is free,** so every `init`, `plan` and backup read costs nothing.
- **Its `eu` jurisdiction is enforced,** which LIB-0006 already requires for
  every R2 bucket in this family.

Moving to it raises two problems:

- **R2 has no object versioning.** Cloudflare's S3 compatibility table lists
  `PutBucketVersioning` and `GetBucketVersioning` as unimplemented. A Scaleway
  bucket can roll a bad state write back to the previous version; an R2 bucket
  can't. Losing state history is the one real cost of the move.
- **Terraform allows one backend per root module.** Terragrunt's
  `remote_state` generates exactly that one `backend` block, so state can't be
  written to R2 and somewhere versioned in the same operation. Dual writes from
  `after_hook`s would run only where the hook runs, and only when it succeeds.
  That makes for a backup no one can reason about.

R2 does support conditional writes (`If-None-Match`, evaluated atomically),
so Terraform's S3 lockfile would work on it. No backend in this family locks
today.

## Decision

### 1. `spoke.hcl` chooses the state backend

`root.hcl` v2.1.0 reads an optional `state_backend` from `spoke.hcl`:

```hcl
locals {
  root_hcl_version    = "2.1.0"
  state_bucket_secret = "NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME"
  state_backend       = "cloudflare"   # or "scaleway", the default
}
```

- **`"scaleway"` is the default.** A spoke that doesn't set the key renders
  byte-for-byte what v2.0.0 rendered, so taking v2.1.0 is a no-op.
- **`"cloudflare"`** points the S3 backend at the account's EU R2 endpoint,
  `https://<account_id>.eu.r2.cloudflarestorage.com`, with `region = "auto"`,
  path-style addressing and `skip_s3_checksum`. It also sets Terragrunt's
  `skip_bucket_versioning` and `disable_bucket_update`, so Terragrunt never
  tries to enable versioning on, or otherwise manage, a bucket that can't
  version.
- **Any other value is a hard error,** naming the value and the known ones.
- **One backend per spoke.** `state_backend` isn't a provider in the LIB-0005
  sense and can't be scoped to leaves. Mixing backends within one spoke would
  mean two places to look for any state.

### 2. The state key doesn't depend on the backend

Both backends use `bucket = <state_bucket_secret's value>` and
`key = <path_relative_to_include()>/terraform.tfstate` (LIB-0001 invariant 4).
Moving a spoke between backends copies objects key for key; no address and no
key changes.

### 3. R2 credentials are S3 keys made by hand

Cloudflare has no Terraform resource for R2's S3-compatible access keys, so
they're created in the dashboard as an R2 API token with *Object Read & Write*,
scoped to the one state bucket. They're stored in the spoke's `secrets.enc` as
`CLOUDFLARE_R2_ACCESS_KEY_ID` and `CLOUDFLARE_R2_SECRET_ACCESS_KEY`. Like the
Scaleway backend keys, they're read whether or not the `cloudflare` provider is
on for a leaf (LIB-0005 §6). The account ID is the existing
`CLOUDFLARE_ACCOUNT_ID`.

### 4. An R2 state bucket is copied offsite to a versioned B2 bucket

R2 is the only backend Terraform reads or writes. A spoke on R2 also copies
its state objects to a Backblaze B2 bucket:

- **The copy is `rclone copy`,** never `sync`, of every `terraform/**` object
  from the R2 state bucket to the B2 backup bucket. It runs after every CI
  apply and on a daily schedule, which catches local applies within a day.
  pigeon-lib ships it as the reusable `state-backup.yml` workflow (since
  `workflows/v1.5.0`; as described here since `v1.5.3`).
- **It reaches B2 through B2's S3-compatible API.** It doesn't use rclone's
  `b2` backend, which authenticates with B2's API v1, and B2 refuses that. The
  account's S3 endpoint is read at run time from the key's own
  `b2_authorize_account` (v4).
- **It decides what to copy by MD5,** read from the two bucket listings
  (`--checksum`). With `--s3-no-head`, rclone never reads or rewrites a B2
  object, which the backup key couldn't do anyway.
- **B2 keeps every version.** A B2 bucket with no lifecycle rules retains all
  versions of a file, so each state write that reaches B2 is kept.
- **The B2 key can list and write, nothing else.** `listBuckets`, `listFiles`
  and `writeFiles`, scoped to the backup bucket, with no expiry. A compromised
  or buggy copy job can add versions but can't read, hide or delete any.
- **A restore uses a separate admin key, by hand,** through B2's native API v4.
  The admin key may be the account's master key, which B2's S3 API refuses. The
  steps are in
  [`docs/runbooks/restore-terraform-state-from-b2.md`](../runbooks/restore-terraform-state-from-b2.md).
- **The cost is storage only.** R2 egress and B2 ingress are both free, so B2
  bills for the bytes it keeps, and for downloads only on a restore.

This makes offsite backup a property of the state layout, not of each spoke's
habits. A spoke on Scaleway doesn't need it: its bucket versions in place.

## Consequences

- **A spoke can move to R2 by changing two `spoke.hcl` lines** and copying its
  state objects across. The copy follows LIB-0004 §3's pull/push runbook, keyed
  identically, so it's checked by `serial` and `lineage` rather than trusted.
- **The rollback window is the copy interval.** A state write that corrupts R2
  between two backup runs can only be recovered from B2's previous version,
  which is at most a day old for a local apply. For a CI apply it's the version
  just before it.
- **A restore needs a different key** than the backup job has. That's by
  design, but it means a restore is a manual, admin-key operation.
- **Each R2 spoke gains two leaves and a key:** a B2 bucket and its
  list-and-write key, plus `BACKBLAZE_*` admin keys in `secrets.enc` to create them.
- **v2.1.0 is a minor release.** No spoke has to change anything to take it.

## Out of scope

- **More than one backend per leaf, or dual writes through hooks.** This is
  permanent: Terraform allows one backend, and §4's copy is the deliberate
  answer.
- **Mixing backends within one spoke.** Permanent, for the reason in §1.
- **State locking** (`use_lockfile` on R2). R2's conditional writes make it
  possible. It's genuinely deferred, and it would apply to both backends
  (noisypigeon/noisypigeon#315).
- **Moving `pigeon.dev` and `willowgraysen.com` to R2.** Each is that spoke's
  own decision and PR. Deferred (noisypigeon/noisypigeon#316).
- **Retiring a spoke's Scaleway state bucket** after its move. The old objects
  stay as a frozen, versioned rollback copy until a later decision. Deferred
  (noisypigeon.com's: noisypigeon/noisypigeon#317).

## Verification

1. **Render parity.** Every `pigeon.dev` leaf (4) was rendered with
   `terragrunt render --json` under v2.0.0 and under this template, with no
   `state_backend` set. Every top-level key other than `locals`, `remote_state`
   included, hashed identically.
2. **The R2 backend.** With `state_backend = "cloudflare"`, `remote_state.config`
   rendered with:
   - the `eu.r2.cloudflarestorage.com` endpoint and `region = "auto"`;
   - `use_path_style`, `skip_s3_checksum`, `skip_bucket_versioning` and
     `disable_bucket_update`;
   - the same key as under Scaleway.

   With `state_backend = "scaleway"`, it matched the default.
3. **The guard.** `state_backend = "bogus"` failed the render with
   "spoke.hcl state_backend is bogus; known: scaleway, cloudflare".
4. **The release.** This record's PR changes `terragrunt/root-hcl/root.hcl` and
   carries `release:minor`, so its merge should cut
   `terragrunt/root-hcl/v2.1.0`. `state-backup.yml` shipped in its own PR (#40) as
   `workflows/v1.5.0`.

## Amendments

### 2026-10-17: COM-0004, `noisypigeon.com`'s state moves to R2 (folded from `noisypigeon/blog`)

Filed 2026-10-15. This was the first spoke to adopt this record. Accepted, and
amended 2026-10-16 when COM-0005 retired its Scaleway rollback copy.

**Decision.**

1. **Three new leaves** (noisypigeon.com#19):
   - the R2 state bucket, EU jurisdiction (LIB-0006);
   - a B2 backup bucket with no lifecycle rules, so B2 keeps every version;
   - a B2 key with `listBuckets`, `listFiles` and `writeFiles` on that bucket
     only, never expiring.

   The first apply ran each new leaf twice, concurrently, and orphaned a B2
   bucket and key. Both were deleted by hand, and pigeon-lib#41
   (`workflows/v1.5.1`) fixed the cause before the re-apply.
2. **The cutover.** `spoke.hcl` takes `root_hcl_version = "2.1.0"`,
   `state_backend = "cloudflare"` and the R2 bucket's secret name. The R2 S3
   keys are a hand-made R2 API token with *Object Read & Write* scoped to the
   state bucket, because Cloudflare has no Terraform resource for them.
3. **Objects are copied, not pushed.** Each leaf's state object went across
   with `rclone copyto`, byte for byte, using `--s3-no-check-bucket` because
   the bucket-scoped token can't create buckets. `terraform state push` was
   tried first, and **into a freshly initialized R2 backend it kept the new
   remote's lineage**. A straight copy keeps serial and lineage, which is what
   makes the move checkable. Old keys left behind by the LIB-0004 renames were
   not copied.
4. **Backups run after every apply,** through a `backup` job in
   `terragrunt-apply.yml` that runs even after a failed apply, and daily and on
   demand through a `state-backup.yml` caller, which also picks up local
   applies.

**Still true.**

- State costs nothing to keep or read: it fits well within R2's free tier,
  and R2 has no egress fees.
- After a CI apply, B2 holds the state from just before it; after a local
  apply, a copy at most a day old.
- The R2 bucket leaf's state lives in the bucket it manages, so destroying it
  would destroy every leaf's state.

**Later.** COM-0005 retired the Scaleway bucket that §3 of the original kept as
a rollback copy, so recovery is now a restore from B2.

Original: [COM-0004](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0004-terraform-state-on-r2.md).

### 2026-10-17: DEV-0164, `pigeon.dev`'s state moves to R2, then Scaleway is retired (folded from `noisypigeon/garden`)

Filed 2026-10-16. Accepted. The full text is also archived as
[`archive/DEV-0164`](archive/DEV-0164-terraform-state-on-r2-and-retire-scaleway.md).

**Decision.**

1. **The same move as COM-0004:** three new leaves, the Backblaze provider
   turned on for `terraform/backblaze/`, hand-made R2 keys, a byte-for-byte
   `rclone copyto --s3-no-check-bucket` checked by serial, lineage and
   resource count, and the cutover with both backup callers.
2. **Then Scaleway was retired in COM-0005's order:**
   - the bucket, by `force_destroy` and then leaf removal;
   - the project, in its own PR;
   - `scaleway` dropped from `providers` (LIB-0005), with the five Scaleway
     secrets removed;
   - finally `state/iam`'s deploy key, destroyed in `noisypigeon`.
3. **The Scaleway bucket's version history was let go.**

**Still true.**

- The domain runs on Cloudflare and Backblaze only.
- Recovery is a restore from B2.
- DEV-0163's `state/iam` arrangement ended, settling
  noisypigeon/noisypigeon#308 for this spoke by retirement.

**Verification.** Every step's apply count is recorded in the archived text.
The account ended with no `pigeon-dev` project, and no
`pigeon-dev-terraform-deploy` application. `mise run plan` showed
`No changes.` on 5/5 leaves without installing the Scaleway provider.

Original: [DEV-0164](https://github.com/noisypigeon/garden/blob/13bcee9a79c86a3a0054ebda7cd6d7fa7c238df2/adr/DEV-0164-terraform-state-on-r2-and-retire-scaleway.md).
