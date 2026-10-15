# Changelog

One line per PR across this whole repo, sectioned by date, newest first. Every
merged PR gets exactly one line here; a PR that changes a releasable unit
additionally gets its full PR body in that unit's own `CHANGELOG.md`. DEV-0160 is
the contract, inherited with the automation when LIB-0002 moved it here.

Not versioned — for versioned, package-scoped changelogs see
`terraform/*/*/CHANGELOG.md` (each Terraform module),
[`zola-site/CHANGELOG.md`](zola-site/CHANGELOG.md) (the theme),
[`terragrunt/root-hcl/CHANGELOG.md`](terragrunt/root-hcl/CHANGELOG.md) (the
`root.hcl` template) and
[`.github/workflows/CHANGELOG.md`](.github/workflows/CHANGELOG.md) (the
reusable CI). Those files
predate this repo: they travelled with their modules through every move since
`pigeon-tf`, so their older entries cite paths and PR numbers from repos this
one never was. That is deliberate — rewriting published release notes to match
a later layout would be a worse lie than a stale path.

Entry format is `- [<tag>] <PR title> ([#N](pr-url))`, where `<tag>` is one of:

- `<provider>/<module>` — a released Terraform module
- `zola-site` — a released theme version
- `workflows` — a released version of the reusable CI
- `terragrunt/root-hcl` — a released version of the spokes' `root.hcl` template
- `terraform` — a `terraform/` change that releases nothing (e.g. a README)
- `terragrunt` — a `terragrunt/` change that releases nothing
- `adr` — decision records under `docs/adr/`
- `ci` — `.github/` workflows and scripts
- `repo` — anything else (root docs, `.mise.toml`, tooling)

The first four are written by `template-release.yml` as part of tagging a
release; the rest by `root-changelog.yml`, which runs on every merged PR and
stands down when `template-release.yml` owns the entry. Both go through
`.github/scripts/root-changelog.sh`, which inserts below the marker at the end
of this header — keep that line where it is.

This file starts at this repo's own beginning. Entries predating LIB-0002,
which created this repo from `noisypigeon/pigeon.dev`, stayed in that repo's
root `CHANGELOG.md` rather than being untangled from it — the same call
ADR-0154 and ADR-0084 each made before it.

<!-- entries below; newest first -->

## 2026-10-15

- [adr] docs(lib-0001): record step 5's completion and the RUN- domain ([#22](https://github.com/noisypigeon/pigeon-lib/pull/22))
- [terragrunt/root-hcl] Optional extra providers and Backblaze support in the root.hcl template ([#21](https://github.com/noisypigeon/pigeon-lib/pull/21))
- [adr] docs(lib-0001): record step 4's completion in the amendments ([#20](https://github.com/noisypigeon/pigeon-lib/pull/20))
- [adr] docs(lib-0001): amend where the implementation deviated ([#19](https://github.com/noisypigeon/pigeon-lib/pull/19))
- [terragrunt/root-hcl] Mark the root.hcl template as generated and committed in spokes ([#18](https://github.com/noisypigeon/pigeon-lib/pull/18))
- [workflows] Add a --check mode to resolve-root-hcl.sh ([#17](https://github.com/noisypigeon/pigeon-lib/pull/17))
- [terragrunt/root-hcl] Add the spokes' Terragrunt root.hcl template ([#16](https://github.com/noisypigeon/pigeon-lib/pull/16))
- [workflows] Let a spoke run terragrunt CI against a materialized root.hcl ([#15](https://github.com/noisypigeon/pigeon-lib/pull/15))
- [workflows] Add a reusable spoke-root-changelog.yml ([#14](https://github.com/noisypigeon/pigeon-lib/pull/14))
- [workflows] Let blog-changelog.yml take a site root via src_dir ([#13](https://github.com/noisypigeon/pigeon-lib/pull/13))
- [workflows] Read release notes from the default branch, not the pinned tree ([#12](https://github.com/noisypigeon/pigeon-lib/pull/12))
- [scaleway/project] Note why the ssh key uses count, not for_each ([#11](https://github.com/noisypigeon/pigeon-lib/pull/11))
- [workflows] Stop the shared concurrency group dropping a release ([#10](https://github.com/noisypigeon/pigeon-lib/pull/10))
- [workflows] The Pages deploy timeout ceiling is hard, not a default ([#8](https://github.com/noisypigeon/pigeon-lib/pull/8))
- [workflows] Raise the Pages deploy timeout to 20 minutes ([#7](https://github.com/noisypigeon/pigeon-lib/pull/7))

## 2026-10-14

- [workflows] Follow pigeon.dev's DEV- prefix rename ([#6](https://github.com/noisypigeon/pigeon-lib/pull/6))

## 2026-10-13

- [workflows] Version the generator with the workflows track ([#5](https://github.com/noisypigeon/pigeon-lib/pull/5))
- [adr] Host the module-redirect generator, and file LIB-0002 ([#4](https://github.com/noisypigeon/pigeon-lib/pull/4))
- [workflows] Stand down root-changelog for the workflows release track ([#3](https://github.com/noisypigeon/pigeon-lib/pull/3))
- [ci] Version the reusable CI as a third release track ([#2](https://github.com/noisypigeon/pigeon-lib/pull/2))
- [repo] Give pigeon-lib its CLAUDE.md, README.md, CHANGELOG.md, .mise.toml and .gitignore ([#1](https://github.com/noisypigeon/pigeon-lib/pull/1))
