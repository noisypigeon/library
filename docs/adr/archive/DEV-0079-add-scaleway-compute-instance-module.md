# DEV-0079: add scaleway/compute-instance module

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-28.
- **Status**: Accepted.

## Context

`terraform/modules/scaleway/` has `project`, `object-bucket`, and
`iam-policy`, but no compute module. `terraform/modules/digitalocean/droplet`
is the DigitalOcean analog, but it bundles a lot of DigitalOcean-specific
machinery on top of the base resource: cloud-init provisioning (rclone, an
LVM auto-combine script, a sudo user), an `access-key` sub-module for
rclone bucket credentials, an SSH-key data source, and a Cloudflare DNS
alias. None of that is wanted yet for Scaleway — this ADR adds a
deliberately minimal wrapper around `scaleway_instance_server`
([resource docs](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/instance_server)),
using `droplet` only for structural inspiration (file layout, the
namespace-random-name convention), not feature parity. Follow-up ADRs will
add functionality (SSH access, storage sizing, networking, tags) as real
usage demands it — the same incremental path ADR-0043 → ADR-0044 took for
`object-bucket`.

**`image` is a required module input despite being an optional resource
argument.** Per the provider's resource docs, `scaleway_instance_server`
has exactly one `(Required)` argument: `type`. `image` is `(Optional)` —
but only because it can be omitted when the server boots from an
*existing* root volume instead of a fresh marketplace/custom image. This
module doesn't support attaching an existing root volume yet (see Out of
scope), so skipping `image` would produce an unbootable instance. `image`
is therefore a required module input, the same kind of resource-argument-
vs-module-input call ADR-0044 made explicitly for `object-bucket`'s
`storage_class`.

**`type` gets a default, everything else required stays required.** Per
the user's ask, `type` defaults to `STARDUST1-S` (Scaleway's smallest
current-generation type) but remains overridable per instance. This is the
one deliberate exception to "initial interface is required fields only" —
every other input (`namespace`, `name`, `image`) has no default.

## Decision

### Module: `scaleway/compute-instance`

```hcl
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "scaleway_instance_server" "server" {
  name  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image = var.image
  type  = var.type
}
```

Inputs: `namespace` (name prefix, required), `name` (name suffix,
required), `image` (UUID or marketplace label, required), `type` (defaults
to `"STARDUST1-S"`). Naming reuses the `${namespace}-${random}-${name}`
scheme verbatim from `digitalocean/droplet` and `scaleway/object-bucket`
(`random_string`, not `random_pet` — the repo-wide convention).

Outputs are pass-through only, no invented indexing into
`public_ips[0]`/`private_ips[0]`: `id`, `name`, `public_ips`, `private_ips`.
By default the resource attaches no IP at all (`enable_dynamic_ip` and
`ip_id` are both out of scope for now), so `public_ips` is an empty list
until a follow-up ADR adds IP control.

File layout matches `object-bucket` exactly: `instance.tf` / `inputs.tf` /
`outputs.tf` / `versions.tf` / `README.md`, no hand-written
`CHANGELOG.md` — `module-release.yml` creates one from scratch on first
merge (confirmed by reading the workflow: its changelog step writes a
fresh `# Changelog` header when the file doesn't already exist), matching
how a module with no ported `pigeon-tf` history should behave.

### Provider pin

`scaleway/scaleway ~> 2.0` and `hashicorp/random ~> 3.0` in `versions.tf`
— identical to `object-bucket`'s pins, since this module uses the same two
providers.

### Repo-wide wiring

- `terraform/modules/README.md` gains a `scaleway/compute-instance` row in
  the Modules table.
- `.github/workflows/module-docs.yml`'s hand-maintained `working-dir:`
  list gains `terraform/modules/scaleway/compute-instance`.
- `.github/workflows/module-release.yml` needs **no change** — its module
  discovery (`find terraform/modules/digitalocean
  terraform/modules/scaleway -mindepth 2 -maxdepth 2 -name versions.tf`)
  and its changelog/tagging automation already generalize to any provider
  root containing a `versions.tf`, confirmed by reading the workflow in
  full.

## Consequences

- Consumers get a working, bootable Scaleway instance with the
  `namespace-random-name` convention, matching the naming scheme already
  used across both providers' modules.
- The module intentionally doesn't cover the resource's full surface area
  — extending it (SSH keys, volumes, networking, tags, IP control) is
  expected as real usage surfaces the need, the same posture ADR-0044 took
  for `object-bucket`.

## Out of scope

- `root_volume` sizing/type (`size_in_gb`, `volume_type`, `sbs_iops`).
- `additional_volume_ids` / `filesystems`.
- `security_group_id` / `placement_group_id`.
- `ip_id` / `ip_ids` / `enable_dynamic_ip` (public IP control).
- `tags`.
- `user_data` / cloud-init.
- `private_network`.
- `zone` / `project_id` overrides (provider-level defaults apply).
- `state` (start/stop/standby control).
- `admin_password_encryption_ssh_key_id` (Windows admin password support).
- Enum validation on `type` — Scaleway's commercial-type catalog is large
  and changes over time; a hardcoded allow-list would be a maintenance
  burden for little benefit over the provider's own validation.
- Attaching to an existing root volume (`root_volume.volume_id` without
  `image`).
