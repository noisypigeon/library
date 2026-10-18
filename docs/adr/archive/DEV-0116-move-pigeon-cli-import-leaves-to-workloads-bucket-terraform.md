# DEV-0116: move `workloads/pigeon-cli/terraform/{import,deduplication}/*` to `workloads/bucket/terraform/pigeon-cli/*`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.
- **Amended**: 2026-10-04, to also cover the `deduplication/*` leaves — the pre-scaffolded `workloads/bucket/terraform/pigeon-cli/deduplication/` placeholder this ADR originally declared out of scope, landed as the anticipated second half of the same decision rather than as a separate ADR-0117.

## Context

`workloads/pigeon-cli/terraform/import/` held exactly 5 leaves — `backblaze`, `email`, `poisoned-computer-snapshots`, `poisoned-mega-storage-consolidation`, `poisoned-t7-backup-2026-05-25` — all of them. All 5 move to a brand-new top-level workload, `workloads/bucket/terraform/pigeon-cli/import/`, establishing `workloads/bucket/` as the home for storage-bucket infrastructure generally, decoupled from which job/CLI happens to consume it, rather than nested under the consuming workload's own directory.

Three of the five `import/` leaves are renamed along the way: `poisoned-computer-snapshots` → `poisoned/computer-snapshots`, `poisoned-mega-storage-consolidation` → `poisoned/mega-storage-consolidation`, and `poisoned-t7-backup-2026-05-25` → `poisoned/t7-backup` (also dropping the date suffix) — grouping the three `poisoned-*` leaves under a shared `poisoned/` directory instead of a flat, repeated prefix.

**Amendment**: `workloads/pigeon-cli/terraform/deduplication/` — the compute-side counterpart, also exactly 5 leaves (`macbook-scratch`, `media`, `poisoned-computer-snapshots`, `poisoned-mega-consolidation`, `poisoned-t7-backup-2026-05-25`) — moves the same way, to `workloads/bucket/terraform/pigeon-cli/deduplication/`, with the same `poisoned/` nesting for its three `poisoned-*` leaves. This empties `workloads/pigeon-cli/terraform/` entirely (it held nothing but `deduplication/` once `import/` had already moved), and since `pigeon-cli` is an external CLI with no `src/` in this repo (it split out via ADR-0084), `workloads/pigeon-cli/` itself is now fully decommissioned — the same "last leaf moves out" pattern ADR-0098/0105/0106 already used for `custodian-buckets/`, `email/`, and `bluesky/`.

One rename needed a deliberate call: the user's requested destination name for the mega-consolidation dedup leaf, `poisoned/mega-storage-consolidation`, actually changes the name (adds "storage-") to match its sibling bucket leaf's naming — unlike every other rename in this ADR, where only the directory path changed and the leaf's own name stayed identical. This leaf is also the only one of the 5 dedup leaves with a real compute instance, block volume, and IAM policy (the other 4, like all 5 `import/` leaves, are bucket-only) — so unlike a bucket rename, changing its actual resource name would trigger live replacement (new compute instance, new IP, new SSH host key). **Confirmed with the user: directory-only rename** — the leaf's `workload_definition.tf` `name` local stays `"poisoned-mega-consolidation"` verbatim; only its repo path changed. The directory name and the resource's actual name intentionally no longer match exactly, the same safety tradeoff already established for every bucket leaf's `name` local in this ADR.

## Decision

### 1. `import/*` — directory-only move, no content changes

All 5 destinations existed beforehand as empty, pre-scaffolded placeholders — the same pattern ADR-0105/0106/0115 established. Moved via `rmdir <empty destination>` + `git mv <source> <destination>`, same as those precedents; `.terraform.lock.hcl`/`.terragrunt-cache/` are gitignored, not moved. All 16 moved files (`terragrunt.hcl`, `bucket.tf`, `workload_definition.tf`, plus `email/iam.tf`) show as pure renames with zero content diff — confirmed via `git diff --cached --stat` reporting `0 insertions(+), 0 deletions(-)` across the board.

**Deliberately not touched**: each leaf's `workload_definition.tf` `name` local, which feeds directly into its real Scaleway bucket's actual name (e.g. `poisoned-computer-snapshots/workload_definition.tf` keeps `name = "poisoned-computer-snapshots"` verbatim even though the directory is now `poisoned/computer-snapshots/`). This is a pure repo-organization and Terraform-state-location change — changing that value would rename/recreate the real cloud bucket, which isn't the goal. Confirmed post-migration: every bucket's actual Scaleway name (`import-<suffix>-<name>`) is byte-identical before and after.

No `workloads/root.hcl` changes needed: its leaf-validity (`path_segments[1] == "terraform"`), remote-state-key (`workloads/${path_relative_to_include()}/terraform.tfstate`), and region/zone resolution are purely structural/path-derived, confirmed workload-name-agnostic (the only name-keyed branch in `root.hcl` is Cloudflare's `pigeon.dev`-domain check, irrelevant here) — a brand-new top-level workload name needs zero wiring, same conclusion ADR-0097/0106/0115 each reached for their own moves.

No `dependency` blocks exist anywhere in `workloads/` referencing these leaves. One real cross-reference exists — `poisoned-mega-storage-consolidation/workload_definition.tf`'s `source_bucket_name = local.import_backblaze_bucket_name` — but that local is synthesized by `root.hcl` from an `.env` key (`ENV_SW_IMPORT_BACKBLAZE_BUCKET_NAME`), entirely independent of any leaf's directory path, so it resolved correctly and unchanged through the move (confirmed: the destination leaf's `terragrunt plan` showed the same bucket name for this reference as the baseline).

State migrated via `git worktree add ... HEAD` + `terragrunt state pull`/`push`, run for all 5 leaves against one shared worktree, against a fully clean, consistent baseline (the `scaleway_project_id` rename that complicated ADR-0115's move had since landed and merged) — no env-var workaround needed. Every leaf's baseline plan (old location, pristine `HEAD`) and post-push plan (new location, real working tree) showed "No changes," with identical resource IDs in both:

| Leaf | Resource ID (unchanged by the move) |
|---|---|
| `backblaze` | `fr-par/import-h7hkdr-backblaze` |
| `email` | `fr-par/import-bfurb3-email` |
| `poisoned/computer-snapshots` | `fr-par/import-5vk8yg-poisoned-computer-snapshots` |
| `poisoned/mega-storage-consolidation` | `fr-par/import-yxtsyz-poisoned-mega-storage-consolidation` |
| `poisoned/t7-backup` | `fr-par/import-a10yv2-poisoned-t7-backup-2026-05-25` |

### 2. `deduplication/*` — same approach, one leaf with real compute to migrate

Same directory-move + worktree-based state migration technique, against an equally clean baseline. 4 of the 5 leaves are bucket-only, migrating 2 state resources each (`random_string.suffix`, `scaleway_object_bucket.bucket`). `poisoned-mega-consolidation` migrated 11: `module.bucket.{random_string.suffix,scaleway_object_bucket.bucket}`, `module.compute.{random_string.suffix,scaleway_instance_ip.ipv4,scaleway_instance_server.server,terraform_data.cloud_init}`, `module.volume.{random_string.suffix,scaleway_block_volume.volume}`, `module.iam.{scaleway_iam_application.application,scaleway_iam_api_key.api_key,scaleway_iam_policy.policy}`. Every baseline and post-push plan showed "No changes," with every resource ID identical before and after — including the live compute instance (`fr-par-1/cade5118-...`), its IP, and its attached volume, confirming the directory-only-rename decision above held: nothing was replaced.

| Leaf | Resource ID (unchanged by the move) |
|---|---|
| `macbook-scratch` | `fr-par/deduplication-heox8d-macbook-scratch` |
| `media` | `fr-par/deduplication-xl9ux9-media` |
| `poisoned/computer-snapshots` | `fr-par/deduplication-73gqar-poisoned-computer-snapshots` |
| `poisoned/mega-storage-consolidation` | bucket `fr-par/deduplication-fep6np-poisoned-mega-consolidation`; server `fr-par-1/cade5118-cc05-43c7-b89b-fd78b5d375e1` |
| `poisoned/t7-backup` | `fr-par/deduplication-4x8tul-poisoned-t7-backup-2026-05-25` |

`poisoned-mega-consolidation/workload_definition.tf`'s `source_bucket_name = "import-yxtsyz-poisoned-mega-storage-consolidation"` is a hardcoded literal string (not a path or `.env`-keyed reference, unlike the `import/` leaves' own cross-reference above) — already correct, and unaffected by either move since it isn't derived from anything that changed. Also fixed a small, pre-existing, unrelated formatting drift in that same file (`terraform fmt`'s column alignment) while it was already being touched — zero semantic change, confirmed via diff.

Old-location state objects (both `import/*` and `deduplication/*`) left as low-priority cleanup, per established precedent.

## Consequences

- `workloads/pigeon-cli/` is fully decommissioned — `import/` and `deduplication/` were its only contents, both now moved out, and it had no `src/` to begin with.
- `workloads/bucket/` now holds both `pigeon-cli/import/*` and `pigeon-cli/deduplication/*` — the storage and compute sides of the same jobs, grouped by purpose rather than by consumer.
- `CLAUDE.md`'s `workloads/pigeon-cli/terraform/` description is replaced with a decommissioning note (mirroring ADR-0098/0105/0106's own framing for their equivalent cases), and its `workloads/bucket/terraform/` description extended to cover `deduplication/*`. Also corrected an unrelated pre-existing inaccuracy surfaced while editing the same sentence: it previously described all 5 dedup leaves as "one compute-instance-plus-volume leaf per dedup job," which was never true — only `poisoned-mega-consolidation` actually has compute+volume; the other 4 are bucket-only, same shape as the `import/` leaves.

## Out of scope

- The stray, unrelated empty directory `workloads/pigeon-cli/terraform/bucket/` this ADR originally flagged turned out to no longer exist (untracked, empty, evidently already gone by the time of the amendment) — nothing to do.
- `workloads/README.md`'s own, separate staleness (not touched by either half of this ADR) — a different document with its own drift, out of scope here.
