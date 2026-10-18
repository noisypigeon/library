# DEV-0134: Hide superseded Terragrunt comments, auto-merge on successful apply

- Status: Accepted
- Date: 2026-10-06
- Author: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).

## Context

`terragrunt-plan.yml` and `terragrunt-apply.yml` (ADR-0128/0129) each post exactly one PR comment per workflow, identified by a hidden HTML marker (`<!-- terragrunt-plan -->` / `<!-- terragrunt-apply -->`). On every re-run, a hand-rolled `github-script` step lists the PR's comments, finds the one matching that marker, and calls `updateComment`, overwriting the previous output in place — so the PR timeline shows only the latest plan/apply result, with no record of earlier attempts.

Separately, once a reviewer comments `terragrunt apply` and it succeeds, `terragrunt-apply.yml` already sets the `terragrunt/apply` commit status to `success` (the merge-gate status ADR-0129 introduced) but stops there — a human still has to click "Merge" by hand every time.

## Decision

### Hide-then-post instead of update-in-place

Both comment steps (`terragrunt-plan.yml`'s "Comment plan output on PR", `terragrunt-apply.yml`'s "Comment apply output on PR") now:

1. Fetch every comment on the PR via `github.paginate(github.rest.issues.listComments, ...)` instead of a single unpaginated call — comments matching the marker now accumulate for the life of the PR instead of being overwritten, so a long-lived PR with many re-triggers needs every page, not just the first 30.
2. Hide every comment whose body includes that workflow's marker via GitHub's GraphQL `minimizeComment` mutation, classified `OUTDATED` (REST has no hide/unhide endpoint for issue comments):
   ```js
   const minimize = `mutation($id: ID!) { minimizeComment(input: { subjectId: $id, classifier: OUTDATED }) { clientMutationId } }`;
   for (const c of comments.filter(c => c.body.includes(marker))) {
     await github.graphql(minimize, { id: c.node_id });
   }
   ```
   GitHub renders these collapsed as "This comment was marked as outdated."
3. Always `github.rest.issues.createComment` with the new body. Never `updateComment`.

The two markers — and therefore the two comment threads (plan vs. apply) — stay independent exactly as before; each step only hides its own prior comments. The two files keep their existing duplicated-logic shape (no new shared composite action), consistent with how these comment blocks were already near-identical copies rather than a shared helper.

### Auto-merge on successful apply

`terragrunt-apply.yml`'s "Set merge-gate status" step is renamed "Set merge-gate status and auto-merge". After it sets the `terragrunt/apply` commit status (unchanged), it now additionally, only when `exitCode === '0'`:

1. Calls `github.rest.pulls.merge({ pull_number, merge_method: 'squash' })`. Squash is the only merge method this repo allows — confirmed via `gh api repos/noisypigeon/noisypigeon` (`allow_squash_merge: true`; `allow_merge_commit`/`allow_rebase_merge`: `false`).
2. On a successful merge, best-effort deletes the head branch (`github.rest.git.deleteRef({ ref: "heads/" + pr.head.ref })`), swallowing any error (e.g. a branch-protection rule, or the ref already gone) — branch cleanup never fails the job.
3. If the merge call itself throws (blocked by a branch rule, merge conflict, already merged, draft PR, etc.), catches the error and posts a one-off plain PR comment: `⚠️ Terragrunt apply succeeded, but auto-merge failed: <message>. Please merge manually.` This comment is not part of the hide/post-new marker scheme above — it is a single ad hoc notice, not a recurring summary — and a blocked auto-merge does not fail the step; the apply itself already succeeded.

Apply failures are unaffected: the status is set to `failure` and no merge is attempted, same as before this ADR.

This repo's native "Enable auto-merge" toggle (`enablePullRequestAutoMerge`) is not used — `allow_auto_merge` is `false` at the repo level, and a direct `pulls.merge` call made right after a known-successful apply is simpler and doesn't depend on that setting.

## Consequences

- Every `terragrunt plan`/`terragrunt apply` re-run leaves a full, readable history on the PR: each prior comment collapses to "marked as outdated" instead of disappearing, and the newest comment stays expanded.
- A PR comment thread with many re-triggers accumulates more comments than before (previously capped at one per marker); this is the explicit tradeoff for keeping history instead of silently overwriting it.
- Merging a leaf-touching PR is no longer a manual step: once `terragrunt apply` succeeds, the PR squash-merges and its head branch is deleted automatically, with no further human action.
- If GitHub branch-protection rules ever require something `pulls.merge` can't satisfy on its own (e.g. a pending required review), auto-merge fails gracefully with a PR comment asking for a manual merge — it does not bypass or weaken any existing merge requirement.
- Both workflows currently declare only `pull-requests: write` (plus `contents: read`, `statuses: write`); this permission set has been sufficient for all prior `issues.*` REST comment calls. If `minimizeComment` turns out to need broader scope in practice, `issues: write` is the follow-up to add — see Out of scope.

## Out of scope

- Adding `issues: write` to either workflow's `permissions:` block preemptively — deferred until live testing shows whether the existing `pull-requests: write` permission is sufficient for the GraphQL `minimizeComment` mutation.
- Any native GitHub "auto-merge" toggle — out of scope per the Decision section above (`allow_auto_merge` is `false` on this repo).
- Retroactively hiding any plan/apply comments posted before this ADR landed on currently-open PRs — the hide-then-post behavior only applies to comments posted going forward.
- The still-outstanding ADR-0129 follow-up (the `gh api` ruleset `PUT` making `terragrunt/apply` a required status check) — unrelated to this change. Auto-merge here is gated by whatever branch-protection rules already exist on `main` (currently just `non_fast_forward`), exactly as a human clicking "Merge" would be gated today.
