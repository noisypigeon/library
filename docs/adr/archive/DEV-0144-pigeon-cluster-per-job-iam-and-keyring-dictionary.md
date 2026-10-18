# DEV-0144: pigeon-cluster per-job policy/key, dictionary keyring, shared cluster defaults

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-07.
- **Status**: Accepted.

## Context

`templates/terraform/scaleway/pigeon-cluster` (v0.1.0, ADR-0138) gives each job its own `iam-application`, but that's as far as per-job IAM isolation goes today. The actual policy and API key a job's instance runs with are composed two layers down, *inside* `compute-instance` (ADR-0122), purely to power that instance's `self_delete_on_exit` call — nothing about that internally-composed key is visible to `pigeon-cluster` itself. So every `keyring` entry's `access_key_id`/`secret_key` has to be hand-supplied by the caller. The commented-out sketch at `workloads/willowgraysen.com/terraform/pigeon-cli/job/consolidate-segment-1/{jobs.tf,iam.tf}` shows exactly what this costs in practice: it stands up its own separate `iam_policy`/`iam_api_key` pair (reusing ADR-0119's old *shared* `pigeon-cli` application — the very pattern ADR-0138 was meant to move away from), then pastes that one key's `access_key`/`secret_key` into all six of its keyring entries by hand. Nothing ties a `job_commands` string's hardcoded alias (`'fastmail:'`) to the keyring entry it means, either — that link is pure caller convention, unchecked by Terraform anywhere in the chain.

This ADR closes both gaps and adds a third piece: a cluster-wide default bucket set so common buckets (e.g. a shared `reports` destination) don't need to be re-declared per job.

### The circular-reference constraint

A job's own `compute-instance` call cannot be the source of its own keyring defaults — `module.job[key]`'s `keyring` input can't depend on `module.job[key]`'s own output, that's a cycle regardless of whether `compute-instance` exposes `access_key_id`/`secret_key` as outputs (it already does, via `outputs.tf`). So the key used to default a job's keyring entries has to be minted by `pigeon-cluster` itself, in a module call that exists *before* the per-job `compute-instance` call is built — necessarily a second, separate key from whatever `compute-instance` composes internally for self-delete.

That separation is used here as a deliberate opportunity, not just a workaround: the self-delete key narrows to instance-management-only permissions, while the new cluster-level key carries the job's real work permissions. This directly addresses the blast-radius concern ADR-0138's own Consequences section flagged ("worth a second look later for a narrower permission set scoped to just delete").

## Decision

### 1. `pigeon-cluster` composes its own `iam-policy` + `iam-api-key` per job

In addition to the existing per-job `iam-application`:

```hcl
locals {
  job_permission_sets = {
    for k, v in var.jobs : k => distinct(concat(var.cluster_config.shared_permission_sets, v.extra_permission_sets))
  }
}

module "job_policy" {
  for_each = { for k, v in local.job_permission_sets : k => v if length(v) > 0 }
  source   = "https://pigeon.dev/modules/scaleway/iam-policy/v4.0.0"
  name     = "${var.cluster_config.name_prefix}-${each.key}-iam-policy"

  application_id          = module.job_application[each.key].id
  project_ids              = [var.cluster_config.project_id]
  project_permission_sets  = each.value
}

module "job_api_key" {
  for_each = var.jobs
  source   = "https://pigeon.dev/modules/scaleway/iam-api-key/v0.2.0"

  application_id     = module.job_application[each.key].id
  description         = "${var.cluster_config.name_prefix}-${each.key} API key"
  default_project_id  = var.cluster_config.project_id
}
```

`iam-policy` validates that a policy has at least one non-empty permission grant, so `job_policy`'s `for_each` is filtered to jobs with a non-empty merged permission set — a job with no `extra_permission_sets` and no `shared_permission_sets` simply gets no policy. `iam-api-key` has no such requirement, so every job gets a key unconditionally (used for keyring defaults even when it ends up with zero actual permissions — matching the module's own README precedent of a job with an empty `keyring`/`extra_permission_sets` being a legitimate no-op). `job_api_key` also sets `default_project_id`, which `compute-instance`'s own internal `iam_api_key` composition has never set despite having `project_ids` available — a pre-existing gap, left as-is there (see Out of scope).

### 2. `keyring` becomes a dictionary, keyed by alias

Both `cluster_config.shared_keyring` and each job's `keyring` change from `list(object({ kind, alias, ... }))` to `map(object({ kind, ... }))` — the map key *is* the alias now, so the `alias` field is dropped from the input schema entirely (no more typing it twice). `access_key_id`/`secret_key` stay optional on `kind = "bucket"` entries, but now default to the job's own `job_api_key` when omitted:

```hcl
locals {
  effective_keyring = {
    for job_key, job in var.jobs : job_key => {
      for alias, entry in merge(var.cluster_config.shared_keyring, job.keyring) : alias => merge(entry, {
        alias = alias
        access_key_id = entry.kind != "bucket" ? entry.access_key_id : coalesce(entry.access_key_id, module.job_api_key[job_key].access_key)
        secret_key    = entry.kind != "bucket" ? entry.secret_key : coalesce(entry.secret_key, module.job_api_key[job_key].secret_key)
      })
    }
  }
}
```

`cluster_config.shared_keyring` entries are merged in first, so a job-specific entry with the same alias overrides the shared one outright (`merge()`'s normal last-wins semantics). An entry can still override its own credentials explicitly — set `access_key_id`/`secret_key` on the entry itself (e.g. to reach a bucket under a different, already-existing auth stack) and `coalesce` picks that over the job's default key. `compute-instance`'s own `keyring` input stays a list unchanged; the boundary conversion is just `values(local.effective_keyring[each.key])`.

### 3. `job_commands` can reference the keyring by alias

`post_provision_commands` is now built with `templatestring`, passing each job's merged keyring map in as the single template variable:

```hcl
post_provision_commands = [
  for cmd in each.value.job_commands : templatestring(cmd, { keyring = local.effective_keyring[each.key] })
]
```

A caller writes `"mkdir /mnt/data/a && mise run pigeon-release job run import --source '${keyring.fastmail.alias}:' ..."` instead of hardcoding the literal string `'fastmail:'`. If `fastmail` isn't a key in that job's merged keyring, `terraform plan` fails outright — turning yesterday's silent, convention-only link between a command string and a keyring entry into a real, checked one. **Known limitation**: `templatestring`'s `${keyring.foo.alias}` dot-syntax only parses for hyphen-free map keys (Terraform's attribute-access grammar); an alias with a hyphen needs bracket syntax instead — `${keyring["my-alias"].alias}`. Not a blocker (every alias in this module's own examples is hyphen-free), just worth knowing.

### 4. `cluster_config` gains `shared_keyring` and `shared_permission_sets`

Both default to empty (`{}` / `[]`) — fully additive for a cluster with no shared defaults. A cluster that wants every job to reach a common `reports` bucket sets `cluster_config.shared_keyring = { reports = { kind = "bucket", ... } }` once, instead of repeating it in every job's own `keyring`.

### 5. The self-delete key narrows

`pigeon-cluster`'s own `iam_config` fed to `module.job` (compute-instance) changes `project_permission_sets` from `each.value.extra_permission_sets` to `[]`. `compute-instance`'s internally-composed key — used solely for its `self_delete_on_exit` trap — now carries *only* the `InstancesFullAccess` it auto-folds in for that purpose, nothing else. The job's real work permissions (object storage, email, etc.) now live entirely on the new cluster-level `job_policy`/`job_api_key`, which is also what the keyring defaults to. Two distinct keys per job, each scoped to exactly what it's for.

**No changes to `compute-instance` or any `iam-*` module** — this is entirely a composition change inside `pigeon-cluster` itself.

### Versioning

`v0.1.0` → `v0.2.0`, `release:minor`. This is a breaking interface change (keyring list → map; new `shared_keyring`/`shared_permission_sets`; narrowed self-delete-key permissions), but follows this repo's established pre-1.0 precedent — `iam-application`/`iam-api-key` have both absorbed interface changes within the `0.x` minor component, with no major-version jump reserved specifically for crossing `0.x` boundaries.

This ADR revises, rather than supersedes outright, ADR-0138's design — specifically the keyring shape and where policy/key composition lives. ADR-0138's one still-open question (the unverified `.location.zone_id` metadata-service field path for self-delete) is untouched by this change and stays `Exploration` there until verified hands-on against a real instance.

## Consequences

- **Per-job IAM isolation now extends to the actual credential, not just the application.** Every job's keyring defaults to a key scoped to exactly that job's own `extra_permission_sets` + the cluster's `shared_permission_sets` — never another job's, and never the broader shared `pigeon-cli` application ADR-0119 introduced.
- **Two API keys per job instead of one.** The self-delete key (inside `compute-instance`, `InstancesFullAccess` only) and the work/keyring key (inside `pigeon-cluster`, the job's real grants) are now separate credentials with separate, narrower scopes each — a net reduction in per-key blast radius, at the cost of one extra `scaleway_iam_api_key` resource per job.
- **`job_commands` strings gain a real, checked link to `keyring`** via `templatestring`, closing the silent-convention gap the original ADR-0138 design left open. The tradeoff is the hyphen/bracket-syntax caveat above.
- **A cluster-wide default (`shared_keyring`/`shared_permission_sets`) is new surface area to keep consistent.** A job-specific `keyring` entry silently overriding a `shared_keyring` entry of the same alias is intentional (the whole point of allowing per-job override), but it's also the one place a typo'd alias could quietly shadow a shared default instead of erroring — there's no `validation` block warning on same-alias shadowing.

## Out of scope

- Fixing `compute-instance`'s own internal `iam-api-key` composition to set `default_project_id` — a pre-existing gap, orthogonal to this ADR, left for its own future ADR if it ever matters (today that key is self-delete-only, which doesn't touch Object Storage).
- Migrating `workloads/willowgraysen.com/terraform/pigeon-cli/job/consolidate-segment-1` onto this interface for real (uncommenting `jobs.tf` and running `terragrunt apply`) — its commented-out sketch is updated in the same change to match this new interface, but stays commented out; applying it is left for the user to do themselves.
- A `validation` block (or any other mechanism) detecting a job-specific `keyring` alias that shadows a `shared_keyring` entry — flagged above as a real gap, not solved here.
- Promoting ADR-0138 itself from `Exploration` to `Accepted` — still gated on verifying the self-delete zone-field-path by hand, unrelated to this change.
