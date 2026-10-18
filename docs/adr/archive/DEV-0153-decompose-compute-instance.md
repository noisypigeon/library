# DEV-0153: Decompose `compute-instance`, composing its parts at `pigeon-cluster`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-10.
- **Status**: Accepted.

## Context

`compute-instance` has accumulated into a monolith: 659 lines across five files, owning six
resources and composing three other modules internally (`block-volume` via ADR-0120,
`iam-policy`/`iam-api-key` via ADR-0122). Because all of those concerns sit behind one version,
*any* change to *any* of them cuts a new `compute-instance` release, which `pigeon-cluster` must
then re-pin and release, which the consuming leaf must then re-pin again — three releases and
three sequential PRs, because a module's short source URL only resolves once its own tag exists.

ADR-0152 paid exactly that toll yesterday. Replacing one `apt-get` step with a `curl` inside the
cloud-init heredoc produced `compute-instance/v6.1.0`, then `pigeon-cluster/v2.0.1`, then a leaf
re-pin — three PRs for a provisioning one-liner that touched nothing about the server resource
itself.

The nesting also hides things. ADR-0144 recorded the cost plainly: a credential "composed two
layers down, *inside* `compute-instance` … nothing about that internally-composed key is visible
to `pigeon-cluster` itself." That invisibility is why each job currently ends up with **two IAM
policies and two API keys on one application** — `pigeon-cluster` builds a "work" pair it can read
back and seed the keyring from (it must, since a job cannot source its own keyring defaults from
its own module without a cycle), while `compute-instance` separately builds a self-delete pair
that `pigeon-cluster` cannot see. The `-work-` segment in the first policy's name exists for no
reason other than to dodge a 409 duplicate-name collision between the two.

### This is the composition-principle revisit ADR-0138 asked for

ADR-0081 established, and ADR-0085 explicitly reaffirmed, that no local module in this provider
root composes another internally. ADR-0120 then carved "a narrow, named exception … for this one
pairing only", ADR-0122 extended it to the IAM pair, and ADR-0138 stretched it again — from "one
module wraps its own singleton dependencies" to "one module wraps N copies of another module" —
while stating in its Consequences that this was "worth revisiting if a third shape of this
exception shows up elsewhere in the repo, to decide whether it's still 'narrow.'"

This is that third shape, and the answer is to stop widening the exception and instead reverse it.
ADR-0120's own test for the carve-out was consumer count and 1:1-ness: `block-volume` had "exactly
one consumer ever, and that consumer always pairing it 1:1 with `compute-instance`", so external
composition "bought no actual flexibility." That reasoning was sound at the time and is now
obsolete, because the consumer changed shape. `pigeon-cluster` composes N jobs, each independently
choosing whether it wants a volume, a public IP, a private NIC, or self-deletion. The pairing is
no longer 1:1, and the plumbing ADR-0120 called "manual ID plumbing every caller had to repeat"
is now written exactly once, in `pigeon-cluster`, for every job at once via `for_each`.

### The state is empty, which is why this is possible now

`terragrunt state list` against `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/`
returns zero resources — the cluster was destroyed after its last job completed. So this refactor
needs no `moved` blocks and no state migration at all.

That window matters, because the same change later would be substantially harder. Moving a
resource from one sibling module to another is not expressible with `moved` blocks: OpenTofu
resolves them relative to the declaring module and "a module may only make `moved` statements
about its own objects and objects of its child modules", so a `moved` in `pigeon-cluster` cannot
carry `module.job[k].scaleway_instance_private_nic.private_nic[0]` across into a sibling. ADR-0122
faced the mirror image of this problem and had to put its `moved` blocks in the consumer leaf.
Doing this refactor against live state would mean destroying and recreating every job instance.

## Decision

### 1. Target shape

```
pigeon-cluster (v3.0.0)
├── scaleway_vpc_{private_network,public_gateway,public_gateway_ip,gateway_network}  [unchanged]
├── scaleway_vpc_public_gateway_pat_rule.bastion_ssh                                [unchanged]
├── scaleway_instance_ip.job_ipv4 / .job_ipv6        for_each   <- lifted
├── scaleway_instance_private_nic.job / .bastion     for_each   <- lifted
├── module.job_block_volume      block-volume/v4.0.0  for_each  <- un-nested
├── module.job_application       iam-application              [unchanged]
├── module.job_policy            iam-policy                   [unchanged]
├── module.job_api_key           iam-api-key                  [unchanged]
├── module.job_self_delete_policy  iam-policy                 <- un-nested
├── module.job_self_delete_key     iam-api-key                <- un-nested
├── module.job_config / .bastion_config  compute-instance-config/v0.1.0  <- NEW
└── module.job / .bastion                compute-instance/v7.0.0         <- now server-only
```

The resulting dependency order is a clean DAG: IAM -> config -> server -> NIC. This was verified
against the current code rather than assumed. `iam.tf` contains no reference to the instance at
all, and `local.self_delete_script` discovers the instance's own identity **at runtime** from the
Scaleway metadata service (`curl http://169.254.42.42/conf?format=json`), not from Terraform. The
only inbound edge is `local.self_delete_script` reading the API key's secret, which runs
IAM-first, server-second.

### 2. New module: `compute-instance-config`

A module with no resources, whose only output is the rendered cloud-init string. There is direct
precedent for this shape: `pigeon-cluster` itself shipped resource-free from ADR-0138 until
ADR-0145, with a bare `terraform {}` in `versions.tf` needed purely so `template-release.yml`'s
discovery (`find templates/terraform -mindepth 3 -maxdepth 3 -name versions.tf`) picks the module
up for tagging. `compute-instance-config` is the first module here whose output is a rendered
template rather than infrastructure.

It takes over, verbatim, the four locals at `compute-instance/instance.tf:48-361`:
`cloud_init` (the 267-line heredoc), `post_provision_script`, `self_delete_script`, and
`post_provision_enabled`. Its inputs are the cloud-init-shaped half of `compute-instance`'s old
surface — `keyring` (with its three existing validations), `cockpit`, `post_provision_commands`,
`enable_transcoding`, `self_delete_on_exit` — plus two that replace references the module can no
longer make:

```hcl
variable "self_delete_credentials" {
  type      = object({ access_key = string, secret_key = string, project_id = string })
  default   = null
  sensitive = true

  validation {
    condition     = !var.self_delete_on_exit || var.self_delete_credentials != null
    error_message = "self_delete_on_exit requires self_delete_credentials -- the instance needs its own IAM credential to delete itself."
  }
}

variable "has_attached_volume" {
  type    = bool
  default = false
}
```

`self_delete_credentials` replaces reading `module.iam_api_key[0].access_key`/`.secret_key` and
`var.iam_config.project_ids[0]` directly, and its validation ports
`compute-instance/inputs.tf:118-121` across the boundary so the constraint is still enforced where
it is now enforceable.

`has_attached_volume` replaces the `%{~if length(local.attached_volume_ids) > 0~}` guard that
gates cloud-init's `mkfs`/`mount`/`fstab` block. It is deliberately a plain bool supplied by the
caller rather than a list of volume IDs. The existing expression only works because a list's
*length* is known even when its elements are apply-time unknown; a bool derived from the job's own
`block_volume_size` keeps the rendered template independent of apply-time values entirely, which
matters more now that the volume is created in a different module.

The output `cloud_init` is `sensitive = true` — it base64-embeds the self-delete credential and
interpolates every `keyring` secret.

Seeds at **v0.1.0**, matching `template-release.yml`'s no-prior-tag fallback and the
`iam-application`/`iam-api-key` precedent (not ADR-0113's `v1.0.0`, which was specific to
`zola-site` already being production code with a different release track).

### 3. `compute-instance` becomes a server wrapper

Deleted: `iam.tf` in its entirety, `module "block_volume"`, `scaleway_instance_ip.ipv4`/`.ipv6`,
`scaleway_instance_private_nic.private_nic`, `local.attached_volume_ids`, and all four cloud-init
locals. What remains is three resources: `random_string.suffix` (still uncounted, so the instance
name survives an `enabled` cycle), `terraform_data.cloud_init` (now hashing `md5(var.cloud_init)`),
and `scaleway_instance_server` with its `replace_triggered_by` lifecycle block. ADR-0126's
in-module `moved` block for `server` -> `server[0]` stays, since the server does not move.

`instance_config` is dropped and the inputs flattened:

```hcl
name_prefix, name_suffix  (string, required)
image                     (string, default "ubuntu_jammy")
type                      (string, default "STARDUST1-S")
ssh_key                   (string, default null)     # was user_config.ssh_key
cloud_init                (string, sensitive, default null)
ip_ids                    (list(string), default [])
additional_volume_ids     (list(string), default [])
enabled                   (bool, default true)
```

Flattening is not cosmetic. `instance_config` was a single `sensitive = true` object straddling
server, cloud-init and block-volume concerns simultaneously — the precise reason the module was
awkward to split, since any split either shreds that object across three modules or passes the
whole sensitive blob to each. ADR-0118 grouped these inputs for a module that owned all three
concerns; that premise no longer holds. ADR-0118 is otherwise untouched and stays `Accepted`:
dropping `profile`, the `name_prefix`/`name_suffix` rename, and the single collapsed `keyring`
list all survive (the last of these moving to `compute-instance-config` intact).

Gone from the interface: `instance_config`, `user_config`, `keyring`, `iam_config`,
`self_delete_on_exit`, `enable_ipv4`, `enable_ipv6`, `private_network_id`,
`enable_private_network`. Outputs shrink from seven to three — `id`, `name`, `public_ips`.
`ipv4_address`, `private_ips`, `access_key_id` and `secret_key` all disappear because the
resources behind them now live in `pigeon-cluster`, which can read them directly instead of having
them relayed back out through an output.

Two consequences worth stating rather than letting them be discovered later:

- **ADR-0126's `enabled` narrows in scope.** It promised that `false` "destroys every resource the
  module manages for that instance — the server, its IP address(es), its block volume (and the
  volume's data …), and its IAM policy/API key." After this change it destroys the server and
  nothing else; the lifted resources are `pigeon-cluster`'s and are unaffected. Nothing breaks
  today — `jobs[*]` has no per-job `enabled` and no caller sets it — but the variable's
  description says so explicitly, and ADR-0126 is marked superseded in part.
- **Rotating the self-delete API key replaces the server.** The chain is
  `self_delete_credentials` -> `cloud_init` -> `md5()` -> `terraform_data.cloud_init.output` ->
  `replace_triggered_by`. This is already true today via the internal `module.iam_api_key`; the
  split does not introduce it, but it does make it an explicit, documented property of a module
  boundary rather than something inherited by accident.

### 4. `pigeon-cluster` composes the parts

The lifted resources become `for_each` over filtered maps of `local.jobs_by_name`. Every one of
those `for_each` expressions keys off a `jobs[*]` boolean, never an ID — ADR-0145 §4's constraint
that `count`/`for_each` can never depend on an apply-time-unknown value is why the per-job
`enable_private_network` boolean exists separately from `private_network_id != null` in the first
place, and the same rule governs here:

```hcl
resource "scaleway_instance_private_nic" "job" {
  for_each           = { for k, v in local.jobs_by_name : k => v if v.enable_private_network }
  server_id          = module.job[each.key].id
  private_network_id = scaleway_vpc_private_network.jobs[0].id
}
```

The NIC stays a standalone resource rather than an inline `private_network` block on the server,
for ADR-0145's original reason: attaching or detaching must never force server replacement.

Lifting it has a side benefit. The `bastion_ssh` PAT rule can now read
`scaleway_instance_private_nic.bastion[0].private_ips` directly instead of going through
`module.bastion[0].private_ips`, which retires the ADR-0145 amendment's workaround — the output it
worked around existed only because `scaleway_instance_server`'s own `private_ips` attribute does
not reflect a separately-attached NIC, so the output had to `try()` the NIC first and the server
second. With the NIC in the same module, there is one authoritative source and no fallback.

`module.job_self_delete_policy` and `module.job_self_delete_key` are kept **separate** from the
existing `job_policy`/`job_api_key` work pair rather than merged into them. Merging would remove
the duplicate pair and the `-work-` naming workaround in one stroke, but it would also hand the
job's keyring credential `InstancesFullAccess` — and ADR-0144 deliberately narrowed the
self-delete policy to nothing else precisely to keep those apart. The duplication is the price of
that isolation and is now at least visible in one file. The `-work-` segment *is* dropped, since
the names no longer collide once both pairs are named in the same module; nothing is live, so that
rename costs nothing.

`module.job` reduces to `name_prefix`, `name_suffix`, `type`, `cloud_init`, `ip_ids` and
`additional_volume_ids`. The bastion gains its own `bastion_config` call so it keeps today's
rclone/neovim/mise/`pigeon.sh` bootstrap, which it currently gets by passing no `instance_config`
at all and letting `compute-instance` render defaults.

This also collapses a pin drift this split exposes: `iam-api-key` was pinned at `v0.1.0` inside
`compute-instance` and `v0.2.0` inside `pigeon-cluster` — the manual-bump cost ADR-0121 accepted,
visible in practice. With the nested call gone there is one pin.

`cluster_config` and `jobs` keep their exact current schemas, so no consuming leaf has to change
anything but its pin. The major bump is for internal resource-address churn, which would mean
destroy/recreate for any caller holding live state.

### 5. ADR-0121's constraint carries forward

Every new and re-pointed module reference uses a released-tag short URL
(`https://pigeon.dev/modules/scaleway/<name>/vX.Y.Z`), never a relative path. ADR-0121 is
superseded as a decision — the specific pin it added is on a line this ADR deletes — but its
finding is load-bearing here and is restated rather than lost: go-getter's HTTP installer fetches
only the referenced module's own directory as its package, so a relative `../<name>` source fails
with `Error: Local module path escapes module package` for any HTTP-sourced consumer. A split that
referenced siblings by relative path would not work at all.

### 6. Three PRs

`template-release.yml` applies one bump level per PR, but a module with no prior tag starts at
`0.1.0` regardless of the label. So the new module and the `compute-instance` rewrite can share
one PR — neither references the other, so there is no tag-ordering dependency between them:

1. `compute-instance-config` (new) + stripped `compute-instance` + this ADR + ADR status edits +
   docs/workflow housekeeping — `release:major`, cuts `compute-instance-config/v0.1.0` **and**
   `compute-instance/v7.0.0`.
2. `pigeon-cluster` rewired to both new tags — `release:major`, cuts `pigeon-cluster/v3.0.0`.
   Opens only after PR 1 has tagged.
3. The consumer leaf's pin bump to `v3.0.0` — no `release:*` label; goes through the
   `terragrunt-plan.yml`/`terragrunt-apply.yml` gate (ADR-0129) instead.

Two hand-maintained registries need the new module appended, neither of which is discovered
automatically: `.github/workflows/module-docs.yml`'s `working-dir:` list, and the module table in
`templates/terraform/README.md`. That table is also corrected while open — its `compute-instance`
row still advertises the top-level `additional_volume_ids` interface ADR-0120 removed, and it has
never had a `pigeon-cluster` row at all.

## Consequences

- A cloud-init change now cuts `compute-instance-config` and a `pigeon-cluster` re-pin, leaving
  the module that owns the live server untouched. The chain is no shorter in PR count for any
  single change — `pigeon-cluster` still has to re-pin whatever moved — but the blast radius is
  much narrower, and the module every consumer pins stops churning for reasons unrelated to the
  server.
- `block-volume` genuinely loses a hop: it was two layers down and is now composed directly by
  `pigeon-cluster`, so a `block-volume` release reaches a job in one re-pin instead of two.
- `release:major` for `templates/terraform/scaleway/compute-instance` (v6.1.0 -> v7.0.0) and
  `templates/terraform/scaleway/pigeon-cluster` (v2.0.1 -> v3.0.0); a new
  `templates/terraform/scaleway/compute-instance-config` at v0.1.0. `compute-instance`'s interface
  change is drastic, but its only consumer is `pigeon-cluster`, and `pigeon-cluster`'s own
  caller-facing schema is unchanged.
- `compute-instance` is no longer `sensitive` as a whole. Only `cloud_init` is, so values derived
  from `image`/`type` stop being marked sensitive by propagation — a readability improvement in
  plan output that ADR-0118's object grouping had cost.
- The repo now has a module whose output is a string, not infrastructure. `compute-instance-config`
  creates nothing, so it never appears in a plan; a bug in it surfaces as a changed `user_data`
  hash and a replaced server, which is the same signal a cloud-init edit has always produced.
- ADR-0081/0085's principle is restored for every pairing in this provider root. ADR-0120 and
  ADR-0122's exceptions are reversed, and ADR-0138's "one module wraps N copies of another" is
  the only form that remains — which is what `pigeon-cluster` is for.
- Doing this against empty state means no `moved` blocks anywhere. The flip side is that this
  specific refactor is effectively a one-time opportunity: repeating it, or reversing it, with
  live job instances would require destroy/recreate, since `moved` cannot cross between sibling
  modules.

## Out of scope

- Per-job `enabled`. `compute-instance` keeps the input, but with the volume, IPs, NIC and IAM now
  owned by `pigeon-cluster`, a true per-job kill switch would have to gate those `for_each`
  expressions too. No caller needs it today.
- Merging the self-delete IAM pair into the work pair. Not deferred — a deliberate boundary: it
  would widen the keyring credential to `InstancesFullAccess`, which ADR-0144 specifically
  separated.
- Giving `compute-instance-config` any awareness of what consumes it. It renders a string from
  inputs and has no provider, no resources, and no knowledge of the server — keeping it that way
  is what makes it independently versionable.
- Splitting `pigeon-cluster`'s own shared VPC resources (private network, gateway, PAT rule) into
  a module. They have exactly one consumer and are already at the composing layer.
- Re-verifying the self-delete metadata path. ADR-0138 flagged `.location.zone_id` as its "best
  guess at the metadata schema from docs alone"; this ADR moves that script between modules
  without changing a character of it, so the caveat travels with it unresolved.
