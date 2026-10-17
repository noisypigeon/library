# LIB-0015: Rename `noisypigeon/pigeon-lib` to `noisypigeon/library`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-17.
- **Status**: Accepted.
- **Amended 2026-10-17**: §3 step 2's "merged by hand" needed `gh pr merge
  --admin`. Each spoke's ruleset requires the `terragrunt/apply` status, which
  only the apply workflow sets, and that workflow runs from `main`, which still
  called the old name. The owner approved bypassing the ruleset for those three
  PRs only. The new `workflows` release turned out to be `v3.1.1` (one
  `release:patch` label), not a new minor.

## Context

LIB-0002 created this repo as `noisypigeon/pigeon-lib`, the hub of LIB-0001's
architecture. LIB-0013 then renamed the `willowgraysen` spoke to `runway`, so
that the repo name says what the repo is. This repo's name says it twice: the
`noisypigeon` owner already carries "pigeon", and "lib" abbreviates the one
word that describes it. `noisypigeon/library` follows the same rule as
`runway`, `garden` and `blog`.

A hub rename isn't as quiet as a spoke rename, because the spokes call into
the hub by name in four ways:

| Reference | Where | After a GitHub rename |
| --- | --- | --- |
| `uses: noisypigeon/pigeon-lib/.github/workflows/…@workflows/vX.Y.Z` | every spoke's workflow callers (ADR-0155, DEV-0155) | **fails**: GitHub doesn't redirect calls into a renamed repo |
| `https://github.com/noisypigeon/pigeon-lib.git` | each spoke's `fetch-lib.sh` (LIB-0002), and every `git::` source the module short URLs resolve to (LIB-0009) | redirected |
| `raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/…` | dashboard URLs (`grafana/dashboard`'s `url` input) | redirected |
| web links | READMEs, `theme.toml`, release posts | redirected |

GitHub's renaming documentation says it "will not redirect calls to an action
hosted by a renamed repository", and that such workflows fail with "repository
not found". A reusable workflow is called the same way, so this record assumes
it fails the same way. The moment this repo is renamed, every spoke's plan and
apply workflows stop working until the spoke points at the new name.

What doesn't break is the public module interface. A consumer's `source =` is
`https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z`, which
LIB-0009 made an interface of its own, independent of this repo's layout and
name. The `git::` source it resolves to follows the redirect until the garden
regenerates it.

## Decision

### 1. The repo is renamed in place to `noisypigeon/library`

The rename is GitHub's own repo rename. It keeps the repo ID, the PR history,
every tag and release, the Actions secrets (`BOT_GITHUB_TOKEN`), and the
fine-grained token scopes that name this repo by ID. The alternative, a new
repo mirrored from this one with this one archived, would avoid the outage in
§3. It would also lose all of that, and nothing would redirect.

### 2. Nothing a consumer pins changes

- **The module short URLs stay as they are** (LIB-0009). No leaf's `source =`
  changes, and every existing tag resolves under the new name.
- **Tag names stay as they are.** A spoke keeps its `.lib-version` and its
  `@workflows/vX.Y.Z` pins. Only the `owner/repo` in front of them changes.
- **The `LIB-` ADR prefix stays as it is.** It names the domain, not the
  repo, as `RUN-` did in LIB-0013 §3.

### 3. The cutover is ordered around the one reference that breaks

1. **Before the rename,** each spoke's fix is prepared and left unpushed:
   garden, blog and runway each get `uses: noisypigeon/library/…` at the pin
   they already have, a `fetch-lib.sh` that clones `library.git`, and updated
   prose. The hub's own change is prepared too: `generate-module-redirects.sh`'s
   `TAG_REPO` default, `zola-site/theme.toml`'s homepage, and prose.
2. **Rename,** then push the three spoke PRs at once. A `pull_request` workflow
   runs from the PR's own workflow file, so each plan already calls
   `noisypigeon/library`. With `root.hcl` unchanged, each must plan
   `No changes.` on every leaf. Each spoke PR is **merged by hand**: there's
   nothing to apply, and the apply workflow runs from the default branch,
   which is broken until the merge.
3. **Then merge the hub PR.** Its release dispatches `garden-pages.yml`, which
   now calls `noisypigeon/library`. Merged before garden's PR, it would leave
   a tagged release whose garden deploy fails.
4. **Then garden takes the new `workflows` release,** so its Pages build
   regenerates every `terraform-get` meta, overview link and release link
   with `noisypigeon/library`. Until then, they still name `pigeon-lib.git`,
   which redirects.
5. **Last, runway's dashboard URL** moves to the new raw path in its own PR,
   applied normally once its apply workflow works again. The fetched JSON is
   the same bytes, so it must plan `No changes.`.

Between steps 2 and 3, spoke CI on `main` is red, and nothing may be applied
in that window.

### 4. Live prose is updated, history is not

As in LIB-0013 §4: where text names the repo as it is today, it now says
`noisypigeon/library`, or "the library" in running prose. Records of what
happened keep `pigeon-lib`: ADRs, `CHANGELOG.md` entries, and citations like
`pigeon-lib#66`. GitHub's redirect keeps those links working.

### 5. `pigeon-lib` is retired

The old name is never reused, by a repo in `noisypigeon` or by a fork moved
into it. A repo created under that name would end every redirect at once: git
remotes, every `git::` source a not-yet-regenerated short URL hands out,
raw dashboard URLs, and every historical link.

## Consequences

- **A short, planned CI outage in every spoke,** from the rename until each
  spoke's PR merges (§3 step 2). It's the price of keeping the repo's identity.
- **`noisypigeon/noisypigeon`'s workflows break for good.** Its three callers
  pin `noisypigeon/pigeon-lib/…@workflows/v1.0.2` and fail with "repository
  not found". That's accepted: its last Terraform leaf must never be applied
  again (LIB-0014), and cleaning up that repo is out of scope.
- **Local clones follow the redirect** but should set their `origin` to
  `library.git`. A local folder may keep its old name.
- **Every reference that redirects is a dependency on §5.** Moving each one to
  the new name (§3 steps 4 and 5) shrinks that dependency without removing it,
  because historical links still go through the redirect.

## Out of scope

- **Repointing `noisypigeon/noisypigeon`'s workflow callers.** A permanent
  boundary, as in LIB-0014: that repo isn't changed by this record.
- **Bumping blog and runway to the new `workflows` release.** Not needed,
  because §3 step 2 keeps their pins valid under the new name. Each takes it
  when it next needs a hub change.
- **Renaming local folders.** Each owner's choice.

## Verification

1. The repo was renamed with the same repo ID (`R_kgDOVItaiA`), and
   `git ls-remote https://github.com/noisypigeon/pigeon-lib.git HEAD` still
   resolves. The old and new raw URLs of the `pigeon-cli` dashboard both
   return 200 with the same SHA-256.
2. garden#51, blog#42 and runway#19 each called `noisypigeon/library` at their
   existing pins. They planned `No changes.` on every leaf they ran (4, 10 and
   18 leaves) and were merged with `--admin` (Amended).
3. library#70 released `workflows/v3.1.1`, `terragrunt/root-hcl/v4.1.1` and
   `zola-site/v1.2.1`. Its garden and blog dispatches succeeded, and both
   Pages deploys passed.
4. garden#52 took `workflows/v3.1.1`. After a dispatched Pages build, a short
   URL's `terraform-get` meta names
   `git::https://github.com/noisypigeon/library.git//…` (checked for
   `scaleway/terraform-deployer-iam/v0.1.0` and `scaleway/object-bucket/v4.2.0`).
   A push touching only workflows doesn't trigger that build, which is why it
   had to be dispatched.
5. runway#20 moved the dashboard URL to `noisypigeon/library`. It planned
   `No changes.` on its 4 leaves, and the apply was 0/0/0 on each. It was
   merged by hand after auto-merge hit noisypigeon/noisypigeon#310.
6. As expected, `noisypigeon/noisypigeon`'s workflows now call a repo that
   doesn't resolve. They weren't changed (Out of scope).
