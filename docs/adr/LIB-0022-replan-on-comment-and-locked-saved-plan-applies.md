# LIB-0022: Re-plan on comment, and locked, saved-plan applies

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Accepted. Amends LIB-0003's spoke Terragrunt CI. Settles the
  state-locking item that LIB-0007 and LIB-0016 left out of scope.
- **Amended 2026-10-20**: LIB-0024 keeps `terragrunt/apply` pending after an
  apply whose plan deferred workload leaves, until a re-plan defers nothing.
- **Amended 2026-10-22**: LIB-0026 replaces the single, truncated plan or apply
  comment with a summary of one row per leaf, and detail comments of one
  section per leaf, never truncated.

## Context

`terragrunt-run.yml` runs both `plan` and `apply` for every spoke (LIB-0003).
It has two gaps.

- **A plan only follows a push.** Plan runs on `pull_request`
  (`opened`, `synchronize` and `reopened`). If a PR's plan goes stale, for
  example because another PR applied the same leaf, the only way to get a new
  one is to push a commit.
- **Apply applies whatever it finds.** `terragrunt apply` plans again
  implicitly, against whatever the state holds at that moment, and applies the
  result. Nothing ties that to the plan in the PR comment, so an apply can
  change something nobody reviewed.
- **No two applies are kept apart.** Each spoke's caller sets concurrency per
  PR (`terragrunt-pr-<n>`), so two PRs can apply at once. No backend locks
  anything: LIB-0007 deferred `use_lockfile`, and LIB-0016 carried that forward
  unchanged. Two applies of one leaf race on its state key.

Both backends this family uses can lock:

- **R2** evaluates `If-None-Match` atomically (LIB-0007's Context).
- **Scaleway Object Storage** documents `If-None-Match: *` on `PutObject`
  ([conditional writes](https://www.scaleway.com/en/docs/object-storage/api-cli/using-conditional-writes/)).
  An earlier community report found that `use_lockfile` overwrote the lock
  there. That report predates the docs, but it is why §4 has to be proved on
  Scaleway before a Scaleway spoke takes it.

Terraform has had an S3-native lockfile since 1.10. It writes a `.tflock`
object next to the state, with a conditional `PutObject`. This repo pins
Terraform 1.16.3.

## Decision

### 1. A `terragrunt plan` comment re-plans the PR's head

A PR comment whose body is exactly `terragrunt plan` reruns the plan at
`refs/pull/<n>/head`, without a new commit.

- **The gate is apply's.** The comment must come from an OWNER, MEMBER or
  COLLABORATOR, and the check stays in the spoke's caller, where it is
  reviewable.
- **The caller's plan workflow gains `issue_comment`.** Its plan job runs on
  `pull_request` or on that comment, with `checkout_ref` set to the PR head
  for the comment.
- **A re-plan shares apply's concurrency group** (`terragrunt-pr-<n>`), so a
  re-plan and an apply on one PR never overlap.
- **The reusable reacts to the comment as it does for apply**: 👀 on start,
  then 👍 or 👎. Its apply-only reaction steps become "whenever the event is
  `issue_comment`".
- **A re-plan resets `terragrunt/apply` to `pending`** on the head SHA, as
  `terragrunt-detect.yml` does for a push.

### 2. A plan is saved, encrypted, and bound to its commit

- **Each unit is planned with `-out=tfplan`.** Terragrunt writes the file into
  the unit's cache directory. A step then collects every file into one
  archive, keyed by leaf path.
- **The archive is encrypted with the spoke's age recipient** from
  `.sops.yaml`. A plan file holds sensitive values in plaintext, and an
  artifact on a public repo is readable by anyone signed in to GitHub.
- **It is uploaded as the artifact `terragrunt-plan-<pr>-<head_sha>`** and
  kept for 7 days. A plan older than that is stale in practice, and §1 makes
  a new one cheap.
- **The plan comment names the head SHA it planned,** so a reader can see
  what the apply will use.
- **A re-plan replaces the artifact for its SHA.** It deletes the old one
  before it plans, and uploads only if the plan succeeds. A failed re-plan
  leaves no artifact, so apply can't fall back to the plan it superseded.

### 3. Apply applies the saved plan, and nothing else

- **Apply resolves the PR's head SHA and downloads exactly that artifact.** If
  there is none, because the head moved after the plan, the plan failed, or
  the artifact expired, apply fails before touching anything and says:
  "no plan for `<sha>`; comment `terragrunt plan`".
- **It decrypts the archive into each unit's cache and runs**
  `terragrunt run --all … -- apply tfplan` over the same unit set the plan
  chose. The unit-selection logic in `terragrunt-run.yml` stays one
  implementation, shared by both commands.
- **A stale plan fails.** Terraform refuses a saved plan when the state's
  serial or lineage has changed since the plan was made. That covers the case
  where another PR applied the same leaf after this PR planned. The failure
  comment says to re-plan, which §1 makes a single comment.

### 4. Both backends lock, and a held lock fails at once

- **`root.hcl` sets `use_lockfile = true`** in `scaleway_state_config` and
  `cloudflare_state_config`. The lock's key is the state key plus `.tflock`,
  so it follows LIB-0001 invariant 4 in both backends.
- **Apply runs with `-lock-timeout=0s`.** A second apply of a leaf that is
  being applied fails straight away on the lock, rather than waiting for it
  and then applying a stale plan. Plan keeps Terraform's default, which takes
  the lock and gives it back.
- **The two failures add up to one rule.** Two PRs applying the same leaf at
  the same time: the second fails on the lock. One after the other: the second
  fails on its stale plan. Either way the second PR needs a new plan.
- **A lock left by a crashed run is released by hand,** with
  `terragrunt force-unlock <id>` in that leaf, after checking that no run
  holds it. A runbook, `docs/runbooks/release-a-stuck-state-lock.md`, gives the
  steps.
- **State backup skips locks.** `state-backup.yml` copies `terraform/**`, and
  its B2 key can't delete. A stray `.tflock` copied there could never be
  removed, so the copy and its post-copy check exclude `*.tflock`.

### 5. Release impact

- **`workflows/` takes a major version.** An apply now needs a plan artifact
  made by the same major version, and the caller's apply job needs
  `actions: read` to download it.
- **`terragrunt/root-hcl` takes a minor version.** `use_lockfile` is
  additive: nothing a spoke sets changes, and every leaf plans `No changes.`
- **Spokes adopt in their own PRs,** template first, then workflows. The R2
  spokes (garden, blog) go first. runway, on Scaleway, takes the template only
  after Verification 1 has passed against Scaleway.

## Consequences

- **The plan in the PR comment is the plan that gets applied.** An apply can
  no longer do something nobody reviewed.
- **One leaf, one apply at a time,** on both backends, without a spoke-wide
  lock. PRs that touch different leaves still apply in parallel.
- **A merge can invalidate other PRs' plans.** When one PR applies a leaf,
  every other open PR that planned that leaf has to re-plan. It should usually
  rebase first: a branch without the merged change plans to undo it.
- **One more artifact per plan,** encrypted and short-lived.
- **A crash can leave a lock behind.** That is a manual release, which is the
  price of the lock never being taken over automatically.
- **A failed re-plan blocks apply** until a plan succeeds. Its comment
  minimizes the old plan's, as a push's plan does now.

## Out of scope

- **A spoke-wide apply lock.** Locking each leaf already stops two applies
  racing, and a spoke-wide lock would also serialize PRs that touch different
  leaves. A permanent boundary.
- **Requiring PRs to be up to date with `main`.** That is a ruleset setting
  for each spoke's owner, not something the reusable CI enforces. A permanent
  boundary.
- **Re-planning other open PRs after an apply.** Deferred
  ([#89](https://github.com/noisypigeon/library/issues/89)).
- **Implementing §§1–5.** This record decides the design. The workflow,
  template, backup and runbook changes ship in later PRs that cite it
  ([#88](https://github.com/noisypigeon/library/issues/88)).

## Verification

To be completed when §§1–5 ship.

1. **The lock holds on both backends.** In a scratch leaf, two concurrent
   `terraform apply -lock-timeout=0s` runs against one state key fail the
   second with `Error acquiring the state lock`, on R2 and on Scaleway. On
   Scaleway, also check that a second `PutObject` of the `.tflock` key with
   `If-None-Match: *` returns `412`.
   - **Scaleway: passed, 2026-10-20**, against a throwaway key
     (`lock-test/lib-0022/`) in runway's state bucket, with Terraform 1.16.3.
     The first apply wrote `terraform.tfstate.tflock` and held it. The second
     apply, with `-lock-timeout=0s`, failed at once with
     `Error acquiring the state lock`. The first apply then completed and
     released the lock. A second `PutObject` with `If-None-Match: *` on an
     existing key returned `PreconditionFailed` (412). Every test object was
     deleted afterwards. The community report in the Context does not
     reproduce, so runway may take root-hcl 4.2.0 (§5).
2. **A stale plan is refused.** PR A and PR B both plan one leaf. A applies.
   B's apply fails with `Saved plan is stale`, and B applies after a
   `terragrunt plan` comment.
3. **No artifact, no apply.** An apply after a push that has no plan yet
   fails before `terragrunt` runs, with the message in §3.
4. **The archive is encrypted.** A downloaded artifact can't be read without
   the age key.
5. **The template is a no-op.** After the minor bump, every leaf in each spoke
   plans `No changes.`
6. **Backup ignores locks.** A `.tflock` left in R2 is not copied to B2, and
   the post-copy check still passes.
