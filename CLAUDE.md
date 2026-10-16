# CLAUDE.md

This is `pigeon-lib`, the **hub** of the hub-and-spoke architecture LIB-0001
defines. It holds everything in this family that is reusable and versioned, and
nothing that is deployed:

- `terraform/<provider>/<module>/` — Terraform modules (Scaleway, Cloudflare, Backblaze, Grafana),
  tagged `terraform/<provider>/<module>/vX.Y.Z`, each self-contained (own
  `versions.tf`, `README.md`, `CHANGELOG.md`). Consumed via short
  `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` URLs that resolve through
  go-getter's HTTP discovery protocol to a `git::` source against this repo.
  **The public URL path is `modules/…`, not `terraform/…`** — that namespace is a
  stable public interface, deliberately decoupled from internal layout
  (ADR-0109/0110), which is what let LIB-0002 flatten this repo's roots without
  touching a single consumer `source =` line.
- `zola-site/` — a reusable Zola theme, tagged `zola-site/vX.Y.Z`, consumed by a
  site setting `[extra].theme_version` and running `resolve-theme.sh`.
  That script resolves everything relative to its **own** location rather than
  asking git, so it works wherever the consuming site fetched it to (ADR-0154).
- `terragrunt/root-hcl/` — the spokes' `root.hcl` template, tagged
  `terragrunt/root-hcl/vX.Y.Z` (LIB-0003). `.github/scripts/resolve-root-hcl.sh`
  copies it to a spoke's root at the version the spoke's `spoke.hcl` pins, and
  the template reads the spoke's instance values (its state-bucket secret name,
  and the `providers` map that turns each provider on, LIB-0005) back out of
  `spoke.hcl`. The spoke **commits** that generated copy, because
  Terragrunt's git filter plans inside worktrees where only tracked files exist,
  and its CI runs the script with `--check` to fail on drift. Copied, never
  symlinked or included, because a leaf's state key is relative to `root.hcl`'s
  own directory (LIB-0001 invariant 4).
- `grafana-dashboards/<set>/` — versioned Grafana dashboard JSON, tagged
  `grafana-dashboards/<set>/vX.Y.Z` per set. Consumers fetch a dashboard by its
  tag's raw URL (`raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/<tag>/<path>`),
  which is what `grafana/dashboard`'s `url` input does, so the same
  pinned file can feed both Terraform and anything else that ships it.
- `.github/workflows/` — the reusable CI the spokes call, tagged
  `workflows/vX.Y.Z`. Reusable workflows must live in `.github/workflows/`, so
  they sit beside this repo's own release automation rather than under a
  templates convention (DEV-0155).
- `.github/scripts/root-changelog.sh` — the one implementation of DEV-0160's
  root-changelog contract, used by this repo and fetched by the spokes.
- `.github/scripts/generate-module-redirects.sh` — generates the `pigeon.dev` site's module
  redirect pages, overview pages, theme-version pages and release posts from
  this repo's tags, READMEs and CHANGELOGs. Runs in a *consuming* site's build,
  so it reads two roots: `LIB_ROOT`, derived from `${BASH_SOURCE[0]}` so it
  finds the clone it was fetched into rather than the site's repo, and
  `--content-root`, which only the caller knows.

These scripts, and `resolve-root-hcl.sh`, live under `.github/scripts/` so the
`workflows/vX.Y.Z` track covers them: a spoke pins one version and gets the
reusable workflows and every script at that version, which is what invariant 2
asks for.

See `README.md` for the consumption contract and `terraform/README.md` for the
module index.

## This repo hosts nothing

There is no site, no Terraform state, no live `root.hcl` (only the template the spokes copy) and no secrets here. The
practical consequence: **every deploy dispatch is cross-repo.** A module release
dispatches `pigeon-dev-pages.yml` in `noisypigeon/pigeon.dev`; a theme release
additionally dispatches `noisypigeon-com-pages.yml` in
`noisypigeon/noisypigeon.com`. Both need `BOT_GITHUB_TOKEN` to carry
`actions: write` on the target, and both fail loudly if it does not — the
symptom otherwise is a tagged, released version whose short URL 404s.

`pigeon-dev-pages.yml` deliberately does **not** live here: `actions/deploy-pages`
always targets the calling repo's own Pages site, so that caller has to live in
the repo whose site it deploys (DEV-0156 — a constraint, not a style choice).

## Where the decisions live

ADRs for this repo live at `docs/adr/LIB-NNNN-<slug>.md`, numbered from `0001`
within that directory. `LIB-0001` defines the architecture; `LIB-0002` created
this repo. Sibling domains live in their own repos, flat in each one's `adr/`:
`DEV-` in `noisypigeon/pigeon.dev`, `COM-` in `noisypigeon/noisypigeon.com`, and
`RUN-` in `noisypigeon/willowgraysen`; `pigeon-cli` keeps its own unprefixed
`docs/adr/`.

Filing one, by hand:

- **Number**: max+1 within `docs/adr/`.
- **Filename and H1 agree**: `LIB-0002-<slug>.md` holds `# LIB-0002: <title>`.
- **Author is always** `Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).`
- **Sections**: `## Context` / `## Decision` / `## Consequences` /
  `## Out of scope`, optionally then `## Verification`. No YAML frontmatter and
  no index — there isn't one.
- Cite `LIB-NNNN` for this domain and `DEV-NNNN`/`COM-NNNN`/`RUN-NNNN` for the others (`NPC-NNNN` in older prose is an alias for `COM-`).
  Bare `ADR-NNNN` in older prose means the `DEV-` corpus (DEV-0160 grandfathered
  those citations).
- Genuinely-deferred `## Out of scope` items get a GitHub issue against
  `noisypigeon/noisypigeon` (ADR-0031); permanent design boundaries do not.

## Runbooks

Operational procedures live at `docs/runbooks/<slug>.md`: step-by-step, for
any spoke, citing the ADR they serve. Today there's one,
`restore-terraform-state-from-b2.md` (LIB-0007 §4). It puts one leaf's state
back into R2 from the B2 backup, through B2's native API with an admin key.

## Dev cycle

Every change ships through a labelled PR — see the `release-pr` skill, which is
the discipline, not just a convenience. The PR body becomes the changed unit's
`CHANGELOG.md` entry and GitHub Release notes **verbatim**, and exactly one
`release:*` label drives the version bump. There is no human reviewer and no
branch protection.

Five releasable units, each its own tag track: a Terraform module
(`terraform/<provider>/<module>/vX.Y.Z`), the theme (`zola-site/vX.Y.Z`), the
reusable CI (`workflows/vX.Y.Z`), the `root.hcl` template
(`terragrunt/root-hcl/vX.Y.Z`), and a Grafana dashboard set
(`grafana-dashboards/<set>/vX.Y.Z`, first version `1.0.0`). `template-release.yml` detects which changed,
bumps it, writes its `CHANGELOG.md` and the root rollup line, cuts the tag and
the GitHub Release, then dispatches the affected spokes. **A spoke never writes
a tag** — that follows from the hub owning every script, and from go-getter
needing a ref in the repo whose tree it resolves to.

Detection is by path, and the predicates are narrow on purpose: a module
release needs a changed `.tf` under `terraform/<provider>/<module>/`, and a
theme release needs a change under `zola-site/templates/`, `zola-site/static/`
or `zola-site/theme.toml`, a CI release a change to `.github/workflows/*.yml` or
`.github/scripts/`, and a template release a change to
`terragrunt/root-hcl/root.hcl`, and a dashboard release a changed
`grafana-dashboards/<set>/*.json`. A README- or CHANGELOG-only change releases
nothing. `root-changelog.yml` duplicates all five predicates to stand down for a
releasing PR — change one and you must change its twin (#301).

Every merged PR also gets exactly one line in the root `CHANGELOG.md`, under a
`## YYYY-MM-DD` section, newest first (DEV-0160). The
`<!-- entries below; newest first -->` marker is where entries get inserted —
`root-changelog.sh` refuses to write without it.

## Commands

- `mise run fmt-terraform` / `mise run fmt-check-terraform` — format / check
  formatting for Terraform files.

There is no build or serve task: this repo publishes a theme but renders no
site.
