# CLAUDE.md

This is `pigeon-lib`, the **hub** of the hub-and-spoke architecture LIB-0001
defines. It holds everything in this family that is reusable and versioned, and
nothing that is deployed:

- `terraform/<provider>/<module>/` — 13 Terraform modules (Scaleway, Backblaze),
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

Both scripts live under `.github/scripts/` so the `workflows/vX.Y.Z` track
covers them: a spoke pins one version and gets the reusable workflows and both
scripts at that version, which is what invariant 2 asks for.

See `README.md` for the consumption contract and `terraform/README.md` for the
module index.

## This repo hosts nothing

There is no site, no Terraform state, no `root.hcl` and no secrets here. The
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
this repo. Sibling domains live in their own repos — `pigeon-cli/docs/adr/`, and
for now `noisypigeon/pigeon.dev`'s `adr/pigeon.dev/` and `adr/noisypigeon.com/`,
whose dispersal LIB-0001 left to each repo's own migration.

Filing one, by hand:

- **Number**: max+1 within `docs/adr/`.
- **Filename and H1 agree**: `LIB-0002-<slug>.md` holds `# LIB-0002: <title>`.
- **Author is always** `Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).`
- **Sections**: `## Context` / `## Decision` / `## Consequences` /
  `## Out of scope`, optionally then `## Verification`. No YAML frontmatter and
  no index — there isn't one.
- Cite `LIB-NNNN` for this domain and `DEV-NNNN`/`NPC-NNNN` for the others.
  Bare `ADR-NNNN` in older prose means the `DEV-` corpus (DEV-0160 grandfathered
  those citations).
- Genuinely-deferred `## Out of scope` items get a GitHub issue against
  `noisypigeon/noisypigeon` (ADR-0031); permanent design boundaries do not.

## Dev cycle

Every change ships through a labelled PR — see the `release-pr` skill, which is
the discipline, not just a convenience. The PR body becomes the changed unit's
`CHANGELOG.md` entry and GitHub Release notes **verbatim**, and exactly one
`release:*` label drives the version bump. There is no human reviewer and no
branch protection.

Three releasable units, each its own tag track: a Terraform module
(`terraform/<provider>/<module>/vX.Y.Z`), the theme (`zola-site/vX.Y.Z`), and the
reusable CI (`workflows/vX.Y.Z`). `template-release.yml` detects which changed,
bumps it, writes its `CHANGELOG.md` and the root rollup line, cuts the tag and
the GitHub Release, then dispatches the affected spokes. **A spoke never writes
a tag** — that follows from the hub owning every script, and from go-getter
needing a ref in the repo whose tree it resolves to.

Detection is by path, and the predicates are narrow on purpose: a module
release needs a changed `.tf` under `terraform/<provider>/<module>/`, and a
theme release needs a change under `zola-site/templates/`, `zola-site/static/`
or `zola-site/theme.toml`. A README- or CHANGELOG-only change releases nothing.

Every merged PR also gets exactly one line in the root `CHANGELOG.md`, under a
`## YYYY-MM-DD` section, newest first (DEV-0160). The
`<!-- entries below; newest first -->` marker is where entries get inserted —
`root-changelog.sh` refuses to write without it.

## Commands

- `mise run fmt-terraform` / `mise run fmt-check-terraform` — format / check
  formatting for Terraform files.

There is no build or serve task: this repo publishes a theme but renders no
site.
