# DEV-0118: Simplify scaleway/compute-instance's provisioning interface

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

`scaleway/compute-instance` (ADR-0079, extended by ADR-0081/0082/0083/0087/0088/0089/0099/0100/0101/0102/0104) has accumulated a `profile` variable (`"docker"` | `"pigeon-cli"`) and four separate, overlapping configuration inputs — `buckets`, `keyring_entries`, `environment_variables`, `cockpit` — all really serving one `pigeon-cli` provisioning path.

A full census of every real consumer (`workloads/**/*.tf`, plus `git log -S` across this repo's entire history) found **exactly one live caller**: `workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/deduplication/compute.tf`. It:

- always passes `profile = "pigeon-cli"` — `profile = "docker"` has never been instantiated anywhere, live or in history (the sibling `rclone` profile was already folded into `pigeon-cli` by ADR-0099, leaving `docker` equally vestigial now).
- passes a `buckets` entry and a `keyring_entries` entry per bucket, with identical `endpoint`/`bucket`/`access_key_id`, because `keyring_entries`'s `bucket` kind never carried a secret while `buckets` always did.
- passes `environment_variables = { PIGEON_SECRET_SOURCE = module.iam.secret_key, PIGEON_SECRET_DESTINATION = module.iam.secret_key }` — the *same* secret already present in the matching `buckets`/`keyring_entries` entry, re-supplied by hand under the `PIGEON_SECRET_<ALIAS>` convention the module's own docs already describe as a suggested, caller-maintained naming scheme, not an enforced one.

So today the one real caller has to keep three separate lists' aliases in sync by hand to describe what is conceptually one secret-bearing bucket, and the module carries a dead `docker` branch through every variable's validation and every cloud-init conditional. This ADR collapses the duplication, removes the unused branch, and groups the remaining inputs under two small config objects instead of a flat, growing top-level variable list.

## Decision

### Drop the `docker` profile and the `profile` variable entirely

`pigeon-cli` behavior (rclone/neovim install, the `pigeon-cli` bootstrap, keyring/rclone config rendering, Cockpit/Alloy wiring) becomes the module's unconditional, only behavior. The `profile` variable, its validation, and every `%{~if var.profile == "docker"~}`/`%{~if var.profile == "pigeon-cli"~}` branch in `instance.tf` are deleted. Every variable that was previously gated on `profile == "pigeon-cli"` (`buckets`, `keyring_entries`, `environment_variables`, `cockpit`) loses that gate — it's always active now.

### Rename `namespace`/`name` to `name_prefix`/`name_suffix`

Same values, same `"${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"` naming scheme — just names that read correctly at every call site (`name_prefix = "job-${local.namespace}"` reads clearer than the former `namespace = "job-${local.namespace}"`, which paired a generic variable name with an already-namespace-shaped value).

### Group SSH access under `user_config`, singularize `ssh_key`

```hcl
variable "user_config" {
  type = object({
    ssh_key = optional(string)
  })
  description = "Per-instance user/access configuration"
  default     = {}
}
```

`ssh_keys` (`list(string)`) becomes `user_config.ssh_key` (a single `string`) — the only real consumer already passes a one-element list; nothing today needs more than one instance-specific key. `scaleway_instance_server.tags`'s `AUTHORIZED_KEY=` rendering collapses from a `for` loop to a single conditional tag.

### Group instance-level config under `instance_config`: move `image`, `type`, `cockpit` into it

```hcl
variable "instance_config" {
  type = object({
    image = optional(string, "ubuntu_jammy")
    type  = optional(string, "STARDUST1-S")
    cockpit = optional(object({
      metrics_push_url = string
      logs_push_url    = string
      token_secret     = string
      scrape_port      = optional(number, 9091)
    }))
  })
  description = "Instance-level configuration: image, commercial type, and Cockpit/Alloy wiring"
  default     = {}
  sensitive   = true
}
```

`image` and `type` move off the top level into `instance_config`, keeping their previous defaults/behavior except `image` is now optional, defaulting to `"ubuntu_jammy"` — the image every real caller already passes explicitly today. `cockpit` keeps its ADR-0102 shape, now addressed as `instance_config.cockpit`, leaving room for future instance-level service config to land in the same object instead of growing the top-level variable list again. Bundling `image`/`type` into the same object as `cockpit` means `instance_config` as a whole must be `sensitive = true` (for `cockpit.token_secret`'s sake), so `image`/`type` changes also stop showing in plan diffs — a minor loss of visibility accepted in exchange for not splitting instance-level config across two top-level objects.

### Collapse `buckets` + `keyring_entries` + `environment_variables` into one `keyring` list

```hcl
variable "keyring" {
  type = list(object({
    kind  = string
    alias = string

    # kind = "email"
    email                = optional(string)
    provider             = optional(string) # email provider name, OR (kind = "bucket") rclone's s3 `provider`
    host                 = optional(string)
    port                 = optional(number)
    max_imap_connections = optional(number)

    # kind = "bucket" -- also feeds rclone.conf
    endpoint             = optional(string)
    bucket               = optional(string)
    access_key_id        = optional(string)
    secret_key           = optional(string) # never rendered into keyring.toml
    encryption_key_alias = optional(string)

    # kind = "encryption-key"
    created_at = optional(string)
  }))
  description = "pigeon-cli keyring.toml entries. kind = \"bucket\" entries also generate an rclone.conf remote; any entry with secret_key set also exports PIGEON_SECRET_<ALIAS> on the instance."
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.keyring : contains(["email", "bucket", "encryption-key"], e.kind)])
    error_message = "keyring.kind must be one of \"email\", \"bucket\", \"encryption-key\"."
  }

  validation {
    condition     = alltrue([for e in var.keyring : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", e.alias))])
    error_message = "keyring aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.keyring) == length(distinct([for e in var.keyring : e.alias]))
    error_message = "keyring aliases must be unique."
  }
}
```

- **`buckets` is gone.** Any `keyring` entry with `kind = "bucket"` now also renders an rclone.conf remote pair (alias → s3), using the same fields the entry already carries for `keyring.toml` (`alias`, `bucket`, `endpoint`, `access_key_id`) plus the two new ones (`secret_key`, `provider`) that only rclone needs.
- **`environment_variables` is gone.** Any `keyring` entry (of any kind) with `secret_key` set exports `PIGEON_SECRET_<ALIAS uppercased, hyphens→underscores>` into both `/etc/profile.d/pigeon-env.sh` and `/etc/environment` (ADR-0101/0104's existing dual-write), replacing the free-form map. The `PIGEON_SECRET_<ALIAS>` convention, previously just a suggestion in the old variable's description, is now the module's own generated name — it can no longer drift from the keyring alias it belongs to.
- **`secret_key` is deliberately never written into `/root/.config/pigeon/keyring.toml`.** Preserves the existing property (true since ADR-0100) that the keyring file itself never carries a plaintext secret — only `alias`/`access_key_id`/references. The secret only ever reaches the instance via `rclone.conf` (`kind = "bucket"` only) and the environment-variable export.

### Rendering changes in `instance.tf`

- `write_files` for `/root/.config/rclone/rclone.conf`: loop `var.keyring`, filter `entry.kind == "bucket"`, emit the same `[alias] type=alias remote=...` / `[bucket] type=s3 provider=... access_key_id=... secret_access_key=... endpoint=...` pair the old `buckets` loop emitted.
- `write_files` for `/root/.config/pigeon/keyring.toml`: same per-kind rendering as today's `keyring_entries` loop (unchanged field names for `email`/`encryption-key`; `bucket` kind unchanged except `secret_key` is never emitted here).
- `write_files` for `/etc/profile.d/pigeon-env.sh` / `/etc/environment`: replace the `for key, value in var.environment_variables` loop with a loop over `var.keyring` entries where `secret_key != null`, exporting `PIGEON_SECRET_${upper(replace(entry.alias, "-", "_"))}`.
- `packages`/`runcmd`: drop every `%{~if var.profile == "docker"~}` block outright (Docker CE apt-repo setup + install); drop every `%{~if var.profile == "pigeon-cli"~}` guard around what is now unconditional (rclone/neovim package install, keyring/rclone config write, the `pigeon.sh` bootstrap curl).
- `scaleway_instance_server.server`: `image = var.instance_config.image`, `type = var.instance_config.type` (was `var.image`/`var.type`).

## Consequences

- `release:major` for `templates/terraform/scaleway/compute-instance` (v3.0.0 → v4.0.0) — breaking rename/removal of `namespace`, `name`, `image`, `type`, `profile`, `ssh_keys`, `buckets`, `keyring_entries`, `environment_variables`, `cockpit`.
- `image`/`type` move into `instance_config`, which must be `sensitive = true` for `cockpit.token_secret`'s sake — so `image`/`type` changes also stop showing in plan diffs, a minor loss of visibility traded for not splitting instance-level config across two top-level objects.
- The module's only secret-bearing variables (`keyring`, `instance_config`) are both `sensitive = true`; `buckets` previously was not, despite carrying `bucket_secret_key` in plaintext through plan output — this closes that gap as a side effect.
- The sole real consumer (`workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/deduplication/compute.tf`) drops from 4 overlapping config inputs (`profile`, `buckets`, `keyring_entries`, `environment_variables`) plus top-level `image`/`type`/`cockpit`/`ssh_keys` down to 2 config objects (`user_config`, `instance_config`) + 1 unified `keyring` list, with its two duplicated bucket/keyring/env-var entries each collapsing into one `keyring` entry.
- Every instance built from this module gets replaced on its next `terragrunt apply` after the pin bumps (same `lifecycle.replace_triggered_by` on cloud-init content as any prior cloud-init change, per ADR-0104's precedent) — apply deliberately, not as a surprise.

## Out of scope

- A generic, non-secret, non-keyring-tied environment-variable passthrough. The old `environment_variables` was documented as usable for any key/value pair, not just keyring-derived secrets; collapsing it into `keyring.secret_key` only covers the secret-aliased-to-a-keyring-entry case the one real caller actually uses. If a future consumer needs an arbitrary env var unrelated to any keyring entry, this ADR doesn't provide a mechanism for it. ([#158](https://github.com/noisypigeon/noisypigeon/issues/158))
- Per-`kind` required-field validation on `keyring` (e.g. requiring `bucket`/`endpoint`/`access_key_id` when `kind = "bucket"`). Matches today's module, which never validated this either — malformed entries render incomplete config rather than failing `plan`.
- Supporting more than one SSH key per instance (`user_config.ssh_key` is deliberately singular, not a list) — a permanent design choice for this ADR, not deferred.
