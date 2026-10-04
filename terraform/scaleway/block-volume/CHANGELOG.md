# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [4.0.0] - 2026-10-04

### Rename block-volume's naming inputs and compose it inside compute-instance

`block-volume` still took `namespace`/`name`, the naming convention every sibling module in this provider root (`compute-instance`, `object-bucket`, `iam-application`) has already moved to `name_prefix`/`name_suffix`. This PR renames them to match.

It also folds volume creation into `compute-instance` itself. A repo-wide census found `block-volume` has had exactly one consumer, ever, and that consumer always paired it 1:1 with the same `compute-instance` call -- composing the two separately bought no real flexibility, just a second module block and manual `additional_volume_ids = [module.volume.id]` plumbing every caller had to repeat. `compute-instance`'s top-level `additional_volume_ids` input is replaced by a new `instance_config.block_volume` object:

- `block_volume` left unset: no managed volume, nothing extra attached.
- `block_volume.size` unset: no managed volume is created, but `block_volume.additional_volume_ids` (pre-created IDs from elsewhere) still attach.
- `block_volume.size` set: `compute-instance` creates the volume itself by composing `scaleway/block-volume` internally, passing through the instance's own `name_prefix`/`name_suffix` so the volume's name matches the instance's -- exactly what the one real past consumer always did by hand. `block_volume.project_id` becomes required in this case, enforced via a `validation` block.

This is a narrow, named exception to ADR-0081/ADR-0085's "no local module composes another internally" principle, which otherwise still holds for every other module pairing in this provider root (`object-bucket`/`iam-policy` keep composing externally -- they're genuinely reused across many leaves, unlike `block-volume`). `block-volume` itself isn't removed; it stays independently callable.

Breaking for both modules:
- `block-volume`: `namespace`/`name` renamed to `name_prefix`/`name_suffix`.
- `compute-instance`: `additional_volume_ids` removed; use `instance_config.block_volume.{size,iops,project_id,additional_volume_ids}` instead.

The one live consumer (`workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/deduplication`) stays pinned to its old `compute-instance/v4.0.0`/`block-volume/v2.0.0` tags rather than being migrated here -- its compute/volume/IAM are already being removed entirely on a separate, not-yet-merged branch, so migrating it now would be wasted effort.

See docs/adr/0120-compose-scaleway-block-volume-inside-compute-instance.md for the full decision record, including strikethrough amendments to ADR-0081 and ADR-0085 marking the principle exception.

[#163](https://github.com/noisypigeon/noisypigeon/pull/163)

## [2.0.0] - 2026-10-02

### Move scaleway modules to top-level modules/, major release each

Moves `terraform/modules/scaleway/*` to top-level `modules/scaleway/*` and cuts a major release for every module, fixing the stale `noisypigeon/pigeon.git` repo name (a prior name of this same repo) to the real current name, `noisypigeon/noisypigeon.git`, in every source string along the way.

**Version bumps** (next available major per module, not a blanket v1.0.0 — two modules were already past 1.0):

| Module | Before | After |
|---|---|---|
| `project` | 0.2.1 | **1.0.0** |
| `object-bucket` | 0.2.0 | **1.0.0** |
| `iam-policy` | 1.1.1 | **2.0.0** |
| `compute-instance` | 0.9.1 | **1.0.0** |
| `block-volume` | 1.0.0 | **2.0.0** |

To make the existing automation compute these correctly (its version lookup is tag-prefix-based and all 22 existing tags live under the old `terraform/modules/scaleway/*` prefix), 5 bookkeeping-only seed tags mirroring each module's current version were pushed directly to origin under the new prefix before this PR — no GitHub Release, no CHANGELOG entry, just enough for `module-release.yml`'s `$LATEST` lookup to find a baseline.

**All 16 live consumers** across `terraform/infrastructure/scaleway/**` updated to the new repo name, new path, and new major tag — this also converges pre-existing version drift (`iam-policy` had one consumer on v0.1.0 against five on v1.1.1; `object-bucket` had three different pinned versions across seven consumers). Verified safe: every variable beyond the always-supplied required ones has a default in both modules, so no consumer needs a new argument added.

Also: `module-release.yml`/`module-docs.yml`'s hardcoded `terraform/modules/scaleway` paths, the `release-pr` skill's path references, `modules/README.md` (moved, repo name and tag-scheme examples fixed), and `terraform/README.md` deleted (its "two independent trees" premise no longer holds once `modules/` isn't under `terraform/`).

Checked every other repo in the `noisypigeon` org (`pigeon-cli`, `pigeon-os`, `dotfiles`) for external consumers — none found.

Full rationale in [ADR-0093](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0093-move-scaleway-modules-to-top-level-modules.md).

## Test plan
- [x] `terraform fmt -check -recursive` clean on `modules/` and `terraform/infrastructure/scaleway/`
- [x] `terragrunt hcl format --check` clean on `modules/`
- [x] `grep -rn "terraform/modules/scaleway\|noisypigeon/pigeon\.git"` returns nothing outside historical ADRs/CHANGELOGs
- [x] All 16 consumer leaves + 1 dead/commented reference verified updated
- [ ] User to run `terragrunt init` on affected leaves to confirm the new module source resolves correctly (not performed here — would need real credentials)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#120](https://github.com/noisypigeon/noisypigeon/pull/120)

## [1.0.0] - 2026-10-01

### Require project_id input on scaleway/block-volume

Adds a new required input, `project_id`, to `scaleway/block-volume`, wired straight through to `scaleway_block_volume`'s existing `project_id` argument.

This is a breaking change to the module's interface: existing callers must now pass `project_id` explicitly, since the resource no longer falls back to the provider's default project for volumes created through this module.

[#110](https://github.com/noisypigeon/noisypigeon/pull/110)

## [0.1.0] - 2026-10-01

### Add scaleway/block-volume module and compute-instance volume attachment

Adds a new `scaleway/block-volume` module wrapping `scaleway_block_volume`, and extends `scaleway/compute-instance` so a volume it creates can be attached to an instance.

`block-volume`'s initial interface is required-fields-only, with two deliberate exceptions: the resource's `size_in_gb` is renamed to `size` (required — this module doesn't support creating from a snapshot yet, so omitting a size would be unsafe), and `iops`, though required by the underlying resource, defaults to `15000` (Scaleway's standard tier) rather than being required of every caller. Naming follows the same `{namespace}-{random}-{name}` scheme as every other module in this provider root. Outputs are `id` and `name`.

`compute-instance` gains one new, backwards-compatible input: `additional_volume_ids` (`list(string)`, default `[]`), wired straight through to `scaleway_instance_server`'s existing argument of the same name. Per this repo's established composition rule, `compute-instance` does not call `block-volume` internally — callers create a volume and pass its `id` through themselves, e.g.:

```hcl
module "scratch_volume" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/block-volume?ref=terraform/modules/scaleway/block-volume/v0.1.0"
  namespace = "import"
  name      = "scratch"
  size      = 100
}

module "instance" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/compute-instance?ref=..."
  ...
  additional_volume_ids = [module.scratch_volume.id]
}
```

Existing `compute-instance` callers are unaffected unless they opt in. Full design rationale in [ADR-0085](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0085-add-scaleway-block-volume-module.md).

[#109](https://github.com/noisypigeon/noisypigeon/pull/109)
