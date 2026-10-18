# DEV-0156: Hoist `workloads/pigeon.dev/src` to `noisypigeon/pigeon.dev` and serve it via GitHub Pages

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-11.
- **Status**: Accepted.

## Context

ADR-0154 moved `templates/` into `noisypigeon/pigeon.dev` but deliberately left the site that
publishes those templates' import URLs behind in this repo. That split is the source of every
coupling ADR-0154 had to rebuild rather than move:

- `workloads/pigeon.dev/fetch-templates.sh` maintains a gitignored blobless clone
  (`/.templates-src/`) purely so a site in *this* repo can read tags, READMEs and `CHANGELOG.md`
  files that live in *that* one.
- `generate-module-redirects.sh`'s `templates_tags()` reads that clone, while its `legacy_tags()`
  reads this repo's own 20 frozen `modules/*` tags directly — one script, two repos, because the
  site and the tags it describes aren't colocated.
- `resolve-theme.sh` lost ADR-0114's live-working-tree symlink for `theme_version = "main"`,
  because the theme is no longer on local disk relative to the site that consumes it.
- ADR-0141's release posts became *generated* from the clone's `CHANGELOG.md` files instead of
  written directly by `template-release.yml`, specifically to avoid a cross-repo write.
- `template-release.yml` has to `gh workflow run zola-sites-deploy.yml -R noisypigeon/noisypigeon`
  after cutting a tag — the one prerequisite ADR-0154 flagged as failing silently (tag cuts, site
  never redeploys, the new version's short URL 404s).

Moving the site into the repo whose tags it publishes collapses all five. The move itself is
small: only **12 tracked files** live under `workloads/pigeon.dev/src` — `config.toml`, four
`_index.md` section markers, two images, five templates. Everything else under that tree
(`public/`, and every generated `.md` under `content/{modules,theme-versions,releases}/`) is
build output, already gitignored (`.gitignore:4-10`). The risk in this change is entirely in the
deploy/DNS cutover that comes with it, not in the file move.

### GitHub Pages is a reintroduction, not an extension

There is no live use of `actions/{configure,upload,deploy}-pages` anywhere in this repo today.
ADR-0132 explicitly retired GitHub Pages for `noisypigeon.com` in favor of a Scaleway bucket
fronted by Cloudflare, and `pigeon.dev` was built on that same bucket pattern from the start
(ADR-0130) — it never used Pages. The closest structural precedent for "build a Zola site, ship
it somewhere" is ADR-0155's `zola-site-deploy.yml` (`aws s3 sync` to a bucket); the closest DNS
precedent is the deleted `workloads/management/terraform/cloudflare/noisypigeon.com/blog/cname.tf`,
which pointed apex + `www` at `noisypigeon.github.io`, both `proxied = false`, commented "github
pages root cname (apex, cloudflare-flattened)".

### Verified before deciding

Four things this design rests on, checked rather than assumed:

- `GET /repos/noisypigeon/pigeon.dev` returns `has_pages: false`, `visibility: public`,
  `default_branch: main`; `GET .../pages` returns `404`. No Pages site exists on that repo today,
  so nothing is being displaced.
- `actions/deploy-pages` deploys to the **calling repo's** Pages site — consistent with ADR-0155's
  finding that `actions/checkout` in a called workflow checks out the caller, `github.*` is the
  caller's context throughout. A caller living here would deploy to *this* repo's Pages site, not
  `pigeon.dev`'s, so the pigeon.dev caller has to live in `noisypigeon/pigeon.dev` itself — not a
  style choice, a constraint.
- GitHub Pages redirects `www` to the apex natively when the custom domain is an apex and the
  `www` CNAME also points at the Pages host. This is what lets `redirect.tf`'s
  `cloudflare_ruleset` be deleted outright instead of retargeted, and it's exactly what the
  pre-ADR-0132 `noisypigeon.com` records relied on.
- Query strings don't affect static serving, so `?terraform-get=1` resolves the same way on Pages
  as on the bucket gateway. The one real difference worth checking live is extensionless-path
  handling: Zola emits `modules/<provider>/<module>/vX.Y.Z/index.html`, and a request for that
  path without the trailing slash has to 301 (Pages does this) rather than 404, since go-getter
  follows the redirect.

All 75 `source =` lines across `workloads/**/*.tf` resolve through `pigeon.dev/modules/...`. A
broken redirect layer breaks `terragrunt init` repo-wide, which is why §10 puts a fully verified
Pages site ahead of any DNS change.

## Decision

### 1. `pigeon.dev/src` lands in the templates repo, and four couplings collapse

Destination: `pigeon.dev/src` inside `noisypigeon/pigeon.dev` — mirrors this repo's
`workloads/<name>/src` convention, sibling to `templates/`, and leaves room for a second site
later without a rename. The 12 tracked files move byte-identical. Then:

- `fetch-templates.sh` is **not** needed there — `templates/` is now local to the site that reads
  it. It stays in this repo, relocated to `workloads/noisypigeon.com/fetch-templates.sh`, colocated
  with its one remaining consumer.
- `generate-module-redirects.sh` moves to `pigeon.dev/generate-module-redirects.sh`. Its two tag
  sources swap which one is local: `templates_tags()` becomes a plain `git -C "$REPO_ROOT" tag
  --list` against the repo it now runs in, and `legacy_tags()` becomes a read of the committed
  frozen list (§2) instead of a call into a clone. The `fetch-templates.sh`-first precondition
  check and the `TEMPLATES_SRC` indirection both disappear; `CONTENT_DIR` and friends rebase onto
  `$REPO_ROOT/pigeon.dev/src/content/...`. The `url_path` / `repo_for_prefix` logic — the part that
  keeps the public `modules/...` namespace stable regardless of which repo a tag lives in — is
  untouched, per ADR-0110's decoupling and ADR-0154's extension of it.
- `resolve-theme.sh`'s `TEMPLATES_REPO_ROOT` override, added by ADR-0154 to escape the
  chicken-and-egg of `git rev-parse --show-toplevel` no longer finding `templates/` locally, stops
  being necessary for this consumer: `theme_version = "main"` becomes a live working-tree symlink
  again. This partially un-amends ADR-0154's amendment of ADR-0114 — a restoration, not a new
  mechanism, and `noisypigeon.com` (still a separate repo from its theme) keeps needing the
  override.
- ADR-0141's release posts still generate from `templates/terraform/*/*/CHANGELOG.md`, now read
  off local disk instead of a fetched clone.

`config.toml`'s `base_url = "https://pigeon.dev"` and `[extra] theme_version = "main"` are
unchanged, so this step alone produces zero content churn.

### 2. The 20 legacy `modules/*` tags become a committed list

`git tag -l 'modules/*'` in this repo returns exactly 20 tags, each pointing at a commit that
predates `templates/` existing — which is why ADR-0154's `filter-repo` couldn't carry them onto
`pigeon.dev`, and one of them, `scaleway/project/v1.0.0`, is still live-pinned (confirmed: it's the
only legacy tag among the 75 live `source =` lines' pinned versions). The generator's `legacy_tags`
function is rewritten to grep a small committed data file — `pigeon.dev/legacy-module-tags.txt`,
one tag per line — instead of shelling into a repo it no longer has local access to.

This is safe specifically *because* ADR-0154 established the set as frozen and permanently unable
to grow; a committed snapshot of a growing set would drift. The alternative considered — inverting
`fetch-templates.sh` so the generator clones `noisypigeon` to enumerate its tags — was rejected:
it re-adds, in the opposite direction, exactly the cross-repo coupling this move exists to delete.

### 3. A reusable `zola-site-pages.yml`, deliberately not pigeon.dev-specific

A new `workflow_call` workflow at `noisypigeon/pigeon.dev/.github/workflows/zola-site-pages.yml`,
sibling to ADR-0155's `zola-site-deploy.yml`, with the same input vocabulary so the two stay
interchangeable at the call site:

| Input | Notes |
| --- | --- |
| `src_dir` | required; the Zola site root |
| `build_cmd` | default `zola build` |
| `extra_step` | optional pre-build script path (pigeon.dev passes the redirect generator) |
| `zola_version` | optional pin |

No secrets at all. Pages deployment authenticates via OIDC (`id-token: write`), which is why this
workflow is simpler than the bucket one rather than merely different. Two jobs, because
`actions/deploy-pages` requires its own job bound to the `github-pages` environment:

- `build`: checkout → resolve theme → run `extra_step` if set → install Zola → run `build_cmd` →
  `actions/configure-pages` → `actions/upload-pages-artifact` with `path: ${{ inputs.src_dir
  }}/public`.
- `deploy`: `needs: build`, `environment: github-pages`, `actions/deploy-pages`.

This is ADR-0155 §3's split applied to a new target: *how to build and ship one Zola site to
Pages* is reusable, *which site, and which repo's Pages* is the caller's business. As with that
ADR, there's no second consumer today and the reuse is speculative — what's concrete is that the
*next* site gets a thin caller instead of a second copy of this workflow.

### 4. pigeon.dev's own caller lives in the templates repo, by constraint

`pigeon.dev/.github/workflows/pigeon-dev-pages.yml`: `on: push` to `main` filtered to
`pigeon.dev/**` and `templates/**` (a template change changes the generated redirect/overview
pages), plus `workflow_dispatch`. Declares `permissions: contents: read, pages: write, id-token:
write` and a `concurrency` group — per ADR-0155 §5, callers keep their own triggers, permissions
and concurrency even when the job body is shared.

It calls `uses: ./.github/workflows/zola-site-pages.yml`, the same-repo form, not
`noisypigeon/pigeon.dev/...@main`. This is the one place this ADR's caller pattern differs from
ADR-0155's: the called workflow there always runs against whatever ref triggered the caller, so a
self-referential `@main` pin buys nothing, and more to the point, §Verified established that
`deploy-pages` *forces* the caller into the owning repo — it's necessarily a same-repo call, not a
style choice.

### 5. `template-release.yml`'s cross-repo dispatch is halved, not removed

After this change:

- A **Terraform module** release dispatches `pigeon-dev-pages.yml` in-repo via the same
  `gh workflow run` pattern `template-release.yml` already uses. The cross-repo
  `-R noisypigeon/noisypigeon -f site=pigeon.dev` call disappears entirely — the module's own repo
  can now redeploy its own site.
- A **`templates/zola-site`** release still has to reach `noisypigeon.com`, which stays a separate
  repo on the Scaleway-bucket deploy path. `template-release.yml` keeps its cross-repo
  `-R noisypigeon/noisypigeon -f site=all` dispatch *and* adds the in-repo `pigeon-dev-pages.yml`
  dispatch, since a theme release now affects two independently-hosted sites in two different
  ways.

So `BOT_GITHUB_TOKEN` still needs `actions: write` on this repo — narrowed to the theme-release
case only, not eliminated. ADR-0154's flagged prerequisite is reduced in blast radius, not closed.
An explicit in-repo dispatch (not just relying on the `pigeon.dev/**` push-path filter) is still
required because `template-release.yml`'s own tag/changelog commit is made with the default
`GITHUB_TOKEN`, which doesn't trigger other workflows' `push` events — ADR-0107's finding, still
true here.

### 6. `wiki/dns` is retargeted at Pages and loses its redirect ruleset

In `workloads/pigeon.dev/terraform/wiki/dns/`:

- `cname.tf`: `root_cname`'s `content` becomes `noisypigeon.github.io`, `proxied` becomes `false`.
  `placeholder_www` becomes a real `www_cname`, also → `noisypigeon.github.io`, also `proxied =
  false`. The file's header comment currently explains the bucket gateway's Host-header routing
  quirk; that stops being the reason for anything here and gets rewritten.
- `redirect.tf`: **deleted.** Its entire reason to exist was working around that Host-header
  behavior — GitHub Pages redirects `www` to the apex natively (§Verified), so there's nothing
  left for a `cloudflare_ruleset` to do.
- A new TXT record, `_github-pages-challenge-noisypigeon`, is added to this leaf for GitHub's
  domain-verification check. This is new, not ported from anywhere — it's the documented control
  against custom-domain takeover and belongs in Terraform rather than being clicked once and
  forgotten.

The leaf keeps its `wiki/dns` path. Renaming it to reflect "no longer in front of a wiki bucket"
would cost the full ADR-0106-style `git worktree` + `terragrunt state pull`/`push` migration for
zero functional gain.

Losing the Cloudflare proxy on the apex is a real, accepted tradeoff: no Cloudflare CDN, caching,
or WAF in front of the site, and TLS comes from GitHub's own Let's Encrypt certificate instead of
Cloudflare's. It's accepted because it's the exact configuration `noisypigeon.com` ran for its
entire GitHub Pages life, and because keeping the record proxied would prevent GitHub from
validating the domain and issuing that certificate at all.

### 7. `wiki/bucket` and `wiki/iam` are decommissioned

Both leaves are deleted once Pages is confirmed serving. `wiki/bucket` is a bucket literally named
`pigeon.dev` with `enable_website`/`enable_public_read` set; `wiki/iam` exists solely to mint the
`PIGEON_DEV_SCW_ACCESS_KEY`/`PIGEON_DEV_SCW_SECRET_KEY` pair `zola-sites-deploy.yml` uses to `aws
s3 sync` into it. With the site no longer deploying there, neither has a consumer left.

`project`, `state/bucket`, `state/iam`, and `fastmail/dns` all stay exactly as they are —
ADR-0130's self-sufficiency pattern still applies to this workload's Terraform state and to the
Fastmail DNS leaf, neither of which this change touches. "Leaving the infrastructure intact" means
the workload's Terraform tree stays in this repo; it does not mean every leaf in it survives
indefinitely once its one consumer is gone.

Deleting a leaf directory needs ADR-0128's `--filter-allow-destroy` on `terragrunt-run.yml`'s
`--filter-affected` invocation — already present — without which the deleted directory would be
silently excluded from the run rather than destroyed. The two `PIGEON_DEV_SCW_*` repo secrets are
retired in the same PR.

### 8. `zola-sites-deploy.yml` drops to one site

Removed: the `deploy-pigeon-dev` job, the `workloads/pigeon.dev/src/**` push-path filter, the
`pigeon.dev` option on the `site` `workflow_dispatch` input, and `detect`'s `pigeondev` output.

Kept: the `detect` job and the `site` input, now serving a single site (`all` and
`noisypigeon.com` are the only remaining meaningful values, and `all` becomes a no-op alias for
`noisypigeon.com`). Two reasons to keep rather than collapse: `-f site=all` and `-f
site=noisypigeon.com` are live dispatch targets from this repo's own `blog-changelog.yml` and from
`pigeon.dev`'s `template-release.yml`, and changing the input's accepted values is itself a
cross-repo coordination risk; and the shape is ADR-0140's, built with a second site already in
mind. Collapsing `detect` entirely, now that the trigger's own path filter alone would suffice for
one site, was considered and rejected as churn that buys nothing and risks breaking those two
external dispatches for no reason tied to this change.

### 9. In-repo bookkeeping

- `.gitignore`: delete the `pigeon.dev/src/public` and three `pigeon.dev/src/content/*` generated
  rules (lines 4-10); `/.templates-src/` is dropped since nothing here fetches a templates clone
  any more. `/workloads/*/src/themes/zola-site` stays — `noisypigeon.com` still resolves it.
- `.mise.toml`: delete the `pigeon-dev-build`/`pigeon-dev-serve` tasks; repoint `blog-build`/
  `blog-serve`'s `fetch-templates.sh` reference from `../../pigeon.dev/fetch-templates.sh` to the
  relocated `./fetch-templates.sh`. `pigeon.dev` gains its own build/serve tasks in its own repo.
- `CLAUDE.md`: its opening paragraph currently states the redirect pages, module pages and release
  posts "are all still generated and served from here, by `workloads/pigeon.dev/`". That's
  corrected, and the file gains a note that `pigeon.dev` is now three things — published templates
  (ADR-0154), shared CI definitions (ADR-0155), and the pigeon.dev site itself (this ADR).
- `workloads/README.md` and `docs/USAGE.md`: checked and corrected for any
  `workloads/pigeon.dev/src` references left stale by this move.

### 10. Five PRs, ordered by blast radius

1. **`pigeon.dev`**: add `zola-site-pages.yml`, `pigeon-dev-pages.yml`, the 12-file `pigeon.dev/
   src`, the rewired generator, `legacy-module-tags.txt`, the repo's own mise tasks, and
   `template-release.yml`'s added in-repo dispatch. Enable Pages on the repo and **verify the site
   fully on its `*.github.io` URL while `pigeon.dev` the domain still resolves to the bucket.**
   This is the property the whole ordering exists to get: nothing user-visible moves in this PR.
   One wrinkle to verify around rather than past: `base_url = "https://pigeon.dev"` means the
   preview build's absolute links point back at the still-live bucket, so check the generated HTML
   directly (page counts, `<meta name="terraform-get">` contents) rather than by clicking through
   the preview, or build once with a `--base-url` override for manual spot checks.
2. **`pigeon.dev`**: set the Pages custom domain to `pigeon.dev`
   (`PUT /repos/noisypigeon/pigeon.dev/pages`, `cname: pigeon.dev`) *before* the DNS flip. It will
   report a failed DNS check, which is expected and harmless at this point — doing it now is what
   shortens the exposure window in the next step.
3. **Here**: the `wiki/dns` retarget (§6), applied through the existing `terragrunt apply` PR
   comment gate. The bucket is still populated and still being deployed to at this point, so
   reverting this one PR alone is a complete rollback. Once DNS propagates, GitHub provisions the
   certificate; then enable Enforce HTTPS on the Pages settings. Stated plainly: between the DNS
   flip and certificate issuance, `https://pigeon.dev` serves a certificate error, and with
   `proxied = false` there is no Cloudflare certificate covering it in the meantime. This should be
   minutes, not hours — step 2 is specifically what keeps it short.
4. **Here**: remove `workloads/pigeon.dev/src/` and `generate-module-redirects.sh`, relocate
   `fetch-templates.sh` to `workloads/noisypigeon.com/`, trim `zola-sites-deploy.yml` (§8), apply
   the §9 bookkeeping, and land this ADR.
5. **Here**: delete `wiki/bucket` and `wiki/iam` (§7). Last, and deliberately so — only once Pages
   has been serving long enough to trust, since this step removes the rollback target step 3's
   ordering was protecting.

## Consequences

- The five ADR-0154 couplings collapse; a module release becomes one repo's business end to end,
  with no fetched clone, no `TEMPLATES_SRC` indirection, and no cross-repo dispatch for the common
  case.
- `pigeon.dev` becomes three things: published templates, shared CI definitions, and now the
  pigeon.dev site itself. Its own `CLAUDE.md` describes only the first two as of ADR-0155 and needs
  a third section.
- No Cloudflare proxy in front of the site any more: no CDN, caching, or WAF, and an availability
  or certificate problem on GitHub's side is no longer absorbable at Cloudflare's edge. GitHub
  Pages also has published soft bandwidth/build limits where a Scaleway bucket has a bill instead
  of a cap.
- The redirect layer serving all 75 `source =` lines in this repo now depends on GitHub Pages
  availability instead of Scaleway Object Storage availability. Not obviously worse, but a
  different single point of failure underneath every `terragrunt init` in the repo.
- `workloads/pigeon.dev/` becomes Terraform-only (`root.hcl`, `secrets.enc`, `terraform/`) — the
  mirror image of `workloads/blog/`'s brief `src/`-only phase before ADR-0132, and the first
  workload in this repo whose content lives in another repo entirely while its infrastructure
  stays here.
- The two Zola sites' deploy mechanisms diverge: `noisypigeon.com` still ships via `aws s3 sync` to
  a bucket, `pigeon.dev` now via GitHub Pages. Two deploy shapes to maintain where ADR-0140 had
  deliberately merged down to one matrix over a single mechanism.
- This repo loses the ability to preview the pigeon.dev site locally — `mise run pigeon-dev-serve`
  moves with the source it serves.

## Out of scope

- Executing the hoist. Not deferred — a deliberate boundary, following ADR-0052/0154/0155's own
  precedent for a decision-record-only ADR; §10 is the runbook.
- Moving `noisypigeon.com` to GitHub Pages too, which `zola-site-pages.yml` would now make nearly
  free to do. Genuinely deferred — file via `mise run adr-issue`.
- Any change to the `modules/<provider>/<module>/vX.Y.Z` public URL convention. A permanent
  boundary, fixed by ADR-0110 and respected again here.
- Decommissioning `wiki/bucket`'s Scaleway project or the `state/*` leaves. A permanent boundary:
  `fastmail/dns` and the retargeted `wiki/dns` still need both.
- Keeping Cloudflare in front of Pages via a proxied record plus a documented DNS-only
  certificate-provisioning window. Deliberate boundary — §6 chose the precedent-backed, simpler
  configuration over one that needs a manual dance every time the certificate is reissued.
- Pinning the called workflow to a `workflows/vX.Y.Z` tag instead of `@main`. The same
  genuinely-deferred item ADR-0155 §6 already raised; reuse that issue via `--issue N` rather than
  filing a second one for the same gap.
- Hosting a second site inside the `pigeon.dev` repo. `pigeon.dev/src` leaves room for it, per §1,
  but nothing needs it yet.

## Verification

Keyed to the §10 steps, with the redirect layer treated as the thing that must not break:

1. **Before any DNS change** (after PR 1): the Pages build generates the same page counts the
   current build does — compare the generator's three "Generated N ..." log lines against a local
   `mise run pigeon-dev-build` on today's `main`. Confirm all 20 legacy `modules/*` redirect pages
   are present, and specifically that `scaleway/project/v1.0.0`'s page still emits
   `git::https://github.com/noisypigeon/noisypigeon.git//modules/scaleway/project?ref=modules/scaleway/project/v1.0.0`
   — it's the one live-pinned legacy tag, and the frozen-list rewrite (§2) is exactly what could
   silently drop it.
2. **The `terraform-get` protocol end to end** — the single highest-risk item:
   `curl -sL 'https://pigeon.dev/modules/scaleway/object-bucket/v4.1.1?terraform-get=1' | grep
   terraform-get` returns the expected `<meta>` tag post-cutover, and the same URL without a
   trailing slash 301s rather than 404s. Then a real `terragrunt init` against one leaf pinned to a
   `templates/terraform/*` tag and one pinned to a legacy `modules/*` tag.
3. **DNS and TLS**: `dig +short pigeon.dev` resolves to GitHub's Pages addresses;
   `https://pigeon.dev` serves with a GitHub-issued certificate; `https://www.pigeon.dev` 301s to
   the apex with no Cloudflare ruleset involved; Enforce HTTPS is on and the custom domain shows
   verified in the repo's Pages settings.
4. **`noisypigeon.com` is unaffected**: a push to `workloads/noisypigeon.com/src/**` still deploys
   it via `zola-sites-deploy.yml`; `blog-changelog.yml`'s `-f site=noisypigeon.com` dispatch still
   resolves against the trimmed `site` input; `mise run blog-build` still works from the relocated
   `fetch-templates.sh`.
5. **A theme release reaches both sites**: cut a `templates/zola-site` release and confirm both the
   in-repo `pigeon-dev-pages.yml` run and the cross-repo `noisypigeon.com` dispatch fire (§5).
6. **The decommission plans clean** (PR 5): `terragrunt plan` shows destroys scoped to exactly
   `wiki/bucket` and `wiki/iam`, and no diff at all in `project`, `state/*`, or `fastmail/dns`.
