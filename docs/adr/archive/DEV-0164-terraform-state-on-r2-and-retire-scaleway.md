# DEV-0164: move `pigeon.dev`'s Terraform state to Cloudflare R2, then retire Scaleway

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted.

## Context

[LIB-0007](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0007-terraform-state-on-r2-with-offsite-backup.md)
gives `root.hcl` v2.1.0 a Cloudflare R2 state backend. It pairs every R2 state
bucket with a versioned Backblaze B2 copy made by `state-backup.yml`, because R2
can't version objects. Moving each remaining spoke is that spoke's own decision
(noisypigeon/noisypigeon#316).

`noisypigeon.com` went first:
- COM-0004 moved its state to R2;
- COM-0005 retired its Scaleway resources.

This repo is in the same position:

- **Four leaves:** `cloudflare/dns-record/fastmail`,
  `cloudflare/dns-record/github-pages`, `scaleway/project/dev` (the `pigeon-dev`
  project) and `scaleway/object-bucket/terraform-state`. The last is the state
  bucket, `pigeon-dev-99vanh-terraform-state`, with versioning on (ADR-0130).
- **A preflight listing** of the project's Object Storage in fr-par, nl-ams and
  pl-waw found that bucket and nothing else.
- **The deploy key** is `pigeon-dev-terraform-deploy`, minted by
  `pigeon.dev/terraform/state/iam` in `noisypigeon/noisypigeon` (LIB-0001 §8,
  DEV-0163). This repo's Scaleway provider and backend authenticate with it.
- **The state bucket, the project and that key are this domain's only Scaleway
  resources.** Everything else is Cloudflare.

## Decision

### 1. State moves to R2, backed up to B2

Following LIB-0007, and as COM-0004 did:

- **Three new leaves:**
  - `cloudflare/bucket/terraform-state`: `dev-<random>-terraform-state`, EU
    jurisdiction (LIB-0006);
  - `backblaze/bucket/terraform-state-backup`: no lifecycle rules, so every
    version is kept;
  - `backblaze/api-key/terraform-state-backup`: `listBuckets`, `listFiles` and
    `writeFiles` on that bucket only, never expiring.

  `spoke.hcl` turns the Backblaze provider on for `terraform/backblaze/`.
- **Hand-made keys.** An R2 API token with *Object Read & Write*, scoped to the
  state bucket, supplies `CLOUDFLARE_R2_ACCESS_KEY_ID` and
  `CLOUDFLARE_R2_SECRET_ACCESS_KEY`. The bucket names and the backup key are
  hand-copied from the leaves' outputs.
- **The state objects are copied byte for byte** from Scaleway to the same keys
  in R2 with `rclone copyto --s3-no-check-bucket`, and checked by serial, lineage
  and resource count. COM-0004 found that `terraform state push` into a fresh R2
  backend keeps the remote's new lineage.
- **The cutover** sets `root_hcl_version = "2.1.0"`, `state_backend = "cloudflare"`
  and `state_bucket_secret = "PIGEON_DEV_R2_TERRAFORM_STATE_BUCKET_NAME"`. It
  also adds the backup callers:
  - a `backup` job after every apply, even a failed one;
  - a daily and on-demand `state-backup.yml`.

### 2. Then Scaleway is retired, in COM-0005's order

1. **The bucket.** `force_destroy = true` is applied on its own first, because a
   destroy only empties a versioned bucket if the setting is already in state.
   Then the leaf is removed, and CI destroys the bucket with every version.
2. **The project.** `scaleway/project/dev` is removed in its own PR. A removed
   leaf can't declare a dependency, and the project can't go while it holds a
   bucket.
3. **Scaleway off.** `spoke.hcl` drops `scaleway` from `providers`. That's
   LIB-0005's map, so no template change is needed. `terraform/secrets.enc`
   loses `SCALEWAY_ACCESS_KEY`, `SCALEWAY_SECRET_KEY`,
   `SCALEWAY_ORGANIZATION_ID`, `SCALEWAY_PROJECT_ID` and
   `PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME`.
4. **The deploy key.** `noisypigeon/noisypigeon` destroys
   `pigeon.dev/terraform/state/iam`, last, because every destroy above
   authenticates with it.

### 3. The Scaleway bucket's version history is let go

As in COM-0005: the old bucket's versions are destroyed with it, not exported.
The current state lives in R2, and every write from the cutover on is versioned
in B2.

## Consequences

- **This domain runs on Cloudflare and Backblaze only,** with five leaves: the
  two DNS leaves and the three state leaves.
- **Recovering state means restoring from B2,** following pigeon-lib's
  `docs/runbooks/restore-terraform-state-from-b2.md`. No Scaleway copy is left
  to fall back to.
- **DEV-0163's `state/iam` arrangement ends.** This settles
  noisypigeon/noisypigeon#308 for `pigeon.dev` by retirement: there's no deploy
  key left to bootstrap.
- **The R2 bucket leaf's state lives in the bucket it manages.** Destroying it
  would destroy every leaf's state.
- **The emptied state objects** of removed leaves stay in R2 and B2, harmless.

## Out of scope

- **State locking.** LIB-0007 defers it for every spoke
  (noisypigeon/noisypigeon#315).
- **`willowgraysen.com`'s move** (noisypigeon/noisypigeon#316). Its own decision.
- **Re-adding Scaleway.** It would mean a new key, the provider back in the map,
  and new leaves. That's a later decision if one is ever needed, not a deferral.

## Verification

1. **The new leaves (#32).** The apply created five resources, each leaf
   exactly once. That's on `workflows/v1.5.3`, pinned first in #31 for the
   duplicate-run fix. Afterwards, the account listed one new R2 bucket,
   `dev-2j1cmn-terraform-state`, and one new B2 bucket,
   `dev-65bctm-terraform-state-backup`.
2. **The copy.** All seven leaves' state objects were copied from Scaleway to
   R2. For every leaf, a `terragrunt state pull` from R2 on the cutover branch
   matched the pull from Scaleway on a worktree of `main` in serial, lineage
   and resource count.
3. **The cutover (#33).** `mise run plan` and CI, both against R2, showed
   `No changes.` on 7/7 leaves. After merging, a manual `state-backup.yml` run
   found 7 files in R2 and 7 in B2.
4. **The bucket (#34, #35).** #34 applied one change, `force_destroy`. #35's
   apply destroyed two resources, the bucket and its suffix. Afterwards, a
   listing of fr-par Object Storage with the deploy key returned no buckets.
5. **The project (#36).** The apply destroyed one resource. Afterwards, the
   organization's only project was `willowgraysen`.
6. **The deploy key (noisypigeon/noisypigeon#319).** The apply destroyed four
   resources: the application, its policy, its key and the key's `time_static`.
   Afterwards, the organization had no `pigeon-dev-terraform-deploy`
   application.
7. **Scaleway off.** With `scaleway` dropped from `providers` and the secrets
   removed, `mise run plan` showed `No changes.` on 5/5 leaves, without
   installing the Scaleway provider.
