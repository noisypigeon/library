# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - 2026-10-28

### Let compute-instance-config take keyring fields from wiring and secrets

`compute-instance-config` v1.1.0 adds two inputs that fill in a keyring entry's fields by alias. A workload's config leaf ([LIB-0043](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0043-workload-compute-kinds.md) §4) needs them, because a keyring entry's bucket name and credentials come from other leaves' outputs, and its secrets come from `secrets.workload.yaml`. Neither fits a literal `keyring` list.

- **`keyring_wiring`**, a sensitive map from alias to `{ bucket, access_key_id, secret_key }`, all optional. A null field leaves the entry's own value. It's what a stub fills from a bucket leaf's name and an API key leaf's credentials.
- **`keyring_secrets`**, a sensitive map from alias to a map of string fields: `email`, `host`, `secret`, `endpoint`, `bucket`, `access_key_id` or `secret_key`. Any other field is refused. It's what root.hcl fills from resolved `secretRef`s.

Each entry is `keyring`'s, then its wiring, then its secrets, merged by alias. Naming an alias that `keyring` doesn't have fails the plan.

**Where the required-field checks run moves.** An email entry still needs `email`, `provider`, `host`, `port` and `secret`, and a bucket entry still needs `endpoint`, `bucket`, `access_key_id` and `secret_key`, with the same messages. They're now checked on the merged entries, as preconditions on the `cloud_init` output, instead of as validations on `keyring`, since a field may arrive through either new input. A caller that sets neither input sees the same errors as before.

Without either input, the module renders exactly what v1.0.0 renders. Verified by applying v1.0.0 and v1.1.0 side by side in a scratch root: the documents are identical with a complete `keyring`, and identical again when the same values arrive split across `keyring`, `keyring_wiring` and `keyring_secrets`. A missing `secret`, and an unknown alias in `keyring_secrets`, each failed the plan with its message.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#222](https://github.com/noisypigeon/library/pull/222)

## [1.0.0] - 2026-10-19

### Write secrets into keyring.toml and stop rendering rclone.conf in compute-instance-config

This release implements LIB-0018. It renders a cloud-init document that current pigeon-cli can actually load. In v0.1.0, `keyring.toml` was written without secrets, but pigeon-cli now keeps every secret in that file and fails to load an entry without one (pigeon-cli ADR-0135). So every pigeon command on a v0.1.0 instance with a non-empty keyring exited before doing anything.

**`keyring.toml` now carries every secret.** Email identities get `secret` and buckets get `secret_key`, matching pigeon-cli's `Identity` and `BucketConfig`. The file is still written to `/root/.config/pigeon/keyring.toml` at `0600`. Every string value goes through `jsonencode()`, which is also a valid TOML basic string, so a quote, backslash or newline in a password can no longer break the file.

**`/root/.config/rclone/rclone.conf` is no longer rendered.** pigeon-cli writes its own `rclone.conf` beside the keyring (`/root/.config/pigeon/rclone.conf`) at the start of every rclone-backed job and passes `--config` explicitly, so it never read the module's file (pigeon-cli ADRs 0136, 0140, 0145, 0148). The `rclone` package is still installed. Bare `rclone` on an instance now has no remotes. Anything in `post_provision_commands` that ran `rclone ... alias:` against the old file needs `--config /root/.config/pigeon/rclone.conf`, and that file exists only after a pigeon job has run. Calling pigeon is the supported path.

**`PIGEON_SECRET_<ALIAS>` is no longer exported** to `/etc/profile.d/pigeon-env.sh` or `/etc/environment`. With the secret in the keyring, the export only overrode a value with itself and left two more copies of each secret on disk. pigeon-cli still honours the variable if an operator sets it by hand. `PIGEON_LOG_DIR` is unchanged and still gated on `cockpit`.

**Breaking changes to the `keyring` input.** Its object type now mirrors pigeon-cli's schema:

- `kind` accepts `email` and `bucket` only. `kind = "encryption-key"` and `created_at` are removed, because pigeon-cli dropped that entry kind (pigeon-cli ADR-0147).
- `encryption_key_alias` is removed from bucket entries.
- Bucket `provider` is removed. It only fed the old `rclone.conf`, and pigeon-cli always uses `provider = Other`. `provider` now exists only on email entries and is validated against `gmail`, `fastmail`, `icloud`, `proton` and `custom`.
- An email identity's secret is now `secret` rather than `secret_key`. A bucket's is still `secret_key`.
- Required fields are validated per kind. Email entries need `email`, `provider`, `host`, `port` and `secret`. Bucket entries need `endpoint`, `bucket`, `access_key_id` and `secret_key`. A missing secret now fails the plan instead of producing an instance whose pigeon can't load its keyring.

Upgrading changes the rendered document, so `compute-instance` replaces any server built from it.

This was checked by rendering the module from a scratch root with one email entry and one bucket entry, each with quotes, backslashes, `<&>` and a newline in its secret. The whole document parses as YAML, and the extracted `keyring.toml` parses with Python's `tomllib` and returns every secret exactly as given. An empty keyring with no `cockpit` renders the three files empty, as before. Each new validation rejects its bad case: an `encryption-key` entry, an email entry with no `secret`, an email `provider = "Gmail"`, and a bucket entry with no `secret_key`.

The only consumer, runway's `pigeon-cli` leaf, reaches this module through `pigeon-cluster` and has its `module "cluster"` block commented out, so nothing live changes. `pigeon-cluster` v4.0.0 adopts the new shape and repins to this tag in a separate PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#78](https://github.com/noisypigeon/library/pull/78)

## [0.1.0] - 2026-10-10

### Split cloud-init into compute-instance-config; stop composing modules inside compute-instance

`compute-instance` had grown to 659 lines owning six resources and composing three other modules internally — `block-volume` (ADR-0120) and the `iam-policy`/`iam-api-key` pair (ADR-0122). Because every one of those concerns sat behind a single version, any change to any of them cut a new `compute-instance` release, which `pigeon-cluster` then had to re-pin and release, which the consuming leaf then had to re-pin again. ADR-0152 paid exactly that toll to turn one `apt-get` line into a `curl`. This splits the module so a provisioning change no longer touches the module that owns the live server.

`compute-instance` is now a thin `scaleway_instance_server` wrapper — 140 lines, three resources: the random name suffix, the cloud-init hash that drives replacement, and the server. Its inputs are flattened: `name_prefix`, `name_suffix`, `image`, `type`, `ssh_key`, `cloud_init`, `ip_ids`, `additional_volume_ids`, `enabled`. The `instance_config` and `user_config` objects are gone, along with `keyring`, `iam_config`, `self_delete_on_exit` and all four networking inputs. Outputs shrink from seven to three (`id`, `name`, `public_ips`) because the resources behind the others now belong to the caller, which can read them directly. A welcome side effect: the module is no longer `sensitive` as a whole, so values derived from `image`/`type` stop being marked sensitive by propagation in plan output.

Cloud-init rendering moves wholesale into a new `compute-instance-config` module. It creates nothing — its only output is the rendered document — which makes it the first module here that returns a string rather than infrastructure. The four locals move across verbatim; two references that could no longer resolve became inputs: `self_delete_credentials` (an object replacing the internally-composed API key, with the `self_delete_on_exit` validation ported across the boundary) and `has_attached_volume` (a plain bool replacing the volume-ID length check, deliberately caller-supplied so the rendered document never depends on an apply-time-unknown value).

Correctness was verified by rendering `local.cloud_init` from the original module and from the new one with matched inputs and diffing: byte-identical across all four combinations of `self_delete_on_exit` and `enable_transcoding`, plus a minimal no-cockpit/no-volume/empty-keyring case, with the output confirmed to parse as valid cloud-config YAML.

Two behavioural notes for callers. ADR-0126's `enabled` kill switch now destroys the server and only the server — the IPs, volume and IAM it used to tear down are the caller's resources now, so a full teardown has to gate those too; the input description says so. And rotating the self-delete API key changes the rendered document, which replaces the server; that was already true via the internal composition, but it is now an explicit property of a module boundary rather than an inherited accident.

This restores the principle ADR-0081 set and ADR-0085 reaffirmed — no module in this provider root composes another internally — and reverses the exceptions ADR-0120 and ADR-0122 carved out. ADR-0138 asked for that revisit "if a third shape of this exception shows up"; this is it. ADR-0120's own test for the carve-out was that `block-volume` had one consumer, always paired 1:1; with `pigeon-cluster` composing N jobs that each independently choose a volume, an IP, a NIC or self-deletion, that is no longer the case. ADR-0120, ADR-0121 and ADR-0122 are marked superseded, ADR-0126 superseded in part. ADR-0121's finding is restated in ADR-0153 rather than lost: a split module must be referenced by released-tag URL, never a relative path, which fails for HTTP-sourced consumers with `Local module path escapes module package`.

`pigeon-cluster` still pins `compute-instance/v6.1.0` and is unchanged by this PR; it is rewired to both new tags in a follow-up, since its new source URLs only resolve once these tags exist.


[#269](https://github.com/noisypigeon/noisypigeon/pull/269)
