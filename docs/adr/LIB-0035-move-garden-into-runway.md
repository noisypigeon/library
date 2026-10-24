# LIB-0035: Move garden into runway

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-24.
- **Status**: Proposed. Applies LIB-0031, LIB-0032 and LIB-0034 to
  `noisypigeon/garden`. Amends:
  - LIB-0001 and LIB-0017, whose spoke list loses garden;
  - LIB-0002, whose module-release dispatch targets runway's generation
    instead of garden's deploy;
  - LIB-0031 §5, whose shim deploy workflow becomes a reusable one.

## Context

LIB-0032 moved the blog into runway as a workload, and left `noisypigeon/blog`
as the two-file Pages shim LIB-0031 describes. LIB-0034 then let the workload
name its shim in `values.yaml`, and dispatch it from one `sites.yml`. garden
was left out of both records
([#150](https://github.com/noisypigeon/library/issues/150)), because its build
does more than the blog's.

`noisypigeon/garden` is a full spoke for a small payload:

- **the site,** a Zola tree at `web/`: `config.toml`, five templates, three
  section `_index.md` files and two images;
- **one zone's leaf,** `terraform/cloudflare/noisypigeon.garden/dns-record/github-pages`.
  It holds the two Pages CNAMEs, `root_cname` at `@` and `www_cname` at
  `www`. These are exactly LIB-0034 §2's defaults, comments included;
- **its own state apparatus:** an R2 state bucket, and a B2 backup bucket and
  key (LIB-0007, LIB-0016), with the CI that plans, applies and backs them
  up.

What makes garden different is that most of what it serves is generated.

- **`generate-module-redirects.sh` runs inside its Pages build,** as
  `garden-pages.yml`'s `extra_step`. It writes, from the library's tags and
  changelogs:
  - a redirect page per module version, which is what makes
    `noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z` resolve
    (LIB-0009);
  - a page per theme version, and a post per release;
  - an `inputs.schema.json` per module version, and the workload schema
    every spoke's `--check` fetches (LIB-0023 §6).

  None of that output is committed: garden gitignores it.
- **The library dispatches that build on every release.**
  `template-release.yml` runs `garden-pages.yml` in `noisypigeon/garden`, so a
  release's short URL exists once the build has finished.
- **A failed build breaks every consumer's `terraform init`.** That includes
  runway's own plan, which resolves its modules through the same URLs.

So moving garden means moving its generation as well as its source. Generation
can't sit in the shim's build: LIB-0031 §5 keeps a shim to a README and one
workflow, and it would then build something `main` never held. And the blog's
shim hand-writes its `zola-site-pages.yml` call
([#164](https://github.com/noisypigeon/library/issues/164)). A second shim
would copy it.

## Decision

### 1. A `garden` workload

`workloads/garden/values.yaml`:

```yaml
prefix: garden
suffix: noisypigeon
features:
  githubPages:
    pagesShim: noisypigeon/noisypigeon.garden
    pagesBaseUrl: noisypigeon.github.io
cloudflare:
  zone: noisypigeon.garden
```

- **It needs no hand-written `dnsRecord` entries.** LIB-0034 §2's defaults
  are garden's two records.
- **`zones.yaml` registers `noisypigeon.garden` to `garden`** (LIB-0030 §2).
- **It gets what every workload does:** LIB-0028's project, deployer and
  state bucket, and LIB-0033's own Cloudflare token, scoped to its zone.
- **The site moves as it is.** `web/`'s `config.toml`, `templates/`, the
  three `_index.md` files and `static/assets/` go to `workloads/garden/`.
  It's a site because `config.toml` exists (LIB-0031 §1).

### 2. Generated artifacts are committed in the workload

- **A reusable `site-generate.yml`** takes `src_dir` and `generate_cmd`. It
  checks out the caller's `main` and fetches the library at the caller's
  `.lib-version`, with every tag. It then installs terraform-docs and runs
  the command. It commits what changed under `src_dir`, and nothing if
  nothing did. It pushes with `blog-changelog.yml`'s rebase-retry loop, in
  the `main-writer` concurrency group.
- **runway's caller is `garden-generate.yml`,** on `workflow_dispatch` only.
  Its command is `generate-module-redirects.sh --content-root
  workloads/garden/content --static-root workloads/garden/static`.
- **The commit deploys itself.** It lands under `workloads/garden/`, outside
  `values.yaml` and `secrets.yaml`, so `sites.yml` dispatches the shim
  (LIB-0034 §3). Generation has one trigger and so does the deploy.
- **The generated paths are tracked.** garden's gitignore lines for them
  don't move.

Why commit rather than generate at build time:

- **The deploy builds exactly what `main` holds.** A short URL is then a
  file with a history, not the side effect of a build.
- **A broken generation stops before the live site.** It fails its own run,
  or it shows up as a diff. Today it fails inside the Pages build that
  replaces the site.

### 3. One reusable shim workflow

`site-pages.yml` takes `spoke` and `workload`. It calls `zola-site-pages.yml`
with:

- `repository: <spoke>`, `ref: main`;
- `src_dir: workloads/<workload>`;
- `fetch_script: fetch-lib.sh` and `theme_script:
  .lib-src/zola-site/resolve-theme.sh`;
- `build_cmd: SITE_COMMIT_SHA=$(git rev-parse --short HEAD) zola build`.

Each shim's `pages.yml` (LIB-0034 §4) then names only its spoke and workload.
The blog's shim moves to it in the same rollout. A shim still runs no library
script except the theme's: generation happens in the spoke (§2).

### 4. A library release dispatches generation, not a deploy

- **`template-release.yml`'s garden step** becomes `gh workflow run
  garden-generate.yml -R noisypigeon/runway`, on every release, as today's
  `garden-pages.yml` dispatch is.
- **A theme release** still dispatches the blog's shim as well. garden's
  theme-version pages change with the release, so its generation covers
  garden.
- **`generate-module-redirects.sh` now runs in a spoke's generation,** not a
  site's build. Its header and the library's `CLAUDE.md` say so.
- **The hazard keeps its guard.** The dispatch needs `BOT_GITHUB_TOKEN` with
  `actions: write` on runway, and fails loudly without it.

### 5. The DNS is imported, never recreated

garden's two records move by LIB-0032 §3's runbook,
`docs/runbooks/import-a-leaf-into-a-workload.md`:

- `root_cname` goes to `workloads/garden/cloudflare/dns-record/github-pages-root-cname`;
- `www_cname` goes to `workloads/garden/cloudflare/dns-record/github-pages-www-cname`.

As there, nothing is applied in garden or runway between the import and the
merge of the PR that adds `features.githubPages`. That PR's plan must be
`No changes.`

### 6. `noisypigeon/garden` becomes `noisypigeon/noisypigeon.garden`

This is the shim, named for its domain, as LIB-0034 §6 named the blog's.

- **It keeps its ID, Pages site, custom domain and `github-pages`
  environment.** So the domain never moves. The short URLs change only in
  what builds them.
- **No state follows the name.** The shim holds no state, and §7's teardown
  removes the buckets that held garden's.
- **GitHub redirects the old name,** so `noisypigeon/garden/...` links in
  records keep resolving.

### 7. Cutover, in order

**The site must serve throughout.** Every step below keeps
`noisypigeon.garden` serving the same short URLs and schemas.

1. **The library:** `site-generate.yml` and `site-pages.yml`, a
   `workflows` minor release. The blog's shim moves to `site-pages.yml`.
2. **runway, bootstrap:** `zones.yaml` gains `noisypigeon.garden`.
   `workloads/garden/values.yaml` holds only `prefix`, `suffix` and
   `cloudflare.zone`. It applies the bootstrap stages.
   - This also proves runway's Cloudflare breakglass token reaches the zone.
     This record assumes the zone is in runway's account. If it isn't, this
     step fails before anything is imported, and the record is amended.
3. **The import,** by runbook (§5), with garden and runway frozen.
4. **runway, entries:** `values.yaml` gains `features.githubPages`.
   - It must plan `No changes.` for both leaves.
   - There's no `config.toml` yet, so `sites.yml` dispatches nothing.
5. **The freeze starts:** no library release, and no merge in garden or
   under runway's `workloads/garden/`. The owner renames the repo (§6).
6. **runway, site:**
   - the site files (§1);
   - `garden-generate.yml`;
   - the generated artifacts, from one local run at runway's `.lib-version`.

   Before it merges, `zola build` in `workloads/garden/` must produce the
   same `public/` as the live site, apart from the commit stamp. Its merge
   dispatches the shim, whose workflow still builds garden's own `web/`, so
   the live site doesn't change yet. It does prove the token reaches the
   renamed repo.
7. **The shim:**
   - the repo keeps `README.md` and a `pages.yml` calling `site-pages.yml`
     with `spoke: noisypigeon/runway` and `workload: garden`;
   - everything else goes: `web/`, `terraform/`, the other workflows,
     `.lib-version`, `spoke.hcl`, the generated `root.hcl` and the secrets;
   - a ruleset check left over from the spoke, such as `terragrunt/apply`,
     is removed first, as the blog's shim needed.
8. **The library:** §4's dispatch, with `CLAUDE.md` and the `release-pr`
   skill. Its own release runs the whole path: generation, the commit,
   `sites.yml`, the shim, the site. The freeze ends.
9. **The owner's teardown:** garden's R2 state bucket, its B2 backup bucket
   and key, and their credentials, by hand. Their Terraform code left in
   step 7.

### 8. Release impact

- **`workflows` takes a minor version in step 1,** for the two new
  workflows.
- **It takes a patch in step 8,** for the dispatch.
- **Existing callers don't change.**

## Consequences

- **The family is runway and the hub.** Every site is a workload and a shim.
- **runway's history gains a bot commit per library release.** It's
  generated content, and it never runs a plan.
- **The module index has a history.** A short URL that changes shows up as a
  diff in runway.
- **runway's `main` now carries both sites.** A broken `main` blocks
  garden's deploy as well as the blog's. A broken garden deploy still blocks
  every `terraform init`, runway's included. So the site has to keep
  serving through every step of the cutover (§7).

## Out of scope

- **A scheduled regeneration.** A missed dispatch fails loudly, and
  `workflow_dispatch` reruns it. A cron would hide the failure it guards
  against. This is a design boundary, not a deferral.
- **Pruning generated pages.** Generation still rewrites every page from the
  tags, as it does today. This is a permanent property of the generator, not
  a deferral.

## Verification

1. **The DNS doesn't change.** The step 4 PR plans `No changes.` for both
   leaves, and `dig` for `noisypigeon.garden` and `www` answers the same
   before and after.
2. **The short URLs never break.** At every step:
   - `terraform init` of a pinned `noisypigeon.garden/terraform/...` source
     succeeds;
   - a redirect page carries its `terraform-get` meta tag;
   - `/schemas/workload/v1.json` serves.
3. **The site is unchanged.** runway's build of `workloads/garden/` matches
   the live site, apart from the commit stamp.
4. **A release regenerates and deploys.** Step 8's own release commits the
   regenerated pages to runway, and the shim deploys them.
5. **The blog's shim still deploys** through `site-pages.yml`.
6. **garden's apparatus is gone.** Its state bucket, backup bucket and key no
   longer exist, and their credentials are revoked.
