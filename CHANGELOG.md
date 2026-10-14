# Changelog

One line per PR across this whole repo, sectioned by date, newest first. Every
merged PR gets exactly one line here; a PR that changes a releasable unit
additionally gets its full PR body in that unit's own `CHANGELOG.md`. PD-0160 is
the contract, inherited with the automation when LIB-0002 moved it here.

Not versioned — for versioned, package-scoped changelogs see
`terraform/*/*/CHANGELOG.md` (each Terraform module) and
[`zola-site/CHANGELOG.md`](zola-site/CHANGELOG.md) (the theme). Those files
predate this repo: they travelled with their modules through every move since
`pigeon-tf`, so their older entries cite paths and PR numbers from repos this
one never was. That is deliberate — rewriting published release notes to match
a later layout would be a worse lie than a stale path.

Entry format is `- [<tag>] <PR title> ([#N](pr-url))`, where `<tag>` is one of:

- `<provider>/<module>` — a released Terraform module
- `zola-site` — a released theme version
- `workflows` — a released version of the reusable CI
- `terraform` — a `terraform/` change that releases nothing (e.g. a README)
- `adr` — decision records under `docs/adr/`
- `ci` — `.github/` workflows and scripts
- `repo` — anything else (root docs, `.mise.toml`, tooling)

The first three are written by `template-release.yml` as part of tagging a
release; the rest by `root-changelog.yml`, which runs on every merged PR and
stands down when `template-release.yml` owns the entry. Both go through
`.github/scripts/root-changelog.sh`, which inserts below the marker at the end
of this header — keep that line where it is.

This file starts at this repo's own beginning. Entries predating LIB-0002,
which created this repo from `noisypigeon/pigeon.dev`, stayed in that repo's
root `CHANGELOG.md` rather than being untangled from it — the same call
ADR-0154 and ADR-0084 each made before it.

<!-- entries below; newest first -->

## 2026-10-13

- [workflows] Version the generator with the workflows track ([#5](https://github.com/noisypigeon/pigeon-lib/pull/5))
- [adr] Host the module-redirect generator, and file LIB-0002 ([#4](https://github.com/noisypigeon/pigeon-lib/pull/4))
- [workflows] Stand down root-changelog for the workflows release track ([#3](https://github.com/noisypigeon/pigeon-lib/pull/3))
- [ci] Version the reusable CI as a third release track ([#2](https://github.com/noisypigeon/pigeon-lib/pull/2))
- [repo] Give pigeon-lib its CLAUDE.md, README.md, CHANGELOG.md, .mise.toml and .gitignore ([#1](https://github.com/noisypigeon/pigeon-lib/pull/1))
