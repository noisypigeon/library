# DEV-0159: Hoist `noisypigeon.com/src` into its own `noisypigeon/noisypigeon.com` repo

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-12.
- **Status**: Accepted.

## Context

This repo has hoisted everything reusable or non-operational out of itself
today: `templates/` (the Terraform modules and `zola-site` theme) to
`noisypigeon/pigeon.dev` (ADR-0154), the job bodies behind every GitHub
Actions workflow to the same repo (ADR-0155), and the full ADR corpus itself
(ADR-0157). `pigeon.dev`'s own Zola site content made the identical move at
some point in that sequence too — `CLAUDE.md`, `docs/ARCHITECTURE.md`, and a
comment in this repo's own `.mise.toml` all assert it as settled fact, and
`pigeon.dev`'s former `pigeon-dev-build`/`pigeon-dev-serve` tasks are
confirmed gone from `.mise.toml` today, consistent with that site no longer
being built from here at all. None of those three sources can actually name
the ADR that did it: all three cite "ADR-0156," which is in fact "Simplify
CLAUDE.md to current-state-only documentation" — unrelated. No ADR in the
0031-0158 corpus documents a pigeon.dev-site hoist. This ADR treats the move
as established fact (the tree proves it happened) without repeating the
wrong citation; fixing it is someone else's cleanup, not this ADR's (see Out
of scope).

`noisypigeon.com` is the one workload whose own content — the blog at
`noisypigeon.com/src` — still lives here, and ADR-0158 put it on the exact
mechanism (`zola-site-pages.yml`, OIDC, no stored secrets) that made the
pigeon.dev-site move possible in the first place. Its own Out of scope
section named this directly: moving `noisypigeon.com` to GitHub Pages was
"the simplified slice of ADR-0156's pattern" (sic — see above) "that
actually applies here," leaving the repo-hoist itself for later. This is
that later.

Today `noisypigeon.com/` holds `CHANGELOG.md`, `fetch-templates.sh`,
`root.hcl`, `secrets.enc`, `src/`, and `terraform/`. The last two are
unrelated by construction: `terraform/` (`project`, `state/{bucket,iam}`,
`blog/dns`, `bluesky/dns`, `proton/dns`, `google-search/dns`) manages DNS,
state, and IAM, and no leaf in it references `src/` by path — the same
infrastructure/content split ADR-0154 drew between `templates/` and the
workloads that consume it. `fetch-templates.sh` and `CHANGELOG.md` exist
only to serve `src/`'s build and its own change history.

### This cutover is cheaper than ADR-0158's

ADR-0158 had to change DNS content: the apex CNAME moved from a
Cloudflare-proxied Scaleway bucket endpoint to `noisypigeon.github.io`,
DNS-only. That record is already in place and does not name any particular
repo — GitHub Pages resolves a custom domain by whichever repo currently has
it claimed and verified in that repo's own Pages settings, not by DNS
content. Which repo serves `noisypigeon.com` is therefore a GitHub-settings
fact, not a Terraform fact, and this move does not touch `blog/dns`, or any
other leaf, at all.

What does have to move is the two callers that read `noisypigeon.com/src/**`:
`noisypigeon-com-pages.yml`'s own header comment already states why it "has
to live here" today — `actions/deploy-pages` always targets the *calling*
repo's own Pages site — and after the hoist, "here" is the new repo.
`blog-changelog.yml` travels with it for the same reason: it writes into
`noisypigeon.com/CHANGELOG.md` and dispatches the deploy, both of which only
make sense colocated with the content. Both callers' job bodies already live
in `noisypigeon/pigeon.dev` (ADR-0155) and don't move again; only the thin
caller files relocate.

### The ADR-0154 §9 pitfall, re-encountered

`blog-changelog.yml` triggers on `pull_request: [closed]`, and GitHub
evaluates a `pull_request`-triggered workflow from the PR's **base** branch
— the same mechanism ADR-0154 §9 found forces `template-release.yml`'s
retirement and `templates/`'s removal into two separate PRs, since a single
combined PR would still fire the pre-deletion version of a workflow it
itself deletes. The same split applies here: retiring the two callers and
removing `noisypigeon.com/src/**` cannot land in the same PR.

## Decision

Move `noisypigeon.com/src/`, `noisypigeon.com/CHANGELOG.md`, and
`noisypigeon.com/fetch-templates.sh` — with history — to a new,
pre-created-empty `noisypigeon/noisypigeon.com`. `noisypigeon.com/terraform/**`,
`root.hcl`, and `secrets.enc` all stay here.

### 1. The new repo's layout is `noisypigeon.com/src/` verbatim

Not flattened to a bare `src/`. Same reasoning ADR-0154 §1 used to keep
`templates/` nested in the new `pigeon.dev` repo: every path-dependent
reference survives unedited. `noisypigeon-com-pages.yml`'s
`src_dir: noisypigeon.com/src` and `blog-changelog.yml`'s
`site_dir: noisypigeon.com` both move across repos with the exact same
values. `fetch-templates.sh`'s own `$(git rev-parse --show-toplevel)`-relative
design (it only ever asks for *its own* repo's root) needs no edit either —
it already resolves correctly in whatever repo it's cloned into.

### 2. Seeding by `git filter-repo`

ADR-0154 §2's recipe, scoped to three paths instead of one:

```sh
git clone git@github.com:noisypigeon/noisypigeon.git /tmp/noisypigeon-com-seed
cd /tmp/noisypigeon-com-seed
git filter-repo --path noisypigeon.com/src/ --path noisypigeon.com/CHANGELOG.md --path noisypigeon.com/fetch-templates.sh
git remote add origin git@github.com:noisypigeon/noisypigeon.com.git
git push -u origin main
```

No tags are at stake here — unlike ADR-0154's `templates/*` tag graph,
nothing resolves a short URL against this content — so there is no
ADR-0157-style "never push tags from the filtered clone" guardrail to carry
forward.

### 3. Four ordered steps, by blast radius

1. **New repo, inert.** Add `noisypigeon-com-pages.yml` and
   `blog-changelog.yml`, byte-identical to their current form here (per §1,
   no value changes). Enable GitHub Pages on the new repo and verify the
   site serves correctly on its default `*.github.io` URL. Nothing
   user-visible moves yet — mirrors ADR-0158 PR 1's own staging step.
2. **Manual GitHub/DNS settings, the actual cutover.** Set the custom domain
   `noisypigeon.com` on the new repo's Pages settings — it will report a
   failed DNS check at first, same as ADR-0158 PR 2's expected-and-harmless
   intermediate state — then clear the custom domain from the old repo's
   Pages settings. No DNS record changes (per Context, above); ownership of
   the verified custom domain is the entire cutover. Confirm the TLS
   certificate reissues on the new repo and that `www.noisypigeon.com` still
   redirects to the apex exactly as before. Reverting this one step alone
   (reclaim the domain on the old repo) is a complete rollback, the same
   property ADR-0158 §"Three PRs" relied on.
3. **This repo, retire the automation.** Delete `noisypigeon-com-pages.yml`
   and `blog-changelog.yml`; drop `.mise.toml`'s `blog-build`/`blog-serve`
   tasks (mirroring pigeon.dev's own now-absent `pigeon-dev-build`/
   `pigeon-dev-serve` — once a site's content leaves, this repo stops
   offering to build it); update `CLAUDE.md`'s layout prose and
   `docs/ARCHITECTURE.md`'s workload table (`noisypigeon.com`'s `src/`
   column becomes "— (its site moved to `noisypigeon/noisypigeon.com`)",
   matching the exact phrasing already used for `pigeon.dev`'s row); and fix
   root `CHANGELOG.md`'s `noisypigeon.com` link — which, independently of
   this move, still points at the pre-flatten `workloads/noisypigeon.com/CHANGELOG.md`
   path — to point at the new repo instead. Content is still present in this
   repo at this point but nothing here reads it any more.
4. **This repo, remove the content.** `git rm -r noisypigeon.com/src noisypigeon.com/CHANGELOG.md noisypigeon.com/fetch-templates.sh`,
   and nothing else. Kept separate from step 3, per the Context section's
   `pull_request: [closed]` base-branch pitfall — step 3 must already be
   merged before this step's PR opens, or the still-live `blog-changelog.yml`
   fires on this PR's own merge and tries to write a changelog entry into a
   directory this same PR just deleted.

Step 2's filter-repo surgery and the Pages/DNS settings changes are
performed by hand, following ADR-0052's precedent for repo-boundary and
credential-adjacent work; steps 1, 3, and 4 are ordinary PRs.

## Consequences

- A `noisypigeon.com` content change — a new post, a theme-version bump —
  becomes a PR in a repo with no Terragrunt gate and, most likely, no branch
  protection at all: ADR-0157 found `pigeon.dev` has none (`rulesets` empty,
  `branches/main/protection` 404), and the new repo is seeded from the same
  posture. Lower-stakes than ADR-0155's equivalent concern (this is content,
  not CI or infrastructure), but worth naming rather than silently
  inheriting.
- `noisypigeon.com`'s "Terraform self-sufficient" bootstrap (ADR-0132)
  narrows to exactly its DNS, state, and IAM leaves — no content, no deploy
  automation — completing the trajectory ADR-0158 already put it on, and
  landing it in the same shape ADR-0156's (so-cited) move left `pigeon.dev`
  in.
- Local iteration loses `mise run blog-build`/`blog-serve`. Editing
  `noisypigeon.com` content means cloning the new repo directly — the same
  tradeoff already accepted for `pigeon.dev`'s site, not a new one.
- This repo's `git log` retains commits for content no longer checked out,
  same unavoidable side effect every prior hoist ADR here has accepted.
- `fetch-templates.sh`'s blobless-clone-of-`pigeon.dev` pattern now runs in a
  third repo. No design change — one more consumer of an already-proven
  mechanism.

## Out of scope

- Moving `noisypigeon.com/terraform/**`, `root.hcl`, or `secrets.enc`.
  Permanent boundary, same one ADR-0154 §8 drew for `templates/`'s
  consumers: the new repo holds published/served content, not a
  Terraform-self-sufficient workload.
- Pinning the reusable workflows the new repo calls (`zola-site-pages.yml`,
  `blog-changelog.yml`) to a `workflows/vX.Y.Z` tag instead of `@main`.
  Genuinely deferred, same gap ADR-0155 §6 and ADR-0158 already raised —
  reuse that tracked issue rather than filing a third one.
- Adding branch protection or required checks to the new
  `noisypigeon/noisypigeon.com` repo. Genuinely deferred, the same open gap
  ADR-0157 flagged for `pigeon.dev`.
- Correcting the wrong "ADR-0156" citation for the pigeon.dev-site hoist in
  `CLAUDE.md`, `docs/ARCHITECTURE.md`, and `.mise.toml`. Pre-existing and
  unrelated to this move; noted in Context so this ADR doesn't repeat it,
  not fixed here.

## Verification

1. Clone the new repo; `git log --follow noisypigeon.com/src/content/posts/<oldest-post>.md`
   shows real pre-move history, not a single squashed commit.
2. In the new repo, run the `fetch-templates.sh` → `resolve-theme.sh` →
   `zola build` sequence (the same steps `blog-build` ran here) and diff
   `public/` against a pre-move build from this repo. Byte-identical apart
   from the `SITE_COMMIT_SHA` footer, which legitimately changes with the
   new repo's own commit SHA.
3. Confirm step 1's new-repo `noisypigeon-com-pages.yml` run deploys cleanly
   on the default `*.github.io` URL, before any DNS/custom-domain change.
4. After step 2's cutover: `curl -sI https://noisypigeon.com` resolves and
   serves the site; `www.noisypigeon.com` still redirects to the apex; the
   old repo's Pages settings no longer show the domain as claimed.
5. Merge one trivial content PR in the new repo (a typo fix) and confirm
   both `noisypigeon-com-pages.yml` redeploys and, on merge,
   `blog-changelog.yml` writes a changelog entry.
6. `terragrunt plan` across `noisypigeon.com/terraform/**` in this repo
   shows "No changes" throughout steps 3 and 4 — nothing in Decision ever
   touches a `.tf`/`.hcl` file.
