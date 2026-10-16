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
- `grafana-dashboards/<set>` — a released version of a Grafana dashboard set
- `terraform` — a `terraform/` change that releases nothing (e.g. a README)
- `terragrunt` — a `terragrunt/` change that releases nothing
- `grafana-dashboards` — a `grafana-dashboards/` change that releases nothing (e.g. a README)
- `adr` — decision records under `docs/adr/`
- `ci` — `.github/` workflows and scripts
- `repo` — anything else (root docs, `.mise.toml`, tooling)

The first five are written by `template-release.yml` as part of tagging a
release; the rest by `root-changelog.yml`, which runs on every merged PR and
stands down when `template-release.yml` owns the entry. Both go through
`.github/scripts/root-changelog.sh`, which inserts below the marker at the end
of this header — keep that line where it is.

This file starts at this repo's own beginning. Entries predating LIB-0002,
which created this repo from `noisypigeon/pigeon.dev`, stayed in that repo's
root `CHANGELOG.md` rather than being untangled from it — the same call
ADR-0154 and ADR-0084 each made before it.

<!-- entries below; newest first -->

## 2026-10-16

- [adr] Add a runbook for restoring Terraform state from B2, and bring LIB-0007 up to date ([#46](https://github.com/noisypigeon/pigeon-lib/pull/46))
- [workflows] Fix state-backup.yml: compare state files by checksum ([#45](https://github.com/noisypigeon/pigeon-lib/pull/45))
- [workflows] Fix state-backup.yml: reach B2 through its S3-compatible API ([#44](https://github.com/noisypigeon/pigeon-lib/pull/44))

## 2026-10-15

- [adr] LIB-0007: state-backup.yml is workflows/v1.5.0 ([#43](https://github.com/noisypigeon/pigeon-lib/pull/43))
- [ci] Correct state-backup.yml's version to workflows/v1.5.0 in LIB-0007 and the changelog ([#42](https://github.com/noisypigeon/pigeon-lib/pull/42))
- [workflows] Stop terragrunt-run.yml running a leaf twice ([#41](https://github.com/noisypigeon/pigeon-lib/pull/41))
- [workflows] Add state-backup.yml: copy R2 Terraform state to a versioned B2 bucket (LIB-0007) ([#40](https://github.com/noisypigeon/pigeon-lib/pull/40))
- [terragrunt/root-hcl] State backend selectable in spoke.hcl: Scaleway or Cloudflare R2 (LIB-0007) ([#39](https://github.com/noisypigeon/pigeon-lib/pull/39))
- [workflows] Regenerate README tables for every module, not a hard-coded list ([#38](https://github.com/noisypigeon/pigeon-lib/pull/38))
- [cloudflare/bucket] Make cloudflare/bucket EU-only, with Standard storage by default (LIB-0006) ([#37](https://github.com/noisypigeon/pigeon-lib/pull/37))
- [terragrunt/root-hcl] Providers enabled and configured in spoke.hcl (LIB-0005) ([#36](https://github.com/noisypigeon/pigeon-lib/pull/36))
- [grafana/dashboard] Move scaleway/grafana-dashboard to grafana/dashboard ([#35](https://github.com/noisypigeon/pigeon-lib/pull/35))
- [cloudflare/bucket] Add cloudflare/bucket, a thin R2 bucket wrapper ([#34](https://github.com/noisypigeon/pigeon-lib/pull/34))
- [adr] Record willowgraysen.com's LIB-0004 adoption and the first leaf splits ([#33](https://github.com/noisypigeon/pigeon-lib/pull/33))
- [terragrunt/root-hcl] A latent Scaleway Cockpit Grafana provider in the root.hcl template ([#32](https://github.com/noisypigeon/pigeon-lib/pull/32))
- [scaleway/grafana-dashboard] grafana-dashboard: dashboards by URL, and an optional first-access hook ([#31](https://github.com/noisypigeon/pigeon-lib/pull/31))
- [cloudflare/ruleset] Add cloudflare/ruleset, a thin wrapper over cloudflare_ruleset ([#30](https://github.com/noisypigeon/pigeon-lib/pull/30))
- [grafana-dashboards/pigeon-cli] Add the pigeon-cli Grafana dashboard set ([#29](https://github.com/noisypigeon/pigeon-lib/pull/29))
- [workflows] Add a grafana-dashboards/<set>/vX.Y.Z release track ([#28](https://github.com/noisypigeon/pigeon-lib/pull/28))
- [adr] docs(lib-0004): record noisypigeon.com's adoption ([#27](https://github.com/noisypigeon/pigeon-lib/pull/27))
- [adr] docs(lib-0004): record pigeon.dev's adoption and link the fast follows ([#26](https://github.com/noisypigeon/pigeon-lib/pull/26))
- [workflows] Generate README tables for cloudflare/dns-record ([#25](https://github.com/noisypigeon/pigeon-lib/pull/25))
- [cloudflare/dns-record] Add cloudflare/dns-record, a thin wrapper over cloudflare_dns_record ([#24](https://github.com/noisypigeon/pigeon-lib/pull/24))
- [adr] docs(lib-0004): normalize the Terraform leaf layout ([#23](https://github.com/noisypigeon/pigeon-lib/pull/23))
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
