# LIB-0027: A staged apply re-plans by itself, and the last apply merges

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-22.
- **Status**: Proposed. Amends LIB-0022's apply, and LIB-0024's staged
  applies.

## Context

Two steps of every Terragrunt PR are still done by hand, and neither needs a
decision.

- **The next stage's plan.** Under LIB-0024, an apply that leaves workload
  leaves deferred keeps the gate pending, and asks for a `terragrunt plan`
  comment to plan the next stage. That comment is the same every time, and
  runway#38 needed it between stages. What a person must review is each
  stage's apply, not the request for its plan.
- **The merge.** After a final apply, `terragrunt-run.yml` merges the PR. On
  runway, that has failed every time (#31, #38 and #41) with "Resource not
  accessible by integration", and the PR was merged by hand.
  - The callers grant `contents: read`, and the merge used the job's
    `GITHUB_TOKEN`. Merging needs `contents: write`.
  - Granting it wouldn't be enough. GitHub starts no workflow from an event
    caused by `GITHUB_TOKEN`, so a merge made with it would skip what follows
    a merge: the root changelog (`root-changelog.yml`, on `pull_request:
    closed`) and garden's deploy.
  - Every spoke already has a `BOT_GITHUB_TOKEN` secret, which reaches the
    reusable through `secrets: inherit`.

For the same reason, the re-plan can't be done by posting a `terragrunt plan`
comment with `GITHUB_TOKEN`: the comment wouldn't start the plan workflow.

## Decision

### 1. An apply that leaves leaves deferred plans the next stage

- **`terragrunt-run.yml` reports what it did.** Its `workflow_call` gains two
  outputs:
  - `deferred`, which is `'true'` when the run left workload leaves deferred
    (LIB-0024 §3);
  - `exit_code`.
- **A spoke's apply caller gains a `replan` job.** It:
  - needs the `apply` job, and runs only when that succeeded and reported
    `deferred`;
  - calls the same reusable with `command: plan`, at the PR's head;
  - shares the PR's concurrency group, `terragrunt-pr-<n>`, so it starts only
    once the apply has finished;
  - takes `secrets: inherit`.
- **Its plan says how it started.** The summary notes that it was planned
  automatically after the previous stage's apply.
- **Only the plan is automatic.** Each stage still needs its own `terragrunt
  apply` comment, against its own reviewed plan (LIB-0022). The loop ends by
  itself, when a plan defers nothing.

### 2. The final apply merges with the bot token

- **The reusable takes an optional `BOT_GITHUB_TOKEN` secret,** and merges
  with it when it's set, falling back to `GITHUB_TOKEN`.
- **A merge with the bot token starts the workflows that follow a merge,**
  such as the root changelog and garden's deploy.
- **The commit status stays on `GITHUB_TOKEN`,** which the callers already
  grant `statuses: write`.
- **A failed merge says why.** The comment names the token used, and that it
  needs Contents and Pull requests write on the repository.
- **A staged apply still never merges** (LIB-0024 §3).

### 3. Release impact

- **`workflows/` takes a minor version.** Callers that add no `replan` job
  behave as before, apart from the merge.
- **A spoke takes it in one PR,** with the new `replan` job. Selection doesn't
  change (LIB-0024 §5). Since an apply runs the default branch's callers, it
  works from the moment that PR merges.

## Consequences

- **A staged workload needs only its applies.** In runway#38's case, that's
  two comments instead of three.
- **PRs merge themselves,** and get their changelog entries, without a manual
  merge.
- **The bot token's reach matters.** It must hold Contents and Pull requests
  write on every spoke. A token without them fails at the merge, and says so.

## Out of scope

- **Applying deferred stages automatically.** Every apply stays a person's
  `terragrunt apply` against a plan they reviewed. A permanent boundary.
- **A GitHub App in place of the bot token,** with installation tokens scoped
  per repository. Deferred ([#131](https://github.com/noisypigeon/library/issues/131)).
- **Building §§1–3,** and the spokes taking it, in later PRs that cite this
  record ([#130](https://github.com/noisypigeon/library/issues/130)).

## Verification

To be completed when §§1–3 ship.

1. **A staged apply re-plans by itself.** On runway, an apply that leaves a
   leaf deferred is followed, without a comment, by a plan of the next stage.
2. **The last apply merges.** The final stage's apply turns the gate green,
   and the PR merges without a hand.
3. **The merge is a real merge event.** The root changelog gets the PR's
   entry.
