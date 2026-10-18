# DEV-0129: Scope CI workflows to real leaves/modules and gate merges on `terragrunt apply`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-05.
- **Status**: Accepted.

## Context

Three gaps accumulated across `.github/workflows/`:

1. `terragrunt-plan.yml` triggered on `pull_request` with `paths: ["workloads/**", ".env.enc", ".sops.yaml"]`. `workloads/**` is broader than "terraform leaves" — it also matches `workloads/blog/src/**` (Zola content, not Terraform) and any doc/README file anywhere under `workloads/`. Every real leaf lives at `workloads/<name>/terraform/...`, the exact convention `root.hcl`'s `is_valid_leaf` already enforces (`path_segments[1] == "terraform"`, docs/adr/0092, widened by docs/adr/0096). So the workflow was doing real work — `mise` install, `sops` decrypt, `terragrunt run --all` — for PRs that touch no leaf at all, e.g. a blog-only or README-only change.

2. `module-release.yml` had no trigger-level path filter whatsoever — it ran on *every* merged PR to `main`, then internally diffed changed files three separate times to decide whether to (a) version/tag a `templates/terraform/scaleway/*` module, (b) update the blog's own changelog + daily digest post (docs/adr/0107), or (c) version/tag `templates/zola-site` (docs/adr/0113). (a) and (c) are both "release a versioned template" and share nearly identical bump/tag/changelog logic; (b) is a content-changelog feature for the blog itself with no versioning involved — a genuinely separate purpose that happened to share a workflow file and an unfiltered trigger.

3. There was no merge gate tying a PR to a successful `terragrunt apply`. `gh api repos/noisypigeon/noisypigeon/rulesets/24067690` confirms the repo's only active ruleset on `main` has a single `non_fast_forward` rule and an empty `bypass_actors` list — no required status checks exist. docs/adr/0039, 0053, and 0123 each explicitly documented "no branch protection, convention only" as a deliberate stance at the time. `terragrunt-plan.yml`/`terragrunt-apply.yml` themselves (added across several commits, first described by docs/adr/0127, given their own ADR by docs/adr/0128) already establish the `terragrunt apply` PR comment — restricted to OWNER/MEMBER/COLLABORATOR — as the human-approval checkpoint for infrastructure changes; today nothing stops a PR from merging without that checkpoint ever being exercised, or after it failed.

The design tension behind (3): a required status check that blocks merges must be reported on *every* PR, including ones that touch no Terraform leaf at all (which must resolve to `success` immediately), or GitHub will show it as perpetually unreported and block merges that have nothing to do with Terraform. That means the job owning this status can't be path-filtered at the trigger level — gating has to happen per-job, after a cheap, always-run "did this touch a leaf" check.

## Decision

### `terragrunt-plan.yml`: split into `detect` + `plan`

Dropped the `paths:` filter from `on.pull_request` entirely, so the workflow fires on every PR. Added a `detect` job (checkout + `git diff --name-only` against the PR's base/head SHAs, no `mise`/`sops`) that:

- Matches changed files against `^workloads/[^/]+/terraform/` or `.env.enc`/`.sops.yaml`.
- Sets a commit status on the PR's head SHA with context `terragrunt/apply`: `success` ("No terraform leaves affected") if nothing matched, `pending` ("Awaiting successful terragrunt apply") if something did.
- Exposes the match result as `affects-leaves`.

The existing `plan` job gained `needs: detect` / `if: needs.detect.outputs.affects-leaves == 'true'` and is otherwise unchanged. The real `terragrunt plan` work now only runs for leaf-touching PRs, while the lightweight `detect` job keeps the merge-gate status accurate for every PR, including ones Terraform has nothing to do with.

### `terragrunt-apply.yml`: report the same status

No change to the existing trigger/gating. Added a final `if: always()` step that fetches the PR's current head SHA (via `pulls.get`, since `issue_comment` events don't carry it) and sets the `terragrunt/apply` status to `success`/`failure` based on the captured exit code. A later push to the PR re-triggers `terragrunt-plan.yml`'s `detect` job on the new SHA, which resets the status fresh for that SHA — a stale `success` from a since-superseded commit never silently carries forward.

### `module-release.yml` → `template-release.yml`

Renamed and scoped to `paths: ["templates/terraform/**", "templates/zola-site/**"]`. Removed the "Determine blog change" step and the entire blog-changelog/daily-digest block; stripped the now-dead `steps.blog.outputs.changed` conditions from the remaining steps. The module- and zola-site-versioning logic (bump-level label, per-dir `CHANGELOG.md`, tag, GitHub Release, and the `blog-pages.yml` dispatch needed for the docs/adr/0109/0114 redirect pages) is otherwise untouched — both are "release a versioned template," now the workflow's sole purpose, matching its new name.

### New `blog-changelog.yml`

Extracted the removed blog-changelog/digest logic verbatim into its own workflow, independently triggered on `pull_request` (`closed`, merged) with `paths: ["workloads/blog/src/**"]`. Since the path filter already guarantees relevance, the internal `steps.blog.outputs.changed` conditional was dropped — the job just always runs its one job (update changelog + digest, commit, dispatch `blog-pages.yml`). Shares the `main-writer` concurrency group with `template-release.yml` and `module-docs.yml`, so all three bot-commit-to-`main` workflows keep serializing against each other as before.

### Merge gate: required status check + bypass

The new `terragrunt/apply` commit status becomes a required status check on the repo's existing `main` ruleset (id `24067690`), via:

```
gh api --method PUT repos/noisypigeon/noisypigeon/rulesets/24067690 \
  --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [
    { "actor_type": "RepositoryRole", "actor_id": 5, "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [{ "context": "terragrunt/apply" }]
      }
    }
  ]
}
JSON
```

(`actor_id: 5` is the built-in "Repository admin" role — the exact ID should be confirmed via `gh api repos/noisypigeon/noisypigeon/rulesets/rule-suites` or the ruleset UI before running this, since bypass-actor IDs are org/repo-specific.) This implements "terraform PRs can't merge without apply [succeeding], or [block on] failed apply, unless merge requirements override" — the required check only resolves `success` after a real `terragrunt apply` succeeds for leaf-touching PRs (or immediately for non-leaf PRs), and repo admins retain the bypass.

This command is deliberately **not** run automatically by this ADR — it's a shared, repo-wide setting change, left as an explicit follow-up step for the user to run (and confirm the actor ID for) once the workflow changes above are merged and have run at least once, consistent with how this repo has historically left GitHub-side cutover steps (docs/adr/0067, docs/adr/0094) to a manual action.

Also updated `.claude/skills/release-pr/SKILL.md` (which referenced `module-release.yml` by name in three places) to say `template-release.yml`.

## Consequences

- `terragrunt-plan.yml` now runs a cheap `detect` job on every PR, but only runs the expensive `plan` job for PRs that actually touch a terraform leaf.
- `template-release.yml` and `blog-changelog.yml` no longer run at all for PRs outside their respective paths, eliminating wasted no-op runs on unrelated PRs (e.g. a DNS-leaf-only change, previously a no-op run of the unscoped `module-release.yml`).
- Once the ruleset change is applied, any PR touching a terraform leaf cannot merge until a `terragrunt apply` comment has succeeded against its current head SHA — pushing new commits resets that requirement for the new SHA. Repo admins can still bypass via the ruleset's `bypass_actors`.
- Blog PRs and template (module/zola-site) PRs are now fully independent CI paths; a change to one never triggers the other's workflow.

## Out of scope

- Confirming/adjusting the exact `bypass_actors` role ID and running the ruleset `PUT` — left as a manual follow-up (see above).
- Any `required_status_checks` entry for the `plan`/`detect` job itself (e.g. requiring the plan to have succeeded before merge) — only the `terragrunt/apply` context is required, since a failed plan already blocks a reviewer from ever commenting `terragrunt apply` in the first place.
- Splitting `module-docs.yml`'s own unfiltered-by-this-ADR behavior (it already has its own `paths: ["**/*.tf"]` filter and isn't part of the three problems above).
