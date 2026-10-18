# DEV-0101: optional keyring bucket encryption key + environment_variables on scaleway/compute-instance

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

This continues ADR-0100 (merged as PR #126, `scaleway/compute-instance` now
at `v2.1.0`), which added `keyring_entries` to render `pigeon-cli`'s
`/root/.config/pigeon/keyring.toml`. Two follow-ups.

**`encryption_key_alias` is a de-facto required field for `kind = "bucket"`
entries, despite its type already saying otherwise.** `keyring_entries`'
type declares `encryption_key_alias = optional(string)`, but `instance.tf`'s
template unconditionally rendered `encryption_key_alias =
"${entry.encryption_key_alias}"` for every bucket entry. Terraform/OpenTofu
errors on string-interpolating `null` ("Invalid template interpolation
value"), so omitting it on a real bucket entry (e.g. a plain backup bucket
with no associated encryption key) broke the render. Verified live: a
scratch `tofu plan` with a bucket entry omitting `encryption_key_alias`
errored before this ADR's fix and renders cleanly (field simply absent)
after it.

**A generic way to set key/value environment variables on the instance, for
secrets.** `pigeon-cli` reads keyring secrets from environment variables
named `PIGEON_SECRET_<ALIAS>` — notably, `keyring.toml`'s `encryption-key`
entries only ever carry `alias`/`created_at`, never the actual key material;
that material is meant to be injected this way instead. This module
shouldn't hardcode that naming convention, though — it's `pigeon-cli`'s
convention to interpret, not this module's business — so the ask is a fully
generic `environment_variables` input that the caller populates however it
likes (e.g. `{"PIGEON_SECRET_PRIMARY" = module.iam.secret_key}"}`), usable
with **any profile** (not gated to `"pigeon-cli"` the way `buckets`/
`keyring_entries` are — confirmed with the user, since there's no reason a
`docker`-profile instance couldn't also want env vars set).

Where to deliver these vars was investigated before picking a mechanism,
since it determines whether the vars actually reach the process that needs
them:

- `pigeon.sh` (the `profile = "pigeon-cli"` bootstrap gist, run once via
  `runcmd` at first boot per ADR-0089/0090) is confirmed (fetched directly)
  to be a one-shot installer with no env-var dependency of its own — it
  doesn't need these vars itself.
- No ADR or code in this repo describes any cron/systemd/recurring
  invocation of `pigeon-cli` — jobs are run manually, later, over SSH
  (matches the `analyze-job-run` skill's framing: a job runs, then
  `pigeon.jsonl` gets reviewed afterward). So the vars mainly need to be
  present in a **later, manual SSH session**, not necessarily at the exact
  moment `runcmd` executes.
- This repo has never marked a secret-*consuming* input `sensitive = true`
  — only `iam-policy`'s secret-*producing* outputs (`access_key`/
  `secret_key`) are — even though `buckets`/`keyring_entries` already carry
  secret-shaped fields (`bucket_secret_key`, `access_key_id`).
  `environment_variables` sets a new precedent here deliberately, since its
  whole purpose is carrying literal secret material.

Rather than build only for one of the two invocation models above, this ADR
covers both cheaply: write the vars to a script that login shells
auto-source, *and* explicitly source that same script early in `runcmd` —
mirroring ADR-0090's own fix for this exact class of problem
(`export HOME=/root` as `runcmd`'s first line, so every later line in the
same cloud-init shell session inherits it).

## Decision

### `keyring_entries`: optional bucket encryption key

In `instance.tf`, the `encryption_key_alias` line for `kind = "bucket"`
entries is now guarded, the same way `max_imap_connections` already is for
`email` entries:

```yaml
          %{~if entry.kind == "bucket"~}
          endpoint = "${entry.endpoint}"
          bucket = "${entry.bucket}"
          access_key_id = "${entry.access_key_id}"
          %{~if entry.encryption_key_alias != null~}
          encryption_key_alias = "${entry.encryption_key_alias}"
          %{~endif~}
          %{~endif~}
```

No `inputs.tf` change — the type already declared this field
`optional(string)`; only the render was out of sync with it.

### New `environment_variables` variable

`inputs.tf`:

```hcl
variable "environment_variables" {
  type        = map(string)
  description = "Key/value environment variables exported on the instance for any profile (e.g. pigeon-cli secrets, by convention named PIGEON_SECRET_<ALIAS> but not enforced by this module)"
  default     = {}
  sensitive   = true

  validation {
    condition     = alltrue([for k in keys(var.environment_variables) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k))])
    error_message = "environment_variables keys must be valid shell variable names."
  }
}
```

No profile-gate validation, unlike `buckets`/`keyring_entries` — usable with
any profile.

### Write + source the env file, for any profile

`instance.tf`'s `write_files:` key previously only rendered at all when
`profile == "pigeon-cli"` — the entire key was wrapped in that `%{if}`.
Restructured so `write_files:` always renders, with the new entry
unconditional and the two existing `pigeon-cli`-only entries nested under
their own `%{if}` instead:

```yaml
    write_files:
      - path: /etc/profile.d/pigeon-env.sh
        permissions: '0600'
        defer: true
        content: |
          %{~for key, value in var.environment_variables~}
          export ${key}="${value}"
          %{~endfor~}
    %{~if var.profile == "pigeon-cli"~}
      - path: /root/.config/rclone/rclone.conf
        ...
      - path: /root/.config/pigeon/keyring.toml
        ...
    %{~endif~}

    runcmd:
      - export HOME=/root
      - . /etc/profile.d/pigeon-env.sh
    %{~if length(var.additional_volume_ids) > 0~}
      ...
```

An empty `environment_variables` renders an empty, harmless script — same
"empty list renders empty content" precedent as `buckets`. Sourcing it
right after `export HOME=/root` means every later `runcmd` line — including
the `docker` profile's install block and the `pigeon-cli` bootstrap line —
inherits these exports within the same cloud-init shell session; placing
the file under `/etc/profile.d/` also auto-sources it for any later
interactive login shell (SSH), covering manual `pigeon-cli` invocations
after boot.

Verified live via a scratch `tofu plan` rendering `local.cloud_init` with
`environment_variables` set, once under `profile = "pigeon-cli"` (alongside
keyring/bucket entries) and once under `profile = "docker"` — in both
cases, `/etc/profile.d/pigeon-env.sh` renders correctly and `runcmd` sources
it regardless of profile, confirming the any-profile scope.

### Documentation & versioning

- `README.md` regenerates automatically via `module-docs.yml` on merge.
- `CHANGELOG.md` appended automatically by `module-release.yml` on merge
  with a `release:minor` label — both changes are backward compatible
  (nothing that worked before stops working; the encryption-key fix only
  makes a previously-erroring case now succeed).
- Tag: `modules/scaleway/compute-instance/v2.2.0`.

## Consequences

- `release:minor` for `scaleway/compute-instance`.
- `environment_variables` is the first secret-*consuming* input in this
  repo marked `sensitive = true` — a deliberate new precedent, not a
  continuation of the existing (arguably inconsistent) convention where
  `buckets`/`keyring_entries` carry secret-shaped fields without it.
- `environment_variables` has no profile gate, unlike `buckets`/
  `keyring_entries` — any profile (including `docker`) can set env vars on
  the instance.
- `scaleway/iam-policy` and other sibling modules are untouched.

## Out of scope

- Retroactively marking `buckets`'/`keyring_entries`' secret-shaped fields
  `sensitive = true` — a real gap, but independent of this ADR's actual
  asks.
- Enforcing or validating the `PIGEON_SECRET_<ALIAS>` naming convention —
  that's `pigeon-cli`'s convention to interpret, not this module's to
  validate; `environment_variables` stays a fully generic key/value map.
- Any change to `workloads/pigeon-cli/terraform/sort/macbook-scratch/` —
  still has unrelated in-progress local edits from before this ADR,
  untouched here.
- Referential-integrity validation between a bucket's `encryption_key_alias`
  and an actual `encryption-key` entry — already out of scope per
  ADR-0100, unchanged by making the field optional.
