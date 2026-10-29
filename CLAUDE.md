# CLAUDE.md

This is `library`, the **hub** of the hub-and-spoke architecture LIB-0001
defines. It holds everything in this family that is reusable and versioned, and
nothing that is deployed:

- `terraform/<provider>/<module>/` — Terraform modules (Scaleway, Cloudflare, Backblaze, Grafana),
  tagged `terraform/<provider>/<module>/vX.Y.Z`, each self-contained (own
  `versions.tf`, `README.md`, `CHANGELOG.md`). Consumed via short
  `noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z` URLs that resolve
  through go-getter's HTTP discovery protocol to a `git::` source against this
  repo. **That URL is a stable public interface of its own** (LIB-0009): its
  `terraform/` matches this repo's prefix by choice, and moving the internal
  layout never changes it.
- `zola-site/` — a reusable Zola theme, tagged `zola-site/vX.Y.Z`, consumed by a
  site setting `[extra].theme_version` and running `resolve-theme.sh`.
  That script resolves everything relative to its **own** location rather than
  asking git, so it works wherever the consuming site fetched it to (ADR-0154).
- `terragrunt/root-hcl/` — the spokes' `root.hcl` template, tagged
  `terragrunt/root-hcl/vX.Y.Z` (LIB-0003). `.github/scripts/resolve-root-hcl.sh`
  copies it, with the `secrets-schema.json` it reads from beside itself, to a
  spoke's root at the version the spoke's `spoke.hcl` pins. The template reads
  the spoke's instance values back out of `spoke.hcl`: its `state_backend`, and
  the `providers` map that turns each provider on (LIB-0005), and its
  `state_backup`. Secrets have fixed names, the same in every spoke (LIB-0010),
  each in the one sops file for its concern under the spoke's
  `terraform/secrets/` (`terraform`, `cloudflare`, `scaleway`, `backblaze`,
  `env`; LIB-0012). Which files are required, and exactly which keys each
  holds, follows from those values; the schema says so, and both the template
  (per leaf, decrypting only the files that leaf needs) and
  `.github/scripts/check-secrets.sh` (spoke-wide, from key names alone)
  enforce it. A provider's entry may also set `breakglass = { leaves = [...] }`:
  only those leaves then read that provider's credentials, and the state
  backend's when it's the same provider, from
  `terraform/secrets/<provider>_breakglass.enc`, a hand-made key Terraform
  never manages (LIB-0014). Cloudflare's or Backblaze's entry may instead set
  `workloads_only = true` with `breakglass = {}`: no hand-written leaf turns
  it on, the spoke keeps no credentials of its own for it, and the breakglass
  key mints each unit's own token or key (LIB-0041). It also builds every unit leaf's module block:
  a workload's from `workloads/<w>/values.yaml`, and a zone's from
  `zones/<zone>/zone.yaml`, which names the one workload that may also write
  in that zone (LIB-0036; `.github/scripts/resolve-workloads.sh` generates
  both kinds of stub). Since LIB-0037 a workload may also live in its zone,
  as `workloads/<zone>/<w>/workload.yaml` (or `workloads/private/<w>/` with
  no zone), in the zone's project, writing only at the host the zone's
  `hosts` gives it; both layouts are read until the major that drops the old. Since LIB-0039 each
  file's content sits under one key, `zone:` or `workload:`, with its records
  at `dnsRecords`, and a zone's `services` imply its mail and identity
  records. `.github/scripts/split-secrets.sh` is the one-time v3→v4
  migration a spoke's owner runs. The spoke
  **commits** those generated copies, because
  Terragrunt's git filter plans inside worktrees where only tracked files exist,
  and its CI runs the script with `--check` to fail on drift. Copied, never
  symlinked or included, because a leaf's state key is relative to `root.hcl`'s
  own directory (LIB-0001 invariant 4).
- `grafana-dashboards/<set>/` — versioned Grafana dashboard JSON, tagged
  `grafana-dashboards/<set>/vX.Y.Z` per set. Consumers fetch a dashboard by its
  tag's raw URL (`raw.githubusercontent.com/noisypigeon/library/refs/tags/<tag>/<path>`),
  which is what `grafana/dashboard`'s `url` input does, so the same
  pinned file can feed both Terraform and anything else that ships it.
- `observability/<set>/` — a local Docker Compose observability stack, tagged
  `observability/<set>/vX.Y.Z` per set. `pigeon-cli` is the one set (its
  CLI-0161). Its Grafana mounts `grafana-dashboards/<set>/` from the same
  checkout rather than keeping a copy.
- `claude-plugins/<set>/` — Claude Code plugins, tagged
  `claude-plugins/<set>/vX.Y.Z` per plugin and listed in
  `/.claude-plugin/marketplace.json` (marketplace name `library`). A consumer
  pins the whole marketplace to one plugin's tag in its `.claude/settings.json`
  and enables `<plugin>@library`. `pigeon-cli` is the one plugin (its
  CLI-0161).
- `.github/workflows/` — the reusable CI the spokes call, tagged
  `workflows/vX.Y.Z`. Reusable workflows must live in `.github/workflows/`, so
  they sit beside this repo's own release automation rather than under a
  templates convention (DEV-0155).
- `.github/scripts/root-changelog.sh` — the one implementation of DEV-0160's
  root-changelog contract, used by this repo and fetched by the spokes.
- `.github/workflows/rust-crate-release.yml` and `.github/scripts/crate-*.sh`,
  `adr-issue.sh` — the Rust crate release pipeline and ADR out-of-scope issue
  filer, hoisted from `pigeon-cli` by its CLI-0161. Run in the *caller's* repo
  after its `fetch-lib.sh`; the caller writes its own `vX.Y.Z` tags and
  publishes to crates.io (LIB-0001's 2026-10-19 amendment). Every
  crate-specific value (`--crate`, `--bin`, `--codesign-id`, the target
  matrix) is an input.
- `.github/workflows/site-dispatch.yml` — a spoke whose workload holds a Zola
  site calls it to dispatch the site's deploy in its Pages shim repo, a repo
  holding only a README and that deploy workflow (LIB-0031). The shim calls
  `zola-site-pages.yml` with `repository` and `ref` to build the spoke's
  `main`, since Pages deploys only the repo it runs in (DEV-0156). Since
  LIB-0035 a shim does that through `site-pages.yml`, naming only its spoke
  and workload, and `site-generate.yml` commits a site's generated files in
  the spoke before it deploys.
- `.github/workflows/container-image-release.yml` — builds a caller's
  Dockerfile natively per platform, runs the caller's smoke test inside each
  image before anything is pushed, then publishes one multi-arch,
  provenance-attested tag set (`X.Y.Z`, `X.Y`, `latest`) to GHCR (LIB-0019).
  The Dockerfile, image name and smoke test stay in the spoke.
- `.github/scripts/generate-module-redirects.sh` — generates the `noisypigeon.garden` site's module
  redirect pages, overview pages, theme-version pages and release posts from
  this repo's tags, READMEs and CHANGELOGs. Runs in a *spoke's* generation,
  runway's `garden-generate.yml` through `site-generate.yml`, which commits its
  output under `workloads/garden/` (LIB-0035 §2), so it reads two roots: `LIB_ROOT`, derived from `${BASH_SOURCE[0]}` so it
  finds the clone it was fetched into rather than the site's repo, and
  `--content-root`, which only the caller knows.

- `.github/scripts/check-policies.sh` — checks a spoke against the policies
  its committed `policies.yaml` turns on, before every plan (LIB-0045). Each
  policy is a jq filter over one inventory of the spoke's leaves, with its
  params' schema beside it, under `.github/scripts/policies/`.

These scripts, `resolve-root-hcl.sh`, `check-secrets.sh`, `check-policies.sh` and `split-secrets.sh` live under `.github/scripts/` so the
`workflows/vX.Y.Z` track covers them: a spoke pins one version and gets the
reusable workflows and every script at that version, which is what invariant 2
asks for.

See `README.md` for the consumption contract and `terraform/README.md` for the
module index.

## This repo hosts nothing

There is no site, no Terraform state, no live `root.hcl` (only the template the spokes copy) and no secrets here. The
practical consequence: **every deploy dispatch is cross-repo.** Every release
dispatches `garden-generate.yml` in `noisypigeon/runway`, which regenerates
`noisypigeon.garden`'s pages and commits them under `workloads/garden/`. That
commit then deploys itself through runway's `sites.yml` and the
`noisypigeon/noisypigeon.garden` shim (LIB-0035). A theme release additionally
dispatches `pages.yml` in `noisypigeon/noisypigeon.com`, the Pages shim that
builds runway's `workloads/blog/` (LIB-0031, LIB-0032, LIB-0034). Both need
`BOT_GITHUB_TOKEN` to carry `actions: write` on the target, and both fail loudly
if it does not — the symptom otherwise is a tagged, released version whose short
URL 404s.

The shims' `pages.yml` deliberately does **not** live here: `actions/deploy-pages`
always targets the calling repo's own Pages site, so that caller has to live in
the repo whose site it deploys (DEV-0156 — a constraint, not a style choice).
Its body does: each shim's `pages.yml` only calls `site-pages.yml` with its
spoke and workload (LIB-0035 §3).

## Where the decisions live

ADRs live at `docs/adr/LIB-NNNN-<slug>.md`, numbered from `0001` within that
directory. `LIB-0001` defines the architecture; `LIB-0002` created this repo.

**This is also where the spokes' decisions live.** The one spoke is runway.
blog and garden are now only Pages shims, `noisypigeon/noisypigeon.com`
(LIB-0032, LIB-0034) and `noisypigeon/noisypigeon.garden` (LIB-0035), whose
sites are runway's `blog` and `garden` workloads. None of them holds ADRs
(LIB-0017): a decision about one of them is an amendment on the `LIB-`
record whose standard it applies, or a new `LIB-` record. Their old records
are all here:

- `DEV-` (garden's, mostly the family's pre-hub history) verbatim in
  `docs/adr/archive/`. That domain is frozen and closed; see its `README.md`.
- `COM-` (blog's) and `RUN-` (runway's), plus DEV-0162 to DEV-0165, as
  amendments whose headings carry the ID. LIB-0017 §2 says which record each
  one went into.

`pigeon-cli` is the exception (LIB-0017 §5, amended by CLI-0161): it keeps
its own ADRs, as `CLI-` records in a flat `adr/`. A bare pigeon-cli `ADR-NNNN`
cited here reads as `CLI-NNNN`.

Filing one, by hand:

- **Number**: max+1 within `docs/adr/`.
- **Filename and H1 agree**: `LIB-0002-<slug>.md` holds `# LIB-0002: <title>`.
- **Author is always** `Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).`
- **Sections**: `## Context` / `## Decision` / `## Consequences` /
  `## Out of scope`, optionally then `## Verification`. No YAML frontmatter and
  no index — there isn't one.
- Cite `LIB-NNNN`. Older IDs stay valid and are never rewritten: `DEV-NNNN`
  (bare `ADR-NNNN` in older prose is an alias, DEV-0160), `COM-NNNN` (`NPC-NNNN`
  is an alias) and `RUN-NNNN`. No new number is issued in any of those.
- Genuinely-deferred `## Out of scope` items get a GitHub issue in this repo,
  labelled `out-of-scope` (DEV-0031, LIB-0017 §6); permanent design boundaries
  do not. The `noisypigeon/noisypigeon#NNN` links in older records point at the
  deleted monorepo and no longer resolve.

## Runbooks

Operational procedures live at `docs/runbooks/<slug>.md`: step-by-step, for
any spoke, citing the ADR they serve. Today there are three:

- `restore-terraform-state-from-b2.md` (LIB-0007 §4) puts one leaf's state
  back into R2 from the B2 backup, through B2's native API with an admin key.
- `release-a-stuck-state-lock.md` (LIB-0022 §4) releases a leaf's `.tflock`
  left behind by a run that died, once nothing still holds it.
- `import-a-leaf-into-a-workload.md` (LIB-0032 §3) moves a hand-written leaf's
  resources into workload leaves, by import, without recreating them.

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
`terragrunt/root-hcl/root.hcl` or `terragrunt/root-hcl/secrets-schema.json`, and a dashboard release a changed
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
