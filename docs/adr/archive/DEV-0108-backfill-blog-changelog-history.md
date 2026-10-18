# DEV-0108: compute brief digest titles from entries, backfill blog changelog history

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

Two follow-ups to ADR-0107's changelog automation (the deploy-trigger fix that followed it, dispatching `blog-pages.yml` after bot-authored commits, landed as PR #137 without its own ADR — a small, mechanical CI fix, not a design decision).

First, the daily on-site digest post's title was hardcoded `"Changelog: ${TODAY}"` — a reader gets a date, not a sense of what changed. The title should summarize the day's actual entries.

Second, ADR-0107 deliberately declared "no backfill of blog history," mirroring the root `CHANGELOG.md`'s own ADR-0050 precedent. The user asked for it anyway. **Research confirmed, verbatim, before planning anything:**

- `git log -- workloads/blog/ service/blog/` turns up exactly 16 commits, of which 14 are in scope and 2 are not: `ab0967f`/PR #135 ("Fix object-bucket endpoint output" — an unrelated Terraform PR; its diff touches blog templates only because another commit landed on the same branch before squash-merge) and `b69365b`/PR #119 ("Move GitHub Pages leaf to `workloads/blog/terraform`" — touches the old DNS leaf path, not `workloads/blog/src/`, out of scope per the same path filter the live automation already uses). Of the remaining 14, two (`972bd63`/PR #136 and its bot-commit `e25e76b`) already have live, correctly-generated automated entries from today — backfilling them would duplicate. That leaves **12 commits across exactly 3 Pacific-time days**: 2026-09-27, 2026-10-01, 2026-10-03 — not the sprawling multi-year history the original no-backfill precedent was guarding against.
- Root `CHANGELOG.md` was **not**, in fact, starting from zero — it already carries a dense hand-authored history back to 2026-09-25 (the ADR-0050/0051 PRs), including an existing `[blog]` line for PR #66: `- [blog] ADR-0067: rewrite the noisypigeon.github.io blog from Jekyll to Zola as `service/blog` ([#66](https://github.com/noisypigeon/pigeon/pull/66))`. "Starts fresh at ADR-0050" means the file's own history begins at the PR that created it, not that it contains zero entries — PR #50's own landing retroactively seeded everything from that point forward in one go.
- PR #118's own body states this repo's explicit precedent: "`docs/adr/0067-rewrite-blog-to-zola.md` ... and `CHANGELOG.md`'s historical `[blog]` entry are left untouched — both accurately describe `service/blog` as it existed when written, consistent with this repo's precedent of not rewriting history." The existing PR #66 entry uses a hand-narrated description (not the raw PR title) and links to the now-renamed `noisypigeon/pigeon` repo — both are left exactly as they are.

## Decision

### 1. Compute digest titles from entries

In `module-release.yml`'s "Update blog changelog and daily digest" step, after appending the new bullet, the title is recomputed from every bullet currently in the file and rewritten in place:

```bash
STRIP_RE='^[a-z]+(\([^)]+\))?: '
N=$(grep -c '^- ' "$DIGEST")
FIRST_RAW=$(grep '^- ' "$DIGEST" | head -n1 | sed -E 's/^- (.*) \(\[#?[^]]*\]\(.*\)\)$/\1/')
FIRST_CLEAN=$(printf '%s' "$FIRST_RAW" | sed -E "s/$STRIP_RE//")
if [ "$N" -gt 1 ]; then
  DIGEST_TITLE="${FIRST_CLEAN} (+$((N-1)) more)"
else
  DIGEST_TITLE="$FIRST_CLEAN"
fi
sed -i "s|^title = .*|title = \"${DIGEST_TITLE_ESCAPED}\"|" "$DIGEST"
```

A leading conventional-commit prefix (`feat(blog): `, `fix(ci): `, etc.) is stripped so the public-facing title reads as prose. The chronologically-first entry of the day becomes the title; additional same-day entries collapse to a `(+N more)` suffix. Scoped to the digest post title only — `workloads/blog/CHANGELOG.md` and the root rollup keep the raw, unstripped PR title verbatim, since those are exact engineering records, not editorialized.

### 2. Backfill — sourcing rule

- **PR-linked commits** (subject ends in `(#N)`: `74df29e`→#66, `1174f1d`→#69, `75e7414`→#118): fetched the real title/body via `gh pr view N --json title,body,url` — byte-accurate to what the live automation would have produced, not a reconstruction from the commit message. PR #118 is a concrete case where this mattered: its real title ("Rename service/blog to workloads/blog/src") differs from its squash-commit subject (`docs(adr-0091): ...`).
- **Direct-push commits** (the other 9, no PR — `f256c83`, `9979a98`, `4da2430`, `bc99d6b`, `9f14bcd`, `eb25e46`, `3dc9e54`, `d865f82`, `8925ece`): commit subject used as the title/bullet text; linked by short SHA to its commit view (`https://github.com/noisypigeon/noisypigeon/commit/<sha>`) instead of a PR URL.

### 3. Backfill — what changed

- **`workloads/blog/CHANGELOG.md`**: all 12 entries added (this file is new as of ADR-0107 and had no prior history to conflict with), newest-first, PR #136's existing live entry staying at the top where it already was.
- **Root `CHANGELOG.md`**: only **10** of the 12 added — PR #66 already had an entry there (see Context) and is left untouched per the documented no-rewrite precedent. The 10 new one-liners join the existing `## 2026-10-03`, `## 2026-10-01`, and `## 2026-09-27` date sections (all three already existed from unrelated PRs landing those same days).
- **On-site digest posts**: `content/changelog/2026-09-27-changelog.md` and `2026-10-01-changelog.md` created new; `2026-10-03-changelog.md` already existed (created live today for PR #136) — the 9 historical bullets were prepended before its existing one (all 9 are chronologically earlier than PR #136's 19:13 PDT merge), and its title recomputed over all 10 resulting entries: `"deploy profiles page (+9 more)"`.

## Consequences

- `/changelog/` gains 2 new posts (`2026-09-27`, `2026-10-01`) and one, `2026-10-03`, grows from 1 to 10 entries with a recomputed title.
- `workloads/blog/CHANGELOG.md` now has 13 total entries (1 live + 12 backfilled); root `CHANGELOG.md` gains 10.
- Root `CHANGELOG.md`'s header sentence "Starts fresh at ADR-0050 — no backfill of prior history" now needs a caveat: this is the one deliberate exception, scoped to exactly 2026-09-27 through 2026-10-03, performed because the actual window was small and concrete rather than open-ended.
- Future digest posts (from today forward) get their title computed automatically per Part 1 — no further manual title-writing needed.

## Out of scope

- Fixing the existing PR #66 root-`CHANGELOG.md` entry's stale `noisypigeon/pigeon` repo link or its hand-narrated (non-verbatim) title — left untouched per this repo's explicit no-rewrite-history precedent (PR #118's own body), not an oversight.
- Any backfill beyond the blog — this ADR is scoped to `workloads/blog/`/`service/blog/` history only.
