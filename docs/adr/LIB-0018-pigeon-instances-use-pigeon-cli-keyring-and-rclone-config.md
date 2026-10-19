# LIB-0018: pigeon instances use pigeon-cli's own keyring.toml and rclone.conf

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-19.
- **Status**: Accepted. Amends DEV-0081 (the module-rendered `rclone.conf`),
  DEV-0100 (the `keyring.toml` template), DEV-0101 and DEV-0104 (the
  `PIGEON_SECRET_<ALIAS>` exports), DEV-0144 (the cluster's keyring entry
  shape) and DEV-0153 (`compute-instance-config`'s `keyring` input).

## Context

`terraform/scaleway/compute-instance-config` renders the cloud-init document
every pigeon-cli instance boots from. Three of the files it writes exist to
hand pigeon-cli its credentials, and all three were designed against a
pigeon-cli that no longer exists.

pigeon-cli keeps its own ADRs (LIB-0017 §5). Five of them changed what it
expects to find on a host:

- **[pigeon-cli ADR-0135](https://github.com/noisypigeon/pigeon-cli/blob/main/docs/adr/0135-plaintext-secrets-in-keyring-toml.md)**
  retired the OS keychain. `keyring.toml` is now the only store for every
  secret, as a plain field on each entry: `secret` on an email identity,
  `secret_key` on a bucket. Neither field has a default, so an entry without
  its secret fails `Store::load`, and every pigeon command calls that.
- **[pigeon-cli ADR-0136](https://github.com/noisypigeon/pigeon-cli/blob/main/docs/adr/0136-rclone-config-generation-and-bucket-alias-addressing.md)**,
  amended by pigeon-cli ADR-0140, sandboxes rclone. pigeon writes its own `rclone.conf`
  from the keyring's bucket entries at the start of every rclone-backed job,
  never reads or merges an existing file, and passes `--config` with that path
  to every rclone call. The file holds one `[<alias>.s3]` backend per bucket,
  with `provider = Other`, plus an `[<alias>] type = alias` pointing at
  `<alias>.s3:<bucket>`. pigeon-cli ADR-0136 names this module's template as the
  translation it was taking over.
- **[pigeon-cli ADR-0145](https://github.com/noisypigeon/pigeon-cli/blob/main/docs/adr/0145-global-keyring-path-flag.md)**
  adds `--keyring-path` and puts the generated `rclone.conf` beside whichever
  `keyring.toml` is in use. For root on Linux with no override, that's
  `/root/.config/pigeon/keyring.toml` and `/root/.config/pigeon/rclone.conf`.
- **[pigeon-cli ADR-0147](https://github.com/noisypigeon/pigeon-cli/blob/main/docs/adr/0147-remove-email-sync-and-email-pull.md)**
  removed client-side encryption and the `encryption-key` entry kind. A
  leftover entry of that kind fails `Store::load` too. A stale
  `encryption_key_alias` on a bucket entry is ignored.
- **[pigeon-cli ADR-0148](https://github.com/noisypigeon/pigeon-cli/blob/main/docs/adr/0148-drop-minio.md)**
  drops `minio`, so every S3 access goes through rclone and that generated
  config. It also makes `PIGEON_SECRET_<ALIAS>` reach bucket entries for the
  first time. Before, the override only worked for IMAP identities.

Against that, `compute-instance-config` v0.1.0 writes:

1. **`/root/.config/rclone/rclone.conf`** (DEV-0081, carried through DEV-0099
   and DEV-0153), one remote per `kind = "bucket"` entry. pigeon never reads it:
   it isn't the path pigeon generates, and pigeon passes `--config` explicitly.
   It's also in the shape pigeon-cli ADR-0140 moved away from, with backends keyed by
   bucket name and a per-entry `provider`.
2. **`/root/.config/pigeon/keyring.toml`** (DEV-0100), **without the secret
   fields**. The input's description says so on purpose: "secret_key is never
   written into keyring.toml itself". Under pigeon-cli ADR-0135 that file **fails to
   parse**, so every pigeon command on a v0.1.0 instance with a non-empty
   keyring exits before doing anything. Any `kind = "encryption-key"` entry
   (DEV-0101) fails it a second way.
3. **`PIGEON_SECRET_<ALIAS>` exports** in `/etc/profile.d/pigeon-env.sh` and
   `/etc/environment` (DEV-0101, DEV-0104), the module's way of getting secrets
   to pigeon while they lived in the keychain. Since pigeon-cli ADR-0135 they only
   override a value that is now required to be in the file anyway.

Nothing live hits this today. The only consumer, runway's `pigeon-cli` leaf,
has its whole `module "cluster"` block commented out. The next job anyone
re-enables would, though.

## Decision

### 1. The module stops rendering `rclone.conf`

The `/root/.config/rclone/rclone.conf` entry in `write_files` is removed. pigeon
generates its own config from the keyring on every job run (pigeon-cli ADR-0136 §2,
pigeon-cli ADR-0145 §5), and that file is what pigeon reads. A second, module-rendered copy
can only drift from pigeon-cli ADR-0140's shape, and pigeon is designed never to trust it.

The `rclone` apt package stays: pigeon checks for `rclone` on `PATH` before
every rclone-backed job (pigeon-cli ADR-0145 §5) and before `keyring add`/`modify bucket`
(pigeon-cli ADR-0148 §3).

### 2. `keyring.toml` carries every secret; the env exports go

`keyring.toml` is written with each entry's secret in the field pigeon-cli
reads: `secret` on an email identity and `secret_key` on a bucket, `0600` as
before. That makes the file pigeon-cli's own storage model, one copy of each
secret, and loadable.

`PIGEON_SECRET_<ALIAS>` is no longer written to `/etc/profile.d/pigeon-env.sh`
or `/etc/environment`. With the secret already in the file, the export would
only ever override a value with itself, while leaving the secret in two more
files. pigeon-cli still honours the variable (pigeon-cli ADR-0087, now for buckets too
per pigeon-cli ADR-0148), so an operator can still set it by hand on a host. The module
just no longer sets it. `PIGEON_LOG_DIR` stays where it is, gated on
`cockpit` as before. The profile script and the `/etc/environment` append now
hold only that line, and with no `cockpit` they're written empty, exactly as
they are today with an empty keyring.

String values are rendered through `jsonencode()` rather than bare
`"${...}"` interpolation. A JSON string literal is also a valid TOML basic
string for these values, so a quote or backslash in a password can no longer
break the file.

The keyring stays at `/root/.config/pigeon/keyring.toml`, pigeon's default
for root, so the generated `rclone.conf` lands at
`/root/.config/pigeon/rclone.conf`. No `--keyring-path` and no
`PIGEON_CONFIG_DIR` is set.

### 3. The `keyring` input mirrors `keyring.toml`'s schema

The input stays one list of `kind`-tagged objects, which is the file's own
`[[entries]]` shape, but every field now means what pigeon-cli's field of the
same name means:

```hcl
variable "keyring" {
  type = list(object({
    kind  = string # "email" | "bucket"
    alias = string

    # kind = "email" -- pigeon-cli's Identity
    email                = optional(string)
    provider             = optional(string) # gmail | fastmail | icloud | proton | custom
    host                 = optional(string)
    port                 = optional(number)
    secret               = optional(string)
    max_imap_connections = optional(number)

    # kind = "bucket" -- pigeon-cli's BucketConfig
    endpoint      = optional(string)
    bucket        = optional(string)
    access_key_id = optional(string)
    secret_key    = optional(string)
  }))
  sensitive = true
}
```

Compared with v0.1.0:

- **`kind = "encryption-key"` and `created_at` are removed** (pigeon-cli
  ADR-0147). The kind validation accepts `email` and `bucket` only.
- **`encryption_key_alias` is removed** from bucket entries.
- **Bucket `provider` is removed.** It fed only the module's `rclone.conf`,
  and pigeon's `BucketConfig` has no such field (pigeon-cli ADR-0136 hardcodes
  `provider = Other`). `provider` now exists only on email entries, where it
  always went into `keyring.toml`, and is validated against pigeon-cli's
  kebab-case `Provider` enum.
- **An email identity's secret is `secret`**, not `secret_key`, matching
  pigeon-cli's `Identity`. A bucket's stays `secret_key`.
- **Required fields are validated per kind**, since `optional()` can't say
  "required when `kind` is X". Email requires `email`, `provider`, `host`,
  `port` and `secret`. Bucket requires `endpoint`, `bucket`, `access_key_id`
  and `secret_key`. A missing secret was silently tolerated before, and now
  fails the plan, the same way pigeon-cli's load would fail on the instance.
  The alias format and uniqueness validations are unchanged.

### 4. `pigeon-cluster` follows the same shape

`cluster_config.shared_keyring` and `jobs[*].keyring` stay `map(object(...))`
keyed by alias (DEV-0144), with the same field changes as §3, minus `alias`
(the map key is the alias). DEV-0144's default carries over unchanged: a
bucket entry that omits `access_key_id`/`secret_key` gets the job's own API
key, merged in by `effective_keyring` before the list goes to
`compute-instance-config`. The `inputs.tf` comments that say bucket entries
"also generate an rclone.conf remote" are corrected. Both
`compute-instance-config` calls, per job and for the bastion, are repinned to
the new tag.

## Consequences

### Releases

| Module | Change | Bump |
|---|---|---|
| `terraform/scaleway/compute-instance-config` (v0.1.0) | `keyring`'s object type changes (fields removed and renamed, a kind removed, new required-field validations); `rclone.conf` and the `PIGEON_SECRET_*` exports are no longer rendered | `release:major` → **v1.0.0** |
| `terraform/scaleway/compute-instance` (v7.0.0) | None: it takes `cloud_init` as an opaque string | **No release** |
| `terraform/scaleway/pigeon-cluster` (v3.0.1) | `shared_keyring` and `jobs[*].keyring` object types change; both config calls repin to `compute-instance-config/v1.0.0` | `release:major` → **v4.0.0** |

The two releases are separate PRs, in that order. `pigeon-cluster` pins
`compute-instance-config` by released-tag URL (DEV-0153, LIB-0009), so its
PR can only resolve once `v1.0.0` exists.

### Consumers

One consumer: runway's
`terraform/scaleway/pigeon-cluster/pigeon-cli/` (`cluster.tf`,
`cluster_definition.tf`). Its `module "cluster"` block is commented out, so
nothing live changes. Re-enabling it now means:

- pinning `pigeon-cluster/v4.0.0` or later rather than the `v3.0.1` its comment
  names;
- removing `provider = "Scaleway"` from `shared_keyring.reports`, which v4.0.0
  no longer reads. Type conversion would drop it silently, so it would only
  mislead;
- moving the commented job commands off `--source-path`/`--destination-path`,
  which pigeon-cli ADR-0136 already replaced with `--source-bucket`/
  `--destination-bucket`. Those are stale whatever this ADR decides.

The bastion passes no keyring and needs nothing beyond the repin.

### Behaviour

- **A v1.0.0 instance can run pigeon at all**, which no v0.1.0 instance with a
  keyring could since pigeon-cli ADR-0135.
- **Every running server is replaced on upgrade.** The rendered document
  changes, and `compute-instance` replaces on a cloud-init hash change
  (DEV-0084). Jobs are self-deleting (DEV-0138), so the practical effect is
  on the bastion only.
- **Bare `rclone` on an instance has no remotes.** Anything in
  `post_provision_commands`, or an operator in a bastion shell, that ran
  `rclone ... alias:` against the module's file now needs
  `--config /root/.config/pigeon/rclone.conf`. That file only exists once a
  pigeon job has run on the host. Calling pigeon is the supported path.
- **`provider = Other` is now the only provider value any instance uses.**
  The module's per-entry `provider` (e.g. `Scaleway`) is gone with its file.
  pigeon-cli ADR-0136 records `Other` as unverified against Scaleway,
  Backblaze B2 and DigitalOcean Spaces. That risk was already live for every
  pigeon job, since pigeon never read the module's file; it is now also the
  only configuration on the host.
- **Secrets sit where they did, minus two copies.** Every secret is still in
  `user_data` and in `keyring.toml` at `0600`, as before. They no longer also
  sit in `/etc/environment` and `/etc/profile.d/pigeon-env.sh`.
- **A missing secret fails at plan time** instead of producing an instance
  whose pigeon can't load its keyring.

## Out of scope

- **The module changes themselves.** This record decides them; the
  `compute-instance-config` v1.0.0 and `pigeon-cluster` v4.0.0 PRs follow it,
  each through the `release-pr` discipline. Named follow-ups, not deferred
  design.
- **Re-enabling runway's leaf.** A runway change, made whenever a job next
  needs to run, against the list above.
- **A non-default keyring location.** `--keyring-path` (pigeon-cli ADR-0145)
  would let a host keep the keyring outside `/root`, for example `/etc/pigeon`.
  Nothing here runs pigeon as any user but root, so there's nothing to choose
  it for. A permanent boundary until something does.
- **Live verification of `provider = Other`.** pigeon-cli's own deferred item
  (pigeon-cli ADR-0136, Consequences and Verification). It needs a real job against each
  backend, not a change here.
- **Keeping secrets out of `user_data`.** A cloud-init document that needs no
  secrets would mean fetching them on boot from somewhere the instance
  authenticates to. Unchanged by this record, and not proposed.
