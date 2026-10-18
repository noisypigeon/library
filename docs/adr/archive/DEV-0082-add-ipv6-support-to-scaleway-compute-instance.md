# DEV-0082: add routed IPv6 support to scaleway/compute-instance

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-30.
- **Status**: Accepted.

## Context

Real usage needs `scaleway/compute-instance` to create and attach a public
IPv6 address. The initial ask pointed at `scaleway_flexible_ip`
([resource docs](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/flexible_ip)).

**`scaleway_flexible_ip` doesn't apply here — confirmed at the provider
source level, not just from a docs page.** The rendered docs already say
Flexible IPs are "exclusively available for Elastic Metal (bare metal)
servers," but to rule out stale documentation this was checked directly
against `internal/services/flexibleip/ip.go` in `scaleway/terraform-
provider-scaleway`. The `server_id` field's schema description is
literally `"The baremetal server associated with this flexible IP"`, and
`ResourceFlexibleIPCreate` only ever calls the dedicated `flexibleip` SDK
client (`scaleway-sdk-go/api/flexibleip/v1alpha1`) — no code path touches
`internal/services/instance` at all. Flexible IP is a distinct Scaleway
product scoped to Elastic Metal, structurally incompatible with
`scaleway_instance_server`, the resource this module wraps. Scaleway's own
marketing site uses "flexible IP" loosely as a general concept across
several products (Elastic Metal, Load Balancers, Public Gateways), which is
what made the Terraform resource look applicable when it isn't.

**The actual mechanism for a standard Instance's public IPv6 address is
`scaleway_instance_ip`** with `type = "routed_ipv6"`, attached via
`scaleway_instance_server`'s `ip_id` argument — confirmed against the
provider's own example:

```hcl
resource "scaleway_instance_ip" "ip" {}

resource "scaleway_instance_server" "web" {
  type  = "DEV1-S"
  image = "..."
  ip_id = scaleway_instance_ip.ip.id
}
```

`scaleway_instance_server.public_ips` — already a pass-through output on
this module per ADR-0079 — is a list of objects with `id`/`address`/
`family`/`gateway`/`netmask`/etc. Once an IPv6 `scaleway_instance_ip` is
attached, its address appears there automatically with `family = "inet6"`.
No output changes are needed.

This ADR resolves part of ADR-0079's deferred `ip_id`/`ip_ids`/
`enable_dynamic_ip` (public IP control) out-of-scope bullet — specifically
just the create-and-attach-a-fresh-routed-IPv6 path, not the full surface
area.

## Decision

### New variable: `enable_ipv6`

`inputs.tf` gains a boolean toggle, matching the `enable_*`-boolean naming
convention `object-bucket`'s `enable_versioning` already established in
this repo:

```hcl
variable "enable_ipv6" {
  type        = bool
  description = "Create and attach a routed IPv6 address (true/false)"
  default     = false
}
```

### `instance.tf`: conditional `scaleway_instance_ip` + `ip_id` wiring

```hcl
resource "scaleway_instance_ip" "ipv6" {
  count = var.enable_ipv6 ? 1 : 0
  type  = "routed_ipv6"
}

resource "scaleway_instance_server" "server" {
  name  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image = var.image
  type  = var.type
  ip_id = var.enable_ipv6 ? scaleway_instance_ip.ipv6[0].id : null

  user_data = { ... } # unchanged, from ADR-0081
}
```

Zone is left to provider-level defaults on both resources — they already
default identically — consistent with ADR-0079's existing "zone/
project_id overrides: provider-level defaults apply" stance. No new zone
variable.

### No output changes

`public_ips` already surfaces the attached IPv6 address's `id`/`address`/
`family`/etc. once `enable_ipv6 = true`; a caller filters by
`family == "inet6"` themselves. Adding a derived `ipv6_address` output
would be exactly the kind of "invented" computation ADR-0079 already
rejected for `public_ips[0]`-style indexing — the same reasoning applies
here.

## Consequences

- `release:minor` for `scaleway/compute-instance` — new, backwards-
  compatible, default-`false` input; no behavior change for existing
  callers.
- `terraform/modules/scaleway/compute-instance/README.md` regenerates
  automatically via `module-docs.yml` on merge.
- Callers wanting the IPv6 address value read it out of the existing
  `public_ips` output, not a new dedicated output.

## Out of scope

- `scaleway_flexible_ip` / Elastic Metal server support — a structurally
  different, much larger change (a different server resource entirely),
  not what was needed here.
- Attaching an *existing*, externally-created `scaleway_instance_ip` (no
  `ip_id`/`ip_ids` passthrough variable) — this ADR only covers creating a
  fresh routed IPv6 the module owns.
- IPv4 routed IPs (`type = "routed_ipv4"` / the default `scaleway_instance_ip`).
- `ip_ids` (multiple attached IPs).
- `enable_dynamic_ip` (Scaleway's separate ephemeral-IP mechanism).
- Reverse DNS (`reverse` argument) and `tags` on the created IP.
- Everything else ADR-0079 already deferred and still untouched: root
  volume sizing, additional volumes, security/placement groups, `tags` on
  the instance itself, `private_network`, `state`, Windows admin password
  support, `type` enum validation, attaching to an existing root volume.
