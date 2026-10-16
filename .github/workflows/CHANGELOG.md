# Changelog

All notable changes to the reusable CI are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.5.2] - 2026-10-16

### Fix state-backup.yml: reach B2 through its S3-compatible API

`state-backup.yml` failed on its first real run with `failed to authorize account: This request is not currently supported on API version number 1`. rclone's `b2` backend authenticates with B2's v1 API, which B2 now refuses. The current rclone release, 1.72.1, does the same.

The workflow now reaches B2 through its S3-compatible API:

- **The endpoint is found at run time.** B2's S3 endpoint is per account (for example `https://s3.ca-east-006.backblazeb2.com`), so the job reads it from the backup key's own v4 `b2_authorize_account`. No new secret is needed.
- **It works with a key that can't read.** Without `readFiles`, the key can't answer the `HeadObject` that rclone sends for a sub-path or after an upload. So the copy runs bucket root to bucket root, filtered to `terraform/**`, with `--s3-no-head`. `--s3-no-check-bucket` stops rclone from trying to create either bucket.
- **The key and its capabilities are unchanged:** `listBuckets`, `listFiles` and `writeFiles`, with no read or delete. B2 keeps a new version for every write that arrives over the S3 API, just as it does over its native API.

These are the exact settings that made noisypigeon.com's first backup. That run copied all nine state files from R2 to B2; a second run copied nothing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#44](https://github.com/noisypigeon/pigeon-lib/pull/44)

## [1.5.1] - 2026-10-15

### Stop terragrunt-run.yml running a leaf twice

`terragrunt-run.yml` could run the same leaf twice, at the same time, against the same state key. That's harmless when the leaf has nothing to change. For a new leaf, every resource got created twice and one copy was orphaned. That happened in noisypigeon/noisypigeon.com#19: two B2 buckets and two B2 keys, with only one of each in state.

### Why it happened

The run selects leaves with two kinds of filter, combined:

- **`--filter '[main...HEAD]'`**, Terragrunt's git filter, runs every leaf it considers changed in a git worktree.
- **An explicit `--filter ./<dir>`** for each directory holding a changed file. It's there for Terragrunt's gap with files a module reads through `file()` (gruntwork-io/terragrunt#6952), and it runs the leaf in the checkout.

Terragrunt doesn't deduplicate the two. A leaf both filters matched (any new leaf, and most changed ones) was selected twice, and both copies ran.

### The fix

Before adding explicit filters, the step now asks Terragrunt which leaves the git filter already selects (`terragrunt find --filter '[main...HEAD]' --json`). It adds `--filter ./<dir>` only for directories missing from that list. A change the git filter misses, such as a dashboard JSON file, still gets its explicit filter.

If that lookup fails, the run fails rather than going ahead without it.

Checked against noisypigeon.com#19's branch: the two filters together had selected each new leaf twice; with this change, each of the nine leaves is selected exactly once. `actionlint` is clean.

Spokes pick this up by bumping their `@workflows/…` pins.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#41](https://github.com/noisypigeon/pigeon-lib/pull/41)

## [1.5.0] - 2026-10-15

### Add state-backup.yml: copy R2 Terraform state to a versioned B2 bucket (LIB-0007)

A new reusable workflow, `state-backup.yml`. It copies a spoke's Terraform state objects from its Cloudflare R2 state bucket to a Backblaze B2 bucket that keeps every version. R2 has no object versioning, so this copy is what lets a bad state write be rolled back ([LIB-0007](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0007-terraform-state-on-r2-with-offsite-backup.md) §4).

### What it does

1. Decrypts the spoke's `secrets.enc` and masks every value before exporting the few it needs. It never writes a config file.
2. Runs `rclone copy r2:<state bucket>/terraform b2:<backup bucket>/terraform`. It's `copy`, never `sync`, so nothing is deleted.
3. Fails if any state file in R2 is missing from B2 afterwards.

### What it needs in `secrets.enc`

- `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_R2_ACCESS_KEY_ID` and `CLOUDFLARE_R2_SECRET_ACCESS_KEY`, the same keys `root.hcl` v2.1.0 uses for the R2 backend.
- The state bucket's name, under the key passed as `state_bucket_secret` (the spoke's `spoke.hcl` value).
- `TERRAFORM_STATE_BACKUP_B2_BUCKET_NAME`, `TERRAFORM_STATE_BACKUP_B2_KEY_ID` and `TERRAFORM_STATE_BACKUP_B2_KEY`. Each name can be overridden with an input.

Give the B2 key only `listBuckets`, `listFiles` and `writeFiles`, scoped to the backup bucket. Then this job can add versions but never read or delete them. A restore uses an admin key, by hand.

### Calling it

```yaml
jobs:
  backup:
    uses: noisypigeon/pigeon-lib/.github/workflows/state-backup.yml@workflows/v1.5.0
    with:
      state_bucket_secret: NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME
    secrets: inherit
```

Call it as a job after `apply` in `terragrunt-apply.yml`, and from a daily scheduled caller so that local applies are picked up too.

Checked with `actionlint`. Its first real run will be noisypigeon.com's move to R2.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#40](https://github.com/noisypigeon/pigeon-lib/pull/40)

## [1.4.1] - 2026-10-15

### Regenerate README tables for every module, not a hard-coded list

\`module-docs.yml\` now finds the modules whose README tables it regenerates at run time, using the terraform-docs action's \`find-dir: terraform\` input, instead of reading a hard-coded \`working-dir\` list. That list had drifted from the tree. Five modules added after it was written got no README regeneration when their \`.tf\` changed: \`cloudflare/bucket\`, \`cloudflare/ruleset\`, \`grafana/dashboard\`, \`scaleway/iam-api-key\` and \`scaleway/iam-application\`. A module added from now on is picked up as soon as it has a \`.tf\` file. The \`paths: '**/*.tf'\` trigger already matched every module, so it is unchanged.

This PR also refreshes the five READMEs the old list skipped, so the workflow's first run on them changes nothing:

- \`cloudflare/ruleset\`: the inputs/outputs table was empty, and is now filled in.
- \`scaleway/iam-api-key\`: the \`default_project_id\` input was missing from the table, and is now listed.
- \`cloudflare/bucket\` and \`grafana/dashboard\`: these tables were generated by hand, and now use the action's terraform-docs 0.20 table formatting. The content is the same.

No module's \`.tf\` changes, so no module is released.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#38](https://github.com/noisypigeon/pigeon-lib/pull/38)

## [1.4.0] - 2026-10-15

### Add a grafana-dashboards/<set>/vX.Y.Z release track

A fifth release unit: versioned Grafana dashboard JSON at `grafana-dashboards/<set>/*.json`, tagged `grafana-dashboards/<set>/vX.Y.Z`, one track per set.

A dashboard is something more than one consumer loads. `willowgraysen.com`'s Grafana leaf applies it with Terraform, and `pigeon-cli`'s local observability stack ships its own copy. A tagged file gives both a pinned version to fetch by URL, `raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/<tag>/<path>`, instead of each keeping a duplicate. This PR adds only the release machinery. The first set arrives in the next PR, and linking `pigeon-cli` to it is out of scope for now.

### Release tracking

- **`template-release.yml`** detects changed `grafana-dashboards/<set>/*.json` and cuts one tag per changed set.
  - The first version is `1.0.0`. After that, the PR's `release:*` label sets the bump, as for modules.
  - Each set gets its own `CHANGELOG.md` and a `[grafana-dashboards/<set>]` root line.
  - A README-only change releases nothing.
- **`root-changelog.yml`** gets the matching stand-down arm, so a dashboard release never gets two root lines, and a `grafana-dashboards` tag for non-releasing changes. That makes five duplicated predicates (noisypigeon/noisypigeon#301).

The hub's `CLAUDE.md`, `README.md`, the root `CHANGELOG.md` header and the `release-pr` skill now list the fifth unit.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#28](https://github.com/noisypigeon/pigeon-lib/pull/28)

## [1.3.2] - 2026-10-15

### Generate README tables for cloudflare/dns-record

Adds `terraform/cloudflare/dns-record` to `module-docs.yml`'s `working-dir` list, so its README gets the same generated input/output tables as the other modules.

The list is still hand-maintained, and `grafana-dashboard`, `iam-api-key` and `iam-application` are still missing from it (noisypigeon/noisypigeon#302). This adds only the new module rather than widening the change.

This touches `.github/workflows/`, so it cuts a `workflows/` patch release. No spoke needs to take it: `module-docs.yml` runs only in this repo.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#25](https://github.com/noisypigeon/pigeon-lib/pull/25)

## [1.3.1] - 2026-10-15

### Add a --check mode to resolve-root-hcl.sh

`resolve-root-hcl.sh` gains a `--check` mode. It writes nothing, and exits 1 unless the spoke's `./root.hcl` is byte-identical to the `root.hcl` template at the version `spoke.hcl` pins.

This is needed because spokes now **commit** the generated `root.hcl` instead of gitignoring it. The reusable `terragrunt-run.yml` plans with Terragrunt's `[main...HEAD]` git filter, and Terragrunt 1.1.6 evaluates every unit inside temporary git worktrees, which contain only tracked files.

- **Against the gitignored design,** a dry run of the `pigeon.dev` hoist failed on every leaf with `Could not find a root.hcl`.
- **With the file committed,** the same command planned `No changes.` for all four leaves.
- **Committing also keeps destroy plans working:** a leaf removed from a spoke still plans its destroy, because the base ref's worktree has its own `root.hcl`.

A spoke's CI runs `./fetch-lib.sh && .lib-src/.github/scripts/resolve-root-hcl.sh --check` through `prepare_cmd`, so a hand-edited or stale `root.hcl` fails the plan. Without arguments, the script still (re)writes `./root.hcl`, which is how a spoke takes a template bump. An unknown argument exits 2.

Tested against a scratch library repo:

- a missing `root.hcl` exits 1;
- a matching one exits 0;
- a one-line drift exits 1;
- a bad argument exits 2.

The written file is now mode 644, not the 600 `mktemp` left behind.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#17](https://github.com/noisypigeon/pigeon-lib/pull/17)

## [1.3.0] - 2026-10-15

### Let a spoke run terragrunt CI against a materialized root.hcl

This makes the reusable Terragrunt CI usable from a spoke, not only from `noisypigeon/noisypigeon`. It also adds the release machinery for a fourth track, `terragrunt/root-hcl/vX.Y.Z`, whose first template version follows in a separate PR (LIB-0003).

### `terragrunt-run.yml`: two new optional inputs

- **`secrets_files`** (default `.env.enc`): space-separated sops dotenv files whose decrypted values are masked in the log. A spoke keeps its secrets in `terraform/secrets.enc`; the old step hardcoded `.env.enc`.
- **`prepare_cmd`** (default empty): a command run from the caller's repo root before Terragrunt. A spoke uses it to fetch `pigeon-lib` and materialize `root.hcl`.

Both defaults do exactly what the workflow did before, so existing callers need no change. The final "fail if the run failed" step also reads its exit code through `env` now, which clears a long-standing `actionlint`/shellcheck error (SC2242).

### `.github/scripts/resolve-root-hcl.sh` (new)

Run it from a spoke's repo root. It reads `root_hcl_version` from `spoke.hcl` and writes `./root.hcl` from `terragrunt/root-hcl/root.hcl`:

- A version such as `"1.0.0"` takes the file at tag `terragrunt/root-hcl/v1.0.0`.
- `"main"` takes the working-tree copy.
- An unknown tag, a missing `spoke.hcl`, or running it inside the library itself fails the run with an error.

The script always copies and never symlinks. A leaf's state key is relative to `root.hcl`'s own directory, so `root.hcl` has to be a real file at the spoke's root. Like `resolve-theme.sh`, the script finds the library from its own location. It sits under `.github/scripts/` so the `workflows/` track versions it.

### Release tracking for `terragrunt/root-hcl/`

- **`template-release.yml`** cuts `terragrunt/root-hcl/vX.Y.Z` when `terragrunt/root-hcl/root.hcl` changes. The first version is `1.0.0`. It writes that unit's `CHANGELOG.md` and a `[terragrunt/root-hcl]` root line. There is no site to redeploy.
- **The hub's `root-changelog.yml`** gets the matching stand-down arm in the same change, so a template release never gets two root lines. Its precedence also gains `terragrunt/` → `terragrunt`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#15](https://github.com/noisypigeon/pigeon-lib/pull/15)

## [1.2.0] - 2026-10-15

### Add a reusable spoke-root-changelog.yml

Adds `spoke-root-changelog.yml`, a reusable workflow that writes DEV-0160's single root `CHANGELOG.md` line for a merged PR in a spoke.

Before this, `pigeon.dev` and `noisypigeon.com` each carried that job inline. Both copies fetched `pigeon-lib`, derived a tag from the changed paths, ran `root-changelog.sh` and pushed, and they differed only in their tag precedence. Spokes carrying their own workflow bodies goes against LIB-0001's first invariant. Resolves noisypigeon/noisypigeon#306.

### Inputs

- `precedence` (required): ordered `<ERE>=<tag>` lines matched against the PR's changed paths. The first line with any match wins.
  - Each line is split on its last `=`, so a pattern may contain `=` and a tag may not.
  - Blank lines are ignored. A line with no `=`, or with an empty pattern or tag, fails the run rather than being skipped.
- `fallback_tag` (default `repo`): the tag for a PR that matches no line.
- `fetch_script` (default `fetch-lib.sh`) and `changelog_script` (default `.lib-src/.github/scripts/root-changelog.sh`): where the caller's fetcher is, and where it leaves the script.
- `git_user_name` and `git_user_email`: the same defaults as `blog-changelog.yml`.

The caller keeps the `pull_request: closed` trigger, the merged-only gate, permissions and concurrency.

### Push retry

A rejected push is now retried up to five times with a rebase each time, as the hub's own `root-changelog.yml` already does. The inline copies did one rebase and one push. That was enough while they shared the `main-writer` concurrency group, but it also exposed them to GitHub's one-pending-run-per-group cancellation, the cause of the lost release in pigeon-lib#9. Callers can now use their own concurrency group. A rebase conflict still fails the run outright.

This is deliberately a separate file from the hub's own `root-changelog.yml`. That workflow has to stand down for PRs that `template-release.yml` releases, and it runs the script from its own tree. A spoke releases nothing, so it never stands down.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#14](https://github.com/noisypigeon/pigeon-lib/pull/14)

## [1.1.0] - 2026-10-15

### Let blog-changelog.yml take a site root via src_dir

`blog-changelog.yml` gains an optional `src_dir` input: the path to the Zola site root itself, using the same vocabulary as `zola-site-pages.yml`. With `src_dir` set, the daily digest is written to `<src_dir>/content/changelog/`.

Until now the digest path was hardcoded as `<site_dir>/src/content/changelog/`. That forced every caller to keep its site in a `src/` directory nested one level below some other directory. A spoke whose site root is `web/`, the shape DEV-0162 gave `pigeon.dev`, had no way to express that. `noisypigeon.com` is about to make the same move.

### Compatibility

The change is additive, so it is a minor bump:

- `site_dir` is now optional, but it behaves exactly as before when a caller passes it. Existing callers need no changes.
- Pass `site_dir` or `src_dir`, not both. A new validation step fails the job before checkout if a caller passes both or neither.
- `src_dir` requires `changelog_path`. `site_dir` has an implicit `<site_dir>/CHANGELOG.md` default; a site root has no equivalent, so the job refuses to guess and fails instead.

### Also in this PR

The hub's `CLAUDE.md` and `README.md` now name `noisypigeon.com`'s ADR prefix as `COM-`, its new name. `NPC-` in older prose is an alias for it. The rename itself lands in `noisypigeon.com`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#13](https://github.com/noisypigeon/pigeon-lib/pull/13)

## [1.0.7] - 2026-10-15

### Read release notes from the default branch, not the pinned tree

`terraform/scaleway/project/v2.0.1` published its **redirect page** but not its **release post**. Found by checking the live site after the release, not by reading code.

```
/modules/scaleway/project/v2.0.1/      -> 200   (tag-derived)
/releases/scaleway-project-v2-0-1/     -> 404   (file-derived)
```

### The asymmetry

Two halves of the same generator read from two different points in time:

| Content | Source | Liveness |
| --- | --- | --- |
| Redirect pages, overview pages, version lists | `git tag --list` on `LIB_ROOT` | **Live** — `fetch-lib.sh` fetches tags in full regardless of checkout |
| Release posts | `find "$LIB_ROOT/terraform" -name CHANGELOG.md` | **Pinned** — working tree is at whatever `.lib-version` names |

`.lib-version` pins a ref that *by construction* predates any release cut after it. So the newest entry — the one a fresh release most needs published — is precisely the one the pinned working tree cannot have. The site would only show the post after an unrelated `.lib-version` bump.

### Why `origin/main` and not the version tag

The tag **does** carry its own entry: `template-release.yml` commits the changelog, pushes to `main`, then tags that same commit (`47f4755` is both `v2.0.1` and `main`'s head). So reading `<tag>:…/CHANGELOG.md` was my first fix, and it was wrong.

**A version tag does not carry entries backfilled for *older* tags afterwards.** Four such entries exist — from #14, which backfilled six previously undocumented module tags without cutting new ones. Reading the tag alone silently dropped all four: **87 posts became 83.**

Neither source is a superset of the other. The default branch is a superset of both. And since release notes are append-only published history, and the tag graph is *already* read live, pinning only the notes is what created the mismatch in the first place.

`CHANGELOG_REF` is overridable and verified with `rev-parse` up front, so a missing ref fails loudly instead of yielding an empty site.

### Verification

Ran both generators against the same `LIB_ROOT` into separate content roots and diffed the full output trees:

```
OLD posts: 87
NEW posts: 88
files only in NEW:   ./releases/scaleway-project-v2.0.1.md
files only in OLD:   (none)
content differences: 0
```

Exactly one added file. Nothing removed, nothing changed. The four backfilled posts are all present. `bash -n` and `shellcheck -S warning` clean — the latter caught a genuine `rm -rf` expansion risk in my first draft, now `${var:?}`-guarded.

### Note on scope

The module **description** on overview pages is still read from the pinned `README.md`, so it has the same staleness in principle. Left alone deliberately — it's a different code path with a much weaker failure mode (descriptions rarely change, and a stale one is wrong rather than missing), and I'd rather not widen a verified fix. It goes in the tracked issue.


[#12](https://github.com/noisypigeon/pigeon-lib/pull/12)

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
