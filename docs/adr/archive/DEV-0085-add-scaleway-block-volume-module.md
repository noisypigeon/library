# DEV-0085: add scaleway/block-volume module, with compute-instance volume attachment

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-30.
- **Status**: Accepted.

## Context

`terraform/modules/scaleway/` has `project`, `object-bucket`, `iam-policy`, and `compute-instance`, but no block-storage module. ADR-0079, which added `compute-instance`, explicitly listed `additional_volume_ids` / `root_volume` sizing as out of scope, with "follow-up ADRs will add functionality ... as real usage demands it." This ADR is that follow-up: a new, deliberately minimal `scaleway/block-volume` module wrapping `scaleway_block_volume` ([resource docs](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/block_volume)), plus extending `compute-instance` so a volume it creates can actually be attached to an instance.

**Resource schema vs. module interface.** Per the provider's resource docs, `scaleway_block_volume` has exactly one `(Required)` argument, `iops`; `size_in_gb`, `name`, `tags`, `zone`, `project_id`, and `snapshot_id` are all `(Optional)`. `size_in_gb` is only safely omittable when `snapshot_id` is set (cloning from an existing snapshot) — this module doesn't support snapshots yet (see Out of scope), so skipping it would produce an unusable, zero-size-intent volume. It is therefore promoted to a required module input, the same resource-argument-vs-module-input reasoning ADR-0079 used for `compute-instance`'s `image`. Per the user's ask, it's also renamed from `size_in_gb` to `size` — this module's own concept, not a pass-through of the provider's argument name.

`iops` stays required on the underlying resource call, but the module gives it a default of `15000` (Scaleway's standard IOPS tier) rather than requiring every caller to specify it — this is the one deliberate exception to "initial interface is required fields only," the same kind of exception ADR-0079 made for `type` defaulting to `STARDUST1-S`.

**Attachment mechanism.** `scaleway_instance_server` already has an `additional_volume_ids` argument: a `list(string)` of pre-created volume IDs, attached to the instance (updates trigger a stop/start of the server). ~~Per ADR-0081's established principle — "no local module ever composes another local module internally" — `compute-instance` does not call `block-volume` as an internal module dependency. It only gains a pass-through `additional_volume_ids` input; callers compose the two at the `terraform/infrastructure/` layer themselves (e.g. `additional_volume_ids = [module.block_volume.id]`), the same way `buckets`/`iam-policy` outputs are wired into `compute-instance` today.~~ Superseded by ADR-0120: with `block-volume` having had exactly one consumer ever, always paired 1:1 with the same `compute-instance` call, external composition bought no real flexibility — ADR-0120 folds volume creation into `compute-instance`'s `instance_config.block_volume`, composing `block-volume` internally as a named exception to this principle. `iam-policy`/`object-bucket` composition stays external.

## Decision

### Module: `scaleway/block-volume`

```hcl
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "scaleway_block_volume" "volume" {
  name       = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  size_in_gb = var.size
  iops       = var.iops
}
```

Inputs: `namespace` (name prefix, required), `name` (name suffix, required), `size` (volume size in GB, required — renamed from the resource's `size_in_gb`), `iops` (defaults to `15000`). Naming reuses the `${namespace}-${random}-${name}` scheme verbatim from every other module in this provider root.

Outputs are pass-through only: `id`, `name` — matching `object-bucket`'s output style, no invented fields.

File layout matches `object-bucket`/`compute-instance` exactly: `volume.tf` / `inputs.tf` / `outputs.tf` / `versions.tf` / `README.md`, no hand-written `CHANGELOG.md` — `module-release.yml` creates one from scratch on first merge, same precedent ADR-0079 confirmed by reading the workflow.

Provider pin: `scaleway/scaleway ~> 2.0`, `hashicorp/random ~> 3.0` — identical to `object-bucket`/`compute-instance`, since this module uses the same two providers.

### Extend `scaleway/compute-instance`

~~Adds one new input, `additional_volume_ids` (`list(string)`, default `[]`), wired straight through:~~ Superseded by ADR-0120 — see that ADR for the current `instance_config.block_volume`-based interface.

```hcl
resource "scaleway_instance_server" "server" {
  name                  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image                 = var.image
  type                  = var.type
  ip_id                 = var.enable_ipv6 ? scaleway_instance_ip.ipv6[0].id : null
  tags                  = [for key in var.ssh_keys : "AUTHORIZED_KEY=${replace(key, " ", "_")}"]
  additional_volume_ids = var.additional_volume_ids
  ...
}
```

Defaults to an empty list, so existing callers are unaffected unless they opt in — backwards compatible, `release:minor`, matching the posture of every prior `compute-instance` input (`buckets`, `enable_ipv6`, `ssh_keys`).

### Repo-wide wiring

- `terraform/modules/README.md` gains a `scaleway/block-volume` row in the Modules table, and the `scaleway/compute-instance` row is updated to mention volume attachment.
- `.github/workflows/module-docs.yml`'s hand-maintained `working-dir:` list gains `terraform/modules/scaleway/block-volume`.
- `.github/workflows/module-release.yml` needs **no change** — its module discovery (`find terraform/modules/digitalocean terraform/modules/scaleway -mindepth 2 -maxdepth 2 -name versions.tf`) already generalizes to any provider root containing a `versions.tf`.

## Consequences

- Consumers can create a Scaleway block volume and attach it to a `compute-instance` instance, composed at the Terragrunt layer, with no change to either module's independence.
- `block-volume`'s interface intentionally doesn't cover the resource's full surface area (snapshots, tags, project/zone overrides) — extending it is expected as real usage surfaces the need, the same posture ADR-0079/0044 took for `compute-instance`/`object-bucket`.
- Attaching or detaching a volume via `additional_volume_ids` triggers a stop/start of the instance (a provider-level behavior of `scaleway_instance_server`, not something this module can avoid).

## Out of scope

### `block-volume`

- `snapshot_id` (creating a volume from an existing snapshot).
- `tags`.
- `project_id` / `zone` overrides (provider-level defaults apply, same posture as every other module in this provider root).
- Enum/range validation on `iops` — Scaleway's supported IOPS tiers are provider-enforced and may change; a hardcoded allow-list would be a maintenance burden for little benefit, the same reasoning ADR-0079 gave for not validating `compute-instance`'s `type`.

### `compute-instance`

- Everything ADR-0079 already deferred and this ADR doesn't touch: `root_volume` sizing/type, `security_group_id` / `placement_group_id`, `ip_id` / `ip_ids` / `enable_dynamic_ip` beyond the existing `enable_ipv6`, `private_network`, `state` control, `admin_password_encryption_ssh_key_id`.
- Detach/delete ordering caveats for local (non-block) volumes in `additional_volume_ids` — not applicable here since `block-volume` only ever produces block volumes, but worth noting this module doesn't guard against a caller passing a local volume ID.
