---
name: release-pr
description: Use this skill when making a change to one of this repo's terraform/ Terraform modules or the zola-site/ theme and getting it merged to main. This is the pigeon-lib hub repo; consumers are the spoke repos (noisypigeon, garden, blog, willowgraysen) and are bumped in a separate PR there. Covers branching off main, committing, opening the pull request, applying the required release:* label, merging, and syncing local main afterward. Trigger on requests like "open a PR for this", "release this module change", "ship this to main", or "merge this terraform module or zola-site theme change".
---

# Releasing a terraform/ or zola-site/ change

This repo's release automation has no human reviewer and no branch-protection
rules — this skill *is* the PR discipline. Follow it in full for every
change, including trivial ones, because the PR body becomes that module's (or
the theme's) changelog entry and GitHub Release notes verbatim, and the label
drives the version bump. There is no separate "write good release notes" step
later — get the PR body right the first time.

## Steps

1. **Branch off `main`.**
   ```
   git checkout main
   git pull
   git checkout -b <descriptive-branch-name>
   ```

2. **Make the change and commit it.** Commit message content is not what
   drives the changelog — the PR title and body are. Write commits for
   git history, not for release notes.

3. **Open the PR with a body written for its second life as a changelog entry
   and release note**, not just for a reviewer:
   - Title: short, imperative, human-readable — it becomes the changelog
     section heading verbatim (e.g. "Add versioning input to object-bucket").
   - Body: written in full sentences a consumer of the module (or theme)
     would want to read later, describing what changed and why it matters to
     someone consuming it — not "fixed bug" or a raw commit list. It is
     copied verbatim into that unit's own `CHANGELOG.md`
     (`terraform/<provider>/<module>/CHANGELOG.md` or
     `zola-site/CHANGELOG.md`) and into the GitHub Release notes by
     `template-release.yml` on merge, with no editing pass in between.
   ```
   gh pr create --title "<title>" --body "<body>" --base main
   ```

4. **Apply exactly one `release:*` label before merging** — this determines
   the version bump for every module changed in this PR:
   - `release:major` — breaking change to a module's inputs/outputs/behavior.
   - `release:minor` — backwards-compatible addition.
   - `release:patch` — fix or internal-only change. This is also what
     `template-release.yml` defaults to if no `release:*` label is present, so
     applying it explicitly isn't strictly required to get a release, but do
     it anyway — an unlabeled PR is a signal something was skipped, not a
     deliberate patch decision.
   - A PR that doesn't touch any `terraform/<provider>/<module>/`
     directory, `zola-site/templates/`, `static/`, or
     `theme.toml`, `.github/workflows/*.yml` or `.github/scripts/`, or
     `terragrunt/root-hcl/root.hcl` or `secrets-schema.json`, or `grafana-dashboards/<set>/*.json` (e.g. root-doc, or
     `zola-site/README.md`/`CHANGELOG.md`-only changes) doesn't
     need a label at all — nothing will be tagged or released regardless. It
     still gets a one-line entry in the root `CHANGELOG.md` from
     `root-changelog.yml` (DEV-0160), so the PR title still has a second life as
     published copy.
   ```
   gh pr edit <pr-number> --add-label "release:patch"
   ```

5. **Merge the PR** once ready (no separate review gate exists — this is the
   discipline checkpoint):
   ```
   gh pr merge <pr-number> --squash --delete-branch
   ```
   Merging triggers `template-release.yml` automatically (tags the changed
   module(s), updates their `CHANGELOG.md` and the root one, cuts a GitHub
   Release, then dispatches `garden-pages.yml` in `noisypigeon/garden`,
   which regenerates this version's redirect page, overview entry and release
   post) and, on any resulting `.tf` changes, `module-docs.yml` (regenerates
   the module's `README.md` input/output table). A `zola-site` release
   additionally dispatches `blog-pages.yml` in
   `noisypigeon/blog`, the other site that renders with the theme.
   None need triggering manually.

   Watch those dispatch steps. This repo hosts no site, so **every** deploy it
   triggers reaches another repo, and each fails if `BOT_GITHUB_TOKEN` loses
   `actions: write` there — the symptom being a tagged, released version whose
   short `noisypigeon.garden/terraform/...` URL 404s, not an obviously broken release.

6. **Sync local `main`.** "Run on main" here means syncing your local clone
   after the automation has landed its own commits — not re-running any
   workflow manually:
   ```
   git checkout main
   git pull
   ```
   Pulling after merge picks up both the squash-merge commit and the
   automated changelog/docs commits that landed on top of it.

7. **Bump the consumer, if there is one.** Module consumers live in
   `noisypigeon/noisypigeon`, pinned by exact version in
   `*/terraform/**/*.tf` as `source = "https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z"`.
   Theme consumers are the `garden` and `blog` site repos, each
   pinning a version per LIB-0001 invariant 2. Either bump is a separate PR in
   that repo, and it can only be opened once this release's deploy has
   finished — the short URL has to resolve before `terragrunt init` can fetch
   it.
