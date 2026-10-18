# DEV-0146: Fold a debug-SSH bastion into pigeon-cluster, drop per-job enable_ipv4

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-08.
- **Status**: Accepted.

## Context

ADR-0145 gave `pigeon-cluster`'s `jobs` a per-job `enable_ipv4` override (default `false`) so a caller could get one job instance's public IP back temporarily, e.g. to SSH into a specific failing instance. It doesn't actually work: that same ADR's shared Public Gateway advertises a default route to every instance on the cluster's Private Network (`ipam_config.push_default_route = true`), and Scaleway's own documented troubleshooting for exactly this symptom confirms the gateway's route advertisement takes priority over an attached instance's own public interface — https://www.scaleway.com/en/docs/public-gateways/troubleshooting/cant-connect-to-instance-with-pn-gateway/. Flipping `enable_ipv4 = true` on a job buys a public IP that still can't be reached by direct SSH.

The one real consumer, `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/`, already worked around this — but only as a one-off, fully commented-out leaf file (`bastion.tf`), never actually applied. It stood up a standalone bastion instance plus a `scaleway_vpc_public_gateway_pat_rule` forwarding the gateway's own public IP (an alternate port) to the bastion's private IP:22 — confirmed, by the file's own comments, as the only path that actually works. Living outside the module that creates the cluster's Private Network/Gateway, it had to look both up by name via `data` sources, and it deliberately kept the bastion's own public IP anyway (`enable_ipv4 = true`) as a diagnostic comparison point against the PAT-rule path — the point of that file was to *prove* the direct-IP path was broken, not to be a reusable feature.

That diagnostic has now served its purpose: the PAT-rule path is confirmed working, the direct-IP path is confirmed broken. There's no reason left to keep either the per-job `enable_ipv4` escape hatch (it doesn't deliver what it promises) or the bastion as hand-rolled, leaf-local code (every `pigeon-cluster` consumer would otherwise have to reinvent it, by-name `data` lookups and all).

Separately, found while reading `cluster.tf` closely for this change: `compute-instance`'s `instance_config.block_volume.iops` input (added alongside `size`, ADR-0120) was never threaded through from `pigeon-cluster`'s own `jobs[*].block_volume_size` — every job cluster-wide silently rides `compute-instance`'s own default (`15000`) with no way to ask for anything else. Fixed in the same change, since it touches the exact same `instance_config.block_volume` object.

Internal module pins were also checked against latest while this file was open: `compute-instance` had a newer patch available (`v5.6.0` → `v5.6.1`); `iam-application`/`iam-policy`/`iam-api-key` were already current.

A module rename (`pigeon-cluster` → `compute-cluster`) was considered alongside this change and explicitly rejected — the module keeps its current name and tag prefix.

## Decision

### 1. Remove `jobs[*].enable_ipv4`

Dropped entirely from the `jobs` variable's object type, along with its ADR-0145 doc comment. `module "job"`'s `compute-instance` call now hardcodes `enable_ipv4 = false` — `compute-instance`'s own default for that input is `true`, so this has to stay explicit now that the per-job override is gone, or every job would silently regain a (useless, per the Context above) public IP.

Breaking at the interface level even though no live caller currently sets it to `true`.

### 2. `cluster_config.enable_bastion` — the bastion moves into the module

New field, default `false`:

```hcl
enable_bastion = optional(bool, false)
```

When `true`, `cluster.tf` provisions one bastion instance on the cluster's existing shared Private Network, folded in from the leaf-level `bastion.tf` but adapted to reference the module's own `scaleway_vpc_private_network.jobs`/`scaleway_vpc_public_gateway.jobs` resources directly instead of by-name `data` lookups:

```hcl
module "bastion" {
  count       = var.cluster_config.enable_bastion ? 1 : 0
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v5.6.1"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = "bastion"

  enable_ipv4             = false
  private_network_id      = scaleway_vpc_private_network.jobs.id
  enable_private_network  = true
}

resource "scaleway_vpc_public_gateway_pat_rule" "bastion_ssh" {
  count = var.cluster_config.enable_bastion ? 1 : 0

  gateway_id   = scaleway_vpc_public_gateway.jobs.id
  private_ip   = [for ip in module.bastion[0].private_ips : ip.address if !strcontains(ip.address, ":")][0]
  private_port = 22
  public_port  = 2222
  protocol     = "tcp"
}
```

**Unlike the original diagnostic file, the bastion gets no public IP** (`enable_ipv4 = false`, explicit — same reasoning as section 1, `compute-instance`'s own default is `true`). The diagnostic's whole point was comparing the direct-IP path against the PAT-rule path; now that the direct-IP path is confirmed non-functional, giving the bastion one would just provision a public IP nobody can use. The PAT rule alone is the complete access path.

A new output surfaces it:

```hcl
output "bastion_connect_command" {
  value = var.cluster_config.enable_bastion ? "ssh -p 2222 root@${scaleway_vpc_public_gateway_ip.jobs.address}" : null
}
```

`pigeon-cluster` had no IP/connection-related output at all before this — `job_ids` was its only output.

Additive at the interface level.

### 3. `jobs[*].block_volume_iops`

New field, same default as `block-volume`'s own `iops` variable and `compute-instance`'s `instance_config.block_volume.iops`:

```hcl
block_volume_iops = optional(number, 15000)
```

Wired into `module "job"`'s `instance_config.block_volume`:

```hcl
block_volume = each.value.block_volume_size == null ? null : {
  size       = each.value.block_volume_size
  iops       = each.value.block_volume_iops
  project_id = var.cluster_config.project_id
}
```

Additive — no caller behavior changes until a job entry actually sets it.

### 4. Internal pin bump

`module "job"`'s (and the new `module "bastion"`'s) `compute-instance` source pin moves from `v5.6.0` to the current latest, `v5.6.1`. No other internal pin (`iam-application`, `iam-policy`, `iam-api-key`) was behind.

### Versioning

Sections 1-4 land together as one `release:major` bump, `v0.3.2` → `v1.0.0` — the `jobs[*].enable_ipv4` removal alone is breaking regardless of the additive work riding alongside it, consistent with this repo's standing discipline that an interface change is breaking whether or not any current caller depends on the removed piece.

Shipped as two sequential PRs, for the same reason as ADR-0145's own amendment (#246/#247): the module's new tag doesn't exist until its own PR merges, so the one real consumer's version-pin bump has to land afterward, in its own PR, not bundled with the module change. PR #1 (`pigeon-cluster` itself, `release:major`) lands this ADR's sections 1-4. PR #2 (`workloads/willowgraysen.com/terraform/pigeon-cli/cluster/`, no release label — touches no `templates/terraform/**` path) deletes the now-fully-superseded `bastion.tf` and bumps `module "cluster"`'s pin to `v1.0.0`, leaving `cluster_config.enable_bastion` unset (defaults `false` — no functional change for that leaf today, since its `bastion.tf` was never actually applied).

**Deliberately not renamed.** `compute-cluster` was considered and rejected — the module stays `pigeon-cluster`, same tag prefix, so none of ADR-0093/0110's seed-tag/two-PR-for-versioning machinery is needed here; the module's existing tag history (`v0.3.2`) already lets `template-release.yml` compute the correct `v1.0.0` on its own.

**Deliberately not touched**: `compute-instance/inputs.tf:137,143` and `instance.tf`'s comments reference "pigeon-cluster" by name as historical design-rationale (why `private_network_id`/`enable_private_network` are shaped the way they are). Left as-is — same precedent as leaving old ADR bodies/CHANGELOG entries untouched after a related change (e.g. ADR-0136) — and editing them would incidentally force an unrelated `compute-instance` release for a cosmetic-only reason.

## Consequences

- The per-job debug-access story changes shape entirely: instead of flipping one job's `enable_ipv4` (which never worked), a caller sets `cluster_config.enable_bastion = true` once per cluster and reads `bastion_connect_command`.
- A cluster with `enable_bastion = true` carries one extra always-on `compute-instance` plus a PAT rule, independent of any individual job's lifecycle, for as long as the flag stays `true`.
- Any caller that had set `jobs[*].enable_ipv4 = true` would break on upgrade — none exists today, so this costs nobody in practice, but it's a real breaking change to the public interface.
- `block_volume_iops` closes a real, silent gap: before this change, no `pigeon-cluster` caller had any way to ask for a block volume IOPS value other than `compute-instance`'s hardcoded default, regardless of workload.

## Out of scope

- Actually turning `enable_bastion` on for the one real consumer leaf — left for the user, once debug SSH access is actually wanted there.
- Any further bastion hardening (SSH key management, access logging, auto-expiry) — this ports the original diagnostic's proven-working mechanism as-is, nothing more.
- Renaming `pigeon-cluster` — explicitly considered and rejected for this change.
