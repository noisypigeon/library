# DEV-0100: add keyring.toml templating to scaleway/compute-instance

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`pigeon-cli` needs a keyring manifest at `/root/.config/pigeon/keyring.toml`
on any instance running `modules/scaleway/compute-instance`'s `"pigeon-cli"`
profile, listing `email`, `bucket`, and `encryption-key` entries — e.g.:

```toml
[[entries]]
kind = "email"
alias = "willow"
email = "willow@example.com"
provider = "gmail"
host = "imap.gmail.com"
port = 993
max_imap_connections = 2

[[entries]]
kind = "bucket"
alias = "backup"
endpoint = "https://nyc3.digitaloceanspaces.com"
bucket = "my-bucket"
access_key_id = "AKID1234567890"
encryption_key_alias = "primary"

[[entries]]
kind = "encryption-key"
alias = "primary"
created_at = "2026-09-24T00:00:00Z"
```

`compute-instance` already solves the identical problem for `rclone.conf`
(ADR-0081): a `buckets` variable — `list(object({bucket_name, bucket_alias,
bucket_endpoint, bucket_access_key, bucket_secret_key, bucket_provider}))`
— rendered into a `write_files` entry inside the module's inline cloud-init
heredoc (`instance.tf`), via a `%{~for bucket in var.buckets~}` loop, gated
behind `%{~if var.profile == "pigeon-cli"~}`. The ask is to extend that same
mechanism to a second file.

**Keyring entries aren't uniform, unlike buckets.** `email`/`bucket`/
`encryption-key` kinds carry different fields, so a single `list(object({}))`
with one fixed schema (the `buckets` approach) doesn't fit directly. Two
shapes were considered: (a) one list variable with a `kind` discriminator and
per-kind-optional attributes (Terraform's `optional()` object-type
modifier), rendered by one `%{~for~}` loop with internal `%{~if entry.kind ==
"..."~}` branches; or (b) three separate, strictly-typed list variables (one
per kind), rendered as three independent loops. (a) was chosen: it mirrors
`buckets`' one-list/one-loop shape exactly, needs only one new variable
instead of three, and preserves the caller's authored entry order in the
rendered file — which (b) would lose by grouping output per kind.

**Secrets stay out of this schema**, the same boundary `buckets`/
`rclone.conf` already draws: `bucket_access_key`/`bucket_secret_key` are
resolved by the caller (typically via `scaleway/iam-policy`) and passed in
already-populated; `compute-instance` never creates or stores credentials
itself. `keyring_entries` follows suit — e.g. no IMAP password field, no
bucket secret key field; it renders metadata the caller already holds.

`workloads/pigeon-cli/terraform/sort/macbook-scratch/compute.tf` — the one
real consumer of `buckets` today — is currently commented out in the
**uncommitted** working tree, mid an unrelated rename
(`local.deduplication_*` → `local.sort_*`, inconsistently applied so far).
That's in-progress work independent of this ADR; this change does not touch
or wire into that leaf.

## Decision

### `scaleway/compute-instance`: new `keyring_entries` variable

`inputs.tf` gains, reusing `buckets`' validation style (alias regex, alias
uniqueness, profile-gate) plus a `kind` enum check:

```hcl
variable "keyring_entries" {
  type = list(object({
    kind  = string
    alias = string

    # kind = "email"
    email                = optional(string)
    provider             = optional(string)
    host                 = optional(string)
    port                 = optional(number)
    max_imap_connections = optional(number)

    # kind = "bucket"
    endpoint             = optional(string)
    bucket               = optional(string)
    access_key_id        = optional(string)
    encryption_key_alias = optional(string)

    # kind = "encryption-key"
    created_at = optional(string)
  }))
  description = "pigeon-cli keyring.toml entries; only used when profile = \"pigeon-cli\""
  default     = []

  validation {
    condition     = alltrue([for e in var.keyring_entries : contains(["email", "bucket", "encryption-key"], e.kind)])
    error_message = "keyring_entries.kind must be one of \"email\", \"bucket\", \"encryption-key\"."
  }

  validation {
    condition     = alltrue([for e in var.keyring_entries : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", e.alias))])
    error_message = "keyring_entries aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.keyring_entries) == length(distinct([for e in var.keyring_entries : e.alias]))
    error_message = "keyring_entries aliases must be unique."
  }

  validation {
    condition     = var.profile == "pigeon-cli" || length(var.keyring_entries) == 0
    error_message = "keyring_entries is only used when profile = \"pigeon-cli\"."
  }
}
```

No cross-entry referential check — e.g. confirming a `bucket` entry's
`encryption_key_alias` actually resolves to an `encryption-key` entry
elsewhere in the same list. `buckets` doesn't validate semantics beyond
shape and uniqueness either, and `pigeon-cli` itself is better positioned to
fail loudly on a dangling alias at startup than Terraform is at plan time.

### `scaleway/compute-instance`: render `keyring.toml` in cloud-init

`instance.tf` gains a second `write_files` entry, alongside `rclone.conf`,
inside the existing `%{~if var.profile == "pigeon-cli"~}` block:

```yaml
      - path: /root/.config/pigeon/keyring.toml
        permissions: '0600'
        defer: true
        content: |
          %{~for entry in var.keyring_entries~}
          [[entries]]
          kind = "${entry.kind}"
          alias = "${entry.alias}"
          %{~if entry.kind == "email"~}
          email = "${entry.email}"
          provider = "${entry.provider}"
          host = "${entry.host}"
          port = ${entry.port}
          %{~if entry.max_imap_connections != null~}
          max_imap_connections = ${entry.max_imap_connections}
          %{~endif~}
          %{~endif~}
          %{~if entry.kind == "bucket"~}
          endpoint = "${entry.endpoint}"
          bucket = "${entry.bucket}"
          access_key_id = "${entry.access_key_id}"
          encryption_key_alias = "${entry.encryption_key_alias}"
          %{~endif~}
          %{~if entry.kind == "encryption-key"~}
          created_at = "${entry.created_at}"
          %{~endif~}

          %{~endfor~}
```

Same `permissions: '0600'` / `defer: true` shape as `rclone.conf` — the file
carries access-key IDs and host/endpoint details. The blank line after each
kind's fields keeps successive `[[entries]]` tables visually separated,
matching the hand-authored template this ADR is based on. Like
`rclone.conf`, the loop renders harmlessly to an empty `content:` block when
`keyring_entries` is `[]`.

Verified live: rendering `local.cloud_init` with one entry of each kind
(email ×2, bucket, encryption-key) via a scratch `tofu plan` produces TOML
byte-for-byte matching the example above.

### Documentation & versioning

- `modules/scaleway/compute-instance/README.md` regenerates automatically
  via `module-docs.yml` on merge — no manual edit.
- `modules/scaleway/compute-instance/CHANGELOG.md` gets appended
  automatically by `module-release.yml` on merge with a `release:minor`
  label (per the `release-pr` skill) — no manual edit.
- Tag: `modules/scaleway/compute-instance/v2.1.0`.

## Consequences

- `release:minor` for `scaleway/compute-instance` — `keyring_entries` is a
  new, backwards-compatible, optional (`default = []`) input.
- Callers can now get both `rclone.conf` and `keyring.toml` provisioned on a
  `"pigeon-cli"`-profile instance from a single `compute-instance` call.
- `scaleway/iam-policy`, `scaleway/block-volume`, and `scaleway/object-bucket`
  are untouched — this ADR adds no nested-module composition; any caller
  wiring real bucket/encryption-key values into `keyring_entries` still
  sources them from an external `iam-policy` (or similar) composition at the
  Terragrunt layer, exactly as `buckets` already requires.
- `workloads/pigeon-cli/terraform/sort/macbook-scratch/compute.tf`'s
  in-progress, uncommitted edit is left untouched; wiring `keyring_entries`
  into a real leaf is left for whenever that leaf is finished and
  re-enabled.

## Out of scope

- Referential-integrity validation between `keyring_entries` (e.g. a
  `bucket` entry's `encryption_key_alias` must match an `encryption-key`
  entry's `alias`) — deferred, see Decision above.
- Making the `/root/.config/pigeon/keyring.toml` path configurable — fixed,
  matching `rclone.conf`'s fixed path; no caller need has surfaced for a
  different path.
- Any change to `workloads/pigeon-cli/terraform/sort/macbook-scratch/` —
  that leaf has unrelated in-progress local edits, untouched here.
- A wrapper or nested-module composition that creates `keyring_entries`'
  bucket/encryption-key values automatically from inside `compute-instance`
  — deliberately rejected, consistent with ADR-0081's external-composition
  precedent.
