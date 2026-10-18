# DEV-0093: move `terraform/modules/scaleway/*` to top-level `modules/scaleway/*`, cut a major release for every module

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

The user wanted `terraform/modules/scaleway/*` relocated to a new top-level `modules/scaleway/*`, every module given a major version bump under the new path, and every source string's repo URL corrected — `git::...noisypigeon/pigeon.git//terraform/modules/scaleway/<module>?ref=terraform/modules/scaleway/<module>/vX.Y.Z` had been pointing at `noisypigeon/pigeon`, a prior name of this same repo, still resolving today only via GitHub's rename-redirect; the real current name is `noisypigeon/noisypigeon`.

Confirmed with the user: "major release" means **the next available major per module**, computed via the normal `release:major`-labeled `/release-pr` flow — not a blanket `v1.0.0` applied uniformly. Research found two modules already past 1.0 (`iam-policy` v1.1.1, `block-volume` v1.0.0), so a correct major bump lands them at v2.0.0, not v1.0.0.

**Research confirmed, before making any change:**

- Current versions (matching each module's `CHANGELOG.md` and latest git tag exactly): `project` v0.2.1, `object-bucket` v0.2.0, `iam-policy` v1.1.1, `compute-instance` v0.9.1, `block-volume` v1.0.0.
- `terraform/modules/` held nothing but `scaleway/` and its own `README.md` (DigitalOcean's modules were already deleted, ADR-0086) — once `scaleway/*` moved out, `terraform/modules/` ceased to exist entirely, same as `service/` and `terraform/infrastructure/digitalocean/` disappearing in prior ADRs.
- 16 live consumers, all inside this repo's own `terraform/infrastructure/scaleway/**` (verified via a full-repo `.tf` grep — none under `workloads/`, none anywhere else): 1× `project`, 6× `iam-policy`, 7× `object-bucket`, 1× `compute-instance`, 1× `block-volume`. One additional `compute-instance` reference, in `custodian/dhj/compute.tf`, is commented-out/dead — not a live consumer, fixed anyway for hygiene.
- Real, pre-existing version drift: `iam-policy` had one consumer on v0.1.0 against five on v1.1.1; `object-bucket` had three different versions pinned across its seven consumers. Verified safe to converge all of them onto the same new major in this same change: read both modules' `inputs.tf` directly — every variable beyond the always-supplied required ones has a default (including `admin_project_id`, added after ADR-0069, `default = null`), so no consumer needed a new argument added to jump straight to the new major.
- No external consumers. Checked every other repo in the `noisypigeon` org (`pigeon-cli`, `pigeon-os`, `dotfiles`) via `gh search code` and a direct git-tree walk — zero `.tf`/`.hcl` files, zero matches anywhere. This migration is fully self-contained to this repo.
- A real automation gap in `.github/workflows/module-release.yml`: its version-bump logic computes the prior version via `git tag -l "${dir}/v*"`, where `$dir` is the module's current directory path. Since every existing tag lives under the old `terraform/modules/scaleway/*` prefix, a lookup against the new `modules/scaleway/*` prefix would find nothing, and the script's empty-match fallback is `NEXT="0.1.0"` — not `$((MA+1)).0.0`. Left alone, the normal `/release-pr` flow would have incorrectly restarted every module at v0.1.0 instead of computing the correct next major.

## Decision

### Seed tags (confirmed with the user, in place of bypassing the automation)

Before merging the release PR, 5 lightweight git tags were pushed directly to origin — no PR, no GitHub Release, pure bookkeeping — mirroring each module's real current version under the new path prefix:

```
modules/scaleway/project/v0.2.1
modules/scaleway/object-bucket/v0.2.0
modules/scaleway/iam-policy/v1.1.1
modules/scaleway/compute-instance/v0.9.1
modules/scaleway/block-volume/v1.0.0
```

This lets `module-release.yml`'s existing `$LATEST` lookup find a correct baseline and compute the right next major with zero changes to its bump arithmetic. These tags are **not** real historical releases — no GitHub Release object, no CHANGELOG entry — and are documented here explicitly so a future reader of `git tag --list` never mistakes them for one. Old tags under `terraform/modules/scaleway/*` are left untouched forever, per this repo's established precedent (ADR-0037) of never rewriting or deleting historical tags.

With the seed tags in place, `release:major` on the move PR computed:

| Module | Before | After |
|---|---|---|
| `project` | 0.2.1 | **1.0.0** |
| `object-bucket` | 0.2.0 | **1.0.0** |
| `iam-policy` | 1.1.1 | **2.0.0** |
| `compute-instance` | 0.9.1 | **1.0.0** |
| `block-volume` | 1.0.0 | **2.0.0** |

### The move

`git mv terraform/modules/scaleway modules/scaleway` and `git mv terraform/modules/README.md modules/README.md` — one commit, module `.tf` content byte-identical. The major bump reflects that **a module's source path is effectively part of its public interface**: relocating it is breaking for every consumer regardless of whether any resource definition changed.

### Automation fixes

- `module-release.yml`: the hardcoded `find terraform/modules/scaleway ...` discovery path → `find modules/scaleway ...`; the root-`CHANGELOG.md` label construction (`"- [terraform/${dir#terraform/modules/}] ..."`, which stripped `terraform/modules/` then re-added a literal `terraform/` — already inconsistent with the module README's own stated scheme even before this move) → `"- [${dir#modules/}] ..."`, producing clean labels like `- [scaleway/compute-instance] ...`. Not generalized beyond `scaleway` specifically — no second provider exists under `modules/` yet; add that generalization when one actually lands, per this repo's established "don't add a knob until needed" pattern (ADR-0043's precedent).
- `module-docs.yml`: the 5-path `working-dir:` list rewritten from `terraform/modules/scaleway/*` to `modules/scaleway/*`.
- `.claude/skills/release-pr/SKILL.md`: its 4 occurrences of the `terraform/modules/` prefix updated to `modules/`.

### `modules/README.md`

Moved and rewritten: module table's `Path` column now `modules/scaleway/*`; "Versioning" section's stated tag scheme corrected to `modules/<provider>/<module>/vX.Y.Z` and its repo-name typo (`pigeon`) fixed to `noisypigeon`; "Consuming" section's example `git::` source and local-clone example both corrected to the real repo name and new path — also fixing a pre-existing, unrelated inconsistency found in research, where the old README's example `ref=` used a short form that never matched what the automation actually tagged. Relative links throughout adjusted for the directory's new, one-level-shallower position (it's no longer nested under `terraform/`).

### All 16 consumers updated

Every `module` block across `terraform/infrastructure/scaleway/**/*.tf` rewritten to the new repo name, new path, and new major tag for its module — converging all pre-existing version drift (every `iam-policy` consumer now on v2.0.0, every `object-bucket` consumer now on v1.0.0, etc.). The one dead/commented `compute-instance` reference in `custodian/dhj/compute.tf` got the same text fix for hygiene, despite being inert.

### Repo-level docs

- `CLAUDE.md`: opening paragraph's description of `terraform/modules/` now describes `modules/`; new ADR-0093 index bullet; `## Dev cycle`'s pointer to the module README updated.
- `docs/USAGE.md`: structure list's module bullet moved out from under the implicit `terraform/` grouping to its own top-level `modules/` bullet, parallel to `terraform/infrastructure/` and `workloads/`.
- `terraform/README.md`: deleted (confirmed with the user). Its whole premise — "two independent trees: `modules/`, `infrastructure/`" — no longer held once `modules/` wasn't under `terraform/` anymore. `docs/USAGE.md`/`CLAUDE.md` now point directly at `terraform/infrastructure/README.md` for that tree and `modules/README.md` for this one, mirroring how `workloads/README.md` already stands alone.

**Left untouched (historical, by established precedent — ADR-0086/0089/0091/0092):** every ADR's own text (0037 through 0092) describing `terraform/modules/scaleway/...` as it existed when written; every module's own `CHANGELOG.md` entries prior to the new major (the new major's entry is simply prepended, same mechanical behavior as every prior release in this repo); `docs/adr/0052`'s generic path-template mention.

## Consequences

- Every leaf consuming a scaleway module needs a fresh `terragrunt init` on its next plan/apply, since the module source changed. Module *content* is byte-identical, so no resource diff or replacement is expected — but this can't be verified in this session without using real credentials (same caution applied in ADR-0092, after an earlier credential-exposure incident this session). Flagged as a manual follow-up for the user, not performed here.
- Old `terraform/modules/scaleway/*` tags remain forever resolvable — anyone still holding an old pinned ref keeps working.
- This is the largest single-PR blast radius in this repo's recent history: 16 live leaves' source strings changed simultaneously, in one PR. No `terraform plan`/`apply` was run against any of them during this change.
- `release:major` on this PR is a one-time artifact of the move touching every module's files at once — it does not imply every module's *interface* changed; only `iam-policy`'s and `object-bucket'`s consumers saw any version convergence, and that convergence was itself non-breaking (verified via `inputs.tf`).

## Out of scope

- Generalizing `module-release.yml`'s module-discovery `find` command beyond `modules/scaleway` to handle a hypothetical second provider — add when one actually exists under `modules/`.
- Any functional change to any module's resources — this ADR is a path/versioning/naming correction only.
