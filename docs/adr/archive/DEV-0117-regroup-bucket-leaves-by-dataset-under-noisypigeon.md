# DEV-0117: regroup `workloads/bucket/terraform/pigeon-cli/*` by dataset under `workloads/bucket/terraform/noisypigeon/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

`workloads/bucket/terraform/pigeon-cli/{import,deduplication}/*` (10 leaves, landed across ADR-0116 and its same-day amendment) restructures again: drop the `pigeon-cli` consumer-grouping segment entirely, regroup by **dataset name** instead, with `import`/`deduplication` collocated as sibling subdirectories under each dataset's own directory rather than being the top grouping. This is a distinct follow-on decision, not the anticipated second half of ADR-0116's — a new ADR, not a further amendment.

Three of the five `poisoned/*` datasets (`computer-snapshots`, `mega-storage-consolidation`, `t7-backup`) have both an `import` and a `deduplication` leaf and now share one parent directory; `macbook-scratch`/`media` keep only `deduplication/`; `backblaze`/`email` keep only `import/`. All 10 destinations were confirmed pre-scaffolded empty beforehand, the same established pattern. One pre-scaffolded placeholder, `workloads/bucket/terraform/noisypigeon/macbook-scratch/import/`, has no corresponding source leaf (no `pigeon-cli/import/macbook-scratch` ever existed) — left empty and untouched, presumably scaffolding for separate future work.

`workloads/root.hcl` confirmed unaffected: no Scaleway credential/region resolution is keyed on `"pigeon-cli"` or `"noisypigeon"` as path segments (only Cloudflare's unrelated `pigeon.dev` check exists); leaf-validity only checks `path_segments[1] == "terraform"`, satisfied regardless of nesting depth or dataset grouping. No `dependency` blocks exist anywhere; the one cross-leaf reference (`poisoned/mega-storage-consolidation/import`'s `source_bucket_name = local.import_backblaze_bucket_name`) resolves via `root.hcl`'s `.env`-keyed locals mechanism, independent of directory paths — confirmed still correct post-move (same bucket name, zero plan diff).

`"pigeon-cli"` as a string survives in two unrelated places, deliberately untouched: `compute.tf`'s `profile = "pigeon-cli"` (a real cloud-init provisioning profile name tied to the actual CLI tool, not a directory-grouping reference) and the entirely separate `workloads/scaleway/terraform/pigeon-cli/cockpit/` leaf (ADR-0115).

**Known complication, handled as a special case**: `workloads/bucket/terraform/pigeon-cli/import/email/iam.tf` was sitting deleted-but-uncommitted from unrelated prior work at the time of this move. Rather than `git mv` the whole `email` directory (which would entangle that pending deletion with this move), its three present files (`bucket.tf`, `terragrunt.hcl`, `workload_definition.tf`) were moved individually, leaving the dangling `iam.tf` deletion exactly where it was at the old path — untouched, not staged, not resolved by this ADR.

Build artifacts (`.terraform.lock.hcl`, `.terragrunt-cache/`) present in several source leaves are gitignored, not moved.

## Decision

### Directory-only move, no content changes

All 10 leaves moved via `rmdir <empty destination>` + `git mv <source> <destination>` (`email` via individual file moves, above). Every `workload_definition.tf` confirmed byte-identical before and after, including `poisoned/mega-storage-consolidation/deduplication`'s continuing divergence between its directory name and its `name` local (`"poisoned-mega-consolidation"`, unchanged since ADR-0116 — not re-litigated here). After all 10 moves, the now-fully-empty `workloads/bucket/terraform/pigeon-cli/` tree was removed from the filesystem (the `email/iam.tf` deletion remains tracked at its path regardless of whether the containing directories still physically exist).

### State migration

Same `git worktree add ... HEAD` + `terragrunt state pull`/`push` runbook as every prior move in this series, all 10 leaves against one shared worktree. Every baseline (old location, pristine `HEAD`) and post-push (new location, real working tree) plan showed "No changes," identical resource IDs throughout — 29 resources total, 18 across the 9 bucket-only leaves (2 each) plus 11 for `poisoned/mega-storage-consolidation/deduplication` (bucket + compute + volume + iam):

| Dataset | Leaf | Resource ID(s) (unchanged by the move) |
|---|---|---|
| `macbook-scratch` | `deduplication` | `fr-par/deduplication-heox8d-macbook-scratch` |
| `media` | `deduplication` | `fr-par/deduplication-xl9ux9-media` |
| `poisoned/computer-snapshots` | `deduplication` | `fr-par/deduplication-73gqar-poisoned-computer-snapshots` |
| `poisoned/mega-storage-consolidation` | `deduplication` | bucket `fr-par/deduplication-fep6np-poisoned-mega-consolidation`; server `fr-par-1/cade5118-cc05-43c7-b89b-fd78b5d375e1`; volume `fr-par-1/3c4dd057-...`; IP `fr-par-1/38ad63db-...` |
| `poisoned/t7-backup` | `deduplication` | `fr-par/deduplication-4x8tul-poisoned-t7-backup-2026-05-25` |
| `backblaze` | `import` | `fr-par/import-h7hkdr-backblaze` |
| `email` | `import` | `fr-par/import-bfurb3-email` |
| `poisoned/computer-snapshots` | `import` | `fr-par/import-5vk8yg-poisoned-computer-snapshots` |
| `poisoned/mega-storage-consolidation` | `import` | `fr-par/import-yxtsyz-poisoned-mega-storage-consolidation` |
| `poisoned/t7-backup` | `import` | `fr-par/import-a10yv2-poisoned-t7-backup-2026-05-25` |

Old-location state objects left as low-priority cleanup, per established precedent.

## Consequences

- `workloads/bucket/terraform/` now groups by dataset first, with `import`/`deduplication` as the finer-grained distinction underneath, rather than grouping by consumer first — `pigeon-cli` no longer appears anywhere in this directory's structure.
- `CLAUDE.md`'s `workloads/bucket/terraform/` description and `workloads/pigeon-cli/` decommissioning sentence are rewritten to match (the latter's claim that leaves "relocated to `workloads/bucket/terraform/pigeon-cli/`" is no longer accurate).
- `workloads/README.md` and `docs/USAGE.md`, both already stale since before ADR-0116 (never updated across either of its two landings), are also corrected now rather than deferred a third time.

## Out of scope

- `workloads/bucket/terraform/noisypigeon/macbook-scratch/import/`'s pre-scaffolded placeholder — left empty, not this ADR's concern.
- The unrelated `email/iam.tf` pending deletion — left exactly as found.
