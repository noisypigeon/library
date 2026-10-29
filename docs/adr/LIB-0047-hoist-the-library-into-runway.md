# LIB-0047: Hoist the library into runway

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed; amended 2026-10-28 (see `## Amendments`). Moves `noisypigeon/library` into
  `noisypigeon/runway`, with its history and every tag. Amends:
  - LIB-0001: §2's role table, §4's "a spoke never writes a tag", and
    invariant 2's fetch, which now clones runway;
  - LIB-0002, which created the library as its own repo;
  - LIB-0009, whose short URLs now resolve to runway. The URL itself
    doesn't change;
  - LIB-0017, whose ADR home moves to runway's `adr/`;
  - LIB-0035 §4, whose garden dispatch stops crossing a repo boundary.

## Context

LIB-0001 split the family into a hub and its spokes. Several spokes would
share one versioned library, and none would carry its own copy. Since LIB-0035
the family is "runway and the hub":

- **runway** is the one full spoke. Every site, zone and workload is in it.
- **`noisypigeon/noisypigeon.com` and `noisypigeon/noisypigeon.garden`** are
  Pages shims. Each holds a README and one `pages.yml` that calls
  `site-pages.yml` (LIB-0035 §3).
- **`pigeon-cli`** calls `rust-crate-release.yml` and pins the
  `claude-plugins/pigeon-cli` marketplace (CLI-0161).

So the hub serves one spoke that consumes almost all of it, plus three repos
that call a handful of workflows. It still pays the full cost of being its own
repo:

- **Every release dispatches across a repo boundary.** `template-release.yml`
  runs `garden-generate.yml` in runway, and that needs `BOT_GITHUB_TOKEN` with
  `actions: write` there. When the dispatch fails, the release still cuts its
  tag, and its short URL 404s (LIB-0001 §4, LIB-0035 §4).
- **Every hub change is two PRs.** One releases it here. A second bumps
  `.lib-version`, `root_hcl_version` or a module pin in runway. Their reviews,
  plans and changelogs are in different repos, and the second PR can only
  start once the first is released.
- **Decisions about runway are filed here** (LIB-0017), while the tree they
  describe lives in runway. A record and the code it describes are always in
  different repos.

What the split protects is invariant 2: a spoke takes a version, never a
branch, so a broken hub change can't reach runway's plan until runway
chooses it. That's about versions, not about having a separate repo. Tags in
runway can do the same job.

## Decision

### 1. The library becomes runway's `lib/`

Every child directory moves under `lib/`, except what the platform pins to a
repo's root:

| In `noisypigeon/library` | In `noisypigeon/runway` |
| --- | --- |
| `terraform/` | `lib/terraform/` |
| `zola-site/` | `lib/zola-site/` |
| `terragrunt/root-hcl/` | `lib/terragrunt/root-hcl/` |
| `grafana-dashboards/` | `lib/grafana-dashboards/` |
| `observability/` | `lib/observability/` |
| `claude-plugins/` | `lib/claude-plugins/` |
| `.github/scripts/` | `lib/scripts/` |
| `README.md`, `CLAUDE.md` | `lib/README.md`, `lib/CLAUDE.md` |
| `CHANGELOG.md` | `lib/CHANGELOG.md` |
| `docs/adr/`, with `archive/` | `adr/` |
| `docs/runbooks/` | `runbooks/` |
| `.claude/skills/release-pr/` | `.claude/skills/release-pr/` |
| `.mise.toml` | merged into runway's `.mise.toml` |
| `.github/workflows/` | `.github/workflows/` |
| `.claude-plugin/marketplace.json` | `.claude-plugin/marketplace.json` |

- **Reusable workflows stay at the root.** GitHub only calls a reusable
  workflow from a repo's `.github/workflows/` (DEV-0155). They share that
  directory with runway's own callers, as they already share it with this
  repo's release automation.
- **So does the marketplace.** Claude Code reads it from the repo root. Its
  plugin `source` becomes `./lib/claude-plugins/pigeon-cli`, and its name
  stays `library`, so `pigeon-cli@library` doesn't change.
- **`lib/CLAUDE.md` is a nested `CLAUDE.md`.** It loads when work is under
  `lib/`, so runway's own `CLAUDE.md` keeps to the spoke and points to it.
- **`lib/CHANGELOG.md` keeps the library's rollup history** and stops there.
  From the hoist on, a PR under `lib/` writes its one line in runway's root
  `CHANGELOG.md`, like every other runway PR (DEV-0160). Each unit's own
  `CHANGELOG.md` moves with its unit and keeps getting entries.
- **Runbooks sit beside `adr/`,** since they're about operating a spoke, and
  runway is the spoke.

Three workflow names collide:

- **`blog-changelog.yml` and `interaction-limits-renew.yml`** are reusables
  here and thin callers in runway. The reusables keep their names, because
  shims and pigeon-cli cite them by path. runway's callers are renamed
  `blog-changelog-on-merge.yml` and `interaction-limits-monthly.yml`.
- **`root-changelog.yml`** is a caller in both. This repo's copy folds into
  runway's (§4).

### 2. The history comes with it

The library's history is rewritten once and merged, not copied:

1. `git filter-repo` on a fresh mirror clone of the library applies §1's map
   as `--path-rename` rules.
2. The same pass uses `--replace-message` to rewrite a bare `(#N)` in a commit
   message to `(noisypigeon/library#N)`. A PR reference then still names the
   library's PR, and doesn't autolink to an unrelated runway PR.
3. runway merges the result with `--allow-unrelated-histories`, in one PR.
   runway allows merge commits for that PR only, as RUN-0000 §4 did for its
   import.

`filter-repo` keeps every blob byte for byte. Only paths and commit IDs change.

### 3. Every tag is recreated, and versions continue

- **All 197 tags keep their names:** `terraform/<provider>/<module>/vX.Y.Z`,
  `zola-site/vX.Y.Z`, `terragrunt/root-hcl/vX.Y.Z`, `workflows/vX.Y.Z`,
  `grafana-dashboards/<set>/vX.Y.Z`, `observability/<set>/vX.Y.Z` and
  `claude-plugins/<set>/vX.Y.Z`. `filter-repo` moves each one to its rewritten
  commit, and they're pushed to runway. runway has no tags today, so no name
  collides.
- **Versions continue.** Each track's next release takes the next number from
  where it stands. There's no reseed, and no major bump just for moving.
  Tag shape and internal layout are private to the hub, and the public
  interface is the short URL (LIB-0001 invariant 3 and §5, LIB-0009).
  DEV-0110's seed tags were the opposite call, under the opposite
  assumption.
- **Every GitHub Release is recreated** on runway (144 today) from
  `gh release view`, with its title and notes verbatim. A tag with no Release
  gets none. garden's release posts link to `releases/tag/<tag>`, and their
  next generation points those links at runway (§6).
- **A recreated tag is the same content at a different path.** That matters
  differently per track:
  - **A module** is self-contained. Its tree at the runway tag is
    byte-identical to the library tag's, under `lib/`. Its `git::` source
    gains `//lib/` and resolves to the same code.
  - **A pre-hoist `workflows/` or `terragrunt/root-hcl/` tag** still names its
    old paths inside its own bodies (`.lib-src/.github/scripts/...`,
    `LIB_TAG_REMOTE`'s library default). Fetched from runway, it would look
    for scripts that aren't there. So **no consumer repoints at a pre-hoist
    version of those two tracks.** They repoint at the first post-hoist
    release (§9 step 4), and until then they keep fetching the archived
    library, which still serves the originals.

### 4. Release automation runs in runway

- **`template-release.yml` and its twin move with the workflows.** Every
  release predicate gains a `lib/` prefix. `lib/terraform/<provider>/<module>/`
  takes a `.tf` change, `lib/zola-site/{templates,static,theme.toml}` a theme
  change, `.github/workflows/*.yml` or `lib/scripts/` a CI change, and so on.
  As before, change one copy and you change its twin (library#301).
- **runway's root changelog takes the units as tags.** Its `precedence`, in
  `root-changelog.yml`, gains one `^lib/<unit>/` line per unit ahead of
  `terraform`. The library's root-changelog logic for releasing PRs, standing
  down so the release writes the line instead, moves into the same caller.
- **The `release-pr` discipline applies to a PR that touches `lib/`:** exactly
  one `release:*` label, and the PR body becomes the unit's changelog entry and
  Release notes verbatim. A PR outside `lib/` takes no label, as today.
- **LIB-0001 §4 is amended: runway writes the lib tracks' tags, and only
  those.** "A spoke never writes a tag" followed from go-getter needing a ref
  in the repo whose tree it resolves to. That repo is now runway. runway still
  writes no tag of its own, for a leaf, a workload or a site.

### 5. Consumers fetch runway, at a tag

- **runway still pins.** `.lib-version`, `root_hcl_version` and every
  hand-written module pin stay exact, and workload leaves keep LIB-0023's
  bounded floats. runway's `fetch-lib.sh` clones runway itself into
  `.lib-src/` at `.lib-version`, so `lib/` on `main` reaches runway's plan
  only when a PR moves the pin. A change and its pin bump may share a PR's
  review, but they're two steps: the release, then the bump.
- **The library's address changes in four places.** Each one's default
  becomes `noisypigeon/runway`:
  - `LIB_TAG_REMOTE` in `root.hcl` and `resolve-workloads.sh`;
  - `LIB_TAG_REMOTE` in `terragrunt-run.yml`'s newest-tag lookup;
  - `TAG_REPO` in `generate-module-redirects.sh`, whose `git_source` and
    `github_url` also gain the `lib/` prefix.
- **`.lib-src/` paths gain `lib/`.** For example `site-pages.yml`'s
  `theme_script` becomes `.lib-src/lib/zola-site/resolve-theme.sh`, and
  workflow bodies run `.lib-src/lib/scripts/<script>.sh`. A `LIB_SRC` override
  must then hold `lib/scripts/`, and `fetch-lib.sh` checks for that.
- **Every caller repoints** from `noisypigeon/library/.github/workflows/<w>.yml@workflows/vX.Y.Z`
  to `noisypigeon/runway/...`, at a post-hoist version:
  - runway's own callers. A reusable called at a tag in its own repo resolves
    like any other ref;
  - each shim's `pages.yml`;
  - pigeon-cli's `release.yml`, its `fetch-lib.sh`, and the marketplace
    `ref` in its `.claude/settings.json`.
- **Dashboard raw URLs** become
  `raw.githubusercontent.com/noisypigeon/runway/refs/tags/<tag>/lib/grafana-dashboards/<set>/<file>`.
  `grafana/dashboard`'s README and the set's README say so.

### 6. The short URL doesn't move

`noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z` is LIB-0009's stable
interface, and this record keeps it.

- **Its pages are regenerated against runway for every tag,** old and new. A
  redirect page's `terraform-get` meta tag then names
  `git::https://github.com/noisypigeon/runway.git//lib/terraform/<provider>/<module>?ref=<tag>`.
- **Generation is no longer dispatched across a repo boundary.**
  `template-release.yml` now runs in runway, and triggers
  `garden-generate.yml` in the same repo. The commit still deploys itself
  through `sites.yml` and the garden shim (LIB-0035 §2).
- **A theme release still dispatches the blog's shim,**
  `noisypigeon/noisypigeon.com`. That dispatch, and `sites.yml`'s to both
  shims, are the only cross-repo ones left. `BOT_GITHUB_TOKEN` still needs
  `actions: write` on the shims, and no longer on runway.

### 7. runway's Terraform never runs `lib/`

- **Detection already excludes it.** runway's `leaf_pattern` is anchored at
  the root (`^terraform/`, `^workloads/...`), so a change under
  `lib/terraform/` affects no leaf. `terragrunt-detect.yml` writes
  `terragrunt/apply` for it as it does for a docs-only PR, so the ruleset
  doesn't block a `lib/` PR.
- **Discovery gets a guard as well.** `terragrunt-run.yml`'s filter gains
  `!./lib/**`. `lib/` holds no `terragrunt.hcl` today, but it does hold
  `root.hcl` and modules, and test data may hold more later. A unit under it
  must never be planned.

### 8. The issues move, and the library is archived

- **Open issues transfer** with `gh issue transfer` (41 today). The
  `out-of-scope` label is created on runway first, and every label is carried
  over. From then on, `## Out of scope` issues are filed in runway (DEV-0031).
- **The library keeps its tags and Releases** and is archived, read-only. Any
  `git::` source, raw URL, workflow call or marketplace pin still naming it
  keeps resolving. That's what lets §9 repoint each consumer on its own
  schedule.
- **Its last commit on `main`** reduces it to a README naming runway's `lib/`.
  Its tags don't reach that commit, so no pinned consumer sees it.

### 9. Cutover, in order

**Every short URL must resolve throughout.** No step below changes what a
pinned consumer fetches until that consumer's own PR repoints it.

1. **The freeze starts:** no library merge, and no runway merge outside
   these steps.
2. **The rewrite:** §2's `filter-repo` pass. The tags are pushed to runway,
   and §3's Releases are recreated there.
3. **One runway PR:** the merge (§2), the renamed callers (§1), the
   predicates and precedence (§4), the four defaults and `lib/` paths (§5),
   and §7's guard. Its plan must be `No changes.`, because nothing under
   `terraform/`, `workloads/` or `zones/` moves. runway's callers still pin
   the library at `workflows/v6.0.0`.
4. **The first post-hoist releases,** cut by step 3's merge from runway:
   `workflows` takes a minor, and `terragrunt/root-hcl` a patch (§10). A
   second runway PR bumps `.lib-version`, `root_hcl_version` and every caller
   to them. It must plan `No changes.` too. The freeze ends.
5. **The consumers repoint,** one PR each: each shim's `pages.yml`, and
   pigeon-cli's caller, `fetch-lib.sh` and marketplace pin.
6. **garden regenerates** from runway (§6). Every redirect page names
   runway, and every release post links to runway's Release.
7. **The library closes:** §8's issue transfer, the README commit, then the
   archive.

### 10. Release impact

- **`workflows` takes a minor in step 4,** for the new defaults and paths. No
  input is added, removed or retyped, so no caller changes beyond its `uses:`
  repo.
- **`terragrunt/root-hcl` takes a patch,** for `LIB_TAG_REMOTE`'s default.
- **No other track releases.** Modules, the theme, dashboards, the
  observability stack and the plugin are byte-identical at their new paths. A
  path-only change under them matches no release predicate.

## Consequences

- **A hub change is one repo and one review.** The library's release, the pin
  bump and the record that justifies both share a history and a search.
- **The family's standing cross-repo dispatch is gone.** A failed garden
  generation is a failed run in the repo that caused it. The "short URL 404s"
  hazard is still there, but it now needs a failure inside one repo, not a
  token scope on another.
- **runway carries the library's history, size and public visibility.**
  RUN-0000 §1's sensitivity rules now bind `lib/` and every PR under it:
  describe resources by role, and read the whole plan.
- **runway now writes tags.** Its history holds a bot release commit per
  `lib/` release, beside LIB-0035's generation commits.
- **A `lib/` change can no longer be tested against "another repo"** by
  pointing a spoke at a branch. Testing still goes through `LIB_SRC` or a
  release, as invariant 2 requires.
- **This repo's `CLAUDE.md` "hosts nothing" section** describes no repo
  afterwards. `lib/CLAUDE.md` keeps the consumption and release contract, and
  runway's `CLAUDE.md` says the hub is a directory of the spoke.
- **pigeon-cli's CLI-0161** names `noisypigeon/library` as its source. A
  matching amendment belongs in pigeon-cli's own `adr/`, which keeps its
  domain (LIB-0017 §5).
- **Records cite the old repo forever.** `noisypigeon/library#N` links keep
  resolving: issue transfers redirect, and archived PRs stay readable. They
  aren't rewritten.

## Out of scope

- **Deleting `noisypigeon/library`.** Its tags back every consumer that
  hasn't repointed yet, and its archive is what keeps old `git::` sources
  resolving. This is a design boundary, not a deferral.
- **Renaming the `library` marketplace or the tag tracks.** Both are
  interfaces a consumer wrote down, and this record moves only what backs
  them. This is a design boundary, not a deferral.
- **Moving the shims' `pages.yml` into runway.** `actions/deploy-pages`
  deploys only the calling repo's site (DEV-0156). This is a constraint, not
  a deferral.
- **Consuming `lib/` in-tree at `HEAD`.** runway could read its own `lib/`
  directly, with local `./.github/workflows/` calls and no fetch. That would
  give up invariant 2 for the one consumer whose plan a broken change would
  hit first. This is a design boundary, not a deferral.

## Verification

1. **Tags match.** `git ls-remote --tags` on runway lists the same 197 names as
   the library. For every module tag, the library tag's
   `terraform/<provider>/<module>` tree and the runway tag's
   `lib/terraform/<provider>/<module>` tree have the same tree hash.
2. **Releases match.** runway has a Release for exactly the tags the library
   has one for, each with the same title and body.
3. **No plan changes.** Steps 3 and 4's PRs both plan `No changes.` for every
   leaf.
4. **The short URLs never break.** At every step:
   - `terraform init` of a pinned `noisypigeon.garden/terraform/...` source
     succeeds;
   - after step 6, its redirect page's `terraform-get` names
     `noisypigeon/runway.git//lib/...`;
   - `/schemas/workload/v1.json` serves.
5. **Consumers run from runway.** After step 5, both shims deploy through
   `site-pages.yml` at the new version. pigeon-cli's release resolves its
   scripts from `.lib-src/lib/scripts/`, and its marketplace pin loads
   `pigeon-cli@library`.
6. **A `lib/` release runs end to end in runway:** a labelled PR, its tag,
   its Release, its line in runway's root `CHANGELOG.md`, garden's
   regeneration and deploy.
7. **The library is closed.** It has no open issues, it's archived, and a
   `git::https://github.com/noisypigeon/library.git//...?ref=<tag>` source
   still resolves.

## Amendments

### 2026-10-28: the cutover, as it will run

Everything above is left as filed. Checking §9 and §10 against the live
trees, before anything moved, found three places where they can't work as
written. Where this entry and the text above disagree, this entry is what
runs.

1. **The hoist merge would release every unit (§9 steps 3 and 4).**
   `template-release.yml` runs on `pull_request: closed`, from the merge
   commit. On the hoist PR every path under `lib/` is new, so every predicate
   matches. It would cut a release for every module, the theme, each
   dashboard set and the plugin.
   - **So the hoist PR lands four workflows set to `workflow_dispatch`
     only:** `template-release.yml`, the library's root-changelog twin (renamed
     `lib-root-changelog.yml` in the rewrite, to stay clear of runway's own),
     `module-docs.yml` and `scripts-test.yml`. That PR is a pure move. Its
     merge tags nothing.
   - **The first post-hoist releases come from two rewiring PRs, not from
     step 3's merge.** The first changes every script path, workflow path and
     default under `lib/scripts/` and `.github/workflows/`, and re-enables the
     four workflows. Its merge runs the new `template-release.yml` and cuts a
     `workflows` minor. The second changes the template, the theme's
     `homepage` and the plugin, and cuts a patch of each. This is DEV-0110's
     "pure rename first, rewiring second", which §9 had collapsed.
   - **Only then does a third runway PR bump the pins** (§9 step 4's second
     half). It must still plan `No changes.`
2. **The plugin takes a patch (§10).** pigeon-cli pins the marketplace at a
   `claude-plugins/pigeon-cli/vX.Y.Z` tag. At every recreated pre-hoist tag,
   `marketplace.json` still names `./claude-plugins/pigeon-cli`, which is now
   under `lib/`. So no recreated plugin tag loads from runway. The plugin
   needs a post-hoist tag that carries the corrected `marketplace.json`, and
   the plugin's own `repository` URL is the change that releases it. Old
   plugin tags join §3's caveat beside `workflows/` and
   `terragrunt/root-hcl/`. Old module and dashboard tags still resolve: a
   dashboard's raw URL just gains `lib/` at the same tag.
3. **The pins are newer than §9 says.** runway pins `workflows/v9.2.0`, not
   `v6.0.0`. Both shims pin `v6.1.0`, and pigeon-cli pins `v3.4.0`. So §9
   step 5 is a jump of several majors for the shims and pigeon-cli. Each one
   checks its caller's inputs against the new version before repointing, and
   a caller that needs more than a `uses:` change gets its own PR.

Two smaller things the check settled:

- **Tag pushes fire nothing.** Across the library's history, only two
  workflows ever had a `push` trigger: `module-docs.yml` and the early
  `pigeon-dev-pages.yml`. Both filter to `branches: [main]`. Pushing
  197 tags to runway runs no workflow. Recreating Releases doesn't either:
  runway has no `release` trigger.
- **The hoist PR needs merge commits for one PR.** The owner turns them on for
  that PR and off again after it merges, as RUN-0000 §4 did.
