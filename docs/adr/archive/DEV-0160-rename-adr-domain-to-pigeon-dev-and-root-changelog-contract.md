# DEV-0160: rename the ADR domain to `adr/pigeon.dev/` with `DEV-` IDs, and make the root changelog a contract

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-13.
- **Status**: Accepted.

## Context

NPC-0000 was the first exercise of the sibling-domain pattern ADR-0157 left
headroom for. It opened `adr/noisypigeon.com/` with `NPC-`-prefixed IDs and
settled how a second domain identifies itself. What it could not do, from inside
its own tree, is make the *first* domain look like a domain.

### 1. `adr/infrastructure/` is not a topic, and its filenames say nothing

ADR-0157 chose the `infrastructure/` segment to leave room for a sibling
"without a second move", and it worked — but the name was picked before per-repo
domains existed, and NPC-0000 then established that a domain is named after a
*repo*. `adr/` now has two children named on different axes:

```
adr/infrastructure/0157-hoist-adrs-to-pigeon-dev.md   <- a topic, bare number
adr/noisypigeon.com/NPC-0000-bootstrap-…-repo.md      <- a repo, prefixed
```

Neither half of that asymmetry is harmless. `infrastructure/` reads as one topic
among several possible topics, when the directory is in fact the decision log
for `noisypigeon/noisypigeon` and this repo — and every ADR filed into it from
here on is a `pigeon.dev` decision, since that is the repo it now lives in.
NPC-0000's own `## Out of scope` already predicted the gap it was leaving:
ADR-0157 "only establishes that `adr/<domain>/` has room for it."

Meanwhile the filenames carry no domain marker at all. A loose
`0157-hoist-adrs-to-pigeon-dev.md` is identifiable only by the directory above
it, which is exactly the property NPC-0000 refused for its own records when it
reasoned that "`NPC-0000` and `ADR-0160` can never be confused". That argument
does not stop at one domain's edge.

### 2. Six spellings of one author, and no rule

The 116 records carry six distinct `- **Author**:` values:

| count | value |
| --- | --- |
| 57 | `Willow Finch ([@noisypigeon](…)).` |
| 44 | `Willow Graysen ([@noisypigeon](…)).` |
| 10 | `Willow Graysen` — no handle, no period |
| 4 | `Willow Finch/Graysen ([@noisypigeon](…)).` |
| 2 | `Willow Graysen.` — no handle |

The split is chronological: every record dated `2026-09-22`–`2026-10-02` says
`Willow Finch`, and the name changed on `2026-10-03`. Three things then went
wrong. `0108` is dated `2026-10-03` but kept the old name. Twelve records in the
new era dropped the handle, the trailing period, or both. And the four most
recent — `0156-simplify-claude-md`, `0157`, `0159`, `NPC-0000` — hedge with
`Willow Finch/Graysen`, a hyphenate that resolves nothing for a reader and
exists only because no ADR ever said which name to use. Nothing in the repo
does.

### 3. The root `CHANGELOG.md` promises something nothing delivers

Its own first line of prose claims "One line per PR across this whole repo",
and the file has **zero entries** after 15 merged PRs. Only
`template-release.yml` writes to it, and only for a PR that touches a releasable
unit's `.tf` files or the theme's `templates/`/`static/`/`theme.toml`. So a PR
touching `pigeon.dev/src/**`, `adr/**`, `.github/**`, the root docs,
`.mise.toml`, or a module's `README.md`/`CHANGELOG.md` alone produces no
changelog entry anywhere — including, pointedly, the two PRs that created `adr/`
in the first place. The `release-pr` skill tells an author that such a PR
"doesn't need a label at all — nothing will be tagged or released regardless",
which is true about *releases* and silently also true about the changelog.

### 4. The rollup code is copied three times and two copies are broken

The same awk block appears at `template-release.yml:145-162`, again at `:224-240`,
and a third time at `blog-changelog.yml:118-144`. Only the third has the
`if [ ! -f "$ROOT_CHANGELOG" ]` seed guard NPC-0000 §2 added after finding the
same omission; the two in `template-release.yml` still `grep`/`awk` the path
unconditionally.

More interesting is a defect all three share, which NPC-0000 did not find
because `noisypigeon/noisypigeon.com` opted out of the rollup entirely. The
insert branch anchors on the first `## ` heading:

```awk
/^## / && !inserted { print today; print ""; print entry; print ""; inserted = 1 }
{ print }
END { if (!inserted) { print ""; print today; print ""; print entry } }
```

The root `CHANGELOG.md` contains no `## ` line — its 16 lines are an `# Changelog`
H1 and prose. So `inserted` stays 0, the `END` block fires, and the first-ever
entry is appended to the **bottom** of the header. Every later date then inserts
above it. The file would have honoured its own "newest first" claim from the
second entry onward and never for the first, permanently. Problem 3 is the only
reason this has not yet fired: nothing has ever written to the file.

One smaller thing, found while reading it: the comment introducing that block
cites `(ADR-0050)`. `0050` is one of the numbers lost in the `pigeon-cli` and
`pigeon-do` splits — it resolves to nothing in any repo.

## Decision

Four changes, one PR in this repo.

### 1. `adr/infrastructure/` → `adr/pigeon.dev/`, with `DEV-`-prefixed filenames

All 116 records move and are renamed `DEV-NNNN-<slug>.md`, via `git mv` so
`--follow` history survives the way ADR-0157 established.

**Numbers do not change.** `0157-hoist-adrs-to-pigeon-dev.md` becomes
`DEV-0157-hoist-adrs-to-pigeon-dev.md` and nothing else about it moves. This
upholds ADR-0157's rule — renumbering "would break several hundred `ADR-NNNN`
citations … for no reader benefit" — and it follows that the three
already-duplicated numbers stay duplicated: `0136`, `0138`, and `0156`, the last
of which no prior ADR has acknowledged even though ADR-0157 cites "ADR-0156"
meaning each of its two files in different sentences. A `DEV-NNNN` is therefore
not quite a unique key, and deduplicating it is still the citation-breaking
change it always was.

**H1s are rewritten; prose citations are not.** All 116 H1s become
`# DEV-NNNN: …`, so a filename and the title inside it agree. The roughly 1,100
in-text `ADR-NNNN` citations stay exactly as written, as do the ~45 inside
published module and theme `CHANGELOG.md` entries and the ~40 in
`noisypigeon/noisypigeon`'s `.hcl`/`.tf` comments. **Bare `ADR-NNNN` and
`DEV-NNNN` are aliases for the same record in this corpus**; new ADRs cite
`DEV-NNNN`. Rewriting the citations instead would mean editing 1,100 lines across
116 files for no reader benefit, and would still leave the two other classes
untouched — moving the alias rather than removing it.

The 32 relative sibling links do get repointed, because those are paths and they
would otherwise dangle. Seven of them sit in `- **Status**:` lines and carry the
supersession graph. Only the target changes:

```markdown
- **Status**: Accepted; superseded in part by
  [ADR-0157](DEV-0157-hoist-adrs-to-pigeon-dev.md).
```

**On NPC-0000's boundary.** That ADR's `## Out of scope` calls prefixing another
ADR domain a permanent boundary, and this ADR crosses it, so the reasoning
matters. An ADR filed in `adr/noisypigeon.com/` is a decision about the blog
repo and its tree of decisions; it can bind what `NPC-` means and what the blog
does, and it cannot settle what another repo calls its own decision log. Read
narrowly — as a statement that *the blog's* precedent does not oblige anyone to
retrofit `adr/infrastructure/` — NPC-0000 is correct and remains so. This ADR is
the `pigeon.dev` domain making the call for its own tree, which is the only tree
it governs.

That cuts both ways, so **this ADR carries the same boundary forward for
`adr/pigeon.dev/`**: `DEV-NNNN` is permanent, these records are never renumbered,
and nothing here retro-prefixes `adr/noisypigeon.com/` or obliges a third
domain. No `- **Status**:` line on NPC-0000 or DEV-0157 is edited — neither
decision is superseded; one is being read at its own scope, and the other's
`infrastructure/` choice did its job by making a sibling possible at all.

### 2. One author name, and a rule that says which

Every record dated **on or after 2026-10-03** gets exactly:

```markdown
- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
```

61 records are in that range; 17 actually change, the rest already matching.
`0108` is the only change of *name* rather than of formatting — it was filed in
the new era under the old name. The 56 records dated `2026-10-02` or earlier keep
`Willow Finch` untouched: they are correct as filed, and rewriting them would be
a different and worse kind of edit than fixing a line that was wrong the day it
was written.

`Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).` is the form
**going forward**, recorded in `CLAUDE.md` so there is somewhere to look. The
`Finch/Graysen` hyphenate is retired.

This rule is corpus-wide, which is why it also edits `NPC-0000` — the one file
this PR touches outside `adr/pigeon.dev/`. Unlike a prefix or a path, an author
line is not a domain's decision to make differently; it is a fact about a person,
and the hyphenate is equally unhelpful in both directories.

Only the bullet's value changes. `DEV-0134`, `DEV-0135` and both `DEV-0136`s keep
their unbolded, reverse-ordered `- Status:`/`- Date:`/`- Author:` keys — see
`## Out of scope`.

### 3. The root changelog contract, stated and then honoured

> Every merged PR produces **exactly one** line in the root `CHANGELOG.md`,
> under a `## YYYY-MM-DD` section, newest first. A PR that changes a
> **releasable unit** additionally produces its full PR body in that unit's own
> `CHANGELOG.md`, under `## [X.Y.Z] - YYYY-MM-DD`. The releasable units are
> `templates/terraform/<provider>/<module>/` and `templates/zola-site/`, and
> nothing else in this repo is versioned.

This ratifies what the two tracks already do — the per-unit entry and the root
rollup are both pre-existing behaviour, and the per-unit files are untouched,
including the five header lines that `head -n 5`/`tail -n +6` makes structurally
load-bearing. What changes is that the root half now applies to every PR instead
of only to releases, and that it works on an empty file.

- **`.github/scripts/root-changelog.sh`** is the one implementation. It takes
  `--tag`/`--title`/`--number`/`--url`, carries the seed guard, and anchors
  insertion on a sentinel line — `<!-- entries below; newest first -->` — rather
  than on the first `## `. That is what fixes problem 4: the anchor no longer
  depends on an entry already existing, and it does not care how long the prose
  header is. If the sentinel is missing the script fails loudly rather than
  guessing. An optional `--date` lets a caller reuse a `$TODAY` it already
  computed, so a release's unit entry and rollup line cannot straddle midnight.

  It is not shared with `blog-changelog.yml`. That workflow is reusable and runs
  against a *caller's* checkout, which cannot see this repo's scripts; its inline
  copy stays, and is dormant anyway since `root_changelog_tag` defaults to empty
  and its sole caller passes nothing.

- **`.github/workflows/root-changelog.yml`** is new, triggers on every merged PR
  to `main` with **no `paths:` filter**, and joins the existing `main-writer`
  concurrency group. It stands down when `template-release.yml` owns the entry,
  re-testing that workflow's two detection predicates verbatim so that no PR can
  get two lines. Otherwise it derives one tag by first match in a fixed
  precedence — `pigeon.dev/` → `pigeon.dev`, `templates/` → `templates`, `adr/`
  → `adr`, `.github/` → `ci`, else `repo` — because one line per PR means one
  tag per PR even for a PR spanning several areas.

- **`CHANGELOG.md`**'s header now states the contract and the whole tag
  vocabulary. It previously documented only `- [<provider>/<module>] …` while
  `template-release.yml` has always also emitted `- [zola-site] …`. It gains the
  sentinel, and its stale `docs/adr/0154-…` link into the monorepo is repointed
  at `adr/pigeon.dev/DEV-0154-…`.

- **`template-release.yml`**'s two inline rollup blocks are replaced by calls to
  the script — which is where they pick up the seed guard they were missing —
  and the dangling `(ADR-0050)` citation becomes `(DEV-0160)`. Two dead
  assignments in the same step, `PROVIDER` and `MODULE`, are removed; nothing has
  read them since before the hoist, and `actionlint` flags both.

### 4. Repoint the docs, and name the author rule in one of them

`README.md` and `CLAUDE.md` still assert that this repo's ADRs live in
`noisypigeon/noisypigeon` under `docs/adr/`, falsified by ADR-0157 and tracked as
`noisypigeon/noisypigeon#294`. Both are corrected here rather than deferred
again — this PR is renaming the directory they would be wrong about, and leaving
them wrong through the rename is how the next reader learns to distrust them.
`CLAUDE.md` additionally carries what a hand-filed ADR needs, since `adr-new.sh`
cannot do it: the path, the max+1-within-the-directory rule, the duplicate-number
warning, the section list, the citation alias, and the author string. `README.md`
stays short and human-facing. This closes `#294`.

`.claude/skills/release-pr/SKILL.md` gets two corrections: it still says the
deploy dispatch lands in `noisypigeon/noisypigeon` (ADR-0156 moved it here), and
its note that an unlabelled PR produces nothing now says that such a PR still
produces a root changelog line.

## Consequences

- **`adr-new.sh` breaks outright on merge, from a repo this PR cannot touch.** It
  hardcodes `ADR_DIR_REL="adr/infrastructure"` and reads max+1 from
  `origin/HEAD:adr/infrastructure`. The moment this merges, that path does not
  exist and the script fails rather than merely producing the wrong thing — a
  harder failure than the one NPC-0000 recorded, where it could not create `NPC-`
  files but still worked for its own domain. It lives in
  `noisypigeon/noisypigeon`, so the fix is a second PR there with nothing
  enforcing the ordering, and until it lands **every** new ADR in either domain is
  hand-written and hand-numbered. Given `0136`, `0138` and `0156`, that risk is
  not hypothetical.
- **A filename and the prose inside it now disagree on purpose.**
  `DEV-0157-….md`, titled `# DEV-0157:`, contains sentences citing `ADR-0154`. Two
  spellings for one corpus, indefinitely, and a reader who meets `DEV-` first has
  to learn that the bare form means the same thing. `CLAUDE.md` says so; there is
  still no index to say it.
- **NPC-0000 reads as contradicted, with no forward pointer.** Its "permanent
  boundary" bullet still says `adr/infrastructure/` keeps bare `ADR-NNNN`
  forever, and by deliberate choice no `Status` line was edited. Only this file
  records the scope reading that reconciles them, so anyone arriving at NPC-0000
  first sees a boundary and no sign it was ever revisited — the same
  no-index problem that ADR already named about `NPC-` itself.
- **ADR-0157's verification step was already false and stays false.** It asserts
  `ls adr/infrastructure | wc -l` is 112; the real count was 116 before this ADR.
  Fixing it is not attempted — it describes a check performed at the time, not a
  current-state claim.
- **Three workflows now push to `main`.** All share the `main-writer` concurrency
  group, so they serialize, but `root-changelog.yml`'s stand-down test is a
  *duplicate* of `template-release.yml`'s detection logic rather than a shared
  one. If either drifts, a releasing PR gets two root lines or none. They cannot
  be shared cheaply: one runs before the release decision and the other derives
  it, and this is the honest cost of covering every PR.
- **The first entry lands correctly only because of the sentinel.** Reflowing the
  root header is now a change with a failure mode. Deleting the marker makes the
  script exit non-zero, which is the intended loud version; preserving it while
  moving it somewhere misleading is the quiet one.
- **Every merged PR now writes to `main`.** An `adr/`-only or docs-only PR used to
  merge and stop. It now triggers a commit-and-push, so a trivially small PR
  costs a workflow run and a commit on `main` that nothing else needed.

## Out of scope

- **Renumbering, or deduplicating `0136`/`0138`/`0156`.** Permanent boundary, for
  the reason ADR-0157 gave and this ADR adopts: all three are pre-existing, and
  all three fixes break citations.
- **Normalizing the four unbolded, reverse-ordered header bullets** (`DEV-0134`,
  `DEV-0135`, both `DEV-0136`s). Permanent boundary, per ADR-0157, which named them
  and declined for the same reason. This ADR edits the *value* of their `Author`
  line and deliberately not its key or position.
- **Rewriting bare `ADR-NNNN` citations** — the ~1,100 in `adr/`, the ~45 in
  published module and theme `CHANGELOG.md` entries, or the ~40 in
  `noisypigeon/noisypigeon`'s `.hcl`/`.tf`. Permanent boundary, and for the
  changelog entries specifically it extends NPC-0000's call that published
  changelog copy is not retrofitted to a later layout: those entries also still
  link to `docs/adr/` paths that no longer exist, and rewriting shipped release
  notes to match a directory rename would be a worse lie than a stale path.
- **Retro-prefixing `adr/noisypigeon.com/`, or obliging a third domain.**
  Permanent boundary — the symmetric half of the jurisdiction argument in
  `## Decision` §1. A future domain picks its own prefix and its own sequence.
- **Teaching `adr-new.sh` the new path.** Genuinely deferred, and the one item
  here that is a live breakage rather than a nicety — see `## Consequences`.
  Extends the existing `--domain`/`--prefix` work already tracked at
  `noisypigeon/noisypigeon#293`; the script is in a third repo, so it is not in
  this PR. Needs an issue.
- **Relocating `blog-changelog.yml` to `noisypigeon/noisypigeon.com`.** Genuinely
  deferred. It is reusable, this repo has no caller for it, and its only consumer
  is that repo; its inline rollup copy is the fourth of the four this ADR
  otherwise consolidated to one. Needs an issue.
- **`pigeon-dev-pages.yml` deploying twice per module release.** Genuinely
  deferred. `template-release.yml`'s changelog commit touches `templates/**`,
  which matches that workflow's `push` path filter, and it is then dispatched
  explicitly as well — so the site builds twice, harmlessly but visibly. Needs an
  issue.
- **No release post for `templates/zola-site` versions.**  Genuinely deferred.
  `generate-module-redirects.sh` globs `templates/terraform` at exactly three
  levels deep, so the theme gets a `content/theme-versions/` redirect page from
  its tags but never a release post, even though its `CHANGELOG.md` is in the
  identical parseable format. Needs an issue.
- **Branch protection, or enforcing the cross-repo merge order.** Permanent
  boundary for now, and raised for the third time: ADR-0157, ADR-0159 and
  NPC-0000 each noted that neither repo has rulesets, and this ADR adds another
  ordering constraint that nothing enforces.

## Verification

1. `ls adr/pigeon.dev | wc -l` is 117 — the 116 renamed records plus this one —
   and `ls adr/pigeon.dev | grep -cv '^DEV-[0-9]\{4\}-'` is 0.
2. `git log --follow adr/pigeon.dev/DEV-0031-out-of-scope-issue-tracking.md` shows
   real pre-move history, the same guardrail ADR-0157 used for the same reason.
3. Every H1 agrees with its filename: 117 files match `^# DEV-[0-9]\{4\}: ` on line
   1, and `grep -rn '^# ADR-' adr/` is empty.
4. No dangling relative link: `grep -rnoE '\]\([0-9]{4}-[a-z0-9-]+\.md\)' adr/` is
   empty, and every `](DEV-NNNN-<slug>.md)` target resolves to a file that exists.
5. The author rule holds in both directions — every record in `adr/**` dated
   `>= 2026-10-03` has exactly the canonical string (61 of them), and every record
   dated `<= 2026-10-02` still says `Willow Finch (…)` (56).
6. `actionlint .github/workflows/root-changelog.yml .github/workflows/template-release.yml`
   and `shellcheck .github/scripts/root-changelog.sh` are clean.
7. The insertion fix is testable before merge, and only on a file with no `## `
   section — which is the state that triggered it. Against a copy of the new
   `CHANGELOG.md`, `root-changelog.sh` must place the first entry **directly below
   the sentinel**, not at the bottom; a second call with the same `--date` must
   add its line above the first, under one heading; a third with a later `--date`
   must open a new section above both. Removing the sentinel must make it exit 1,
   and a missing `--tag` must exit 2.
8. `mise run pigeon-dev-build` still succeeds and `git status --porcelain` is clean
   afterwards — the rename is invisible to the site generator, which never reads
   `adr/`.
9. This PR is the end-to-end test of §3. It touches `adr/**`, `.github/**` and the
   root docs, but no `.tf` and no theme asset, so on merge `template-release.yml`
   must not run at all while `root-changelog.yml` writes exactly one `- [adr] …`
   line into this repo's first-ever `## YYYY-MM-DD` section, positioned directly
   below the sentinel. Per the `release-pr` skill it needs no `release:*` label;
   confirm no tag and no GitHub Release is cut.
