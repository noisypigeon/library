# LIB-0009: Terraform short URLs move to `noisypigeon.garden/terraform/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-16.
- **Status**: Accepted.

## Context

Every module consumer in this family writes its source as
`https://pigeon.dev/modules/<provider>/<module>/vX.Y.Z`. go-getter fetches that
URL with `?terraform-get=1`, reads the `terraform-get` meta on the page, and
follows it to a `git::` source against this repo at the module's tag. DEV-0109
introduced the short URL, DEV-0110 fixed its `modules/` namespace as a public
interface independent of this repo's layout, and DEV-0136 moved the host to
`pigeon.dev`. The pages are written by `.github/scripts/generate-module-redirects.sh`,
which runs in the `pigeon.dev` site's build.

LIB-0008 made `noisypigeon.com` the canonical identity and deferred two moves:

- **pigeon.dev's redirect moves to the noisypigeon.com repo**
  (noisypigeon/noisypigeon#321), with a warning: unless the module short URLs
  keep resolving, every consumer's `source =` breaks.
- **noisypigeon.garden becomes pigeon.dev's new home**
  (noisypigeon/noisypigeon#322): the site, the short-URL host, and its zone.

COM-0006 then moved willowgraysen.com's redirect into noisypigeon.com, which is
the precedent for how a zone changes repo. This record makes both deferred moves
in one go, because the short URLs can only have one host and they move with the site.

## Decision

### 1. The public module source becomes `https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z`

- **The path changes from `modules/` to `terraform/`.** It now matches this
  repo's own prefix, which makes a source address readable as a path in this
  repo. That's a choice, not a coupling. DEV-0110's rule still holds:
  the public path is an interface of its own, and moving the internal layout
  never changes it.
- **The `git::` target doesn't change.** It's still
  `git::https://github.com/noisypigeon/pigeon-lib.git//terraform/<provider>/<module>?ref=<tag>`,
  so a short URL pointing at a given tag fetches the same bytes as before.
- **Every tag is published at the new address,** old versions included. The
  generator works from the tag list, not from the release history.

### 2. A clean break: `pigeon.dev` short URLs stop resolving

`pigeon.dev` gets no path-preserving redirect. After the cutover, its ruleset
sends every path to `https://noisypigeon.garden` with a 301, and go-getter finds
no `terraform-get` meta there.

- **Old commits that pin `pigeon.dev/modules/…` won't `terraform init`.** Every
  current leaf is rewritten in the cutover, and history is history.
- **Old module tags that nest short URLs are dead.** `scaleway/pigeon-cluster`
  through v3.0.0 and `scaleway/compute-instance` v5.3.1 to v6.1.0 source other
  modules by `pigeon.dev` URL. Their tags stay, but they can't be initialized.
  `pigeon-cluster` gets a patch release with garden URLs. A consumer that
  re-enables an older pin takes that release instead.
- **One consumer pins a dead tag:** `noisypigeon/willowgraysen`'s
  `scaleway/pigeon-cluster/pigeon-cli`. It pins v1.2.0, and its module call is
  commented out, so nothing live breaks.

### 3. The generator writes `terraform/` paths into `content/terraform/`

`generate-module-redirects.sh` changes in three places:

- the per-version redirect page's `path` becomes `terraform/<provider>/<module>/vX.Y.Z`;
- the section becomes `content/terraform/`, so each overview page sits at
  `/terraform/<provider>-<module>/`;
- the overview's version links point at the new paths.

Theme-version pages and release posts keep their paths and move host with the
site. The change ships as a `workflows/` minor release. Nothing renders it until
the site bumps its pin at cutover.

### 4. The site is `noisypigeon/garden`, deployed by `garden-pages.yml`

`noisypigeon/pigeon.dev` is renamed `noisypigeon/garden`, and its Pages workflow
becomes `garden-pages.yml`. `template-release.yml`'s dispatch becomes
`gh workflow run garden-pages.yml -R noisypigeon/garden`. It's the one place the
old repo name is load-bearing: a POST to the dispatch endpoint shouldn't rely on
GitHub's rename redirect. The Pages custom domain becomes `noisypigeon.garden`,
and the site's `base_url` changes to match.

### 5. The cutover runs in this order, with Terraform PRs and hub releases frozen

1. **Rename** the repo and the workflow, then repoint the hub's dispatch.
2. **Zone leaves in garden** (LIB-0008 §1–3):
   - the spoke takes `root.hcl` v2.2.0;
   - `dns-record/{fastmail,github-pages}` move under `terraform/cloudflare/pigeon.dev/`;
   - `terraform/cloudflare/noisypigeon.garden/dns-record/github-pages` points the
     new apex and `www` at GitHub Pages.
3. **The generator release** (§3).
4. **The site cutover.** The custom domain moves to `noisypigeon.garden`, and the
   site takes the new pin and `base_url`. From this point, `pigeon.dev` short
   URLs are dead (§2).
5. **Consumers switch.** Here, `pigeon-cluster` and the READMEs move to garden
   URLs. Then each spoke rewrites its sources, with a plan that must show
   `No changes.`
6. **pigeon.dev's zone moves to noisypigeon.com:**
   - `fastmail` moves with its state, by COM-0006's pattern;
   - `github-pages` is destroyed;
   - noisypigeon.com adds proxied placeholders and a ruleset that sends
     `pigeon.dev` and `www` to `https://noisypigeon.garden`.

### 6. LIB-0008's zone layout extends to both domains

- **`noisypigeon.garden` zone leaves live in `noisypigeon/garden`,** the repo
  that serves the site.
- **`pigeon.dev` zone leaves live in `noisypigeon.com`,** next to
  `willowgraysen.com`'s. A domain that only redirects belongs in the identity's
  repo, as LIB-0008 intended. The one change from willowgraysen.com: pigeon.dev
  redirects to the garden, not to the identity, because its readers were the
  garden's.

## Consequences

- **Every consumer's `source =` changes host and path once.** The module
  versions and the resources they manage don't change.
- **Old pins become archaeology.** Checking out an old commit and running
  `terraform init` fails on the source. That's accepted, so that a second domain
  never has to keep serving the meta pages.
- **pigeon.dev keeps its email.** Fastmail's records move to noisypigeon.com
  unchanged. Only the web side redirects.
- **The hub's docs change:** `CLAUDE.md` and `README.md` describe
  `noisypigeon.garden/terraform/…`, and the "`modules/`, not `terraform/`"
  paragraph goes away.

## Out of scope

Permanent boundaries, with no issue:

- **The `DEV-` prefix stays.** `noisypigeon/garden` keeps the `DEV-NNNN` corpus;
  only the repo is renamed.
- **The `PIGEON_DEV_*` secret names and the state bucket's name stay.** They're
  identifiers, not addresses. Renaming them is a state move that buys nothing.
- **No compatibility redirect for `pigeon.dev/modules/…`,** per §2.

## Verification

Recorded as each phase of §5 lands.
