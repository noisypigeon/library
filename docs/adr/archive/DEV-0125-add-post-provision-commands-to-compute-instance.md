# DEV-0125: Add post-provision commands to compute-instance

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

`compute-instance`'s cloud-init only ever runs a fixed, hardcoded `runcmd` sequence (mount a volume, install `mise`, bootstrap `pigeon-cli`, optionally install Alloy). There's no way for a caller to run their own command once provisioning is done — e.g. kicking off a long-running `pigeon-cli` job (`mise run pigeon-release job run deduplicate ...`) as soon as an instance comes up.

A naive implementation would just append the caller's command to the existing `runcmd:` list. That's wrong for this use case: `runcmd` executes synchronously inside cloud-init's own `cloud-final.service`, so cloud-init itself won't report "done" until the command finishes — for a long-running job, potentially hours. The goal is a command that runs *after* cloud-init is genuinely complete, decoupled from its completion status, not one more step cloud-init blocks on.

The fix is a systemd oneshot unit ordered `After=cloud-final.service`/`Wants=cloud-final.service`, enabled from `runcmd`. Two non-obvious correctness issues surfaced while designing this, both worth recording since they're exactly the kind of gotcha ADR-0104 previously found worth documenting in this same module:

1. **A real deadlock in the obvious invocation.** `runcmd` runs *inside* `cloud-final.service`'s own process. `systemctl enable --now <unit>` blocks by default waiting for the new unit's start job — but that job is ordered `After=cloud-final.service`, i.e. after the very process that's blocked waiting on it. That's a genuine deadlock: cloud-init would never finish, defeating the whole point. The fix is `systemctl --no-block enable --now <unit>`, which queues the job and returns immediately; systemd's own ordering machinery then starts the unit once `cloud-final.service` actually finishes.
2. **`/etc/environment` doesn't reach systemd services for free.** The `PIGEON_SECRET_*` secrets this module already writes to `/etc/environment` (ADR-0104) only reach login/SSH sessions, via PAM's `pam_env` — PID 1 does not source that file into system service units. A new unit needs to say so explicitly (`EnvironmentFile=-/etc/environment`, the leading `-` tolerating a missing file).

The command itself is arbitrary caller-supplied shell — potentially multi-line, with quotes, `$`, backticks, `%`. Embedding it directly into YAML (indentation-sensitive block literals) or into the unit's own `ExecStart=` line (which has its own `%`-specifier and quoting rules, independent of the shell's) is fragile. Writing it to its own file via cloud-init's `write_files[].encoding: b64` sidesteps both — base64's alphabet has no YAML- or systemd-significant characters.

## Decision

`instance_config` gains a new optional field:

```hcl
post_provision_commands = optional(list(string), [])
```

- `[]` (default): nothing extra runs — unchanged behavior for every existing caller.
- Non-empty: the commands run, in order, inside one generated script (`#!/bin/bash`, `set -euo pipefail`, `export PATH="/root/.local/bin:$PATH"` since systemd units don't source `.bashrc`/profile scripts and the `pigeon-cli` bootstrap installs `mise` there, `cd /root` matching the bootstrap's own clone target of `$HOME/pigeon-cli`), base64-encoded into `/root/.config/pigeon/post-provision.sh` via cloud-init `write_files`.
- A matching `pigeon-post-provision.service` unit is written alongside it:

```ini
[Unit]
After=cloud-final.service
Wants=cloud-final.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/root
EnvironmentFile=-/etc/environment
ExecStart=/bin/bash /root/.config/pigeon/post-provision.sh
ExecStartPost=/bin/systemctl disable pigeon-post-provision.service

[Install]
WantedBy=multi-user.target
```

- `RemainAfterExit=yes` so a finished run shows `active (exited)` (success) or `failed`, rather than reverting to `inactive (dead)` — indistinguishable at a glance from "never ran."
- `ExecStartPost=systemctl disable ...` makes this run exactly once ever: after a successful run, the unit disables itself so a later reboot doesn't re-trigger it (desirable for a job that mutates/moves data, like the dedup example). A failed run leaves it enabled, so a reboot naturally retries it.
- `runcmd` enables it with `systemctl daemon-reload && systemctl --no-block enable --now pigeon-post-provision.service` — the `--no-block` is required to avoid the deadlock described above.
- Output is inspected with `journalctl -u pigeon-post-provision.service`, not cloud-init's own log, since the command runs outside cloud-init's process entirely.

No new `validation` block — this is a freeform list with no cross-field constraint, unlike `block_volume.project_id`.

This is purely additive: a new optional field defaulting to `[]`. `release:minor`, `v5.1.0` → `v5.2.0`.

## Consequences

- Any change to `post_provision_commands` changes the rendered cloud-init content, which (via the pre-existing `terraform_data.cloud_init` / `replace_triggered_by` mechanism) forces the instance to replace — same as any other `instance_config`/`keyring` edit today, not a new behavior introduced by this field.
- `instance_config` stays `sensitive = true` as a whole (unchanged from ADR-0118); this field is non-diffable in `plan` output too, same accepted tradeoff as every sibling field.
- `README.md` for `compute-instance` regenerates automatically via `module-docs.yml` on merge.
- No consumer migration: `workloads/pigeon-cli/terraform/job` is currently fully commented out (an unrelated, deliberate prior change), so there is no active caller to update. If/when that leaf is re-enabled, it would set `instance_config.post_provision_commands` to run its dedup job, e.g.:

  ```hcl
  post_provision_commands = [
    "cd pigeon-cli",
    "mise run pigeon-release job run deduplicate --source-bucket source: --concurrency 8 --report-bucket pigeon-cli-reports: --yes --local-output /mnt/data/pigeon-job --remote-output destination:",
  ]
  ```

## Out of scope

- Re-running on every boot (vs. once ever) is not configurable — always once-ever via the self-disabling unit. A caller wanting recurring behavior would need a different mechanism.
- Per-command success/failure granularity: all commands run as one script under `set -e`; the first failing command aborts the rest, and the unit reports a single pass/fail for the whole batch.
