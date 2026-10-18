# DEV-0154: Hoist `templates/` into its own `noisypigeon/pigeon.dev` repo

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-11.
- **Status**: Accepted; superseded in part by [ADR-0157](DEV-0157-hoist-adrs-to-pigeon-dev.md) (§8's no-move boundary for ADRs is reversed; nothing is renumbered or split).

## Context

`templates/` holds this repo's two versioned, independently-consumable artifacts: 13 Terraform
modules under `templates/terraform/<provider>/<module>/` (ADR-0110) and the shared Zola theme at
`templates/zola-site/` (ADR-0112). Neither is infrastructure this repo runs. Every other
top-level directory here is either live Terragrunt state (`workloads/*/terraform/`) or site
content (`workloads/*/src/`); `templates/` is a published library, consumed through the
`pigeon.dev/modules/<provider>/<module>/vX.Y.Z` short URLs (ADR-0109/0110/0136) and
`[extra].theme_version` (ADR-0113/0114/0139).

That it is published rather than run is already visible in the repo's own machinery. It has its
own release discipline (`release:*` labels, `template-release.yml`, the `release-pr` skill), its
own tag namespace, its own per-unit `CHANGELOG.md` files, and its own docs workflow
(`module-docs.yml`) — a parallel track that shares nothing with the Terragrunt CI
(`terragrunt-plan.yml`/`terragrunt-apply.yml`, ADR-0128/0129) beyond living in the same checkout.
ADR-0129 already acted on that separation once, scoping `template-release.yml`'s trigger to
`templates/**` and splitting the blog-changelog logic out of it, on the grounds that "template
versioning and blog content-changelogging are unrelated concerns that had only ever shared a
workflow file by historical accident". The same sentence applies one level up, to the directory.

`noisypigeon/pigeon.dev` already exists on GitHub, created empty earlier today — size 0, no
branches, no tags — pre-staged for this move. The name is deliberate: it is the host that already
serves these artifacts' import URLs.

### What makes this cheap, and what makes it expensive

Cheap: ADR-0109/0110 built a redirect layer precisely so a module's location could change without
consumers noticing. All 75 `source =` lines across `workloads/**/*.tf` name
`https://pigeon.dev/modules/...` and none of them change. ADR-0110 called that "the entire payoff
of building the redirect layer first", and this is the second time it pays.

Expensive: the thing that *resolves* those URLs lives here and reads `templates/` off the local
filesystem. `workloads/pigeon.dev/generate-module-redirects.sh` enumerates `git tag` in this
checkout, scrapes each module's `README.md` for its description and `## Usage` block (ADR-0141),
and emits a `git::` source naming `noisypigeon/noisypigeon.git`. `templates/zola-site/resolve-theme.sh`
symlinks or `git archive`s out of `$(git rev-parse --show-toplevel)`. `template-release.yml` writes
release posts into `workloads/pigeon.dev/src/content/releases/`. Each of those is a same-checkout
assumption, and the pigeon.dev site itself is staying here.

### The legacy tag era is not a footnote

Three tag prefixes exist: 32 ancestral `terraform/modules/*` (ADR-0037 era, permanently excluded
from the redirect layer by ADR-0109), 20 `modules/*` (ADR-0093 era), and 53 current
`templates/*` — 49 for the modules, 4 for the theme.

The 20 `modules/*` tags point at commits that predate `templates/` existing at all:
`git ls-tree --name-only modules/scaleway/project/v1.0.0` has no `templates` entry. A
`git filter-repo --path templates/` therefore cannot carry them into the new repo, and this is
not hypothetical. Of the 16 distinct versions this repo's leaves currently pin,
`scaleway/project/v1.0.0` exists **only** under the `modules/` prefix. Whatever the new topology
is, that one page has to keep pointing at `noisypigeon.git`.

Current released versions: 13 modules, latest `scaleway/compute-instance/v7.0.0` and
`scaleway/pigeon-cluster/v3.0.0`; theme at `templates/zola-site/v1.2.0`.

## Decision

Move `templates/` — with its history, its tags, and its release machinery — to
`noisypigeon/pigeon.dev`. Everything else in this repo keeps behaving identically, including the
pigeon.dev site, which stays.

### 1. The new repo's layout is `templates/` verbatim

Its root holds `templates/terraform/**` and `templates/zola-site/**` at byte-identical paths. A
repo containing nothing but `templates/` arguably wants that segment flattened away, and this
deliberately doesn't do it. Keeping the paths means every tag prefix, the redirect generator's
two-prefix allowlist regex, `module-docs.yml`'s 10-entry `working-dir` list, and
`template-release.yml`'s `find templates/terraform -mindepth 3 -maxdepth 3 -name versions.tf`
all keep working with no edit at all.

No module gets a major re-seed. ADR-0093's principle — "a module's source path is effectively part
of its public interface" — is not engaged here: both the public `modules/<provider>/<module>/vX.Y.Z`
URL path and the in-repo subdirectory stay exactly as they are. The only thing that moves is the
repo slug inside the `git::` URL the redirect page emits, which is not part of the interface any
consumer writes down.

### 2. Seeding by `git filter-repo --path templates/`

ADR-0037's merge recipe run in reverse:

```sh
git clone git@github.com:noisypigeon/noisypigeon.git /tmp/pigeon-dev-seed
cd /tmp/pigeon-dev-seed
git filter-repo --path templates/
git remote add origin git@github.com:noisypigeon/pigeon.dev.git
git push -u origin main
git push origin --tags
```

ADR-0037's observation is what makes this work: "`git filter-repo` preserves every tag,
repointing it at the corresponding rewritten commit". All 49 `templates/terraform/*/*/vX.Y.Z` and
4 `templates/zola-site/vX.Y.Z` tags land in the new repo on commits whose tree genuinely contains
the path their `git::` URL names.

This departs from ADR-0084's split mechanism (force-push a byte-identical copy of the full
history, then land one pruning commit in each repo) — that ADR's reasoning was that "splitting
apart doesn't have the tag/history-collision problems merging two histories does", which is true
of the *commits* but not of the *tags* here, since 53 of them must resolve as module sources
after the move. A path filter is the only thing that guarantees that.

Tags are **not** deleted from `noisypigeon`. They remain immutable historical pointers, every
`terraform/modules/*` and `modules/*` page depends on them continuing to exist, and §3 depends on
that too.

### 3. The redirect generator maps prefix to repo

`generate-module-redirects.sh` currently hardcodes one repo (`:55`):

```sh
git_source="git::https://github.com/noisypigeon/noisypigeon.git//${prefix}/${provider}/${module}?ref=${full_tag}"
```

It becomes a mapping off the prefix it has already matched:

- `modules` → `noisypigeon/noisypigeon` — a frozen set of 20 tags that can never grow again,
  because nothing will ever create another `modules/`-prefixed tag.
- `templates/terraform` → `noisypigeon/pigeon.dev`.

`github_url` (`:56`) and the overview page's `tree/main` link (`:128`) split the same way. The
theme-version pages' `github_url` (`:182`) moves wholesale to the new repo, since all 4 of those
tags move.

`url_path` (`:54`) is not touched. ADR-0110 called that line "the entire stable-URL guarantee",
and it is why this ADR rewrites zero consumer `.tf` files — the second time that decision has paid
for itself, after ADR-0136's hostname swap.

The 32 `terraform/modules/*` tags stay outside the allowlist regex, unredirected, exactly as
ADR-0109 fixed as a permanent boundary.

### 4. One shared blobless clone, fetched per build

A new `workloads/pigeon.dev/fetch-templates.sh` in this repo ensures a gitignored
`/.templates-src/` is an
up-to-date `--filter=blob:none` clone of `noisypigeon/pigeon.dev`, tags included. It runs as the
first step of any build that needs templates, and both consumers below share it, so a build
clones once rather than twice. Blobless keeps it cheap while still giving `git tag` and
`git archive` everything they need. It sits in `workloads/pigeon.dev/` next to the generator
that is its main consumer rather than in a new top-level `scripts/`, which means
`noisypigeon.com`'s build reaches across into `pigeon.dev`'s directory for it — accepted to
avoid adding a top-level directory for one file.

`generate-module-redirects.sh` then reads from two places instead of one: `$TEMPLATES_SRC` for the
`templates/terraform/*` and `templates/zola-site/*` tag lists, the module `README.md` files it
scrapes, and the `CHANGELOG.md` files §6 needs; and this repo's own `git tag` for the frozen
`modules/*` set. Its regenerate-all semantics, its warning on unexpected tag shapes, and every
line of its front-matter output are otherwise unchanged.

Nothing new is checked in. This is the same posture ADR-0139 settled on for themes — "nothing
under `themes/<name>` is ever committed … just a version named directly and resolved fresh by the
build tool" — now applied to the module metadata as well.

### 5. Theme resolution across the repo boundary

`resolve-theme.sh` is part of the theme's published interface (`templates/zola-site/README.md`
documents it as the pinning mechanism), so it moves with the theme. But it resolves
`$(git rev-parse --show-toplevel)` and reads `$REPO_ROOT/templates/$THEME_NAME`, which after the
hoist is a chicken-and-egg problem: a consuming site cannot run the script until it already has
the repo the script lives in.

Fix: the script derives its own root from `${BASH_SOURCE[0]}` (`<dir>/../..`) instead of asking
git, so wherever the clone is, is the root — it needs no argument and no environment variable,
and in-repo invocation is unchanged. An earlier draft of this ADR used a `TEMPLATES_REPO_ROOT`
environment override instead; that was abandoned on contact with the implementation, because it
fails *silently*: the copy of the script that actually runs is the one in the clone, so until the
clone contains the override-aware version, `git rev-parse --show-toplevel` quietly resolves the
**consuming** repo and the theme appears to resolve correctly while pointing at the wrong tree.
Deriving from the script's own path has no such transitional window. Both resolution modes
survive intact: `"main"` is still a symlink (now into the clone), and a pinned tag is still
`git archive templates/zola-site/vX.Y.Z | tar -x --strip-components=2`.

One ordering consequence remains either way: the clone's copy of `resolve-theme.sh` is the one
that runs, so §9's PR 2 carries this same patch into the new repo rather than relying on the seed
having been taken after PR 1.

One real semantic change: `"main"` used to symlink into this repo's live working tree, so editing
`templates/zola-site/` and reloading `zola serve` showed the edit immediately. It now symlinks
into a clone refreshed per build, so local theme iteration means working in the new repo's
checkout and pointing `TEMPLATES_REPO_ROOT` at it. That is the honest cost of the split, and it
lands on exactly one workflow: editing the theme and a consuming site in the same sitting.

`templates/zola-site/README.md`'s claim that pinning "requires the tag to exist in the consuming
clone's local git history … there is no network fetch involved" becomes false and is corrected in
the same change. ADR-0114 is amended in part here, not superseded — the `[extra].theme_version`
mechanism it designed is unchanged; only where the bytes come from moves.

Because `template-release.yml`'s zola-site detector matches only
`^templates/zola-site/(templates/|static/|theme\.toml$)`, a `resolve-theme.sh`-and-README change
cuts no tag. Both consumers stay on `theme_version = "main"`.

### 6. Release posts become generated rather than committed

`template-release.yml` moves to the new repo, where it can no longer write
`workloads/pigeon.dev/src/content/releases/`. Rather than reach across the boundary to write
content, the generator derives those posts from each module's `CHANGELOG.md` in the clone, using
the same parse ADR-0141's own backfill used: `## [X.Y.Z] - DATE` / `### <title>` / body /
`[#N](url)` becomes `title`/`date`/`slug`/`description` front matter plus body.

This reproduces today's set exactly. The 81 committed posts and the 81 `## [` entries across the
13 module CHANGELOGs are a one-for-one bijection, verified per module: compute-instance 35,
pigeon-cluster 13, object-bucket 8, iam-policy 7, block-volume 4, project 4, backblaze/api-key 2,
backblaze/bucket 2, iam-api-key 2, and 1 each for cockpit-observability,
compute-instance-config, grafana-dashboard, iam-application. No zola-site release posts exist
today and none are introduced.

The 81 files are deleted here, and `content/releases/*.md` joins `content/modules/*.md` and
`content/theme-versions/*.md` in `.gitignore` — generated, `_index.md` excepted, exactly the
existing pattern at `.gitignore:5-8`. ADR-0141's choice to commit them made sense when the
workflow writing them shared a checkout with the site; once it doesn't, generating them from the
changelog that is already their source of truth removes a cross-repo write rather than adding one.

### 7. The one remaining cross-repo coupling is a deploy dispatch

A tag cut in the new repo has to reach the site that publishes its redirect page. The new repo's
`template-release.yml` ends with a cross-repo dispatch in place of today's in-repo one (`:278`):

```sh
gh workflow run zola-sites-deploy.yml -R noisypigeon/noisypigeon --ref main -f site=pigeon.dev
```

with `-f site=all` on a zola-site release instead, since both sites track `"main"` and a theme
release affects both. ADR-0140 added that `site` input for exactly this class of caller.

Correspondingly, `zola-sites-deploy.yml` here loses its `templates/zola-site/**` push trigger
(`:9`) and its `THEME_CHANGED` branch (`:60`) — there is no longer any such path in this repo to
push to — and gains the §4 fetch step before `resolve-theme.sh` (`:122`).

**Prerequisite:** `BOT_GITHUB_TOKEN` must carry `actions: write` on `noisypigeon` in addition to
`contents: write` on `pigeon.dev`. This is the one piece that fails silently rather than loudly
if missed — the release still cuts its tag and the site simply never redeploys, leaving a version
whose short URL 404s. Confirm it before landing §9's PR 2.

### 8. What each repo keeps

Moving to the new repo: `templates/**` with history; `.github/workflows/template-release.yml`
(minus the §6 release-post write, plus the §7 dispatch) and `module-docs.yml` (verbatim — its 10
`working-dir` paths are unchanged by §1); `.claude/skills/release-pr/`, whose paths are likewise
unchanged and whose "this repo's templates/terraform/" prose is retargeted; a root `CHANGELOG.md`
that takes over the `[<provider>/<module>]` and `[zola-site]` rollup lines; a `CLAUDE.md` pruned
to templates scope; a `README.md` built from `templates/terraform/README.md`'s index; and a `.mise.toml` split by
tool domain, the same way ADR-0084 split it. Not `.github/scripts/adr-issue.sh`, despite
ADR-0084's precedent for keeping it in both repos: it appends issue links into `docs/adr/` files
in place, and this ADR keeps every ADR — including future template ones — in this repo, so there
would be nothing in the new repo for it to annotate.

Leaving this repo: `templates/`, those two workflows, the `release-pr` skill, and `templates/`-scoped
prose in `CLAUDE.md`, `docs/USAGE.md:15-16,57`, and `CHANGELOG.md:5-6`. Root `CHANGELOG.md`
*history* stays unmodified in both repos, following ADR-0084's judgement that "untangling which
historical bullet belongs to which repo is unrequested, high-effort, low-value busywork".

ADRs are **not** renumbered, split, or archived. All 29 `templates/`-referencing ADRs stay here,
as the decision history of the repo that made those decisions and still owns the site that serves
their output; the new repo's `CLAUDE.md` points back at `noisypigeon/noisypigeon`'s `docs/adr/`
rather than keeping a filtered copy. This differs from ADR-0084, which gave the departing repo a
filtered `docs/adr/`, because there the departing code was the *subject* of 51 ADRs; here the
subject of nearly every `templates/`-touching ADR is the monorepo's own layout and automation,
which is staying.

No existing ADR is superseded. ADR-0109 (§3, the `git_source` single-repo assumption) and
ADR-0114 (§5, theme resolution without a network fetch) are amended in part and say so above.

### 9. Four PRs, in order

0. **Seed the new repo's `main`** (§2). PR 1 points the build at it, so it has to resolve first.
   Nothing fires on this push — the new repo has no workflows until PR 2.
1. **This repo, mechanism only.** `workloads/pigeon.dev/fetch-templates.sh`, the generator
   rewrite (§3/§4/§6), `.mise.toml` rewiring, the `resolve-theme.sh`/README changes (§5), the
   `zola-sites-deploy.yml` changes, `.gitignore`, and the 81 release-post deletions. `templates/`
   is still present but nothing reads it locally any more.
2. **New repo, wired.** The two workflows, the `release-pr` skill, §5's `resolve-theme.sh` patch,
   and its own `CLAUDE.md`/`README.md`/`CHANGELOG.md`/`.mise.toml`. Confirm all 53 tags landed and
   that one `git::` fetch against a moved tag resolves, before touching this repo again.
3. **This repo, retire the automation.** Delete `template-release.yml`, `module-docs.yml`, and
   `.claude/skills/release-pr/`; fix the `CLAUDE.md`/`docs/USAGE.md`/`CHANGELOG.md` prose; land
   this ADR.
4. **This repo, remove `templates/`.** `git rm -r templates/`, and nothing else.

Steps 3 and 4 are separate PRs, and that is not cosmetic. A diff deleting `templates/` includes
11 files matching `template-release.yml`'s own zola-site detector
(`^templates/zola-site/(templates/|static/|theme\.toml$)`), and for `pull_request: [closed]`
GitHub runs the workflow file from the **base** branch. So a combined PR would fire the very
workflow it deletes: it would recreate the just-deleted `templates/zola-site/CHANGELOG.md`, commit
it to `main`, and cut a bogus `templates/zola-site/v1.3.0` tag and GitHub Release — while its
module step failed outright on `find templates/terraform` against a missing directory. Removing
the automation first makes PR 4 inert. The same ordering keeps `module-docs.yml`'s `**/*.tf` push
trigger from firing on the deletion too.

PR 3 must not open before PR 2 has pushed, or the repo sits in a state where every
`templates/terraform/*` redirect page names a repo that has no such tags. This is the same
sequencing discipline ADR-0110 and ADR-0136 both used, for the same reason: the first PR's output
has to already resolve before the second one relies on it.

Step 0's filter-repo surgery and push are performed by the user, following ADR-0052's precedent
for repo-boundary work on live content ("this ADR does not execute its own merge"); §2 is the
runbook for it. The four PRs themselves are ordinary work.

## Consequences

- A module or theme change no longer has to pass through a repo full of live Terragrunt state. It
  also no longer gets `terragrunt-plan.yml`'s `detect` job setting a `terragrunt/apply` status on
  it, which ADR-0129 made a required check — today a templates-only PR gets an immediate
  `success` from that job, and after the move it isn't gated by it at all.
- Conversely, a change that spans a module and its consumer — the common case for every
  `pigeon-cluster` revision — becomes two PRs in two repos, where the module's has to merge, tag,
  and deploy before the consumer's can pin it. That round trip already existed (the short URL has
  to resolve before `terragrunt init` can fetch it, so the tag always had to land first); what's
  new is that the two halves can no longer sit in one branch while being developed.
- Local module iteration keeps the escape hatch `templates/terraform/README.md` already
  documents: clone the repo as a sibling and `source = "../pigeon.dev/templates/terraform/..."`
  by relative path, bypassing the redirect layer entirely until the change is ready to tag.
- Every build of either Zola site now makes a network fetch it didn't before. `zola-sites-deploy.yml`
  already runs in a fresh checkout, so the clone is additive there; locally it means `mise run
  pigeon-dev-serve` needs connectivity on first run per clone.
- The redirect layer now spans two repos permanently, not transitionally. The `modules/*` →
  `noisypigeon` arm of §3's mapping is load-bearing for as long as any leaf pins
  `scaleway/project/v1.0.0`, and deleting those 20 tags from this repo would break live
  infrastructure.
- `noisypigeon` becomes, for the first time, a repo whose contents are entirely things it runs:
  `workloads/` and the docs/automation around it. The `templates/<kind>/` convention ADR-0110
  opened and ADR-0112 extended moves out wholesale rather than being abandoned — it's the new
  repo's top-level layout now, with room for a third `templates/<kind>/` that has nothing to do
  with this repo's workloads.

## Out of scope

- Executing the hoist, per §9. Not deferred — a deliberate boundary, following ADR-0052: the
  user performs repo-boundary git surgery on live, credential-adjacent content.
- Flattening `templates/` out of the new repo's root. Genuinely deferred: §1 keeps it purely to
  hold the blast radius down, and a later ADR could drop the segment, at the cost of new tag
  prefixes, a third allowlist arm in the generator, and ADR-0093's major-re-seed argument.
- Moving `workloads/pigeon.dev/` — the site, its Terraform, and its site-local
  `module-redirect.html`/`theme-redirect.html` — into the repo that now shares its name.
  Genuinely deferred, and genuinely tempting given the name collision, but that site is a
  workload with its own Scaleway project, state bucket, deployer IAM, and Cloudflare DNS
  (ADR-0130/0137); relocating it is the ADR-0130/0132/0133 self-sufficiency question over again,
  not part of this move.
- Deleting or rewriting any tag in `noisypigeon`. Not deferred — a permanent boundary: §2 and §3
  both depend on all 105 existing tags staying exactly where they point.
- Renumbering, splitting, or archiving this repo's ADRs, per §8. Not deferred — a deliberate
  boundary.
- Untangling the root `CHANGELOG.md`'s historical `[<provider>/<module>]` entries, per §8. Not
  deferred — a permanent boundary, following ADR-0084.
- Backfilling `## Usage` sections into the modules that lack one, and an RSS feed for
  `/releases/`. Both remain ADR-0141's open items, unaffected by which repo the modules live in.

## Verification

1. `mise run pigeon-dev-build` before and after PR 1, diffing `public/`. The only expected deltas
   are the `git_source`/`github_url` repo slugs on `templates/terraform/*` and `templates/zola-site/*`
   pages. Every `modules/*` page, every `url_path`, and all 81 release posts must come out
   byte-identical.
2. `curl -s 'https://pigeon.dev/modules/scaleway/project/v1.0.0?terraform-get=1' | grep terraform-get`
   still names `noisypigeon.git` — the legacy-prefix case from §3 — while
   `.../scaleway/compute-instance/v7.0.0` names `pigeon.dev.git`.
3. `git clone --filter=blob:none` of the new repo, then `git tag | wc -l` = 53, and
   `git ls-tree --name-only templates/terraform/scaleway/project/v1.0.0` shows `templates`.
4. The real test, since a short URL is only as good as what it fetches: `terragrunt init` in a
   `workloads/willowgraysen.com/terraform/pigeon-cli/bucket/*` leaf — these pin
   `scaleway/project/v1.0.0` alongside `templates/terraform`-era modules, exercising both sides of
   the §3 mapping in one unit — then `terragrunt plan` → "No changes".
5. `mise run blog-build`, confirming theme resolution for `noisypigeon.com`, a site that consumes
   the theme and nothing else.
6. Merge one trivial module PR in the new repo and walk the whole chain: tag cut, GitHub Release
   created, `CHANGELOG.md` entry written, cross-repo dispatch fired, this repo's site redeployed,
   and the new version's redirect page, overview-page version list, and release post all live.
