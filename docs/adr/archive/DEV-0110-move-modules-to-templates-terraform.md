# DEV-0110: move `modules/` to `templates/terraform/`, keep the noisypigeon.com short URLs stable

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

The repo held versioned Terraform modules at `modules/scaleway/{project,object-bucket,compute-instance,iam-policy,block-volume}` plus `modules/README.md`. The goal: move this to `templates/terraform/` (i.e. `templates/terraform/scaleway/*`), establishing `templates/` as a new top-level convention for versioned reusable scaffolding, while the public short import URLs added by [ADR-0109](DEV-0109-short-module-source-urls-via-blog-redirect.md) (`https://noisypigeon.com/modules/<provider>/<module>/vX.Y.Z`) must not change.

**Research confirmed, verbatim, before planning anything:**

- [ADR-0093](DEV-0093-move-scaleway-modules-to-top-level-modules.md) already did this exact kind of move once (`terraform/modules/scaleway/*` → `modules/scaleway/*`) and established the governing principle: "a module's source path is effectively part of its public interface: relocating it is breaking for every consumer regardless of whether any resource definition changed" — so it forced a major-version **seed tag** for every module under the new prefix (bookkeeping only, no content change), rather than making the automated tooling search multiple tag prefixes forever. It also confirmed git tags are immutable snapshots — "old tags... are left untouched forever... anyone still holding an old pinned ref keeps working" — moving a directory in a later commit never invalidates an existing tag.
- Fresh tag inventory: 43 total tags across two prefix eras — 23 legacy `terraform/modules/*` tags from before ADR-0093, 20 current `modules/*` tags. The 5 modules' latest versions going into this move: `project` v1.0.0, `object-bucket` v2.0.0, `iam-policy` v2.0.1, `compute-instance` v2.3.4, `block-volume` v2.0.0.
- Crucially, **all 22 `workloads/**/*.tf` consumer `source =` lines already use the stable `https://noisypigeon.com/modules/...` redirect form**, landed by ADR-0109. Unlike ADR-0093's move, which rewrote 16 live consumer leaves by hand, this move touches zero consumer `.tf` files — the entire payoff of building the redirect layer first.
- The one place that actually needed new logic: `workloads/blog/generate-module-redirects.sh`, which assumed tag-prefix == git-source-subdirectory == public-URL-path (all the literal string `modules/...`). After this move those three diverge: new tags get prefix `templates/terraform/...` (the real new directory, needed for `git::` resolution), but the public URL path must stay hardcoded `modules/...` forever, decoupled from the real directory.
- **A real operational hazard, found by testing rather than assumed**: `module-release.yml`'s "Determine changed module directories" step diffs the merge commit's changed files against discovered module directories, matching any `.tf` path under them. Landing the `git mv` and the discovery-path update (`find modules/scaleway` → `find templates/terraform/scaleway`) in the *same* PR would make every renamed `.tf` file show up as "changed" against the new path — with zero tags yet existing under that new prefix, the automation's "latest version" lookup would find nothing and fall through to its `NEXT="0.1.0"` default, auto-tagging and auto-releasing all 5 modules at a bogus `v0.1.0` regardless of any `release:*` label (the label only selects the bump arithmetic, which is skipped entirely when no prior tag is found). Confirmed empirically via `git diff --name-only` against the real move commit before merging anything.

User confirmed, following ADR-0093 precedent exactly: cut a major-version seed tag for every module under the new prefix — bookkeeping only, same tree content as the move commit — rather than making `module-release.yml`'s "latest version" lookup search two prefixes permanently.

## Decision

### 1. Land the move as two sequential PRs, to defuse the auto-tagging hazard

**PR #142** ("file move only"): pure `git mv modules/scaleway templates/terraform/scaleway` and `git mv modules/README.md templates/terraform/README.md` (content byte-identical), plus repointing `module-docs.yml`'s hardcoded working-dir list at the new location (had to land atomically with the move — `module-docs.yml` triggers on any `**/*.tf` push, so leaving it pointed at the now-nonexistent old path would break the very next unrelated `.tf` push anywhere in the repo). `module-release.yml` was deliberately left untouched in this PR: its discovery (`find modules/scaleway ...`) now finds nothing (`find: 'modules/scaleway': No such file or directory`), so `CHANGED_MODULES` stays empty and no changelog/tag/release step fires — confirmed from the actual `module-release` run's logs after merging.

**This PR** (the follow-up): updates `module-release.yml`'s discovery path, the redirect generator, the `release-pr` skill, `templates/terraform/README.md`, `CLAUDE.md`, `docs/USAGE.md`, the root `CHANGELOG.md` header, and this ADR. It touches **zero** `.tf` files (the move already happened in PR #142), so `CHANGED_FILES` for this merge contains no `.tf` path at all — the newly-correct `MODULE_DIRS` discovery has nothing to match against, so no module is detected as changed here either. Neither PR touches any `modules/<provider>/<module>/` or `templates/terraform/<provider>/<module>/` directory in a way the automation acts on — no `release:*` label needed on either.

### 2. Update `workloads/blog/generate-module-redirects.sh`

The tag regex became an explicit two-prefix allowlist — deliberately not a generic catch-all, to preserve ADR-0109's decision that legacy `terraform/modules/...` tags stay unredirected:

```bash
if [[ ! "$tag" =~ ^(modules|templates/terraform)/([a-z0-9-]+)/([a-z0-9-]+)/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
```

`git_source`/`github_url` use the real, matched `prefix` (whatever the tag's actual commit tree looks like); `url_path` — the **public** URL — stays hardcoded literal, independent of `prefix`:

```bash
url_path="modules/${provider}/${module}/v${version}"
```

That one line is the entire stable-URL guarantee. Verified locally by creating a throwaway local tag `templates/terraform/scaleway/object-bucket/v3.0.0` (never pushed — deleted after the check) and confirming `mise run blog-build` produced a page at the same public path `/modules/scaleway/object-bucket/v3.0.0/` with a `terraform-get` tag correctly pointing at the new `templates/terraform/...` git subpath, while the pre-existing `v1.0.0` page's output stayed byte-for-byte unchanged. The tag-listing glob was extended to `git tag --list 'modules/*/*/v*' 'templates/terraform/*/*/v*'`.

### 3. Update `.github/workflows/module-release.yml`

```diff
-MODULE_DIRS=$(find modules/scaleway -mindepth 2 -maxdepth 2 -name versions.tf -printf '%h\n' | sort)
+MODULE_DIRS=$(find templates/terraform/scaleway -mindepth 2 -maxdepth 2 -name versions.tf -printf '%h\n' | sort)
```
```diff
-ROOT_ENTRY="- [${dir#modules/}] ${PR_TITLE} ([#${PR_NUMBER}](${PR_URL}))"
+ROOT_ENTRY="- [${dir#templates/terraform/}] ${PR_TITLE} ([#${PR_NUMBER}](${PR_URL}))"
```

No other changes needed — `$dir`-derived tag naming and the `git tag -l "${dir}/v*"` latest-version lookup both naturally follow the new discovery path, staying single-prefix going forward.

### 4. `.github/workflows/module-docs.yml`

Rewrote the hardcoded working-dir list to the 5 new paths under `templates/terraform/scaleway/` (landed in PR #142, see step 1).

### 5. Cut 5 seed tags + releases, continuing each module's version with a forced major bump

Performed manually against `main` after both PRs merged (not via the automated flow — see step 1):

```
project          v1.0.0 → templates/terraform/scaleway/project/v2.0.0
object-bucket     v2.0.0 → templates/terraform/scaleway/object-bucket/v3.0.0
iam-policy        v2.0.1 → templates/terraform/scaleway/iam-policy/v3.0.0
compute-instance  v2.3.4 → templates/terraform/scaleway/compute-instance/v3.0.0
block-volume      v2.0.0 → templates/terraform/scaleway/block-volume/v3.0.0
```

Bookkeeping only — identical tree content to the move commit, just a new tag name. Each got a matching GitHub Release, mirroring `module-release.yml`'s own "Tag and release each changed module" step and exactly how ADR-0093's seed tags were cut.

### 6. Update `.claude/skills/release-pr/SKILL.md`

Rewrote every `modules/<provider>/<module>` path reference (frontmatter description, H1 heading, step 3/4 examples) to `templates/terraform/<provider>/<module>`.

### 7. Update `templates/terraform/README.md` (the moved file)

- Extended the move-history chain with this ADR.
- Versioning section now documents three tag-prefix eras (pre-ADR-0037 shortest form → `terraform/modules/...` → `modules/...` → `templates/terraform/...`), reiterating old tags are never renamed/deleted.
- New clarifying paragraph, the single most important fact for anyone reading this after the move: the public `noisypigeon.com/modules/<provider>/<module>/vX.Y.Z` short-URL namespace stays `modules/...` forever, regardless of which era a version's tag lives under or where this directory itself moves in the future — a stable public interface, deliberately decoupled from internal layout.
- Local-clone-by-path example updated to `../noisypigeon/templates/terraform/scaleway/object-bucket`.

### 8. Update `CLAUDE.md`, `docs/USAGE.md`, root `CHANGELOG.md`

Repo-layout description, structure listing, and the versioned-changelog pointer in the root `CHANGELOG.md`'s header all updated to `templates/terraform/`. Added ADR-0109 and ADR-0110 bullets to CLAUDE.md's ADR list (ADR-0109 had been landed but never got a bullet — fixed here too). Every historical ADR bullet/body narrating `modules/` or `terraform/modules/` as it was at the time was left untouched, per this repo's own established precedent (confirmed: ADR-0093 itself left ADR-0037-era bullets untouched).

## Consequences

- The repo's Terraform module source now lives at `templates/terraform/scaleway/*`; `modules/` no longer exists.
- Every pre-existing `noisypigeon.com/modules/...` short URL continues to resolve exactly as before — unchanged `terraform-get` content for every pre-move tag.
- Five new major versions exist (`v2.0.0`/`v3.0.0` per module) purely as bookkeeping; their short URLs are new (`.../v3.0.0`) and resolve to the new `templates/terraform/...` git subpath.
- Zero `workloads/**/*.tf` consumer edits were needed — the direct payoff of landing ADR-0109 before this move.
- `module-release.yml`/`module-docs.yml`/the `release-pr` skill all now target `templates/terraform/scaleway/*`; the "latest version" lookup stays single-prefix.
- `templates/` is now an established top-level convention name (`templates/terraform/` its first occupant), available for other versioned/reusable scaffolding kinds later.
- Landing this kind of move as two sequential PRs (pure rename, then config/doc updates) is now the established pattern for any future directory move that the automated release pipeline might otherwise misinterpret as a content change.

## Out of scope

- Legacy pre-ADR-0093 (`terraform/modules/...`) tags still don't get redirect pages — unchanged boundary from ADR-0109, not reopened here.
- No other `templates/<kind>/` sibling is designed in this ADR — only the naming convention is opened up.
- The stale `pigeon.git`-repo-name example left in `templates/terraform/scaleway/iam-policy/README.md`'s hand-written usage snippet (pre-dates even ADR-0093, never fixed) is pre-existing drift, unrelated to this move — not fixed here to keep this change tightly scoped.
