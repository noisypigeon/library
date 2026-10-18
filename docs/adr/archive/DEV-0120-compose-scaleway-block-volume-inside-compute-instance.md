# DEV-0120: Rename block-volume's naming inputs; compose it inside compute-instance

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Superseded by [ADR-0153](DEV-0153-decompose-compute-instance.md).

## Context

`scaleway/block-volume` (ADR-0085) still takes `namespace`/`name`, the naming convention every sibling module in this provider root has since moved away from: `compute-instance` (ADR-0118), `object-bucket` and `iam-application` (ADR-0119) all now take `name_prefix`/`name_suffix`. `block-volume` was the one module left behind.

**Every real use of `block-volume` has composed it 1:1 with `compute-instance`.** A repo-wide census finds exactly one consumer of `block-volume`, ever — `workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/deduplication/`'s `module "volume"` — and it always paired the same `namespace`/`name` values onto both the `block-volume` and `compute-instance` calls, wiring `additional_volume_ids = [module.volume.id]` by hand. That leaf is pinned to explicit tag URLs (`compute-instance/v4.0.0`, `block-volume/v2.0.0`); per ADR-0109/ADR-0110's established posture, old tags are never deleted, so this breaking change doesn't disturb it. It is deliberately **not** migrated to the new interface by this ADR: its `compute.tf`/`iam.tf`/`module "volume"` block are already being deleted outright by a separate, not-yet-merged branch, making a migration here wasted effort.

**ADR-0081 established, and ADR-0085 explicitly reaffirmed, that no local module in this provider root composes another internally** — `compute-instance` and `block-volume` were kept as independent sibling modules with independent release cycles, composed only at the calling leaf, "the same way `buckets`/`iam-policy` outputs are wired into `compute-instance` today" (ADR-0085). That reasoning holds well for `object-bucket` and `iam-policy`/`iam-application`, which are genuinely reused independently across many leaves (`object-bucket` alone has 12 consumers, per ADR-0119) — real sibling-module independence worth preserving. It does not hold for `block-volume`: with exactly one consumer ever, and that consumer always pairing it 1:1 with `compute-instance`, external composition bought no actual flexibility — just a second module block and manual ID plumbing every caller had to repeat. This ADR carves out a narrow, named exception to ADR-0081/ADR-0085's principle for this one pairing only; it does not repeal the principle itself, which still governs every other module pairing in this provider root.

## Decision

### `scaleway/block-volume`: rename `namespace`/`name` → `name_prefix`/`name_suffix`

Same values, same naming scheme (`${name_prefix}-${random_code}-${name_suffix}`), just renamed to match every sibling module. `release:major`, `v3.0.0` → `v4.0.0`.

### `scaleway/compute-instance`: fold volume creation into `instance_config.block_volume`

The top-level `additional_volume_ids` input (ADR-0085) is removed. In its place, `instance_config` gains a `block_volume` field:

```hcl
instance_config.block_volume = optional(object({
  size                  = optional(number)
  iops                  = optional(number, 15000)
  project_id            = optional(string)
  additional_volume_ids = optional(list(string), [])
}))
```

- `block_volume` left unset (`null`, the default): no managed volume, nothing extra attached — unchanged from omitting `additional_volume_ids` before.
- `block_volume.size` unset: no managed volume is created, but `block_volume.additional_volume_ids` (pre-created volume IDs, e.g. from a standalone `block-volume` call) still attach — covers the old `additional_volume_ids`-only use case.
- `block_volume.size` set: `compute-instance` creates the volume itself, ~~composing `scaleway/block-volume` internally by relative path (`source = "../block-volume"`)~~ composing `scaleway/block-volume` internally (superseded by ADR-0121: pinned to a released tag instead of a relative path, which escapes the module package once `compute-instance` itself is fetched over HTTP), passing through `name_prefix`/`name_suffix` from the instance's own inputs so the volume's name matches the instance's, exactly as the one real past consumer always did by hand. `project_id` becomes required in this case — enforced with a `validation` block (matching this file's existing `keyring` validation style) rather than making it unconditionally required, since it's meaningless when no volume is being created.

The managed volume's `id` (if any) and `block_volume.additional_volume_ids` are merged into a new `local.attached_volume_ids`, which now feeds both `scaleway_instance_server.additional_volume_ids` and the cloud-init mkfs/mount block's trigger condition (previously keyed on `length(var.additional_volume_ids) > 0`) — same single-device (`/dev/sdb`) behavior as before (ADR-0089), unchanged.

`release:major`, `v4.0.0` → `v5.0.0`.

## Consequences

- A caller wanting a managed data volume on a `compute-instance` now sets `instance_config.block_volume.{size,iops,project_id}` directly, instead of composing a separate `module "block-volume"` call and wiring its `id` output by hand.
- `block-volume` itself is not removed or deprecated — it remains independently callable for any hypothetical future caller that wants a volume with no attached instance.
- The one live consumer, `poisoned/mega-storage-consolidation/deduplication`, is left pinned to `compute-instance/v4.0.0`/`block-volume/v2.0.0` rather than migrated — not because the breaking change is harmless to it in the abstract, but because that leaf's compute/volume/IAM are already being removed entirely by a separate, in-progress branch not yet merged to `main`.
- `README.md` for both modules regenerates automatically via `module-docs.yml` on merge.
- ADR-0081 and ADR-0085 are amended with a strikethrough note pointing at this ADR, narrowly for the `block-volume`/`compute-instance` pairing; their general "no internal composition" principle still applies to every other module in this provider root.

## Out of scope

- Migrating `poisoned/mega-storage-consolidation/deduplication` to the new interface — left on its old pinned versions (see Consequences); it's already slated for full removal on a separate branch.
- Everything ADR-0085's Out of scope already listed and this doesn't touch: `snapshot_id`, `tags`, `project_id`/`zone` overrides beyond what `block_volume.project_id` already threads through, `iops` enum/range validation.
- Multi-volume cloud-init device handling — the mkfs/mount block still only knows about a single `/dev/sdb`, same limitation as before (ADR-0089). A caller setting both a managed volume and `additional_volume_ids` gets multiple volumes attached, but only the first is formatted/mounted automatically.
