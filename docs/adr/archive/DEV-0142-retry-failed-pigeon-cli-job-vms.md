# DEV-0142: automatic retry for a failed pigeon-cli job VM before self-delete

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-07.
- **Status**: Exploration.

`Exploration`, per ADR-0138's precedent: a design spike recording a chosen
direction and its open questions, not a build that's landed. This ADR is
documentation only, written from log analysis -- no Terraform/module changes
accompany it.

## Context

A review of 33 `pigeon job run deduplicate`/`import` run bundles (archived to
the ADR-0100-era report bucket, 2026-10-05 through 2026-10-07) surfaced a
deployment-layer gap, not a `pigeon-cli` code bug: there is no automatic
retry for a job VM that fails.

Every `pigeon-cli` job VM provisioned via `compute-instance`
(`templates/terraform/scaleway/compute-instance/instance.tf:43-72`) runs its
`post_provision_commands` under `set -e` with a `trap '... scw instance
server delete ... with-volumes=all force-shutdown=true' EXIT` prepended --
deliberately, per ADR-0126/ADR-0138, so the instance self-destroys on *any*
exit, success or failure, rather than idling (and billing) after its one job
finishes. That design is sound for the success case. It means a **transient**
failure is treated identically to a permanent one: the VM runs the job once,
fails, and deletes itself (server, IP, block volume) before anyone or
anything has a chance to retry.

This is exactly what happened across the sampled runs. 4 of 33 `import` runs
failed outright:

- `consolidate-a5tl5v-segment-2-1235` and `consolidate-e2qpr0-segment-2-1241`:
  rclone exhausted its `--retries 5` budget against sustained Backblaze B2
  `429 Too Many Requests` (see the companion `pigeon-cli` ADR-0106, and ADR-0143
  below for the concurrent-scheduling angle that made this worse).
- `consolidate-aut1w2-segment-1-check-1232`: the same, against a `fastmail:`
  source.
- `consolidate-setsye-segment-1-4957`: `error reading source directory:
  directory not found` against a `mega:` source -- a single immediate
  failure (28ms after the leg started), looking like a source-mount-readiness
  race rather than a real missing directory (a sibling leg against the same
  `mega:` remote succeeded cleanly minutes later in the same multi-leg run).

None of these four correspond to a committed Terragrunt `job/` leaf in this
repo -- only a `workloads/willowgraysen.com/terraform/pigeon-cli/bucket/bulk-segment-1`
*bucket* definition exists, no matching `job/` leaf for any `segment-1`/
`segment-2`/`-check` name. The operator noticed each failure (via Cockpit/
Grafana or the reports bucket) and hand-rolled a replacement run outside the
normal Terraform-tracked pattern -- exactly the manual-intervention cost this
ADR proposes removing.

## Decision

Add a bounded automatic retry to the job-VM lifecycle, building on
`compute-instance`'s existing `self_delete_on_exit` hook (ADR-0138) rather
than replacing it:

1. **Distinguish transient from permanent failure at the point of exit.**
   `pigeon-cli`'s own exit codes already separate categories (`FAILURE_EXIT_CODE`
   for job-level failures vs. rclone's own exit codes for `import`, per the
   companion `pigeon-cli` ADR-0106's findings). The post-provision script
   wrapping each job command should capture the exit code and classify it
   (e.g. "exhausted-retries"/"source-unavailable" vs. a hard configuration
   error) rather than treating every nonzero exit identically.
2. **Retry the job command a bounded number of times, with backoff, before
   the self-delete trap fires** -- e.g. up to 2-3 retries with an increasing
   delay between attempts, long enough to outlast a short rate-limit storm or
   a source-mount race, short enough that a genuinely broken job still
   self-deletes promptly rather than looping forever. This can live entirely
   inside the post-provision script `compute-instance` already generates
   (`local.post_provision_script`,
   `templates/terraform/scaleway/compute-instance/instance.tf:68-80`), with no
   new infrastructure required -- the retry loop wraps
   `var.instance_config.post_provision_commands`, the self-delete trap stays
   exactly where it is (still firing on whatever the *final* exit is).
3. **Surface retry attempts in the existing observability path** (Cockpit/
   Alloy already streams `pigeon.jsonl` and job VM logs per ADR-0102/ADR-0103)
   so a run that needed 2 retries to succeed is visible as such, not
   indistinguishable from a clean first-attempt success.
4. Note explicitly: this is not the "automatic pruning of completed jobs from
   `var.jobs`" reconciliation gap ADR-0138 already flagged as its own future
   work -- that's about `pigeon-cluster`'s Terraform state tracking a
   self-deleted instance; this ADR is about what happens to the *job itself*
   before the VM is allowed to delete itself.

## Consequences

- A transient failure (provider rate-limiting, a source-mount race) no longer
  requires a human to notice and hand-roll a replacement run outside the
  normal Terragrunt `job/` pattern.
- Slightly longer worst-case VM lifetime (and cost) for a job that needs to
  retry -- bounded and small relative to the multi-hour runs observed in the
  sampled data.
- A job that fails for a genuinely permanent reason (bad credentials, wrong
  bucket) still fails and self-deletes, just after a few wasted-but-bounded
  attempts instead of zero.

## Out of scope

- `pigeon-cluster`'s `var.jobs` reconciliation gap (ADR-0138) -- unrelated,
  already tracked there as future work.
- Any change to `pigeon-cli`'s own retry logic inside a single process
  invocation (rclone's `--retries`/`--low-level-retries`, or `pigeon-cli`'s
  own upload retry) -- that's the companion `pigeon-cli` ADR-0106; this ADR
  is strictly about retrying the *whole job command* at the VM/deployment
  layer once `pigeon-cli`'s own in-process retries have already been
  exhausted.
- Building a general job queue/scheduler -- explicitly rejected by ADR-0138
  for the same reasons; this ADR stays within "retry this one job command a
  few times before the VM dies."

## Verification

- Manual: force a job command to fail its first N-1 attempts (e.g. a
  deliberately-flaky test command) and confirm the VM retries before either
  succeeding or exhausting its bound and self-deleting.
- Confirm retry attempts are visible in Cockpit/the archived `pigeon.jsonl`
  for a run that needed one.
- `mise run ci`/`terraform validate` clean on the affected module(s).
