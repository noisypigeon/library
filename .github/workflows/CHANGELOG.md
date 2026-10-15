# Changelog

All notable changes to the reusable CI are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.6] - 2026-10-15

### Stop the shared concurrency group dropping a release

`template-release`, `root-changelog` and `module-docs` all declared `concurrency.group: main-writer` with `cancel-in-progress: false`.

**GitHub keeps at most one *pending* run per concurrency group, and cancels any previously-pending run when a third arrives.** A `.tf` merge triggers all three of these. So one is always lost — and it was the release.

### It already cost a real release

PR #9 merged, and:

```
template-release  pull_request  completed/cancelled   ← the release
module-docs       push          completed/success
root-changelog    pull_request  completed/success
```

`root-changelog` started and held the group, `template-release` went pending, `module-docs` arrived 1 second later and displaced it.

Outcome: **no tag, no Release, no module `CHANGELOG.md` entry** — and because `root-changelog` had *correctly* stood down for a releasing PR, no root changelog line either. A labelled release PR merged to a completely silent outcome. Nothing failed loudly; the run just said `cancelled`.

### Why four earlier merges didn't hit it

The failure is timing-dependent and shape-dependent. `module-docs` triggers on `**/*.tf`, so a `.github/`-only change triggers two of the three — and two fit, one running and one pending. Every merge in this repo so far has been structural. The first genuine module release found it immediately, which is exactly why that release was worth doing before anything depended on it.

### The fix

Each workflow gets its own group: `main-writer-release`, `main-writer-rollup`, `main-writer-docs`. Nothing can displace anything.

That removes the serialization those groups were providing, so the two writers we control now **retry a rejected push** — up to five times, re-fetching and rebasing each round, with a backoff:

```bash
for attempt in 1 2 3 4 5; do
  git fetch origin main
  if ! git rebase origin/main; then
    git rebase --abort || true
    echo "::error::rebase onto origin/main conflicted; refusing to guess"
    exit 1
  fi
  if git push origin HEAD:main; then echo "Pushed on attempt ${attempt}."; exit 0; fi
  echo "Push rejected (attempt ${attempt}/5); another writer won the race."
  sleep $((attempt * 5))
done
```

**A rebase conflict stays fatal.** A rejected push means someone else moved `main` and rebasing is correct; a conflict means two writers touched the same lines, and that's the `pigeon-lib#2` → `#3` double-write class of bug — guessing there is worse than failing.

For a releasing PR the writers touch disjoint files anyway (`template-release` owns the root changelog, `root-changelog` stands down, `module-docs` writes READMEs), so a conflict should mean a genuine defect.

`module-docs` pushes through `terraform-docs/gh-actions`, so its push isn't retry-protected here. Low stakes — it only regenerates README tables and self-heals on the next `.tf` change.

### After this

Re-running PR #9's cancelled run to recover `terraform/scaleway/project/v2.0.1`. The state is clean for that: the merge commit is on `main` and none of the four release artifacts were written, so the re-run has nothing to collide with.

`actionlint` clean on all three files. (`terragrunt-run.yml` reports a pre-existing SC2242 that also reproduces at `origin/main`; untouched here.)


[#10](https://github.com/noisypigeon/pigeon-lib/pull/10)

## [1.0.5] - 2026-10-15

### The Pages deploy timeout ceiling is hard, not a default

**#7 does not work, and this corrects it.**

`actions/deploy-pages` clamps the `timeout` input to a hard maximum of **600000 ms**. #7 set `1200000`, and the action's own log says what became of it:

```
timeout: 1200000
##[warning]Warning: timeout value is greater than the allowed maximum
           - timeout set to the maximum of 600000 milliseconds.
```

So #7 was inert in the worst way: it set the value back to the exact default it was trying to raise, and added a warning to every deploy from then on. Caught in `pigeon.dev#20`'s deploy log, which is the first deploy that actually ran the change — the step then succeeded in 43 s, so the raised value was never the reason it passed.

I had the input name right and verified it against the action's echoed inputs. What I didn't check was whether the value was *accepted*, and "600000" was sitting there in that same echo as the clue that it was a ceiling rather than a default.

### What this changes

`timeout: 600000` — equal to the default, so behaviour is unchanged and the warning stops. Kept rather than deleted because it documents the ceiling at the exact point someone would try to raise it, which is the mistake #7 made. The comment carries the warning text verbatim so the next reader doesn't have to discover it from a log.

### What this means for the wedge

**The orphaning risk is unmitigated, and cannot be mitigated this way.** Waiting longer is not available at any price:

- 600 s is the ceiling, so the action will always give up while GitHub may still be working.
- When it does, it cancels a deployment the Pages *service* still holds, and later deployments fail with `due to in progress deployment` until a server-side reaper clears it — ~45 minutes in the one incident we have.
- No client-reachable API shortens that. `POST .../cancel` returns 204 and is reflected in the read path without releasing the creation lock; a Deployments-API status write is accepted with no effect; reruns fail identically.

That makes this a tracked issue rather than a fixed bug, and raises its priority — it's the one failure mode in this architecture with no self-service recovery. Filing it against `noisypigeon/noisypigeon` per ADR-0031 with the full log evidence, since "wait for a reaper" is not a conclusion anyone should have to re-derive at 2am.

Cuts `workflows/v1.0.5`; `pigeon.dev` re-pins in the follow-up.


[#8](https://github.com/noisypigeon/pigeon-lib/pull/8)

## [1.0.4] - 2026-10-15

### Raise the Pages deploy timeout to 20 minutes

`actions/deploy-pages` defaults to a **600000 ms** timeout. That default is what orphaned `pigeon.dev`'s Pages deployment yesterday and blocked four consecutive deploys.

### What happened

PR #17's merge created a deployment that reported `Current status: updating_pages` for **110 consecutive polls** — that was the only status it ever reached. At 10 minutes the action's own timeout fired:

```
16:26:13Z  Current status:
16:26:13Z  ##[error]Timeout reached, aborting!
16:26:14Z  Canceled deployment with ID e936dae…
```

It self-cancelled a deployment the Pages **service** still held. Every later deployment then failed with `due to in progress deployment. Please cancel e936dae… first` for ~45 minutes, until a server-side reaper released it.

### Nothing could clear it from the client side

Worth recording, because the recovery is non-obvious:

- `GET /pages/deployments/<sha>` reported `{"status":"deployment_cancelled"}` while `POST /pages/deployments` kept 400ing about that same sha. **The two sides of the Pages API disagreed.**
- `POST /pages/deployments/<sha>/cancel` returned **204** twice and was reflected in the read path — it was not a no-op — but did not release the creation lock.
- `POST /deployments/<id>/statuses -f state=inactive` was accepted, no effect.
- Four `deploy` reruns, including a fresh `workflow_dispatch` on a different build version, all failed identically.

Everything on our side was ruled out: zero in-flight runs, no wait timer or required reviewer on the `github-pages` environment, all deployments terminal, cert approved and domain verified, and `noisypigeon.com` deployed 5/5 successfully in the same window — including two concurrent runs — so it was neither an outage nor a concurrency fault.

### The change

`timeout: 1200000` (20 minutes), with a comment explaining why the default is dangerous rather than just that it was raised.

This **reduces the odds, it does not remove them** — a slow-enough deployment still self-cancels. So the incident is also being filed as a tracked issue, since the recovery path is "wait for a reaper" and that is worth writing down somewhere findable.

Input name verified against the action's own echoed inputs (`timeout: 600000`, `error_count: 10`, `reporting_interval: 5000`) rather than assumed, since an unknown input would warn and change nothing. `actionlint` clean.

### On merge

Touches `.github/workflows/`, so `template-release.yml` cuts **`workflows/v1.0.4`**. `pigeon.dev` re-pins to it in the next PR, which retires its own automation and so touches `.github/` anyway. `noisypigeon.com` stays on `v1.0.2` — its deploys are healthy.


[#7](https://github.com/noisypigeon/pigeon-lib/pull/7)

## [1.0.3] - 2026-10-14

### Follow pigeon.dev's DEV- prefix rename

[DEV-0161](https://github.com/noisypigeon/pigeon.dev/pull/17) flattened `pigeon.dev`'s ADR corpus to `adr/` and re-prefixed it `PD-` → `DEV-`. This repo holds **133** of those citations, so they follow.

### Why rewrite rather than grandfather

PD-0160 grandfathered 1,100+ bare `ADR-NNNN` on volume: rewriting them would churn published changelog entries and another repo's `.hcl`/`.tf`. `PD-` carries none of that weight and was one day old, so DEV-0161 rewrote it instead — leaving **two** live spellings for that corpus rather than three. This PR is this repo's share of that.

Breakdown of the 133:

| Where | Count |
| --- | --- |
| `LIB-0001` + `LIB-0002` | 82 |
| five published module changelogs | 20 |
| `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `terraform/README.md`, the skill | 14 |
| workflows and scripts | 17 |

### The published changelogs are included, deliberately

NPC-0000's precedent is that published changelog copy is **not** retrofitted to a later layout — the reason those files still carry `docs/adr/` paths that stopped existing two moves ago. It doesn't bite here, and I checked rather than assumed:

- Those versions have **no GitHub Release in this repo** to diverge from (`gh release view` → `release not found`). The historical Releases live in `noisypigeon` under the old `templates/terraform/…` tag names.
- The site's release posts are **generated** from these files, so rewriting keeps file and published post consistent rather than splitting them.

DEV-0161's permanent boundary covers bare `ADR-NNNN`, not `PD-`, so this is in scope rather than against it.

One quotation needed care: `LIB-0002` quotes LIB-0001's own phrase *"re-opens every coupling PD-0156 closed"*. Since LIB-0001 is rewritten in the same commit, the quote stays an accurate quotation of its source.

### Verified

- `grep -r 'PD-'` over the repo returns **0**.
- Bare `ADR-NNNN` is **334 before and after** — the grandfathering is not collateral damage.
- `shellcheck` clean on both fetched scripts and `resolve-theme.sh`; `actionlint` clean apart from the pre-existing `terragrunt-run.yml` SC2242 that predates this repo.
- The generator still produces 49 / 13 / 4 / 87 after its comment rewrite — same counts as before.

### On merge

Touches `.github/workflows/` and `.github/scripts/`, so `template-release.yml` cuts **`workflows/v1.0.3`** with this body as its changelog entry and Release notes. No module or theme release: no `.tf` and no theme asset changes.

The five callers stay pinned at `v1.0.2`. A pin exists so it needn't track latest, and the delta here is comment text — but `pigeon.dev` will pin **v1.0.3** when it starts fetching, so it gets the DEV-corrected scripts from the outset.

[#6](https://github.com/noisypigeon/pigeon-lib/pull/6)

## [1.0.2] - 2026-10-13

### Version the generator with the workflows track

Corrects a placement mistake from #4, before Phase C pins anything to a version.

### The gap

I put `generate-module-redirects.sh` at the repo root. The `workflows/` release predicate covers `.github/workflows/*.yml` and `.github/scripts/` — so the generator sat outside it. A spoke pinning `@workflows/vX.Y.Z` would have got a pinned *workflow* and a generator tracked from `main`: invariant 2 half-satisfied, in exactly the branch-tracking direction it exists to forbid. A hub commit touching the generator would have reached every site's next build with no version change to show for it.

Moving it beside `root-changelog.sh` — the other script spokes fetch — means **one pin covers everything a spoke takes from the hub**.

### The path arithmetic, re-verified rather than assumed

`LIB_ROOT` is derived from `${BASH_SOURCE[0]}` precisely so the script finds the clone it was fetched into rather than the consuming site's repo. Moving the file down two directories invalidates that derivation — the same class of breakage the flatten caused in `resolve-theme.sh`, where `../..` silently became one level too high.

So it climbs two levels now, and the proof is empirical: the generator's output from `.github/scripts/` is **byte-identical** to its output from the root — same 49 / 13 / 4 / 87 counts, and `diff -r` across all three content directories is clean.

The comment now also says *why* the arithmetic is what it is, so the next move doesn't get it wrong by inheritance.

### On merge

This touches `.github/scripts/`, so it fires the `workflows/` track and cuts **`workflows/v1.0.2`** — and that is the ref Phase C pins into five caller files across two repos. I'll confirm the cut version before writing it anywhere, since a typo'd ref is how `noisypigeon`'s merge gate gets stuck.

`root-changelog.yml` stands down; `template-release.yml` writes the `[workflows]` line.

[#5](https://github.com/noisypigeon/pigeon-lib/pull/5)

## [1.0.1] - 2026-10-13

### Stand down root-changelog for the workflows release track

Fixes a bug I introduced in #2.

### What broke

#2 added `.github/` as a third releasable unit to `template-release.yml`, but left `root-changelog.yml`'s stand-down predicate checking only the module and theme arms. So on a `.github/`-only PR both workflows concluded they owned the root changelog line:

- `root-changelog.yml` saw "not a release" → wrote `- [ci] …`
- `template-release.yml` saw "release" → wrote `- [workflows] …`

Both insert into the same `## YYYY-MM-DD` section, so the second one to rebase hit `CONFLICT (content): Merge conflict in CHANGELOG.md` and `template-release`'s commit step failed.

DEV-0160 named this risk in the same breath as it created it — the predicates are duplicated across two workflows on purpose, and it wrote that "if one drifts, a PR gets either two root lines or none". This is that drift, one commit after the track was added. The fix is the third arm, and the comment now says what happened so the next person adding a track sees the cost of forgetting.

### Nothing was lost

The collision failed *before* the tag step, so #2 cut no tag and no Release — `git tag -l` was still 53 afterward. `workflows/v1.0.0` has since been seeded by hand at `main`, with the GitHub Release carrying the entry #2 already wrote for it, exactly as #2's changelog entry said would happen.

#2's own root line reads `[ci]` rather than `[workflows]`, which is accurate in retrospect: it released nothing.

### A correction to something #2's body asserted

I said `template-release.yml` wouldn't fire on #2's merge because "a `pull_request: closed` workflow runs from the base branch" — DEV-0154 §9's reasoning, which I took at face value. **It fired**, and the run's step list proves it used the *head* version: it executed "Determine reusable-CI change", a step that only existed on the branch.

So for `pull_request`, GitHub evaluates both the `paths:` filter and the job bodies from the PR's merge commit, not the base. DEV-0154's conclusion — split "retire the automation" from "delete the content" into separate PRs — is still the prudent order, but its stated *reason* doesn't hold, and anything relying on that reason should be re-checked rather than inherited. I'll carry the correction into LIB-0002.

### On merge

This PR touches `.github/`, so with the fix applied from head: `root-changelog.yml` stands down, and `template-release.yml` cuts `workflows/v1.0.1` with this body as its changelog entry and Release notes — the first release this track cuts on its own, and the real test of it.

[#3](https://github.com/noisypigeon/pigeon-lib/pull/3)

## [1.0.0] - 2026-10-13

### Seed the reusable CI's version track

`workflows/v1.0.0` is a seed tag, written by hand rather than by
`template-release.yml`, because the automation that cuts this track is itself
introduced by the PR that this entry documents — and a `pull_request: closed`
workflow runs from the **base** branch, so the version it adds cannot cut its
own first release. The same bootstrapping pattern DEV-0110 used for its five
module seed tags.

It marks the reusable CI as it stood when `pigeon-lib` was stood up by LIB-0002:
the five workflows the spokes call (`terragrunt-detect`, `terragrunt-run`,
`blog-changelog`, `interaction-limits-renew`, `zola-site-pages`), plus
`.github/scripts/root-changelog.sh`, which they fetch.

**No behaviour change from the last `@main` state the spokes consumed**, beyond
what LIB-0002's flatten already required: `zola-site-pages.yml` takes
`fetch_script`/`theme_script` instead of a hardcoded `.templates-src` path, and
`zola-site-deploy.yml` is gone — it had no caller in any repo and its own
`:60` hardcoded a path into a caller's checkout that DEV-0159 had moved away.

From here the track behaves like the other two: one `release:*` label per PR,
the PR body becomes this file's entry and the GitHub Release notes verbatim.

PR: see LIB-0002.
