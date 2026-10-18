# DEV-0137: fix `pigeon.dev/terraform/state/bucket` to use its own dedicated deployer

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-07.
- **Status**: Accepted.

## Context

`workloads/pigeon.dev/terraform/state/bucket` failed to plan in CI with
`AccessDenied` on `GetBucketCors`, surfaced while landing an unrelated PR. The
hypothesis under investigation was that `terragrunt-plan.yml`/`terragrunt-apply.yml`
might be authenticating with one shared Scaleway credential across every workload,
even though `pigeon.dev`, `noisypigeon.com`, and `willowgraysen.com` each now have
their own dedicated Scaleway project, state bucket, and deployer IAM ("Terraform
self-sufficiency", ADR-0130/0131/0132/0133).

That hypothesis was half right, in a specific way. `terragrunt-plan.yml`/
`terragrunt-apply.yml` inject exactly one secret, `SOPS_AGE_KEY`, and nothing
else — no global Scaleway key that could shadow anything. Each leaf's own
`terragrunt.hcl` → `root.hcl` chain resolves its own credentials independently, and
that chain is not broken in general: a repo-wide `git grep` for the explicit
shared-root include (`path = "${get_repo_root()}/workloads/root.hcl"`) across every
`terragrunt.hcl` finds exactly 4 matches — the three `state/iam` leaves
(`noisypigeon.com`, `pigeon.dev`, `willowgraysen.com`), which are deliberately and
permanently pinned there by design (IAM-only, no circular-backend concern, per
ADR-0130), and **`pigeon.dev/terraform/state/bucket`**. Every other `pigeon.dev`
leaf (`project`, `wiki/bucket`, `wiki/iam`, `wiki/dns`, `fastmail/dns`) already uses
`find_in_parent_folders("root.hcl")` and correctly resolves `pigeon.dev`'s own
dedicated root. `state/bucket` is the one leaf that was never switched over.

Because of that stale include, this leaf authenticates with the **shared
repo-wide deployer's** Scaleway credentials (from the root `.env.enc`) and its
`bucket.tf` reads `project_id = local.scaleway_project_id_pigeon_dev` — the shared
root's suffixed local — instead of the per-workload root's plain
`local.scaleway_project_id`. The shared deployer's `iam-api-key` (module `v0.1.0`,
no `default_project_id`) is bound to one project for S3-signed data-plane calls
(`HeadBucket`, `GetBucketCors`, etc.) regardless of IAM policy `project_ids` grants
— control-plane calls like `CreateBucket` honor the grant, S3-signed calls don't.
That mismatch is exactly why `GetBucketCors` 403s.

This is not a new bug. ADR-0132 hit and fixed the identical gap for
`noisypigeon.com`'s own `state/bucket` leaf, explicitly confirmed live at the time
that `pigeon.dev`'s leaf "fails identically with the shared deployer today," and
listed retroactively repairing it as **out of scope** — "straightforward to apply
there too, not done here since that workload wasn't otherwise touched by this PR."
ADR-0133's regression check independently re-confirmed the gap still existed. No
GitHub issue was ever filed for it. `pigeon.dev`'s own dedicated deployer
(`workloads/pigeon.dev/terraform/state/iam/iam.tf`) already uses `iam-api-key/
v0.2.0` with `default_project_id` set — the exact fixed module version ADR-0132
found "worked immediately" once in use — so once this leaf actually resolves
`pigeon.dev`'s own root, the bug disappears with no infrastructure changes beyond
the include/local fix itself.

`terragrunt state list` against the live leaf (read-only check, no changes) shows it
currently tracks 2 resources — `module.bucket.random_string.suffix[0]` and
`module.bucket.scaleway_object_bucket.bucket` — both presumably created during
ADR-0130's original bootstrap, before this limitation was discovered.

## Decision

Apply ADR-0132's exact, already-proven fix, mirrored for `pigeon.dev`:

- `workloads/pigeon.dev/terraform/state/bucket/terragrunt.hcl`: `include "root"`'s
  `path` changes from the explicit `"${get_repo_root()}/workloads/root.hcl"` to
  `find_in_parent_folders("root.hcl")` — identical to `project` and every other
  non-`state/iam` leaf in this workload.
- `workloads/pigeon.dev/terraform/state/bucket/bucket.tf`: `project_id` changes
  from `local.scaleway_project_id_pigeon_dev` to `local.scaleway_project_id`.
- `state/iam` is untouched — it stays the deliberate, permanent exception, for the
  same chicken-and-egg reason ADR-0130 established.

This repoints the leaf's backend at `pigeon.dev`'s own dedicated state bucket, so
its 2 tracked resources are migrated there via the same `git worktree add ... HEAD`
+ `terragrunt state pull`/`push` runbook used for every prior cross-root move in
this repo (ADR-0106/0115/0116/0117/0124/0127, and ADR-0132's own identical fix):
pull state from the shared bucket's key for this leaf in an isolated pre-fix
worktree, apply the fix on the real branch, push that state into the new backend
location under the same relative key, then confirm a clean plan.

## Consequences

- `workloads/pigeon.dev/terraform/state/bucket` now authenticates with its own
  dedicated deployer, like every other `pigeon.dev` leaf except the permanently
  shared `state/iam`.
- `pigeon.dev`'s Terraform self-sufficiency (ADR-0130) is now actually complete —
  no leaf in this workload still depends on the shared repo-wide deployer except by
  deliberate design.
- The repo-wide `git grep` for the explicit shared-root include now returns exactly
  3 matches (the three permanent `state/iam` leaves), down from 4.
- No change to `.github/workflows/terragrunt-plan.yml`/`terragrunt-apply.yml` was
  needed — confirms the CI workflow layer was never the problem, only this one
  leaf's stale `include`.

## Out of scope

- Fixing the shared deployer's underlying `iam-api-key`/S3-cross-project-access
  limitation itself, or reconciling the duplicate `0136` ADR number that landed on
  `main` from two concurrently-merged PRs — unrelated to this fix.
