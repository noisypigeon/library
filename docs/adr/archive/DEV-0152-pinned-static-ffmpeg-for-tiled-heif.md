# DEV-0152: Pinned static ffmpeg on `compute-instance`, for tiled HEIF

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-10.
- **Status**: Accepted.

## Context

A `pigeon-cli transform --input-file-type=heic` run failed on one file (`LG - 504.HEIC`) while
eight other `.heic` files in the same batch converted fine. `ffprobe` explains the asymmetry: the
failing file is a **grid-tiled HEIF** — 48 separate 512x512 HEVC tile streams plus a thumbnail,
reassembled through HEIF's grid derived-image mechanism — while the eight that worked are simple
single-frame HEICs. Large phone-camera photos are commonly encoded this way. The file is not
corrupt, and this is not a `pigeon-cli` bug; it is an ffmpeg capability gap on the job VM, which
this repo provisions.

Investigating that gap found ADR-0150's provisioning further from working than its own record
suggests, on three counts.

**1. The capability is version-gated, not build-flag-gated.** ADR-0150 reached for
`ppa:savoury1/ffmpeg4` on the stated grounds that Ubuntu's archive build "isn't compiled with
`--enable-libheif`". There is no such ffmpeg configure option. ffmpeg decodes HEIC natively, via
its HEIF demuxer plus the HEVC decoder — libheif is not in the picture at all. What actually
gates grid-tile reconstruction is the ffmpeg *version*: `- ffmpeg CLI tiled HEIF support` appears
under `version 8.1:` in FFmpeg's own `Changelog`, and nowhere earlier.

**2. The failure mode below 8.1 is silent, not loud.** ADR-0150 and ADR-0151 both describe the
no-ffmpeg case as failing fast with ffmpeg's "decoder not found" error. For a tiled file on a
pre-8.1 ffmpeg that is not what happens: with no grid support, ffmpeg picks the first video
stream — one 512x512 tile — writes it, and exits 0. A job checking only exit status sees success
and silently produces cropped output.

**3. `ppa:savoury1/ffmpeg4` installs ffmpeg 4.4.8**, four major versions below the floor, so the
`enable_transcoding` flag as shipped could never have decoded this file. ADR-0150 left "verify
the PPA live" as an explicit Out-of-scope caveat and ADR-0151 restated it; nothing had exercised
it until now.

The obvious repairs were checked and both fail:

- **Bump the PPA.** `ppa:savoury1/ffmpeg8` does publish 8.1.3 for Jammy. But every savoury1
  ffmpeg PPA above `ffmpeg4` — `ffmpeg6`, `ffmpeg7`, `ffmpeg8`, `ffmpeg9` — carries the same
  notice: *"FFmpeg builds here need the private PPA to successfully install!"*, that private PPA
  (`ppa:savoury1/ffmpeg`) being granted to donors on request. Unattended cloud-init cannot
  authenticate to it. `ffmpeg4` being the one self-sufficient PPA in the set is very likely why
  ADR-0150 landed on it.
- **Bump the base image.** No Ubuntu archive reaches 8.1: Jammy ships 4.4.2, Noble 6.1.1, and
  Resolute (26.04 LTS) 8.0.1. `ubuntu_resolute` *is* available on Scaleway — confirmed against
  the marketplace API, present in both `fr-par` and `nl-ams` and compatible with the `PRO2-*` and
  `POP2-*` types these jobs use — so this looks like the clean fix right up until the version is
  checked. 8.0.1 is one minor release short. Recorded here so the option is not re-litigated.

That leaves the static build ADR-0150 considered and declined for consistency with the module's
apt-based provisioning style. With both apt routes now closed, that consistency argument no
longer has anything to be consistent with.

Current released versions: `compute-instance` `v6.0.0` and `pigeon-cluster` `v2.0.0`.

## Decision

### 1. `compute-instance`: `enable_transcoding` installs a pinned static ffmpeg

`instance_config.enable_transcoding` keeps its name, its type, its `false` default, and its
position in `runcmd` (after the `pigeon-cli` gist bootstrap, before the Cockpit/Alloy block).
Only what it installs changes — the PPA block at `instance.tf:327-336` becomes:

```yaml
      - curl -fsSL -o /tmp/ffmpeg.tar.xz https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-10-10-13-04/ffmpeg-n9.0.2-25-g67b60c310b-linux64-gpl-9.0.tar.xz
      - echo '7e898ca0a18e8620c0caa9af9a728bc01be006398dd5db5a99d53f14de010a9a  /tmp/ffmpeg.tar.xz' | sha256sum -c -
      - mkdir -p /tmp/ffmpeg
      - tar -xJf /tmp/ffmpeg.tar.xz -C /tmp/ffmpeg --strip-components=1
      - install -m 0755 /tmp/ffmpeg/bin/ffmpeg /tmp/ffmpeg/bin/ffprobe /usr/local/bin/
      - rm -rf /tmp/ffmpeg /tmp/ffmpeg.tar.xz
      - /usr/local/bin/ffmpeg -version
```

`xz-utils` is added to the `packages:` block under the same `enable_transcoding` guard, following
the existing `self_delete_on_exit` → `jq` precedent, rather than unconditionally — an
unconditional entry would change the rendered cloud-init for every caller and so replace every
instance.

Choices worth stating:

- **9.0.2, not 8.1.** 8.1 is the floor; 9.0 is the current stable branch and clears it with room,
  which matters for a pin that will sit unattended.
- **An immutable `autobuild-*` tag with its published sha256**, not BtbN's rolling
  `ffmpeg-n9.0-latest-...` asset. `terraform_data.cloud_init` holds `md5(local.cloud_init)` as a
  `replace_triggered_by`, so the rendered script is already treated as part of the instance's
  identity; a URL whose bytes change underneath that hash would be exactly the kind of
  unversioned drift this repo avoids elsewhere. The cost is that moving ffmpeg forward needs a
  module release.
- **BtbN's builds over johnvansickle's**, whose newest release build is 7.0.2 — below the floor.
  BtbN targets glibc >= 2.28 and Jammy ships 2.35.
- **`install` into `/usr/local/bin`**, which is on systemd's default unit `PATH`, so ADR-0125's
  `pigeon-post-provision.service` resolves the new binary with no unit change. Only `ffmpeg` and
  `ffprobe` are installed; `ffplay` and the tarball's `doc/`, `include/` and `lib/` trees are
  discarded with the extraction directory.
- **`sha256sum -c -` before extracting**, so a tampered or truncated download fails the step
  rather than installing. Combined with `-fsSL`, a fetch or integrity failure surfaces in
  `cloud-init-output.log` instead of silently leaving no ffmpeg behind.

The `instance_config` description is rewritten to state the pinned version, the 8.1 floor and why
it exists, the silent single-tile failure below it, and that the pinned artifact is an x86_64
(`linux64`) binary — so the flag must not be set alongside an arm64 `instance_config.type` such
as `COPARM1-*`. That description is the only documentation surface a caller sees, since
`README.md`'s input table is regenerated from it by `module-docs.yml`. ADR-0150's
`--enable-libheif` claim is deleted rather than reworded.

**Versioning**: the interface is untouched and every existing caller is unaffected by the `false`
default, so this is not breaking. But it is more than an internal fix — the flag swaps ffmpeg
4.4.8 for 9.0.2, a four-major-version jump in a general-purpose tool. `release:minor`,
**v6.0.0 → v6.1.0**.

### 2. `pigeon-cluster`: re-pin only

Both `compute-instance` sources — `cluster.tf:153` (`module "job"`) and `cluster.tf:215`
(`module "bastion"`) — move from `v6.0.0` to `v6.1.0`. Nothing else changes:
`jobs[*].enable_transcoding` keeps its name and passthrough, and `module "bastion"` passes no
`instance_config` at all. `release:patch`, **v2.0.0 → v2.0.1**.

### 3. ADR-0150 is marked superseded

ADR-0150's gating design survives intact — an `instance_config` bool, defaulting off, rendering
an install step at that point in `runcmd`. What this ADR reverses is its actual decision: install
ffmpeg from `ppa:savoury1/ffmpeg4`, with a static build declined. Both halves of that are now
undone, and its stated rationale was mistaken, so its `Status` becomes
`Superseded by ADR-0152` rather than staying `Accepted` as it did through ADR-0151's rename.

ADR-0151 stays `Accepted`: its rename of `enable_heic_transcoding` to `enable_transcoding` is
untouched and reads *better* under this change, since the installed build is now unambiguously
general-purpose. Its own standing caveat — whether the PPA covers every codec a future transform
might need — is resolved by no longer using a PPA.

### 4. Two sequential PRs, and the leaf left alone

`template-release.yml` applies one bump level per PR, and a module's short source URL resolves
only once its tag exists:

1. `compute-instance` plus this ADR and ADR-0150's status edit — `release:minor`, cuts
   `compute-instance/v6.1.0`.
2. `pigeon-cluster`'s re-pin — `release:patch`, cuts `pigeon-cluster/v2.0.1`. Opens only after
   PR 1 has tagged.

The consumer leaf `workloads/willowgraysen.com/terraform/pigeon-cli/cluster/` is deliberately
excluded from both, on the same grounds ADR-0151 §5 used: its two `.tf` files carry substantial
unrelated in-flight work (the cluster being uncommented, bastion and private-network/public-gateway
toggles enabled, the `transform-heic-to-jpg` job added, `pigeon-cluster` already moving
`v1.2.0` → `v2.0.0`). Its re-pin to `v2.0.1` rides that branch rather than dragging it into a
module release PR.

## Consequences

- `release:minor` for `templates/terraform/scaleway/compute-instance` (v6.0.0 → v6.1.0) and
  `release:patch` for `templates/terraform/scaleway/pigeon-cluster` (v2.0.0 → v2.0.1). No caller
  has to change anything: both are interface-compatible, and `pigeon-cluster` is
  `compute-instance`'s only consumer.
- Any instance with `enable_transcoding = true` is replaced on next apply, since the rendered
  cloud-init changes and `terraform_data.cloud_init` triggers replacement on its hash. Harmless
  here — the only such instances are ephemeral job VMs, and there are none live today.
- Provisioning with the flag set now downloads ~151 MB and installs two ~100 MB static binaries,
  against a few MB of apt packages before. Acceptable one-time cost on a job VM, but it is real,
  and it makes boot depend on GitHub release downloads being reachable.
- The pin will go stale. It is a dated `autobuild-*` tag, so it stops receiving upstream fixes
  the day it lands and only moves when someone cuts a module release. This is the deliberate
  trade for reproducibility, not an oversight.
- The flag is now x86_64-only in a way it was not before. An apt install would have resolved the
  host's architecture; a pinned `linux64` tarball will not. Documented in the input description,
  not enforced, since `instance_config.type` would have to be parsed to tell.
- ADR-0150's record is now contradicted on a point of fact (`--enable-libheif`), not just
  superseded on a decision. Future readers reaching for that reasoning should find this ADR via
  its `Status` line.

## Out of scope

- Refreshing the pin as it ages. Genuinely deferred: nothing watches BtbN for new 9.0.x builds,
  and bumping it is a manual module release. ([#266](https://github.com/noisypigeon/noisypigeon/issues/266))
- Guarding `enable_transcoding` against an arm64 `instance_config.type`. Deferred: BtbN publishes
  a matching `linuxarm64-gpl` asset, so a second pin selected by architecture is possible, but no
  caller needs arm64 today and it would double the pins to maintain. ([#267](https://github.com/noisypigeon/noisypigeon/issues/267))
- Verifying that `pigeon-cli`'s own `transform` invokes ffmpeg in a way that benefits from
  automatic grid assembly — i.e. without an explicit `-map 0:v:0`, which re-selects a single tile
  even on 8.1+. That binary lives in `noisypigeon/pigeon-cli`, not verifiable from here, and is
  the one remaining way this file could still convert wrong after this change.
- Bumping `instance_config.image` off `ubuntu_jammy`. Not deferred — a static ffmpeg makes the
  base image irrelevant to this problem, and `ubuntu_resolute`'s 8.0.1 would not have solved it
  anyway.
- Hardening the other `curl | sh` provisioning steps (`mise.run`, the `pigeon.sh` gist, the
  Scaleway CLI installer) to the same checksum-verified standard this ADR applies to ffmpeg. A
  real inconsistency, but a separate decision.
