# LIB-0034: A site workload declares its Pages shim

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-24.
- **Status**: Accepted, with Verification items 2 and 3 open. Amends:
  - LIB-0031, whose site dispatch (§4) reads its target from `values.yaml`,
    and whose site changelog (§6) becomes one line per PR;
  - LIB-0032, which left `noisypigeon/blog`'s name out of scope;
  - COM-0007, folded into LIB-0016, which named repos for their role.

## Context

LIB-0032 moved the blog into runway as `workloads/blog/`. It deploys through
the Pages shim `noisypigeon/blog` (LIB-0031). Three parts of that setup are
now either wrong or written for the blog alone.

- **The blog's `CHANGELOG.md` holds whole PR bodies.** For each merged PR,
  `blog-changelog.yml` prepends a `## DATE — title` heading, the PR's body
  and its link. Every other changelog in the family has one line per PR under
  `## YYYY-MM-DD`, newest first (DEV-0160). The blog's daily digest post
  already uses that shape. The file is long, and its format is the only one
  of its kind.
- **The site dispatch names the blog.** runway's `blog-site.yml` hardcodes
  `workloads/blog/**`, `noisypigeon/blog` and `blog-pages.yml`. A second site
  workload, such as garden once #150 moves it, would need its own copy.
- **The Pages DNS is written out by hand.** `values.yaml` holds the two
  CNAMEs that point `noisypigeon.com` and `www` at `noisypigeon.github.io`.
  They follow from which shim deploys the site, so they could be derived
  from it. As it stands, nothing checks them.
- **The shim's name describes a workload it no longer holds.** COM-0007
  renamed `noisypigeon/noisypigeon.com` to `noisypigeon/blog`, naming the
  repo for its role. The repo then held the blog. Since LIB-0032 it's a shim:
  a README and a deploy workflow for one custom domain's Pages site. A shim's
  role is its domain.

## Decision

### 1. `features.githubPages` in `values.yaml`

A workload's `values.yaml` gains a top-level `features` key. Its first
feature says which shim deploys the site:

```yaml
features:
  githubPages:
    pagesShim: noisypigeon/noisypigeon.com
    pagesBaseUrl: noisypigeon.github.io
```

- **`pagesShim`** is the shim repo, as `owner/name`. **`pagesBaseUrl`** is the
  Pages host its custom domain points at. Both are required.
- **It needs `cloudflare.zone`.** The records in §2 land in that zone, and
  LIB-0030 §2 already requires `zones.yaml` to register the zone to the
  workload.
- **A workload is still a site because `config.toml` exists** (LIB-0031 §1).
  `githubPages` says how the site deploys, not whether it is a site. A site
  without `githubPages` would never deploy, so the dispatch (§3) fails on it.
- **`resolve-workloads.sh`, `root.hcl` and the workload schema all learn the
  key.** They're the three twins LIB-0023 keeps in step.

### 2. It implies the two Pages records

`githubPages` adds two entries to `cloudflare.dnsRecord`:

| Key | `name` | `type` | `content` | `ttl` | `proxied` | `comment` |
|---|---|---|---|---|---|---|
| `github-pages-root-cname` | `@` | `CNAME` | `pagesBaseUrl` | `1` | `false` | `github pages root cname (apex, cloudflare-flattened)` |
| `github-pages-www-cname` | `www` | `CNAME` | `pagesBaseUrl` | `1` | `false` | `github pages www cname` |

- **The keys and values are the blog's current records.** A record's stub
  path, and so its state key, comes from its key. Deleting the hand-written
  entries and adding `githubPages` leaves the same two leaves with the same
  inputs.
- **An explicit entry overrides field by field.** A `cloudflare.dnsRecord`
  entry with one of those keys is merged over the default, and its fields win.
  An entry with nothing under it keeps the defaults.
- **Both scripts apply the defaults before any check.** That means the
  defaults count toward the stub list, LIB-0030 §6's clash checks (one record
  per name and type, and an `apexRedirect`'s placeholder at `@`) and the
  `secrets.yaml` check for undeclared entries.
- **The defaults can't be switched off.** A site that serves neither the
  apex nor `www` from Pages isn't the site `githubPages` describes. This is a
  design boundary, not a deferral.

### 3. One site dispatch for every site workload

`site-dispatch.yml` (LIB-0031's amendment) gains a mode driven by
`values.yaml`.

- **With no `site_repo`,** it diffs the push. It finds each
  `workloads/<w>/` with a change outside `values.yaml` and `secrets.yaml`
  and a `config.toml`, reads that workload's `pagesShim`, and dispatches
  `pages.yml` there (§4).
- **On `workflow_dispatch`,** it dispatches every site workload.
- **A site with no `githubPages` fails the run,** as a failed dispatch
  already does.
- **`site_repo` and `workflow` keep working.** A caller that passes them
  dispatches as before.

The spoke's caller becomes one `sites.yml`. It runs on a push to `main`
under `workloads/**`, except `workloads/*/values.yaml` and
`workloads/*/secrets.yaml`, and on `workflow_dispatch`. It names no workload,
so a second site needs no new workflow.

### 4. Every shim's deploy workflow is `pages.yml`

The dispatch and the theme release both name the shim's workflow. A fixed
name keeps `githubPages` to the two keys a site actually differs by.
`noisypigeon/noisypigeon.com`'s `blog-pages.yml` becomes `pages.yml`, and
`template-release.yml` dispatches it there.

### 5. The site changelog is one line per PR

- **The format is the root changelog's.** Each line is
  `- [<tag>] <PR title> ([#N](<url>))`, under `## YYYY-MM-DD`, newest first,
  inserted below DEV-0160's `<!-- entries below; newest first -->` marker.
  The blog's tag is `blog`.
- **`root-changelog.sh` writes it.** It's DEV-0160's one implementation.
  `blog-changelog.yml` fetches it with the caller's `fetch-lib.sh`, as
  `spoke-root-changelog.yml` already does, and gains a `changelog_tag` input,
  defaulting to `blog`. The script's note that `blog-changelog.yml` can't see
  it is no longer true.
- **The digest post and the optional root rollup don't change.**
- **Past entries are rewritten into the new shape, as far as they can be.**
  Each `## DATE — title` entry becomes one line under its date, and keeps the
  PR link it already has. An entry with no link keeps only its title. The
  bodies stay in git history and in each PR.

### 6. `noisypigeon/blog` becomes `noisypigeon/noisypigeon.com`

- **The shim is named for its domain,** which is its role. This applies
  COM-0007's rule, not reverses it. The workload stays `blog`.
- **The rename is GitHub's own.** The repo keeps its ID, its Pages custom
  domain and `github-pages` environment, and its secrets. A fine-grained
  `BOT_GITHUB_TOKEN` names repos by ID, so its access follows.
- **No state follows the name.** The shim has held no state since LIB-0032,
  so LIB-0016 has no bucket to rename.
- **Old links keep working.** GitHub redirects `noisypigeon/blog`, so the
  `noisypigeon/blog/...` links in folded `COM-` records keep resolving.
  Links from before COM-0007 to `noisypigeon/noisypigeon.com/...` resolve
  directly again. The redirect lasts only while nothing else takes the old
  name.

### 7. Order, freeze and release impact

COM-0007's rule applies: a rename of a dispatch target needs a freeze.

1. **The library ships §§1–3 and §5 first.** None of it depends on the rename.
2. **The freeze starts,** for hub theme releases and for runway merges that
   touch `workloads/blog/`.
3. **The owner renames the repo,** and the shim's `blog-pages.yml` becomes
   `pages.yml`.
4. **The library's theme dispatch targets `pages.yml` in
   `noisypigeon/noisypigeon.com`.**
5. **runway takes those releases.** In one PR, `values.yaml` gains
   `githubPages`, the two hand-written CNAMEs go, `sites.yml` replaces
   `blog-site.yml`, and the changelog caller and the blog's `CHANGELOG.md`
   change shape. Its plan must show `No changes.` for every blog leaf. The
   freeze ends when it merges.

Releases:

- **`workflows` takes a major version.** A caller's site changelog without
  the marker now fails, because `root-changelog.sh` won't guess where to put
  the line.
- **`terragrunt/root-hcl` takes a minor version,** for §2's defaults.

## Consequences

- **A second site costs a `values.yaml` stanza and a two-file shim,** with no
  new workflow in the spoke.
- **The Pages DNS can't drift from the shim it serves.** Changing
  `pagesBaseUrl` changes both records.
- **The blog changelog loses its prose.** The long form lives in the PRs. The
  file now reads like every other changelog here.
- **Every shim workflow must be called `pages.yml`.** A shim that names it
  otherwise is never dispatched. Nothing checks this before the dispatch
  fails.

## Out of scope

- **Moving garden** into a workload. This record makes it possible but
  doesn't do it. Deferred
  ([#150](https://github.com/noisypigeon/library/issues/150)).
- **A reusable shim `pages.yml`.** Each shim still hand-writes its
  `zola-site-pages.yml` inputs. Deferred
  ([#164](https://github.com/noisypigeon/library/issues/164)).
- **`blog-changelog.yml` reading its deploy target from `values.yaml`.** Its
  caller still passes `deploy_repo` and `deploy_workflow`. Deferred
  ([#165](https://github.com/noisypigeon/library/issues/165)).

## Verification

Recorded 2026-10-24, from the rollout in §7: library#168 and #167
(`terragrunt/root-hcl/v5.5.0`, `workflows/v4.14.0` and `v5.0.0`), the repo
rename,
[noisypigeon.com#55](https://github.com/noisypigeon/noisypigeon.com/pull/55),
library#169 (`workflows/v5.0.1`) and
[runway#65](https://github.com/noisypigeon/runway/pull/65). Items 2 and 3
remain open.

1. **The DNS doesn't change.** runway's PR that adds `githubPages` and
   removes the two hand-written CNAMEs plans `No changes.` for every blog
   leaf.
   - **Passed:** runway#65's plan at its head, `986ff33`, had 57 leaves with
     no changes and none with changes. Before it opened, the stub list and
     both `github-pages-*` stubs were byte-identical with and without the
     stanza, and `root.hcl`'s merge gave the same inputs.
2. **A post deploys through the renamed shim.** A post-only runway PR
   reaches `noisypigeon.com` through `noisypigeon/noisypigeon.com`'s
   `pages.yml`. This also closes LIB-0031 Verification item 1.
   - **Open, in part:** runway#65's merge, and the changelog commit after
     it, each ran `sites.yml`, which dispatched `pages.yml` in
     `noisypigeon/noisypigeon.com` for `workloads/blog`. The shim deployed,
     and `noisypigeon.com` returned 200. A post-only PR hasn't been merged
     yet.
3. **A theme release reaches the site.** A `zola-site` release dispatches
   `pages.yml` in `noisypigeon/noisypigeon.com`, and it deploys.
   - **Open:** library#169 points the dispatch there, and a bare dispatch
     of the renamed `pages.yml` deployed. No theme release has happened
     since.
4. **The changelog takes the new shape.** The next blog PR's line lands under
   its date in `workloads/blog/CHANGELOG.md`, below the marker.
   - **Passed:** runway#65's merge wrote
     `- [blog] The blog declares its Pages shim in values.yaml (LIB-0034)`,
     with its link, under `## 2026-10-24`, below the marker and above the
     collapsed entries.
