# DEV-0090: fix missing `$HOME` in `scaleway/compute-instance`'s cloud-init `runcmd`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`cloud-init status --long` on a freshly-provisioned instance reported:

```
status: error
errors:
    - ('scripts_user', RuntimeError('Runparts: 1 failures (runcmd) in 1 attempted commands'))
```

`/var/log/cloud-init-output.log` (requested from the user to confirm root cause rather than guess) shows exactly where it failed. An initial hypothesis — that the new unconditional `mkfs.ext4` (ADR-0089) was hitting an interactive "destroy existing filesystem?" prompt on a reattached volume — was **ruled out**: the log shows `mkfs.ext4`/`mkdir`/`mount`/fstab all completing cleanly, with "Writing superblocks and filesystem accounting information: done" and no errors anywhere near them. The real failures all appear later, after the volume-mount block:

```
mise: selected 2026.9.18 (minimum release age: 24h)
sh: 325: HOME: parameter not set
/var/lib/cloud/instance/scripts/runcmd: 9: cannot create ~/.bashrc: Directory nonexistent
bash: line 6: HOME: unbound variable
```

**Confirmed root cause.** cloud-init's `runcmd` module writes every list item into a single combined shell script (`/var/lib/cloud/instance/scripts/runcmd`) and executes it once via `/bin/sh` — and that execution environment has **no `$HOME` set at all**. This single gap broke three independent things in the same script:

1. The `mise.run` installer script (piped to `sh`) references `$HOME` internally and aborts at its own line 325 (`sh: 325: HOME: parameter not set`).
2. This module's own `echo '...' >> ~/.bashrc` line (added in ADR-0081, still used to activate `mise`) fails at runcmd script line 9: with `$HOME` unset, `~` doesn't tilde-expand, so the shell tries to treat the literal 2-character path `~/.bashrc` as a nonexistent directory (`cannot create ~/.bashrc: Directory nonexistent`).
3. The `pigeon-cli` profile's bootstrap script (ADR-0089, `curl ... | bash`) references `$HOME` under `bash`'s strict mode and aborts at its own line 6 (`bash: line 6: HOME: unbound variable`).

This is a long-standing latent bug present since `mise`/`~/.bashrc` was introduced (ADR-0081, 2026-09-30) — it just hadn't surfaced until `pigeon-cli`'s externally-fetched script also hit the same missing-`$HOME` gap, and until someone checked `cloud-init-output.log` closely enough to see the per-line failures cloud-init's generic "Runparts: 1 failures" status otherwise hides.

## Decision

Add `export HOME=/root` as the first line of `runcmd:`, unconditional across every profile. Because cloud-init bundles all `runcmd` items into one script run by one shell process, an exported variable on line 1 is inherited by every later line in that same script — including the `mise.run` installer and any `curl | bash` pipeline, since `bash` inherits its parent process's exported environment:

```hcl
    runcmd:
      - export HOME=/root
    %{~if length(var.additional_volume_ids) > 0~}
      - mkfs.ext4 -L data /dev/sdb
      ...
    %{~endif~}
      - curl -fsSL https://mise.run | sh
      - echo 'eval "$(/root/.local/bin/mise activate bash)"' >> /root/.bashrc
```

Also switched the mise-activation line's target from `~/.bashrc` to the absolute `/root/.bashrc` — removes this module's own dependency on `$HOME`/tilde-expansion entirely, as a second, independent layer on top of the `export HOME=/root` fix. Consistent with this module being root-only (ADR-0081, Scaleway marketplace images boot as `root` with no sudo-user machinery).

No changes to `inputs.tf`/`outputs.tf` — this is a pure bugfix to the rendered cloud-init body, not an interface change.

## Consequences

- `release:patch` — no new/changed input or output; this fixes behavior that was always broken, it doesn't add or change capability.
- Every profile's `mise` activation and, for `pigeon-cli`, the bootstrap script, now actually run to completion instead of silently failing partway through `runcmd` (cloud-init only ever surfaced this as one generic `status: error`, not which line failed).
- Cloud-init content changes → every existing instance using this module gets replaced on its next apply, per the existing force-replace lifecycle (ADR-0084).

## Out of scope

- Auditing other cloud-init-adjacent scripts (e.g. the `docker` profile's apt bootstrap) for other latent `$HOME`-dependent failures — none were observed in the log, and `docker`'s `runcmd` lines don't reference `$HOME` or `~`.
- Switching `runcmd`'s shell or otherwise changing how cloud-init itself invokes scripts — `export HOME=/root` works within cloud-init's existing execution model and needs no deeper change.
