# DEV-0155: Hoist `.github/workflows/` to `noisypigeon/pigeon.dev` as reusable workflows

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-11.
- **Status**: Accepted.

## Context

ADR-0154 moved `templates/` into `noisypigeon/pigeon.dev`, taking `template-release.yml` and
`module-docs.yml` with it. Four workflows remain here:

| Workflow | Lines | What it is |
| --- | --- | --- |
| `terragrunt-apply.yml` | 216 | `terragrunt apply` on a `terragrunt apply` PR comment, then auto-merge |
| `terragrunt-plan.yml` | 193 | `terragrunt plan` on PRs, and the `terragrunt/apply` merge gate |
| `blog-changelog.yml` | 130 | noisypigeon.com's changelog entry and daily digest post |
| `interaction-limits-renew.yml` | 19 | monthly re-application of the repo's interaction limit |

This hoists their job bodies to `pigeon.dev` and calls them back from here.

### This is reuse of job bodies, not a relocation

GitHub's mechanism is reusable workflows (`workflow_call`), and it does not permit hoisting a
workflow wholesale: a trigger cannot live in another repo. Every one of these four keeps a file
here carrying its `on:` block, and what moves is the job underneath. The honest description of
the end state is four thin callers here and five called workflows there, not "the workflows moved".

Reusable workflows also have to live in the called repo's `.github/workflows/`. They cannot sit
under `templates/`, so this lands beside `pigeon.dev`'s own release automation rather than inside
the templates convention that repo was created for.

### What the reuse is actually worth

There is no second consumer today, so the reuse itself is speculative, and this ADR does not
pretend otherwise. The concrete win is narrower and real: `terragrunt-plan.yml` and
`terragrunt-apply.yml` are roughly 70% the same file. Both run the same mise setup, the same sops
secret masking, the same cache clearing, the same `terragrunt.hcl`-walking `--filter` computation
(ADR-0138's workaround for an upstream gap), and the same truncate-and-minimize PR comment
machinery. They differ in the subcommand, the checkout ref, and an apply-only merge gate.

That duplication is not theoretical. **Every** commit that has ever substantively changed either
file changed both: six of them — ADR-0124 creating the pair, ADR-0128 adding
`--filter-allow-destroy`, ADR-0129 scoping the jobs, ADR-0134 reworking the PR comments, ADR-0138
adding the `--filter` walk, and one operational fix (#252). Not once has a change applied to only
one. Collapsing them removes about 140 duplicated lines and, more to the point, removes the
standing opportunity to update one and forget the other.

The cost is equally concrete: a CI change becomes a change in another repo, and at `@main` this
repo's required merge check depends on another repo's HEAD. §6 covers that.

### Verified before deciding

Four things the design rests on, checked against the live API rather than assumed:

- **`pigeon.dev` is public, so its reusable workflows are callable with no configuration at all.**
  `GET /repos/noisypigeon/pigeon.dev/actions/permissions/access` answers `422 Access policy only
  applies to internal and private repositories` — that refusal is the confirmation.
- **Calling a reusable workflow renames jobs to `caller / called`, and that does not break the
  merge gate.** It would, if the gate were a check run matched by job name. The `main` ruleset
  requires exactly one check, `terragrunt/apply`, and that is a *commit status* written through
  `repos.createCommitStatus` with an explicit `context` string, so the job rename is cosmetic.
- **A stuck gate is recoverable.** The ruleset carries two `bypass_mode: always` actors. This is
  what makes a live `@main` dependency tolerable underneath a required check.
- **`actions/checkout` in a called workflow checks out the *caller's* repo**, and `github.*` is the
  caller's context throughout. That is what lets these jobs keep reading `workloads/`, `.env.enc`,
  and `workloads/noisypigeon.com/CHANGELOG.md` after they move.

The default workflow token permission here is `read`, which is why every caller declares its own
`permissions` block (§5).

## Decision

### 1. Five reusable workflows land in `pigeon.dev/.github/workflows/`

| New file | Replaces | Shape |
| --- | --- | --- |
| `terragrunt-run.yml` | the bodies of both terragrunt workflows | one job, `command: plan\|apply` |
| `terragrunt-detect.yml` | `terragrunt-plan.yml`'s `detect` job | sets the gate status, outputs `affects-leaves` |
| `zola-site-deploy.yml` | `zola-sites-deploy.yml`'s `deploy` job | **one** site, parameterized |
| `blog-changelog.yml` | its `changelog` job | site paths as inputs, defaulted |
| `interaction-limits-renew.yml` | its `renew` job | unchanged — already generic |

They sit next to `template-release.yml` and `module-docs.yml`, which are that repo's own CI rather
than shared definitions. The distinction is by `workflow_call` in the trigger, not by filename:
anything with it is called from elsewhere, anything without it is that repo's own.

### 2. The two terragrunt workflows collapse into one parameterized file

This is the payoff described above. `terragrunt-run.yml` takes `command` (`plan` or `apply`) and
`checkout_ref`, and gates on `inputs.command == 'apply'` the four pieces that genuinely diverge:
the eyes/👍/👎 comment reactions, the comment marker, the comment heading, and the
merge-gate-plus-auto-merge step (ADR-0134). Everything else is shared verbatim.

`detect` becomes its own file rather than a second job inside `terragrunt-run.yml`, because it is
plan-only and its result has to gate the run. It declares a `workflow_call` output, so the plan
caller keeps exactly the shape it has today — `needs: detect` plus
`if: needs.detect.outputs.affects-leaves == 'true'`.

### 3. `zola-sites-deploy.yml` keeps its matrix here, deliberately

The one exception to "the job body moves", and the reason is a hard constraint rather than taste.
That workflow reads `secrets[matrix.access_key_secret]` — a *dynamic* secret lookup — and a
reusable workflow's `workflow_call.secrets` must be statically declared. Pushing the matrix down
would make the whole thing depend on `secrets: inherit` resolving a dynamic index inside the called
workflow.

So the `detect` job and the matrix stay here, and the called workflow deploys exactly one site:
`src_dir`, `bucket`, `build_cmd` and `extra_step` as inputs, `scw_access_key` and `scw_secret_key`
as two declared secrets. The caller resolves `${{ secrets[matrix.access_key_secret] }}` in its own
context, which is precisely what happens today, and passes the values down. That sidesteps the
constraint instead of betting against it.

It is also the more honest decomposition. *Which* sites exist is this repo's business — they are
its workloads. *How to build and ship one Zola site* is the part another repo could use.

### 4. Secrets: `inherit` where the name is fixed, declared where it isn't

`terragrunt-run`, `blog-changelog` and `interaction-limits-renew` take `secrets: inherit`, each
needing one fixed, named secret — `SOPS_AGE_KEY`, `BOT_GITHUB_TOKEN`, `GH_ADMIN_TOKEN`
respectively. `zola-site-deploy` takes its two Scaleway keys as explicitly declared secrets, per
§3.

`terragrunt-detect` is passed no secrets at all: it writes the commit status through
`actions/github-script` on the default `GITHUB_TOKEN`, so what it needs is the caller's
`statuses: write` permission (§5), not a secret.

### 5. Callers keep triggers, permissions, concurrency, and the event gates

Each caller here retains its `on:` block, its `permissions:` block, its top-level `concurrency`
group, and its event-level `if:` conditions.

The last of those is a deliberate choice, not an artefact of what `workflow_call` happens to
allow. `terragrunt-apply.yml`'s gate — `github.event.comment.body == 'terragrunt apply'` and an
`OWNER`/`MEMBER`/`COLLABORATOR` author association — is the authorization boundary for applying
real infrastructure to real Scaleway projects. It stays in the repo whose infrastructure is at
stake, reviewable in the same diff as the leaves it protects, rather than in a repo whose stated
purpose is publishing templates.

### 6. Callers pin `@main`, and what that costs

`@main`, live, matching how both Zola sites already consume the `zola-site` theme
(`theme_version = "main"`, ADR-0114/0139) and the clone `fetch-templates.sh` maintains. One PR
changes CI.

The risk is specific enough to name precisely. If `terragrunt-detect.yml` becomes unparseable on
`pigeon.dev`'s `main`, the caller fails to load, the `terragrunt/apply` commit status is never
written, and **every** PR in this repo blocks on a required check that can no longer resolve —
including the PR that would fix it. That is survivable only because of the two `bypass_mode:
always` actors on the ruleset, and that is the reason this ADR is willing to accept a live ref
under a required check at all. A `workflows/vX.Y.Z` tag track is the documented escape hatch if it
ever actually bites.

### 7. One latent fragility the move forces us to fix

`blog-changelog.yml` ends with `gh workflow run zola-sites-deploy.yml --ref main -f site=noisypigeon.com`,
with no `-R`. That works today only because `gh` infers the repository from the git remote of the
checkout it happens to be standing in. Once the step is defined in another repo, relying on that
inference is a coincidence rather than a design, so it becomes explicit:
`-R ${{ github.repository }}`.

### 8. What does not move

`.github/scripts/adr-issue.sh`. No workflow invokes it — `mise run adr-issue` does — and it appends
issue links into `docs/adr/` files in place, which live here. Same reasoning that kept it out of
`pigeon.dev` in ADR-0154 §8.

### 9. Three PRs, ordered by blast radius

1. **`pigeon.dev`**: add all five reusable workflows. Inert on merge — nothing calls them yet, and
   `workflow_call` is their only trigger.
2. **Here**: convert the three callers that gate nothing — `interaction-limits-renew`,
   `blog-changelog`, `zola-sites-deploy`. Each is independently verifiable, and a failure in any of
   them blocks no merges.
3. **Here**: convert `terragrunt-plan` and `terragrunt-apply`, together, last. They are the merge
   gate, and this PR's own CI is the first real exercise of the new plan caller.

## Consequences

- A change to the shared terragrunt logic is one edit instead of two, and lands in one place for
  both plan and apply. That was the point.
- A change to any CI behavior is now a PR in `pigeon.dev`, which has no required checks and no
  Terragrunt gate of its own — so CI changes get *less* scrutiny than the infrastructure they
  guard, inverting the current arrangement. §5 keeps the authorization boundary here specifically
  to limit what that inversion can reach.
- Reading "what does CI do on a PR here" now requires two repos. The callers are short enough to
  make the indirection obvious rather than hidden, but it is still indirection where there was
  none.
- `pigeon.dev` becomes two things: the published templates repo ADR-0154 made it, and the shared CI
  definition repo. Its `CLAUDE.md` currently describes only the first, and gains the second.
- The job entries in the checks UI are renamed to `caller / called`. Cosmetic, per the verified
  constraint above, but anyone reading `gh pr checks` output will see it.
- The four workflows stop being self-contained artefacts of this repo's history. Their prior
  evolution — ADR-0128, ADR-0129, ADR-0134, ADR-0138, ADR-0140 — stays documented here, since this
  repo remains the decision-record home for both (ADR-0154 §8), but the files those ADRs describe
  will no longer be in the repo whose `docs/adr/` describes them.

## Out of scope

- Executing the hoist. Not deferred — a deliberate boundary, following ADR-0052's precedent for a
  decision-record-only ADR; §9 is the runbook.
- A `workflows/vX.Y.Z` tag track for the called workflows. Genuinely deferred: §6 documents it as
  the escape hatch if live-`@main` breakage actually happens, rather than paying for it upfront.
- Moving `.github/scripts/adr-issue.sh`, per §8. Not deferred — a permanent boundary.
- Composite actions instead of reusable workflows, which *could* live under `pigeon.dev`'s
  `templates/` convention and would fit its stated purpose better. Not deferred — a deliberate
  boundary: these are whole multi-step jobs, and composite actions would leave every caller as long
  as it is today while forcing every secret through an input.
- Making `pigeon.dev` a general-purpose shared-CI repo for arbitrary repos or orgs. Not deferred —
  a deliberate boundary: nothing here is designed for an unknown caller. The inputs exist to serve
  this repo's two Zola sites and its one Terragrunt tree, and §3's split of "which sites" from "how
  to deploy a site" is the only place that distinction is even drawn.
- Giving `pigeon.dev` its own Terragrunt gate or required checks so that CI changes face the same
  scrutiny as the infrastructure they guard. Genuinely deferred, and the sharpest open question
  this ADR leaves behind — see the second consequence above.

## Verification

Cross-repo reusable workflows cannot be exercised locally (`act` does not resolve a `uses:` against
another repo), so every step below is a real run. This is why §9 orders the conversions by blast
radius rather than by convenience.

1. **`interaction-limits-renew` first.** It has `workflow_dispatch`, so trigger it on demand and
   confirm the `contributors_only` limit is re-applied to `noisypigeon/noisypigeon` — which proves
   `github.repository` resolves to the caller, the premise everything else depends on, using the
   one workflow where a wrong answer costs nothing.
2. **`zola-sites-deploy`.** Dispatch `site=pigeon.dev`, then `site=all`. Confirm each leg builds
   the right site, that `secrets[matrix.*]` still resolves in the caller (§3), and that the sync
   target bucket is unchanged. Then confirm a push touching only one site's `src/` still redeploys
   only that site, which is the behavior ADR-0140's `detect` job exists for.
3. **`blog-changelog`.** On a real `workloads/noisypigeon.com/src/**` PR: the changelog entry, the
   daily digest post, and the now-explicit `-R` dispatch (§7) firing the deploy.
4. **`terragrunt-plan`, both outcomes**, on throwaway PRs. One touching no leaf → `terragrunt/apply`
   resolves `success` / "No terraform leaves affected" immediately. One touching a leaf → `pending`,
   then a plan comment. Confirm the status `context` is still exactly `terragrunt/apply`, since the
   ruleset matches that string and nothing else.
5. **`terragrunt-apply`.** Comment `terragrunt apply` on the leaf-touching PR; confirm the eyes
   reaction, the apply comment, the status flip to `success`, and the auto-merge. Then confirm a
   comment from a non-collaborator does **not** trigger it — §5's boundary is only worth keeping
   here if it still works.
6. Confirm `gh pr checks` reports a resolvable gate on an ordinary PR, and that the renamed
   `caller / called` entries are the only visible difference.
