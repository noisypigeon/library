# DEV-0149: pigeon-cluster per-job network opt-out and independent Private Network/Public Gateway toggles

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-09.
- **Status**: Accepted.

## Context

`pigeon-cluster` (ADR-0138/0144/0145/0146) provisions, unconditionally, for every cluster: one shared `scaleway_vpc_private_network.jobs`, one shared `scaleway_vpc_public_gateway_ip.jobs` + `scaleway_vpc_public_gateway.jobs`, and one `scaleway_vpc_gateway_network.jobs` attachment between them. Every entry in `var.jobs` becomes a `compute-instance` call hardcoded to attach to that Private Network and never get a public IP (`enable_private_network = true`, `enable_ipv4 = false`) — there is no per-job override today. ADR-0146 deliberately removed the one override that previously existed, `jobs[*].enable_ipv4`, because Scaleway's own documented behavior (a Public Gateway with `ipam_config.push_default_route` wins over an attached instance's own public interface for inbound reachability) made it a dead end for any job still attached to the shared Private Network.

Two gaps motivate this change:

1. **Not every job needs the cluster's shared networking.** A job that doesn't touch Object Storage over the private endpoint has no way to just be a plain `compute-instance` with a normal public IP, decoupled from the cluster's shared Private Network/Gateway entirely — it's forced onto both regardless.
2. **The shared Private Network and Public Gateway have no independent lifecycle.** They're a single all-or-nothing unit. There's no way to tear down just the Private Network once every job that needed it has completed or been removed, while leaving the Public Gateway running (e.g. because the bastion still depends on it, or to avoid losing its stable IP and having to re-provision later) — or the reverse, tearing down the metered Gateway once nothing needs internet/private-Object-Storage egress while leaving the (free) Private Network provisioned for later.

This mirrors a pattern already established one layer down, at `compute-instance`: ADR-0126's `enabled` kill switch (moving a resource from an unconditional singleton to `count = var.enabled ? 1 : 0`, protected by a `moved` block), and ADR-0145's `enable_private_network`/`private_network_id` split — a boolean gate kept deliberately separate from the resource-ID's nullness, because that ID is frequently apply-time-unknown (e.g. a Private Network created in the same apply) and `count`/`for_each` can never depend on such a value. This ADR applies both patterns inside `pigeon-cluster` itself.

## Decision

### 1. Per-job opt-out: `jobs[*].enable_private_network` (default `true`)

New optional field on `jobs`:

```hcl
enable_private_network = optional(bool, true)
```

`true` (default) preserves today's exact behavior. `false` makes this job a direct, undecorated `compute-instance` call — no private NIC, no dependency on the cluster's shared Private Network/Gateway at all.

### 2. Reinstating `jobs[*].enable_ipv4`

New optional field on `jobs`:

```hcl
enable_ipv4 = optional(bool, false)
```

This reinstates the per-job public-IP override ADR-0146 removed. That removal was specifically about *inbound* reachability — a direct public IP on an instance attached to the cluster's Private Network couldn't be reached by SSH, because the Gateway's `push_default_route` always wins. It doesn't follow that the field itself has no use: once a cluster can disable its Gateway outright (Decision #3 below), a Private-Network-attached job has no competing default route to lose to, and the removed-field's original problem doesn't apply. Reinstating it is what lets a job in that configuration — or a job that has opted out of the Private Network entirely via Decision #1 — actually have a usable public IP.

Wiring in `cluster.tf`'s `module "job"` block:

```hcl
private_network_id     = each.value.enable_private_network ? try(scaleway_vpc_private_network.jobs[0].id, null) : null
enable_private_network = each.value.enable_private_network
enable_ipv4             = each.value.enable_private_network ? each.value.enable_ipv4 : true
```

A job attached to the Private Network gets `enable_ipv4`'s literal value (default `false`, unchanged from today — the ADR-0146 inbound-SSH caveat still applies whenever the cluster's Gateway is active and pushing a default route, called out in the field's own description). A job that opts out of the Private Network entirely always gets a public IP regardless of this field's value — it has no other network path — so the expression above forces `true` rather than silently ignoring a caller-supplied `false`.

Neither field changes anything about how `pigeon-cluster` composes a job's keyring or IAM policy/key — only its network attachment.

### 3. Independent cluster-level toggles: `cluster_config.enable_private_network` / `enable_public_gateway`

New optional fields on `cluster_config`, both default `true`:

```hcl
enable_private_network = optional(bool, true)
enable_public_gateway   = optional(bool, true)
```

The four shared resources become conditional:

```hcl
resource "scaleway_vpc_private_network" "jobs" {
  count = var.cluster_config.enable_private_network ? 1 : 0
  ...
}

resource "scaleway_vpc_public_gateway_ip" "jobs" {
  count = var.cluster_config.enable_public_gateway ? 1 : 0
  ...
}

resource "scaleway_vpc_public_gateway" "jobs" {
  count = var.cluster_config.enable_public_gateway ? 1 : 0
  ip_id = scaleway_vpc_public_gateway_ip.jobs[0].id
  ...
}

resource "scaleway_vpc_gateway_network" "jobs" {
  count              = var.cluster_config.enable_private_network && var.cluster_config.enable_public_gateway ? 1 : 0
  gateway_id         = scaleway_vpc_public_gateway.jobs[0].id
  private_network_id = scaleway_vpc_private_network.jobs[0].id
  ...
}
```

`scaleway_vpc_gateway_network.jobs` — the attachment between the two — needs both IDs, so it's gated on the conjunction rather than inheriting either resource's own count.

This is the independent-disable mechanism directly: once no remaining job needs the shared Private Network, set `enable_private_network = false` to tear it down (and the Gateway-Network attachment with it) while `enable_public_gateway` stays `true` — the Gateway, and its stable IP, keeps running untouched (e.g. still fronting the bastion's PAT rule). The reverse also works: disable the metered Gateway once nothing needs internet/private-Object-Storage egress, leaving the free Private Network provisioned for later.

`module.bastion` and `scaleway_vpc_public_gateway_pat_rule.bastion_ssh` (both already gated on `enable_bastion`) have their Private-Network/Gateway references updated to `try(scaleway_vpc_private_network.jobs[0].id, null)` / `try(scaleway_vpc_public_gateway.jobs[0].id, null)`, since those resources are now conditional. `outputs.bastion_connect_command` similarly guards its `scaleway_vpc_public_gateway_ip.jobs[0].address` lookup.

### 4. Validation

One new `validation` block on `cluster_config`, referencing only fields within that same variable (no cross-variable validation feature needed):

```hcl
validation {
  condition     = !var.cluster_config.enable_bastion || (var.cluster_config.enable_private_network && var.cluster_config.enable_public_gateway)
  error_message = "cluster_config.enable_bastion requires enable_private_network and enable_public_gateway to both be true."
}
```

The symmetric case — a job requesting `enable_private_network = true` against a cluster that has disabled its own Private Network — is **not** given a dedicated check here, since that would require `jobs`'s own `validation` block to reference `cluster_config`, a cross-variable check this repo hasn't adopted elsewhere. Instead, the existing chain already produces a correct, if one-level-indirect, error: a disabled cluster-level Private Network resolves `private_network_id` to `null` for any job still requesting `enable_private_network = true`, which trips `compute-instance`'s own existing validation (`!var.enable_private_network || var.private_network_id != null` → *"private_network_id must be set when enable_private_network is true."*). This is a deliberate, accepted gap, consistent with this repo's existing tolerance for similar convention-only edges (e.g. ADR-0144's keyring-alias-shadowing gap).

### 5. `moved` blocks

The four resources that move from unconditional singletons to `count`-gated each get a `moved` block, the exact ADR-0126 precedent, protecting any existing caller's state through the address change:

```hcl
moved {
  from = scaleway_vpc_private_network.jobs
  to   = scaleway_vpc_private_network.jobs[0]
}
moved {
  from = scaleway_vpc_public_gateway_ip.jobs
  to   = scaleway_vpc_public_gateway_ip.jobs[0]
}
moved {
  from = scaleway_vpc_public_gateway.jobs
  to   = scaleway_vpc_public_gateway.jobs[0]
}
moved {
  from = scaleway_vpc_gateway_network.jobs
  to   = scaleway_vpc_gateway_network.jobs[0]
}
```

### Versioning

Additive at the interface level: every new field defaults to reproducing today's exact resource graph for any caller that sets nothing new — the `moved` blocks absorb the only internal state change. `jobs[*].enable_ipv4` is a field name ADR-0146 removed in a `release:major` bump; reinstating it under the same name with the same type/meaning is not itself a shape break. `release:minor`, `v1.1.0` → `v1.2.0`.

The one real consumer, `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/`, needs no required change — every new field defaults to today's behavior. Bumping its `source` pin to `v1.2.0` is left to the user, same as past minor releases.

## Consequences

- A cluster operator can now shrink its shared networking footprint to match what's actually in use, independently in either direction (Private Network vs. Public Gateway), rather than always paying for and running both as a fixed unit.
- A job that opts out of the shared Private Network is, by design, "just a `compute-instance`" from a networking standpoint — it gains no benefit from and has no dependency on anything `pigeon-cluster` provisions beyond its own IAM/keyring composition.
- Reinstating `enable_ipv4` reopens a knob this repo explicitly closed once already (ADR-0146) for a documented reason (broken inbound SSH). That reason is now caveated rather than solved — the field's own description states plainly when it is and isn't useful, so a caller can still misuse it (set it `true` on a Private-Network-attached job while the cluster's Gateway is still active) and get a public IP that doesn't help with inbound SSH, same as before ADR-0146. This is accepted as the cost of giving the knob back.
- Misconfiguring a job's `enable_private_network = true` against a cluster with its own Private Network disabled produces a real `plan`-time failure, but from `compute-instance`'s validation message rather than one naming `pigeon-cluster`'s own fields directly — a one-level-indirect error, not a silent misconfiguration or an opaque provider failure.

## Out of scope

- A whole-cluster `enabled` kill switch tearing down every job/bastion/Private-Network/Gateway at once — not asked for; `jobs`/`enable_bastion` already let a caller shrink to zero job-shaped resources without this.
- Actually fixing inbound SSH to a Private-Network-attached job's own public IP while the cluster's Gateway is still active and pushing a default route — still Scaleway's documented, unfixed behavior. Reinstating `enable_ipv4` doesn't change that; it's reachable/useful either with `enable_public_gateway = false` or for outbound-only use of the IP.
- A dedicated cross-variable `validation` catching a job's `enable_private_network = true` against a cluster with the Private Network/Gateway disabled — flagged above as a real, accepted gap; `compute-instance`'s own validation already catches it, one level removed.
- Automating the Object Storage private-access enablement call (ADR-0145 Decision #5) — unrelated, still manual.
