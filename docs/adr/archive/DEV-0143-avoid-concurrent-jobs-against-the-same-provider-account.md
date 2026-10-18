# DEV-0143: avoid scheduling concurrent pigeon-cli jobs against the same provider account

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-07.
- **Status**: Exploration.

`Exploration`, per ADR-0138's precedent: a design spike recording a chosen
direction and its open questions, not a build that's landed. This ADR is
documentation only, written from log analysis -- no Terraform/module changes
accompany it.

## Context

The same 33-run review (ADR-0142's context) found that the worst Backblaze B2
rate-limiting episodes in the sampled data coincide with two independently-
provisioned job VMs running at the same time against the same B2 account.

Timestamps (UTC, 2026-10-07):

- `consolidate-g35xor-segment-1` ran three legs sequentially on one VM:
  `mega:` → `deduplicate-p7d0kd-backblaze-mega-consolidation` (20:08-20:24),
  `macbook:` → `deduplicate-qb27gx-macbook` (20:24-21:10), `snapshots:` →
  `deduplicate-h4w903-backblaze-computer-snapshots` (21:10-21:47).
- `consolidate-a5tl5v-segment-2` ran concurrently on a *different* VM:
  `google:` → `deduplicate-0msi9l-backblaze-google-consolidation`
  (20:07-20:24).

Different destination buckets, but the same Backblaze B2 account -- and this
exact 20:07-20:24 overlap window is when `consolidate-a5tl5v-segment-2`
logged 205,306 `429 Too Many Requests` errors (59% of its entire rclone log)
and ultimately failed, while the concurrently-running `g35xor` legs were
simultaneously generating their own share of the ~494K total 429 errors
observed across the full sample. No per-account request-rate budget or
scheduling constraint exists today to stop two independently-provisioned job
VMs from both hammering the same upstream account at once -- each job's own
`--transfers`/`--checkers` concurrency (the subject of the companion
`pigeon-cli` ADR-0106) is tuned (or mistuned) in isolation, with no awareness
of what else might be running against the same destination account
concurrently.

These particular "segment" jobs were run ad-hoc (per ADR-0142's context, no
committed `job/` Terragrunt leaf exists for any of them), so there was no
single place a scheduling constraint could have been enforced even if one
existed -- itself part of the gap this ADR addresses.

## Decision

1. **Tag each job leaf with its destination provider account** (not just the
   bucket alias) -- e.g. a `provider_account` local/tag on each
   `workloads/.../pigeon-cli/job/<job-name>/job_definition.tf`, since today a
   job only names its bucket alias, with no machine-checkable link back to
   "which upstream account does this actually hit."
2. **Enforce at most one concurrently-running job per provider account**, at
   whichever layer ends up owning job scheduling going forward -- this
   composes naturally with ADR-0138's `pigeon-cluster` module (a per-account
   semaphore/queue a cluster's jobs respect before provisioning the next
   instance) rather than requiring a brand-new scheduler. Jobs against
   different accounts remain free to run fully in parallel, since the
   observed problem is specifically *same-account* concurrency.
3. **Until (1)/(2) land, document the constraint operationally**: any
   hand-rolled multi-segment bulk migration (the kind that produced the
   sampled `segment-1`/`segment-2` runs) should be sequenced by hand against
   the same destination account, not parallelized across VMs, until
   scheduling enforces this automatically.

## Consequences

- Reduces the single largest contributor to the 429 storms observed in the
  sampled data -- concurrent same-account pressure compounding what any one
  job's own concurrency tuning (ADR-0106) can mitigate alone.
- Jobs against genuinely independent provider accounts are unaffected and
  stay fully parallel.
- Some bulk migrations that previously ran faster by accident (via
  uncoordinated parallelism) will take longer once properly sequenced against
  a shared account -- the direct trade-off against reliability.

## Out of scope

- The per-job concurrency/retry tuning itself (rclone's `--transfers`/
  `--checkers`/`--tpslimit`) -- that's the companion `pigeon-cli` ADR-0106;
  this ADR is about cross-job scheduling, not any one job's internal
  settings.
- Building a general-purpose multi-tenant rate-limiter -- out of scope; a
  simple per-account "one at a time" constraint is sufficient for the
  observed problem and this deployment's current scale.
- Retrying a failed job automatically -- that's the companion ADR-0142.

## Verification

- Manual: provision two jobs known to target the same provider account and
  confirm the scheduling constraint prevents them from running concurrently
  (the second waits or is rejected until the first completes).
- Confirm jobs against different provider accounts are unaffected and still
  run concurrently.
- `terraform validate`/`mise run ci` clean on the affected module(s).
