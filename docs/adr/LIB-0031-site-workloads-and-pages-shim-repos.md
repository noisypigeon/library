# LIB-0031: A workload can be a site, deployed by a Pages shim repo

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-23.
- **Status**: Accepted; amended 2026-10-23 (see `## Amendments`), with
  Verification item 1 open. Amends LIB-0001, whose spokes gain a second shape, the
  shim repo, and LIB-0023, whose second amendment's gitignore narrows. Second
  of three records, with LIB-0030 and LIB-0032, that move the blog into
  runway. LIB-0034 has §4's dispatch read its target from `values.yaml`, and
  §6's site changelog take one line per PR.

## Context

The family has three spokes: garden, blog and runway (LIB-0017). Two of them
exist mostly for one reason.

- **GitHub Pages deploys only its calling repo's site.** `actions/deploy-pages`
  always targets the repo the workflow runs in (DEV-0156), and a repo has one
  Pages site with one custom domain. So each site with its own domain needs
  its own repo. garden serves `noisypigeon.garden`, and blog serves
  `noisypigeon.com`.
- **Everything else about a site fits a workload.** A site is a Zola source
  tree plus the DNS that points at it. LIB-0030 lets a workload own a zone and
  its records. Its state, secrets and review then live where the rest of the
  infrastructure does.

The cost of a repo per site is a spoke's whole apparatus: its own state
bucket and backup, secrets, `.lib-version`, Terragrunt CI and changelog. blog
carries all of that for four DNS leaves, two redirects and a Zola site.

What a site needs from its own repo is only the Pages deploy. So that's all
the repo should keep.

## Decision

### 1. A workload may carry a Zola site

`workloads/<w>/` may hold a Zola site's source beside `values.yaml`:

```
workloads/blog/
  values.yaml        # LIB-0023: kinds, including LIB-0030's zones
  secrets.yaml       # LIB-0025, optional
  config.toml        # Zola
  content/
  static/
  templates/         # optional, site overrides of the theme
  CHANGELOG.md       # the site's own, as blog-changelog.yml writes it
```

- **Zola ignores `values.yaml`, `secrets.yaml` and the provider directories.**
  The stubs sit under `scaleway/`, `backblaze/` and `cloudflare/`, which are
  not Zola directories.
- **The theme is fetched as today.** `config.toml`'s
  `[extra].theme_version` pins it, and `resolve-theme.sh` resolves it relative
  to its own location (DEV-0154).
- **A workload is a site because `config.toml` exists.** No `values.yaml` key
  says so.

### 2. The spoke's gitignore names the provider directories

LIB-0023's second amendment gitignores `/workloads/*/*/`, which would also
ignore `content/`, `static/` and `templates/`. It becomes:

```
/workloads/*/scaleway/
/workloads/*/backblaze/
/workloads/*/cloudflare/
/workloads/*/themes/
/workloads/*/public/
```

A provider gaining kinds adds its line. `resolve-workloads.sh --check` still
fails on a tracked stub, so a missing line shows up as a failed check, not a
committed stub.

### 3. A post doesn't run a plan

`terragrunt-detect.yml`'s default pattern matches `^workloads/`, so every new
post would start a Terragrunt plan that selects nothing. It narrows to
`^workloads/[^/]+/(values|secrets)\.yaml$`. LIB-0023's second amendment
already selects workload leaves by those two files.

### 4. The spoke dispatches; the shim repo builds and deploys

Pages can't deploy across repos, but a workflow can dispatch one.

- **In the spoke,** a site deploy workflow runs on a push to `main` that
  touches `workloads/<w>/`, other than `values.yaml` and `secrets.yaml`, and
  on `workflow_dispatch`. It dispatches the shim repo's deploy workflow with
  `BOT_GITHUB_TOKEN`, which needs `actions: write` on the shim repo. It fails
  loudly if the dispatch fails.
- **In the shim repo,** the deploy workflow checks out the spoke's current
  `main` and builds `workloads/<w>/`, then deploys it to the shim repo's own
  Pages site.
  - **The spoke is public, so the checkout needs no token.**
  - **It builds `main` as it is when it runs,** not a SHA the dispatch passes.
    A late or repeated dispatch then still deploys the newest site, and runs
    are serialised by the workflow's concurrency group.
- **`zola-site-pages.yml` gains `repository` and `ref` inputs.** They default
  to the calling repo and its ref, so existing callers don't change. The
  shim passes the spoke and `main`, with `src_dir: workloads/<w>` and
  `fetch_script` and `theme_script` as paths in that checkout.
- **A theme release still reaches the site.** `template-release.yml`
  dispatches the shim's deploy workflow by name, which still exists, and that
  workflow still builds with the theme version the site pins.

### 5. The shim repo is a README and one workflow

```
README.md
.github/workflows/<deploy>.yml
```

- **The README says why the repo is empty, where the source is
  (`<spoke>/workloads/<w>/`), and the site's public URL.**
- **No Terraform, no secrets, no `.lib-version`.** The deploy workflow pins
  `zola-site-pages.yml` at a `workflows/vX.Y.Z` tag like any caller; that pin
  is its only library dependency.
- **Pages settings stay in the shim repo:** the custom domain, HTTPS and the
  `github-pages` environment.
- **It's not a spoke.** It holds no leaves, writes no tags and runs no
  Terragrunt.

### 6. The site's changelog moves with it

- **`blog-changelog.yml`** writes the site's daily digest and dispatches its
  deploy. It gains a `deploy_repo` input, defaulting to the calling repo, so
  it can dispatch the shim instead.
- **The site's `CHANGELOG.md` lives in its workload directory.** The spoke's
  root `CHANGELOG.md` keeps one line per merged PR, as DEV-0160 has it.

### 7. Release impact

`workflows/` takes a minor version:

- `zola-site-pages.yml`'s `repository` and `ref` inputs;
- `blog-changelog.yml`'s `deploy_repo` input;
- the detect pattern.

Existing callers don't change.

## Consequences

- **A site costs a workload and a two-file repo**, not a spoke.
- **The infrastructure spoke now publishes something.** Content lands in the
  same repo, and the same review, as its Terraform. Its PRs mix posts and
  plans, though only `values.yaml` and `secrets.yaml` changes run a plan.
- **Two repos, two tokens.** A site deploy needs `BOT_GITHUB_TOKEN` in the
  spoke to reach the shim. A broken token means a merged post that never
  deploys. The dispatch failing loudly is the guard.
- **The shim deploys whatever the spoke's `main` holds.** A deploy is only as
  reviewed as the spoke's `main`.

## Out of scope

- **garden.** It would follow the same path, but its build also generates
  module pages from the library's tags, so its move is a record of its own.
  Deferred ([#150](https://github.com/noisypigeon/library/issues/150)).
- **Building §§1–7.** The workflow changes ship in later PRs that cite this
  record ([#148](https://github.com/noisypigeon/library/issues/148)).

## Verification

Recorded 2026-10-24, from LIB-0032's migration. Item 1 remains open.

Run against LIB-0032's migration of the blog.

1. **A post deploys.** A PR adding a post under `workloads/blog/content/`
   runs no Terragrunt plan. Merging it dispatches the shim, which deploys the
   post to the public URL.
   - **Open, in part:** [runway#64](https://github.com/noisypigeon/runway/pull/64),
     which moved the site, ran no Terragrunt plan, and its merge dispatched
     the shim. Once the shim was in place, noisypigeon.com served commit
     `dbe097d`, built from runway's `main`. A post-only PR hasn't been merged
     yet.

2. **A dispatch alone deploys.** A `zola-site` release's dispatch, with no
   runway commit, rebuilds and redeploys the site from runway's `main`.
   - **Passed, by hand:** a bare dispatch of noisypigeon/blog's
     `blog-pages.yml`, with no runway commit, checked out
     `noisypigeon/runway` at `main`, built `workloads/blog/` (68 pages) and
     deployed. A theme release dispatches the same workflow by name, but
     hasn't happened since.

3. **Stubs stay untracked.** `resolve-workloads.sh --check` passes with the
   site's files committed, and fails on a tracked stub.
   - **Passed:** `--check` passes with the site's 177 files committed
     (runway#64), and the stubs, the fetched theme and `public/` stay
     ignored.

4. **Existing callers don't change.** garden's site still deploys from its own
   repo with `zola-site-pages.yml` called as before.
   - **Passed:** garden's site deployed from its own repo after it took
     `workflows/v4.12.0` and `v4.13.0`
     ([garden#70](https://github.com/noisypigeon/garden/pull/70),
     [#71](https://github.com/noisypigeon/garden/pull/71)).

## Amendments

### 2026-10-23: what building it changed

§§2–7 shipped in `workflows/v4.12.0`. Building them settled two things.

1. **The spoke's dispatch is a reusable workflow, `site-dispatch.yml`.** §4
   had the spoke dispatch the shim itself, but spokes hold no CI logic
   (LIB-0001 invariant 1). So the spoke's caller holds only its `on:` paths,
   and calls `site-dispatch.yml` with `site_repo` and `workflow`. That fails
   loudly when `BOT_GITHUB_TOKEN` can't reach the shim.
2. **§3's narrower pattern reaches only callers that use the default.**
   runway passes its own `leaf_pattern`, `^workloads/` among it, so runway's
   caller narrows the same way in LIB-0032's PRs.

