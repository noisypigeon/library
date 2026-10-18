# DEV-0104: fix `environment_variables`/`PIGEON_LOG_DIR` not reaching non-login SSH invocations

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

On `job-deduplication-zsv8st-media-worker` (the
`workloads/pigeon-cli/terraform/deduplication/media` leaf, which wires
`cockpit = {...}` into `modules/scaleway/compute-instance`), a real
`pigeon job run dedupe` run wrote its JSONL log to
`~/.local/share/pigeon/logs/pigeon.jsonl` instead of
`/var/log/pigeon/pigeon.jsonl`, the path ADR-0102's Alloy config
hardcodes for `loki.source.file`. Confirmed live: running
`tail -f $PIGEON_LOG_DIR/pigeon.jsonl` in a current interactive SSH
session correctly resolves to `/var/log/pigeon/pigeon.jsonl` (the var is
genuinely exported there) — yet the actual log file from the real run
sits under the XDG-based default that `pigeon-cli` falls back to when the
var isn't set at all (`noisypigeon/pigeon-cli`'s
`src/observability/mod.rs::default_log_dir`).

**Root cause**: `instance.tf` only ever delivers `environment_variables`
(and the cockpit-gated `PIGEON_LOG_DIR`, ADR-0102) via
`/etc/profile.d/pigeon-env.sh` (ADR-0101). `/etc/profile.d/*.sh` is sourced
by `/etc/profile`, which only interactive **login** shells read. A one-off
`ssh host 'pigeon job run dedupe ...'` — an ordinary way to kick off a job
and disconnect — opens a non-login shell and never sources it, so that
invocation falls through to `pigeon`'s own default. A later, separate
interactive login session (what produced the `tail -f` check above) *does*
source it correctly, which is exactly why the two checks disagreed:
they're two different shell sessions with two different environments, not
one inconsistent one.

ADR-0101 explicitly designed for the login-shell case only ("placing the
file under `/etc/profile.d/` also auto-sources it for any later
interactive login shell \[...] covering manual `pigeon-cli` invocations
after boot") and reasoned, correctly at the time, that "no ADR or code in
this repo describes any cron/systemd/recurring invocation of
`pigeon-cli`." A direct `ssh host cmd` is neither of those things, but it
is a third real invocation shape that slipped through — this is a genuine
gap in that ADR's coverage, not a reason to revisit its login-shell
mechanism itself.

## Decision

Also deliver the same key/value pairs via `/etc/environment`, alongside
(not instead of) the existing `/etc/profile.d/pigeon-env.sh`.

`/etc/environment` is read by PAM's `pam_env` module (`readenv=1`) during
session setup for *any* SSH-authenticated session — login shell or a
direct `ssh host cmd` — because PAM's session phase runs regardless of
whether a shell is actually started afterward. This is Ubuntu/Debian's
default `sshd` PAM stack (`pam_env.so readenv=1` via
`/etc/pam.d/common-session`, included by `/etc/pam.d/sshd` on the
`ubuntu_jammy` image this module already uses) — no new package or config
beyond writing the file.

### `instance.tf`: a second `write_files` entry

Added right after the existing `/etc/profile.d/pigeon-env.sh` entry,
reusing the identical `%{for}`/`%{if}` template body minus the `export`
keyword (`/etc/environment` is plain `KEY="VALUE"` lines, no shell
syntax):

```yaml
      - path: /etc/environment
        permissions: '0600'
        defer: true
        append: true
        content: |
          %{~for key, value in var.environment_variables~}
          ${key}="${value}"
          %{~endfor~}
          %{~if var.cockpit != null~}
          PIGEON_LOG_DIR="/var/log/pigeon"
          %{~endif~}
```

`append: true` is essential: Ubuntu cloud images ship `/etc/environment`
pre-populated with a `PATH=...` line that must survive, not be clobbered.

**Permissions tightened to `0600`, not the conventional world-readable
`0644`.** `var.environment_variables` is already `sensitive = true`
specifically because it carries secret material (ADR-0101) — e.g. this
repo's own `deduplication/media` leaf passes `PIGEON_SECRET_SOURCE`/
`PIGEON_SECRET_DESTINATION` through it. `/etc/environment` is
conventionally world-readable since it normally holds nothing sensitive,
but once it carries these secrets too, that default is wrong for this
use case. Restricting it to `0600` doesn't break the mechanism: `sshd`
itself still runs as root when its PAM session stack reads the file,
before it drops privileges to the connecting user — the same reason
`pigeon-env.sh` was already `0600`.

No change to `/etc/profile.d/pigeon-env.sh` itself — it stays as a
secondary, human-visible path for anyone who does open an interactive
login shell to inspect the environment by hand.

## Consequences

- `release:patch` for `scaleway/compute-instance` — a bug fix, no
  input/output signature change.
- Every existing `profile = "pigeon-cli"` instance with `cockpit != null`
  (or any instance using `environment_variables` at all, regardless of
  profile) picks this up on its next cloud-init content change, which
  force-replaces the instance (`lifecycle.replace_triggered_by`,
  ADR-0084) — not applied to any live leaf as part of this ADR; the user
  bumps a leaf's module version pin and applies it on their own schedule,
  same precedent ADR-0102 itself called out for its own rollout.
- The already-written `~/.local/share/pigeon/logs/pigeon.jsonl` from the
  run that surfaced this bug stays where it is — Alloy only tails forward
  from the path it's configured to watch; retroactively relocating that
  one file (if wanted) is a manual, out-of-band SSH step, not something
  this ADR performs.

## Out of scope

- Recovering or relocating the already-misplaced log file from the live
  `job-deduplication-zsv8st-media-worker` instance.
- Bumping any leaf's `modules/scaleway/compute-instance` version pin or
  running `terragrunt apply` against it.
- Any cron/systemd-based recurring invocation of `pigeon-cli` — still not
  something any ADR or code in this repo describes; this fix is about the
  manual-SSH invocation shapes that do exist today.
