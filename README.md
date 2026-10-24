# library

Reusable, versioned building blocks for the `noisypigeon` family: Terraform
modules, a Zola theme, a Terragrunt `root.hcl` template, and the shared CI that
releases and deploys them.

This repo is the **hub**. It holds what other repos reuse and nothing that is
deployed — no site, no Terraform state, no secrets. The repos that consume it
(`garden`, `noisypigeon.com`, `runway`, and what is left of
`noisypigeon`) are spokes: content plus the
infrastructure that serves it, each pinning a version of what it takes from
here. The full argument is
[LIB-0001](docs/adr/LIB-0001-composable-hub-and-spoke-repo-architecture.md).

## What's here

| Path | What | Tagged |
| --- | --- | --- |
| [`terraform/`](terraform) | Terraform modules (Scaleway, Cloudflare, Backblaze, Grafana) | `terraform/<provider>/<module>/vX.Y.Z` |
| [`zola-site/`](zola-site) | a reusable Zola theme | `zola-site/vX.Y.Z` |
| [`terragrunt/root-hcl/`](terragrunt/root-hcl) | the spokes' Terragrunt `root.hcl` template | `terragrunt/root-hcl/vX.Y.Z` |
| `grafana-dashboards/<set>/` | versioned Grafana dashboard JSON, fetched by tag URL | `grafana-dashboards/<set>/vX.Y.Z` |
| `.github/workflows/` | the reusable CI the spokes call | `workflows/vX.Y.Z` |

Plus two scripts a consuming site runs at build time:
[`zola-site/resolve-theme.sh`](zola-site/resolve-theme.sh) (materializes the
theme version a site pins) and
[`.github/scripts/generate-module-redirects.sh`](.github/scripts/generate-module-redirects.sh) (generates
`noisypigeon.garden`'s module pages and release posts from this repo's tags and
changelogs). Both resolve their own location rather than asking git, so they
work wherever a site fetched them to.

## Consuming a module

Pin the short URL, not this repo:

```hcl
module "state_bucket" {
  source = "https://noisypigeon.garden/terraform/scaleway/bucket/v5.0.0"
  ...
}
```

`terraform init` resolves it through go-getter's HTTP discovery protocol to a
tagged `git::` source here. The public namespace is `modules/...`, **not**
`terraform/...` — it is a stable public interface, deliberately decoupled from
this repo's internal layout. That decoupling is why flattening these
directories, and re-cutting all 53 tags, changed no consumer's `source =` line.

See [`terraform/README.md`](terraform/README.md) for the full contract,
including the equivalent hand-written `git::` form and how to iterate locally
against an unreleased change.

## Consuming the theme

A site sets `theme = "zola-site"` and `[extra].theme_version` in its
`config.toml`, fetches this repo, and runs
[`zola-site/resolve-theme.sh`](zola-site/resolve-theme.sh) before building. See
[`zola-site/README.md`](zola-site/README.md).

## Releasing

Every change ships through a labelled PR — the PR body becomes the changelog
entry and GitHub Release notes verbatim, and the `release:*` label drives the
version bump. See
[`.claude/skills/release-pr/SKILL.md`](.claude/skills/release-pr/SKILL.md),
which is the discipline; `.github/workflows/template-release.yml` is the
automation that acts on it.

Every merged PR also adds one line to the root [`CHANGELOG.md`](CHANGELOG.md).
Per-module and theme `CHANGELOG.md` files carry the full, versioned entries.

## Decision records

The family's ADRs live in [`docs/adr/`](docs/adr), as `LIB-NNNN-<slug>.md`.
The spokes (garden and runway) have none of their own, because they
depend on this repo for their design standards
([LIB-0017](docs/adr/LIB-0017-spokes-do-not-get-their-own-adrs.md)). The older
`DEV-` records are archived verbatim in [`docs/adr/archive/`](docs/adr/archive),
and the `COM-` and `RUN-` records (`NPC-` is an alias for `COM-`) are amendments
on the `LIB-` records they applied. `pigeon-cli` keeps its own ADRs, as `CLI-` records in its `adr/`.
