# DEV-0145: Private Network access to pigeon-cli job buckets

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-08.
- **Status**: Accepted.

## Context

Every `pigeon-cli` job instance reaches Scaleway Object Storage over the public `https://s3.fr-par.scw.cloud` endpoint today, for every bucket (source/destination/reports) it touches. That's billed as external egress even though the instance and the bucket live in the same Scaleway datacenter — the public endpoint resolves to a public IP, and Scaleway bills traffic to it like any other internet-bound traffic regardless of where it physically terminates. Scaleway's own pricing only waives this for intra-regional transfer over its *private* path, not the public one.

Scaleway's fix is **Object Storage private access**: authorizing a Private Network to reach buckets over `https://<bucket>.s3-vpc.<region>.scw.eu` instead of the public `https://<bucket>.s3.<region>.scw.cloud`, with no change to bucket ACLs or the public path — it's purely an additional network route. This feature is in private beta, fr-par-only; fr-par is already this repo's default and, in practice, only region (`workloads/root.hcl`), so that scoping isn't a blocker. Enabling it is a direct call against the Scaleway VPC API, authorizing a specific Private Network ID — no confirmed Terraform resource exists for this enablement step as of this ADR, and this repo has no existing `local-exec`/`null_resource`/`http`-provider idiom for driving an external API call from Terraform. The established pattern here for a step Terraform genuinely can't do is to document it as an explicit manual step (ADR-0067's GitHub Pages cutover, ADR-0094's manual `terragrunt init` state copy, ADR-0105's plan-only Cloudflare ruleset) — this ADR follows that precedent rather than faking automation around it.

Independent corroboration already sits in this repo: an in-progress, uncommitted edit to a job leaf's keyring swapped a bucket endpoint from `s3.fr-par.scw.cloud` to `s3-vpc.fr-par.scw.eu` before this ADR was written — the same hostname this research arrived at independently.

Two existing modules need a private-network attachment point to make this possible: `compute-instance` (the per-job VM, ADR-0118/0120/0122/0125/0126/0138) and `pigeon-cluster` (ADR-0138/0144 — the module that provisions one self-deleting `compute-instance` per pending job). The network should be configured **once, at the cluster level**, shared by every job instance in that cluster — not a separate network per job, since bucket access is a cluster-wide concern, not a per-job one.

**A second, related decision made while scoping this work:** if job instances are going to reach buckets over a Private Network instead of the public internet, there's no reason most of them need a public IP at all — `compute-instance`'s `enable_ipv4` currently defaults to `true` for every instance it creates. Within `pigeon-cluster` specifically, that default should flip to `false`, with an easy per-job override for debugging (e.g. SSH into one specific failing instance). But cloud-init's own provisioning steps (`apt-get`, the `mise`/`pigeon.sh`/`scw`-CLI installer `curl`s, the Grafana Alloy package install) all need outbound internet access today, and nothing NATs Private Network traffic to the public internet by default — removing every job's public IP would silently break provisioning unless something else provides that path. The fix is a shared Public Gateway on the cluster's Private Network, NATing outbound traffic for every job instance regardless of whether it has its own public IP.

**Scaleway resource research, confirmed against the actual installed provider** (`scaleway/scaleway v2.86.0`, queried live via `tofu providers schema -json` rather than trusted from documentation alone):

- `scaleway_vpc_private_network` — no required arguments at all (`name`/`project_id`/`tags` all optional).
- `scaleway_instance_private_nic` — `server_id` and `private_network_id` required; attaches an instance to a Private Network as its own resource, independent of the server resource (unlike the deprecated inline `private_network` block on `scaleway_instance_server`, which forces server replacement on change). Confirmed: `scaleway_instance_server` itself already exposes a computed `private_ips` block reflecting whatever private NICs are attached to it by any mechanism — `compute-instance`'s existing `private_ips` output needs no change to pick this up.
- `scaleway_vpc_public_gateway_ip` — no required arguments; reserves a flexible IP for a gateway.
- `scaleway_vpc_public_gateway` — only `type` is required (`ip_id`/`name`/`project_id` optional); `move_to_ipam` is confirmed **deprecated** on the installed provider version (`v2.86.0`'s own validation warning: "All gateways now use IPAM. This field is no longer needed") — omitted entirely rather than set.
- `scaleway_vpc_gateway_network` — `gateway_id` and `private_network_id` required; `enable_masquerade` must be set explicitly (not on by default) to actually NAT; an `ipam_config { push_default_route }` block controls whether attached instances receive a default route through the gateway.
- Provider version: IPAM-mode gateway arguments (`move_to_ipam`, `ipam_config`) need `scaleway/scaleway >= 2.52`. Every `.terraform.lock.hcl` in this repo is already locked to `2.86.0` — comfortably above that floor, so no `versions.tf` lower-bound change is needed anywhere in this repo as a result of this ADR.
- This is a real, metered resource (a `VPC-GW-S`-class gateway bills continuously) — a new fixed cost traded against the variable egress cost this ADR removes.

## Decision

### 1. `compute-instance` — bring-your-own Private Network attachment

New optional input, grouped with `enable_ipv4`/`enable_ipv6` (the module's other network-attachment inputs):

```hcl
variable "private_network_id" {
  type        = string
  description = "ID of an existing Scaleway Private Network to attach this instance to via a dedicated private NIC (scaleway_instance_private_nic), alongside its normal public IP(s). null (default): no private NIC, unchanged behavior. Bring-your-own ID -- this module does not create the Private Network itself (see pigeon-cluster, which creates one shared PN per cluster and passes its ID here to every job instance)."
  default     = null
}
```

New conditional resource, next to the existing `scaleway_instance_ip` resources:

```hcl
resource "scaleway_instance_private_nic" "private_nic" {
  count              = var.enabled && var.private_network_id != null ? 1 : 0
  server_id          = scaleway_instance_server.server[0].id
  private_network_id = var.private_network_id
}
```

**This `count` expression turned out to be broken on first real apply — see the amendment in section 4 below**, which replaces `var.private_network_id != null` with a dedicated `var.enable_private_network` boolean. Kept here unedited as the original design text; section 4 is where the fix is recorded.

No cloud-init change needed — a `kind = "bucket"` keyring entry's `endpoint` stays entirely caller-supplied, exactly as today; a caller that wants private routing simply passes a `s3-vpc.<region>.scw.eu` endpoint string, the same mechanism as every other endpoint value. `object-bucket` is untouched by this ADR.

This is a second "bring-your-own ID" network-attachment input, consistent with the module's existing `additional_volume_ids` pattern — no new internal module composition, so this doesn't stretch the ADR-0081/0122 "modules compose modules" exception any further.

No `versions.tf` change — `scaleway_instance_private_nic` is already covered by `scaleway/scaleway ~> 2.0`.

Purely additive. `release:minor`, v5.4.0 → v5.5.0.

### 2. `pigeon-cluster` — one shared Private Network and Public Gateway per cluster

New resources, created once per cluster (not per job):

```hcl
resource "scaleway_vpc_private_network" "jobs" {
  name       = "${var.cluster_config.name_prefix}-jobs"
  project_id = var.cluster_config.project_id
}

resource "scaleway_vpc_public_gateway_ip" "jobs" {
  project_id = var.cluster_config.project_id
}

resource "scaleway_vpc_public_gateway" "jobs" {
  name       = "${var.cluster_config.name_prefix}-jobs-gw"
  type       = "VPC-GW-S"
  ip_id      = scaleway_vpc_public_gateway_ip.jobs.id
  project_id = var.cluster_config.project_id
}

resource "scaleway_vpc_gateway_network" "jobs" {
  gateway_id         = scaleway_vpc_public_gateway.jobs.id
  private_network_id = scaleway_vpc_private_network.jobs.id
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }
}
```

No new `cluster_config` field for naming/tags on any of these — fixed derived names match this module's existing low-configurability style (e.g. `job_policy`'s name is already derived, not caller-set), and there's exactly one PN and one gateway per cluster by design.

Wired into every `module "job"` (compute-instance) call:

```hcl
private_network_id     = scaleway_vpc_private_network.jobs.id
enable_private_network = true
enable_ipv4             = each.value.enable_ipv4
```

(`enable_private_network` was added by the amendment in section 4 below, after this ADR's original text shipped — kept here reflecting the real, final shape rather than the since-superseded first draft.)

`jobs` gains a new per-job field, defaulting to `false` — unlike `compute-instance`'s own `enable_ipv4` default of `true`, which stays unchanged for any other direct caller:

```hcl
enable_ipv4 = optional(bool, false)
```

A job sets `enable_ipv4 = true` on its own entry to get a public IP back temporarily (e.g. to SSH directly into a specific failing instance) without touching any sibling job in the same cluster.

`versions.tf` previously declared `terraform {}` with a comment stating the module composes only, no resources of its own — no longer true, so it gains a real `required_providers` block pinning `scaleway/scaleway ~> 2.0` (confirmed sufficient per the version research above).

Additive at the interface level — nothing renamed or removed. `release:minor`, v0.2.0 → v0.3.0.

### 3. `pigeon-cluster` — `jobs` becomes a list, not a map

Unrelated to private networking itself, but landing in the same change: `jobs` moves from `map(object({...}))` keyed by job name to `list(object({...}))`, each entry naming its own `job_name`:

```hcl
jobs = [
  {
    job_name     = "deduplicate-segment-1"
    job_commands = local.job_commands
    ...
  }
]
```

`for_each` still needs a map for stable per-job resource addressing (a `count`/list-index `for_each` would recreate every job after a removed/reordered entry), so the list is converted once, internally:

```hcl
locals {
  jobs_by_name = { for j in var.jobs : j.job_name => j }
}
```

...and every existing `for_each = var.jobs` / `for ... in var.jobs` site (`job_application`, `job_permission_sets`, `job_api_key`, `effective_keyring`, `job`) switches to `local.jobs_by_name`. `each.key`/`each.value` usage is otherwise untouched — the key is still the job name, the value is still the full job object, now additionally carrying its own `job_name` field. A new validation on `jobs` requires `job_name` values to be unique, so a caller mistake can't silently collide inside that conversion:

```hcl
validation {
  condition     = length(var.jobs) == length(distinct([for j in var.jobs : j.job_name]))
  error_message = "jobs[*].job_name must be unique."
}
```

Still part of the same v0.2.0 → v0.3.0 `release:minor` bump above.

### 4. Amendment (2026-10-08) — fix `Invalid count argument` on first apply

Testing this feature live, against a real `test-private-connectivity` job, immediately failed `tofu plan`:

```
Error: Invalid count argument
  on instance.tf line 23, in resource "scaleway_instance_private_nic" "private_nic":
  23:   count = var.enabled && var.private_network_id != null ? 1 : 0
The "count" value depends on resource attributes that cannot be determined
until apply, so OpenTofu cannot predict how many instances will be created.
```

**Root cause**: this is a well-known Terraform/OpenTofu limitation, not a typo in section 1's design above. `count`/`for_each` must be fully determinable at plan time, but `pigeon-cluster` passes `private_network_id = scaleway_vpc_private_network.jobs.id`, and that Private Network is created in the *same* apply as the job instances that reference it — on a brand-new cluster's first apply, a new resource's `.id` is unknown until apply. Because `private_network_id`'s declared type is a plain, nullable `string`, OpenTofu cannot statically prove an unknown value of that type is non-null, so `var.private_network_id != null` is itself unknown, and the `count` expression depending on it can't be evaluated at plan time. Every other `count`/`for_each` in both modules was checked for the same hazard and is unaffected (`block_volume`'s count depends on a literal caller-supplied number; `iam_policy`/`iam_api_key`'s count depends on whether `iam_config` — the whole object, always passed as a non-null literal by `pigeon-cluster` — is null, never on an unknown nested field).

The fix: stop gating `count` on the ID's nullness, and gate it instead on an explicit, always-statically-known boolean. `compute-instance` gains:

```hcl
variable "enable_private_network" {
  type        = bool
  description = "Whether to attach a scaleway_instance_private_nic using private_network_id. Kept separate from private_network_id (rather than gating on private_network_id != null) because that ID's value is frequently only known after apply -- e.g. a Private Network created in the same apply, as pigeon-cluster does -- and count/for_each can never depend on such a value without OpenTofu failing to plan with \"Invalid count argument\". default false."
  default     = false

  validation {
    condition     = !var.enable_private_network || var.private_network_id != null
    error_message = "private_network_id must be set when enable_private_network is true."
  }
}
```

(The validation block itself is safe even though `private_network_id` may be apply-time-unknown — unlike `count`, a `validation` condition is simply deferred until the value is known, not required to resolve at plan time.)

```hcl
resource "scaleway_instance_private_nic" "private_nic" {
  count              = var.enabled && var.enable_private_network ? 1 : 0
  server_id          = scaleway_instance_server.server[0].id
  private_network_id = var.private_network_id
}
```

`pigeon-cluster` sets `enable_private_network = true` unconditionally in its `module "job"` call (every job always attaches to the cluster's shared PN). Verified by reproducing the exact error in a scratch config (a real, not-yet-applied `scaleway_vpc_private_network` composed with `compute-instance`) and confirming the fix produces a clean plan instead.

Shipped as two sequential PRs, for the same reason as the earlier v5.4.0→v5.5.0 pin incident (#244/#245): `enable_private_network` didn't exist as a real tag until `compute-instance`'s fix merged. PR #246 (`compute-instance`, `release:minor`, v5.5.0 → v5.6.0) first; PR #247 (`pigeon-cluster`, `release:patch`, v0.3.1 → v0.3.2 — internal-only fix, no interface change to `pigeon-cluster` itself) bumped the internal pin and set the new flag once v5.6.0 was real.

### 5. Object Storage private-access enablement — manual, not automated by this ADR

Once `scaleway_vpc_private_network.jobs` exists for a given cluster, authorizing it for Object Storage private access is a direct call against the Scaleway VPC API (private beta enrollment, then the authorization call itself naming that Private Network's ID) — performed by the user, out of band. No confirmed Terraform resource exists for this today, and this repo has no established pattern for driving an ad hoc external API call from Terraform. Job buckets are **not** reachable over `s3-vpc.<region>.scw.eu` from an attached instance until this step has actually been run for that specific Private Network.

## Consequences

- Egress-cost reduction is the goal but unverified until measured against a real invoice before/after — and is now netted against a new fixed cost (the `VPC-GW-S` gateway bills continuously, whether or not any job is currently running).
- A cluster now owns three shared, cluster-scoped resources (the PN, the gateway, the gateway-network attachment), independent of any individual job's lifecycle — none of them torn down by a job's own self-delete.
- Job instances lose their public IP by default; reaching a stuck or failed instance directly now means flipping that one job's `enable_ipv4 = true` and re-applying, rather than always having a public IP available.
- Bucket endpoint selection (public vs. private hostname) stays entirely caller-supplied per keyring entry — nothing stops a caller from forgetting to flip it, the same convention-only risk ADR-0144 already flagged for alias/keyring linking.
- The self-delete drift pattern ADR-0138 already documented (Terraform's state believes a self-deleted server still exists until the next `apply`) now extends to its private NIC too — same category of gap, not a new one.
- `jobs` as a list is a breaking caller-facing change on its own (independent of private networking) — every existing `jobs = { <name> = {...} }` caller must become `jobs = [{ job_name = "<name>", ... }]`. Per-job resource addressing/stability is unaffected, since the module still keys internally by `job_name`.
- Any caller that adopted `private_network_id` before the section-4 amendment must add `enable_private_network = true` to keep the same behavior — the implicit null-check gate is gone. No real external caller existed yet (`pigeon-cluster` was the only consumer, fixed in the same two-PR sequence), so this cost nobody but this repo's own in-flight testing.

## Out of scope

- `object-bucket` module changes — buckets themselves are unaffected; only the network path to them changes.
- Migrating any real consumer leaf (`workloads/willowgraysen.com/terraform/pigeon-cli/{job,cluster}/*`) onto the private endpoint — deliberate follow-up, left for the user once the manual enablement step above has actually been run for that leaf's cluster's Private Network.
- Automating the VPC-API enablement call from Terraform — no confirmed resource exists today.
- Confirming whether deleting a server via the existing self-delete `scw instance server delete ... with-ip=true with-volumes=all` trap also cleanly detaches/deletes its private NIC — first real validation step before relying on this: boot one throwaway cluster job and observe.
- Per-job or cluster-level control over the gateway's own egress (e.g. restricting what the NAT path can reach) — the gateway is all-or-nothing NAT for anything not reaching the private Object Storage endpoint.
