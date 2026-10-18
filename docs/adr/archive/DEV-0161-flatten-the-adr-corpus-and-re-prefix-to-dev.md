# DEV-0161: flatten the ADR corpus to `adr/` and re-prefix it `DEV-`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-13.
- **Status**: Accepted.

## Context

PD-0160 renamed `adr/infrastructure/` to `adr/pigeon.dev/` and gave its 116 records
a `PD-` prefix, on the argument that `adr/` had grown two children named on different
axes — a topic and a repo — and that the topic one was really this repo's decision log.

That argument was right and incomplete. It fixed the naming axis and left the
nesting, which had become redundant the moment the directory was named after the repo
containing it: `pigeon.dev/adr/pigeon.dev/`. The same redundancy PD-0159 noted for
`noisypigeon.com/src` inside a repo called `noisypigeon.com`, and the same one
LIB-0001 is in the middle of removing elsewhere by giving each repo its own
`docs/adr/`.

Two other things in `adr/` are now wrong rather than merely untidy:

- **`adr/pigeon-lib/` is a stale duplicate.** LIB-0002 moved that domain into
  `noisypigeon/pigeon-lib` at `docs/adr/`, by `filter-repo` with a `--path-rename`.
  The copy here was never deleted, so `LIB-0001` existed in two repos at once.
- **`adr/noisypigeon.com/` is a foreign domain.** LIB-0001 invariant 5 says each
  spoke owns its own decisions, and `NPC-0000` is the ADR that defined the
  `noisypigeon.com` repo. It was only here because PD-0157 had hoisted everything
  into one place before that invariant existed.

And the prefix itself is wrong for what this repo is becoming. `PD-` was chosen when
this repo was `pigeon.dev` the templates host. DEV-0162 reduces it to `pigeon.dev`
the site — content and nothing else. `DEV-` names the repo rather than the era.

## Decision

### 1. Flatten `adr/pigeon.dev/` to `adr/`, and re-prefix `PD-` → `DEV-`

All 117 records move to `adr/DEV-NNNN-<slug>.md`, by `git mv`, so `--follow` history
survives — the guardrail PD-0157 and PD-0160 both used.

**Numbers are unchanged**, `0031` through `0161`. PD-0160's "never renumbered" rule
holds in full, including the three duplicate numbers (`0136`, `0138`, `0156`) it
declined to deduplicate. Only the prefix and the directory change.

**H1s move with the filenames**, as PD-0160 established: `# DEV-0157: …` in
`DEV-0157-….md`.

### 2. Rewrite the `PD-` citations; leave bare `ADR-NNNN` alone

All 231 `PD-` occurrences in this repo become `DEV-` — citations, the bare prefix
token, the `PD-NNNN` placeholder in prose, the `PD-[0-9]{4}` regexes in verification
text, and the 33 relative sibling link targets. The 133 in `pigeon-lib` and the three in
`noisypigeon` and `noisypigeon.com` are rewritten in their own PRs.

Those 133 include 20 inside five published module changelog entries, which needs
justifying rather than assuming: NPC-0000's precedent is that published changelog
copy is not retrofitted to a later layout. It does not bite here, because those
versions have **no corresponding GitHub Release in `pigeon-lib`** — the historical
Releases live in `noisypigeon` under the old tag names — so there is nothing to
diverge from, and the site's release posts are generated from these files, so
rewriting keeps them consistent rather than splitting them.

The 1,127 bare `ADR-NNNN` citations are **not** touched, and that asymmetry is the
point. PD-0160 grandfathered them on volume: rewriting would churn ~45 published
module and theme changelog entries and ~40 comments in another repo's `.hcl`/`.tf`.
`PD-` has none of that weight — 217 of its occurrences are inside `adr/` itself, and
it was one day old. Rewriting the cheap spelling and grandfathering the expensive one
leaves **two** live spellings for this corpus instead of three, which is the most a
reader should have to carry.

### 3. `adr/pigeon-lib/` is deleted; `adr/noisypigeon.com/` moves to its repo

The `pigeon-lib` copy is simply stale — the real one is in that repo, with history.

`NPC-0000` moves to `noisypigeon.com/docs/adr/`, added there first so the record is
never absent from both repos at once. **Its git history does not travel.** For a
single file, PD-0157's `filter-repo` plus `merge --allow-unrelated-histories` recipe
for a non-empty destination is disproportionate; the history stays reachable here.
That is a deliberate departure from all four prior splits, which preserved history,
and it is recorded rather than glossed. The file itself is byte-identical: it cites
this corpus as bare `ADR-NNNN`, the grandfathered spelling, so §2 had nothing to
rewrite in it.

### 4. On crossing PD-0160's boundary

PD-0160 §1 wrote, of this corpus: "`PD-NNNN` is permanent, these records are never
renumbered, and nothing here retro-prefixes `adr/noisypigeon.com/` or obliges a third
domain." This ADR crosses the first clause and honours the second — nothing is
renumbered — so the reasoning has to be explicit.

The licence is PD-0160's own. It crossed NPC-0000's identically-worded boundary on
the argument that "an ADR filed in `adr/noisypigeon.com/` is a decision about the
blog repo and its tree of decisions … it cannot settle what another repo calls its
own decision log", and that it was "the `pigeon.dev` domain making the call for its
own tree, which is the only tree it governs." That is exactly this ADR's position,
one domain later. A rule that a domain may always rename itself cannot also promise
that it never will; PD-0160 wanted both and could only have the first.

What is worth admitting is the cost of exercising it twice in two days. A reader who
meets `ADR-0154`, `PD-0154` and `DEV-0154` has three spellings to reconcile for one
record, and only the oldest is still written anywhere. §2 caps that at two going
forward, and this ADR is the place that says so.

**This ADR carries no permanence claim forward.** PD-0160's did, and it was wrong to
— not because the intent was wrong but because the claim is not one a single ADR can
make about a tree that later ADRs also govern. What replaces it is weaker and
truthful: renaming a corpus is cheap in filenames and expensive in citations, so the
bar is whether the citation churn is worth it, and §2 is the arithmetic for deciding.

## Consequences

- **Three spellings now exist for one corpus, two of them live.** `ADR-NNNN` in older
  prose and published changelogs, `DEV-NNNN` going forward, and `PD-NNNN` nowhere at
  all — it survives only in git history and in merged PR bodies, which is the one
  place the churn is unrecoverable.
- **`git log --follow` is the only way back past two renames.** A record's history now
  crosses `docs/adr/NNNN-…` → `adr/infrastructure/NNNN-…` → `adr/pigeon.dev/PD-NNNN-…`
  → `adr/DEV-NNNN-…`. Plain `git log <path>` shows one rename; `--follow` shows all.
- **`adr/` is flat and single-domain, which it has never been.** The `adr/<domain>/`
  shape PD-0157 introduced for forward-compatibility is gone from this repo, having
  served its purpose: it let two sibling domains exist long enough to be given their
  own repos.
- **`adr-new.sh` is wrong for the third time.** It hardcodes `ADR_DIR_REL="adr/infrastructure"`,
  which PD-0160 broke, and now the prefix and the nesting are both wrong too. It lives
  in `noisypigeon/noisypigeon` and remains hand-written work (`noisypigeon#293`).
- **One file lost its history on moving.** `NPC-0000` in `noisypigeon.com` begins at
  one commit. Recoverable only by reading this repo.

## Out of scope

- **Renumbering anything,** or deduplicating `0136`/`0138`/`0156`. Permanent boundary,
  inherited from PD-0157 and PD-0160 and genuinely untouched here.
- **Rewriting bare `ADR-NNNN`** — in `adr/`, in published module and theme changelog
  entries, or in `noisypigeon`'s `.hcl`/`.tf`. Permanent boundary, for the volume
  reason PD-0160 gave and this ADR re-tests rather than assumes.
- **Dispersing the `DEV-` corpus out of this repo.** It is already in the repo whose
  decisions it records, which is what LIB-0001 invariant 5 asks for.
- **Preserving `NPC-0000`'s history into `noisypigeon.com`.** Permanent boundary for
  that one file, per §3.
- **Teaching `adr-new.sh` any of this.** Genuinely deferred; folded into the existing
  `noisypigeon#293`.

## Verification

1. `ls adr | wc -l` is 118 — the 117 renamed records plus this one — and
   `ls adr | grep -cv '^DEV-[0-9]\{4\}-'` is 0, so no subdirectory and no stray name
   survives.
2. Every H1 agrees with its filename: for each `adr/DEV-NNNN-*.md`, line 1 matches
   `^# DEV-NNNN: `, and `grep -rn '^# PD-' adr/` is empty.
3. `git log --follow adr/DEV-0031-out-of-scope-issue-tracking.md` shows real pre-move
   history across all three prior locations, not a single rename.
4. No dangling link: `grep -rnoE '\]\(PD-' adr/` is empty, and every
   `](DEV-NNNN-<slug>.md)` target resolves to a file that exists.
5. `grep -r 'PD-' ` over the whole repo returns nothing, and the same holds in
   `pigeon-lib`, `noisypigeon` and `noisypigeon.com` once their PRs land.
6. **The grandfathering is not collateral damage**: bare `ADR-NNNN` in `adr/` counts
   **1,115**, and every unit of the change from 1,129 is accounted for rather than
   assumed — less the 2 inside the stale `adr/pigeon-lib/LIB-0001` copy §3 deletes,
   less the 13 inside `NPC-0000` as it moves to its own repo, plus the 1 this ADR
   cites itself. Checked per-file as well as in aggregate, since an aggregate alone
   would hide an offsetting error in either direction.
7. `NPC-0000` exists in `noisypigeon.com/docs/adr/` and is byte-identical to the copy
   deleted here.
