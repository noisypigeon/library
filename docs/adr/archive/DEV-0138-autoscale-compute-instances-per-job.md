# DEV-0138: Autoscale compute instances per pigeon-cli job

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-07.
- **Status**: Exploration.

`Exploration` has no precedent elsewhere in `docs/adr/` — every prior ADR here ships `Status: Accepted`, even narrow ones. This one is deliberately different: it's a design spike recording a chosen direction and its open questions, not a build that's landed. Treat anything below marked "to confirm" as exactly that.

## Context

Today, every `pigeon-cli` job gets its own hand-authored Terraform leaf under `workloads/willowgraysen.com/terraform/pigeon-cli/job/<job-name>/`, each wiring exactly one `compute-instance` module call (ADR-0133). Turning a job "on" or "off" means a human flips ADR-0126's `enabled` kill switch and runs `terraform apply` — a manual, Terraform-triggered destroy/recreate. Nothing today lets an instance remove itself, and nothing scales the *number* of instances to the number of jobs actually pending; headcount is however many leaves exist, as of whenever someone last applied.

The ask here is the opposite shape: given some number of pending jobs, provision that many instances, one job per instance, and have each instance scale itself down — tear itself down — the moment its job finishes, whether it succeeds or fails.

### What Scaleway offers, and why it doesn't fit directly

Scaleway has an "Autoscaling Groups" feature (CPU Instances → Instance groups). It scales a fleet up/down based on **resource-utilization metrics** (RAM/bandwidth thresholds, sourced from Cockpit) and is built to sit behind a **Load Balancer** distributing connections across interchangeable members — scaling policies take a type (`flat_count` / `percent_of_total_group` / `set_total_group`) and act on the whole group. That's the right tool for a stateless web-server fleet. It is not the right tool here: there's no "scale down this *specific* instance because *its* job finished" primitive, membership isn't keyed to job identity, and the whole model assumes members are interchangeable and load-balanced, not each running a distinct one-shot task. Scaleway's Terraform provider (`scaleway/scaleway`) didn't show a confirmed resource for this feature in this research pass either — it may currently be API/CLI-only, which would mean stepping outside this repo's all-Terraform workflow to use it at all.

**This ADR does not build on Autoscaling Groups.** It's recorded here as the considered-and-rejected alternative.

### Two-module layering, not a leaf hack

An earlier pass at this design tried to get away with zero Terraform module changes — self-termination as a hand-rolled `trap` in a leaf's `job_commands`, instance count as a leaf-level `for_each`. That's fragile: every leaf would need to re-derive the same `trap`/credential/self-lookup logic correctly, and "one leaf per job" still doesn't give each job its own clean IAM boundary. This revision instead puts the behavior where it belongs, as two layers:

- **`compute-instance`** (existing module) gains a built-in, opt-in deletion hook. It stays single-instance — no `for_each`/`count` beyond the `enabled` kill-switch conditional it already has (ADR-0126).
- **`pigeon-cluster`** (new module) is where "many jobs → many instances" lives: it composes one `compute-instance` (with the deletion hook turned on) plus one dedicated IAM application per job, and is where each job's access — its keyring entries, its IAM permission grants — gets defined, isolated from every other job in the same cluster.

`pigeon-cluster` composing N `compute-instance` calls is a bigger version of the "modules don't compose modules, except..." exception ADR-0122 already carved out narrowly (`compute-instance` composing `block-volume`/`iam-policy`/`iam-api-key`, always 1:1). Worth stating plainly: this ADR is consciously stretching that exception further, from "one module wraps its own singleton dependencies" to "one module wraps N copies of another module," rather than quietly reusing the same justification at a different scale.

## Decision

### 1. `compute-instance`: a built-in deletion hook, still single-instance

New top-level input, additive default `false`:

```hcl
variable "self_delete_on_exit" {
  type        = bool
  description = "When true, the instance deletes itself (server, IP(s), block volume) once post_provision_commands finishes, success or failure. Requires iam_config to be set -- the module folds the permission needed to delete itself into the composed IAM policy automatically, on top of whatever project_permission_sets the caller already requested."
  default     = false
}
```

- Validation: `self_delete_on_exit == false || var.iam_config != null` — no credential to self-delete with, otherwise.
- When `true`, the module itself — not the caller — prepends `trap '<self-delete-script>' EXIT` as the first line of the generated post-provision script. This is the same fix an earlier draft of this ADR applied at the leaf level (the `set -e` gotcha below), now done once, correctly, inside the module instead of re-derived per leaf.
- The module writes its own internally-composed `iam_api_key` credentials onto the instance — same `/etc/environment` + `write_files` mechanism already used for `PIGEON_SECRET_*` (ADR-0104) — as `SCW_ACCESS_KEY`/`SCW_SECRET_KEY`/`SCW_DEFAULT_PROJECT_ID`/`SCW_DEFAULT_ZONE`, and conditionally installs the `scw` CLI in `runcmd` only when `self_delete_on_exit = true`.
- The module automatically merges an instance-management permission set into the internally-composed `iam_policy`'s `project_permission_sets` whenever `self_delete_on_exit = true`, so callers never need to know or request it themselves.
- **The `set -e` gotcha** (same spirit as ADR-0125's own documented gotchas): `post_provision_commands` are concatenated into one script under `set -euo pipefail`. A naive "run the job, then call the self-delete API" ordering means a *failing* job command aborts the script before the self-delete line ever runs — exactly backwards from "scales down once the job completes **or fails**." Prepending the `trap` (rather than appending a plain call) is what makes it fire on every exit path.
- **Confirmed since the first draft** (implemented in `templates/terraform/scaleway/compute-instance/instance.tf`/`iam.tf`):
  - The `scw` CLI incantation for tearing down the server plus its IP(s) plus its block volume in one shot: `scw instance server delete <id> zone=<zone> with-ip=true with-volumes=all force-shutdown=true` — real, documented `scw` syntax.
  - The IAM permission set: `InstancesFullAccess` is a real, documented Scaleway permission set, already in live use today for an unrelated purpose at `workloads/willowgraysen.com/terraform/state/iam/iam.tf` (the willowgraysen.com Terraform deployer's own policy). The module folds it into the composed `iam_policy` automatically whenever `self_delete_on_exit = true`.
- **Still unverified, needs hands-on confirmation before this ships for real** — exactly why this ADR is `Exploration` rather than `Accepted`:
  - The exact Scaleway instance metadata-service (`169.254.42.42`, already relied on by cloud-init itself as a datasource) JSON field path for the instance's own **zone** — `curl http://169.254.42.42/conf?format=json` is confirmed to return the server's own `id`, but the exact key for zone wasn't confirmed from docs alone. The implementation currently guesses `.location.zone_id`, with an inline comment flagging it as unverified — a wrong guess means `SELF_ZONE` is empty and the instance never actually self-deletes. First real validation step: boot one throwaway instance with `self_delete_on_exit = true`, curl the endpoint by hand, and correct the `jq` filter if needed.
- Versioning: purely additive (`self_delete_on_exit` defaults `false`, unchanged behavior for every existing caller) — `release:minor`, `v5.3.1` → `v5.4.0`.

### 2. New module: `templates/terraform/scaleway/pigeon-cluster/`

Takes a map of job definitions and composes one self-deleting `compute-instance` + one dedicated `iam-application` per job:

```hcl
variable "cluster_config" {
  type = object({
    name_prefix = string
    project_id  = string
    cockpit     = optional(object({ metrics_push_url = string, logs_push_url = string, token_secret = string }))
  })
  description = "Settings shared by every job instance in this cluster."
}

variable "jobs" {
  type = map(object({
    job_commands          = list(string)
    instance_type         = optional(string, "STARDUST1-S")
    block_volume_size     = optional(number)
    keyring               = optional(list(object({ kind = string, alias = string, /* ... */ })), [])
    extra_permission_sets = optional(list(string), [])
  }))
  description = "Jobs to run right now, keyed by job name. Each entry becomes one self-deleting compute-instance. Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality."
}
```

This is where each job's access is actually defined: every job gets its *own* IAM application and its own composed policy/key (`compute-instance`'s existing internal `iam_config` composition, ADR-0120/ADR-0122), scoped to exactly `each.value.extra_permission_sets` plus whatever `self_delete_on_exit` folds in automatically — nothing shared across jobs. Each job's `keyring` entries are likewise per-job, so one job's instance never sees another job's bucket/email credentials. Internally:

```hcl
module "job_application" {
  for_each = var.jobs
  source   = "https://pigeon.dev/modules/scaleway/iam-application/v0.1.0"
  name     = "${var.cluster_config.name_prefix}-${each.key}"
}

module "job" {
  for_each    = var.jobs
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v5.4.0"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = each.key

  self_delete_on_exit = true
  keyring             = each.value.keyring

  instance_config = {
    type                    = each.value.instance_type
    cockpit                 = var.cluster_config.cockpit
    block_volume = each.value.block_volume_size == null ? null : {
      size       = each.value.block_volume_size
      project_id = var.cluster_config.project_id
    }
    post_provision_commands = each.value.job_commands
  }

  iam_config = {
    application_id          = module.job_application[each.key].id
    project_ids              = [var.cluster_config.project_id]
    project_permission_sets  = each.value.extra_permission_sets
  }
}
```

New module, standard file set (`README.md`, `versions.tf`, `inputs.tf`, `outputs.tf`, `cluster.tf`), starts at `v0.1.0` — matching `iam-application`/`iam-api-key`'s precedent for brand-new modules. Per ADR-0079's own precedent, `CHANGELOG.md` is not hand-written here -- `template-release.yml` creates it (and compute-instance's new `[5.4.0]` entry) from this PR's title/body on merge. Both this module and `compute-instance`'s `self_delete_on_exit` are implemented as of this ADR revision -- see `templates/terraform/scaleway/pigeon-cluster/`.

A batch of 5 pending jobs means `var.jobs` has 5 entries and one `apply` provisions 5 instances; as each job's instance self-terminates, the fleet's *actual* size shrinks without another `apply` — but Terraform's own view of desired state doesn't shrink until someone removes that entry and re-applies (see Consequences). This stays **variable-driven and re-applied per batch**, not a live-polled queue.

## Consequences

- **Reconciliation gap, by design.** Once a job's instance self-deletes, `pigeon-cluster`'s `module.job["<key>"]` block and state entry are untouched — Terraform still believes it should exist. The *next* `apply` that still lists that job in `var.jobs` will recreate it, re-running the job from scratch. This ADR does not solve automatic pruning of finished entries; today that's the same human/CI step the `enabled` kill switch already requires (ADR-0126), just applied to cluster membership instead of a boolean.
- **Per-job IAM isolation is now a first-class property**, not an afterthought: because `pigeon-cluster` gives each job its own IAM application/policy/key and its own keyring entries, a compromised or misbehaving job instance's blast radius is bounded to that job's own grants plus the auto-added self-delete permission — never another job's bucket or email credentials.
- **`pigeon-cluster` stretches the ADR-0122 composition exception further** than its original 1:1 case (one module, one set of singleton dependencies) to "one module, N copies of another module." Worth revisiting if a third shape of this exception shows up elsewhere in the repo, to decide whether it's still "narrow."
- **Observability survives instance death fine.** Alloy already streams logs/metrics to Cockpit in near-real-time (ADR-0102/ADR-0103/ADR-0073's JSONL log), so a self-terminated instance's job history isn't lost — it just isn't *queryable through Terraform state* after the fact.
- **Each self-deleting instance carries a delete-capable IAM credential** (`InstancesFullAccess`, project-scoped), a bigger blast radius per key than today's (today's keys don't need instance-management permissions at all). `InstancesFullAccess` grants every instance action, not just delete — worth a second look later for a narrower permission set scoped to just "delete this one instance," if Scaleway's permission-set catalog ever offers one.

## Out of scope

- Automatic detection/pruning of completed jobs from `var.jobs` (e.g. something reading the ADR-0073 JSONL log or job metrics to drive cluster membership) — future work, not this ADR.
- The exact metadata-service JSON field path for the instance's own zone — flagged above as the one remaining unconfirmed piece; verify hands-on against a real instance before relying on it.
- Any live/dynamic job queue or poller — explicitly rejected in favor of the variable-driven-batch approach.
- Building the design around Scaleway Autoscaling Groups — considered and rejected (see Context).
- Migrating existing `workloads/willowgraysen.com/terraform/pigeon-cli/job/<job-name>/` leaves onto `pigeon-cluster` — not done here; those leaves can keep calling `compute-instance` directly, `pigeon-cluster` is for new multi-job fleets going forward.
- A promotion of this ADR's `Exploration` status to `Accepted` — only worth doing once the unconfirmed pieces above are verified against a real instance.
