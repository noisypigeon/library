# LIB-0019: A reusable workflow publishes a spoke's container image

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Accepted.

## Context

pigeon-cli ships a `Dockerfile` (its CLI-0087, CLI-0155) that bundles every
external binary its jobs call: `rclone`, `ffmpeg`, LibreOffice, Calibre,
pandoc and Ghostscript. Nobody publishes the image. Anyone who wants it builds
it locally, for `linux/arm64` only, from whatever commit they have checked out.
So no image corresponds to a released `vX.Y.Z`.

pigeon-cli's CLI-0161 moved its release pipeline into the hub as
`rust-crate-release.yml`. LIB-0001 puts reusable machinery here, so the
publishing mechanics come here too. The Dockerfile describes what
pigeon-cli needs, so it stays in pigeon-cli, as the crate's own build does.

## Decision

### 1. A separate reusable workflow, `container-image-release.yml`

The workflow is new and standalone, not a job added to `rust-crate-release.yml`:

- Nothing about building and publishing an image is Rust-specific. A spoke
  without a crate can call it.
- A caller sequences it after its own release, with `needs:`. The `version`
  it publishes therefore names a tag that already exists, and the image is
  built from that tag rather than from whatever `main` holds by then.

It is on the `workflows/vX.Y.Z` track like every other reusable workflow.

### 2. The spoke owns what the image is; the hub owns how it ships

The caller passes:

- the Dockerfile and build context
- the image name (by default `ghcr.io/<owner>/<repo>`, lowercased)
- build arguments
- the platform matrix
- a **smoke test**

The hub decides how those are built, checked, tagged and attested.

The smoke test is a shell snippet run inside each platform's image, with
its entrypoint overridden, **before anything is pushed**. Only the spoke knows
which binaries its image must contain, so only the spoke can write that check.
Running it before the push means a broken image never reaches the registry.

### 3. Native per-platform builds, one multi-arch tag set

Each `{runner, platform}` entry builds on its own native runner. By default
that is `ubuntu-24.04-arm` for `linux/arm64` and `ubuntu-24.04` for
`linux/amd64`.

Each platform's image is pushed by digest only, with a per-platform
GitHub Actions layer cache. A final job joins the digests into one index
and tags it with:

- `X.Y.Z`
- `X.Y`
- `latest`, unless the caller turns it off

QEMU was rejected: an emulated Rust release build is slow enough to dominate
the run.

### 4. GHCR, with build provenance

Images go to `ghcr.io` and are pushed with the caller's `github.token`. No new
secret and no registry infrastructure is needed. OCI labels record the
source, revision, version and licence. The `source` label is also what links
the package to its repository.

The index gets an `actions/attest-build-provenance` attestation pushed beside
it, so a consumer can check it with `gh attestation verify`.

The caller must grant `contents: read`, `packages: write`, `id-token: write`
and `attestations: write` on the calling job.

## Consequences

- A release of a calling spoke now also produces a published, multi-arch,
  attested image at the released version. The first caller is pigeon-cli
  (its CLI-0163).
- A new package's visibility starts private on GHCR. Making it public is a
  one-time manual step per package, in the package's settings.
- The `merge` job needs both platforms to succeed. A single failed
  platform publishes nothing, rather than a tag missing an architecture.
- `workflows/v3.4.0` is a minor release: purely additive, no existing
  caller changes.

## Out of scope

- **Mirroring to Scaleway's registry.** Its instances could pull from
  `rg.fr-par.scw.cloud` rather than GHCR. Deferred until something deployed
  actually runs the image.
- **Signing with cosign.** Provenance attestation covers today's need,
  which is "was this built by this repo's workflow". Signing would add a
  verification path consumers don't use yet.
