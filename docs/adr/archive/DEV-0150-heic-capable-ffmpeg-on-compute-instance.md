# DEV-0150: libheif-enabled ffmpeg on `compute-instance`, re-pinned in `pigeon-cluster`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-10.
- **Status**: Superseded by [ADR-0152](DEV-0152-pinned-static-ffmpeg-for-tiled-heif.md).

## Context

`pigeon-cli`'s `transform --input-file-type=heic` path needs an ffmpeg build with `--enable-libheif` to decode `.heic` input. Ubuntu's default apt ffmpeg build (the `ubuntu_jammy` image `compute-instance` defaults to) typically does not include libheif-based HEIC decode support — without it, `transform` fails fast on the very first `.heic` file with ffmpeg's own "decoder not found" error.

`templates/terraform/scaleway/compute-instance/instance.tf:94-343` is this module's entire provisioning surface: an inline cloud-init heredoc, no separate shell script or template file. Its `packages:` block (`instance.tf:98-103`) installs only `rclone`/`neovim` (plus `jq` when `self_delete_on_exit` is set) — there is no ffmpeg anywhere in the module today. Its `runcmd` bootstraps `pigeon-cli` via a gist script (`instance.tf:326`); fetching and reading that script confirms it only apt-installs `build-essential pkg-config libssl-dev git curl ca-certificates` plus `mise`/Claude Code via curl — it doesn't touch ffmpeg either. So adding HEIC-capable ffmpeg here is new provisioning, not an override of some existing vanilla install.

The module already has a working precedent for a conditional, third-party-repo-based apt install gated behind an `instance_config` sub-field: the Cockpit/Alloy block (`var.instance_config.cockpit != null` → `instance.tf:327-335`), which adds Grafana's apt repo and installs `alloy`.

Current released version: `v5.6.1` (`templates/terraform/scaleway/compute-instance/CHANGELOG.md:7`).

`pigeon-cluster` (`templates/terraform/scaleway/pigeon-cluster/`, currently `v1.2.0`) is this repo's only consumer of `compute-instance` for `pigeon-cli` work, composing it twice — once per pending job (`cluster.tf:153`, `module "job"`) and once for its optional debug bastion (`cluster.tf:214`, `module "bastion"`) — both currently pinned to `v5.6.1`. Its one real consumer, `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/cluster.tf`, has had its entire `module "cluster"` block commented out since PR #252 — an inert scaffold, so this change needs no leaf-level migration.

## Decision

### 1. `compute-instance`: new `instance_config.enable_heic_transcoding` (bool, default `false`)

New optional field on `instance_config`:

```hcl
enable_heic_transcoding = optional(bool, false)
```

`false` (default, unchanged behavior): no ffmpeg installed at all, same as today. `true` adds, in `runcmd`, right after the `pigeon-cli` bootstrap step and before the Cockpit/Alloy block:

```hcl
%{~if var.instance_config.enable_heic_transcoding~}
      - apt-get install -y software-properties-common
      - add-apt-repository -y ppa:savoury1/ffmpeg4
      - apt-get update
      - DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg
%{~endif~}
```

`ppa:savoury1/ffmpeg4` is a third-party build with libheif support compiled in — Ubuntu's own archive ffmpeg isn't built with `--enable-libheif`. A statically-linked ffmpeg build was considered as an alternative but not pursued, to stay consistent with this module's existing apt/PPA-based provisioning style (the same tradeoff Cockpit/Alloy already makes for Grafana's repo).

The field's description carries this caveat directly, since it's the only documentation surface a caller sees — `README.md`'s input table is regenerated from it by `module-docs.yml`.

**Versioning**: purely additive; every existing caller is unaffected by the default. `release:minor`, **v5.6.1 → v5.7.0**.

### 2. `pigeon-cluster`: re-pin + per-job passthrough

New optional field on `jobs`:

```hcl
enable_heic_transcoding = optional(bool, false)
```

Wired into `module "job"`'s `instance_config` block as `enable_heic_transcoding = each.value.enable_heic_transcoding`. `module "bastion"` gets nothing — it never runs transforms, only debug SSH.

Both `compute-instance` source pins (`cluster.tf:153` and `cluster.tf:214`) move from `v5.6.1` to `v5.7.0`.

**Versioning**: additive — the new `jobs[*]` field defaults to today's behavior, and the re-pin itself changes no interface. `release:minor`, **v1.2.0 → v1.3.0**. The disabled consumer leaf needs no change to keep working; actually re-enabling it and setting `enable_heic_transcoding = true` on a real job is left to the user, same as ADR-0149's own minor bump.

### 3. Two sequential PRs

Per the `release-pr` skill and the ADR-0136 precedent for splitting module-tag-cutting work: the `compute-instance` change merges and tags first, since `pigeon-cluster`'s new source URL (`.../compute-instance/v5.7.0`) only resolves once that tag exists. `pigeon-cluster`'s re-pin and passthrough field land in a second PR.

## Consequences

- Any `pigeon-cluster` job can opt into HEIC-capable ffmpeg with one field; every other caller of either module is unaffected by default.
- `enable_heic_transcoding = true` adds a third-party PPA to the instance — an added update/trust surface beyond Ubuntu's own archive, accepted as the simplest apt-based route to a libheif-enabled ffmpeg build.

## Out of scope

- Verifying live that `ppa:savoury1/ffmpeg4` currently publishes a Jammy build with `--enable-libheif` — taken as given; the first real `terragrunt apply` with the flag set is the actual test.
- A static-ffmpeg-build alternative — not pursued, for consistency with this module's existing provisioning style.
- Whether `pigeon-cli`'s own `transform` code path works end-to-end once ffmpeg is present — that binary lives in the separate `noisypigeon/pigeon-cli` repo, not verifiable from here.
- Re-enabling the commented-out consumer leaf or flipping `enable_heic_transcoding = true` on any real job — left to the user.
