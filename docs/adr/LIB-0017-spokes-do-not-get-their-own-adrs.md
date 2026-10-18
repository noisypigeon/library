# LIB-0017: Spokes don't get their own ADRs

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-17.
- **Status**: Accepted. Amends LIB-0001 (invariant 5, §2, and its 2026-10-15
  amendment's item 1), and DEV-0031's filing target (§6).

## Context

LIB-0001 invariant 5 said every spoke owns its ADRs, with its own prefix and
sequence. Three spokes followed it:

| Spoke | Domain | Records | What they hold |
|---|---|---|---|
| `noisypigeon/garden` | `DEV-` | 122 | Mostly the family's pre-hub history, plus DEV-0162 to DEV-0165 |
| `noisypigeon/blog` | `COM-` (`NPC-`) | 8 | The blog's bootstrap, content split, hoist, R2 move, Scaleway retirement, redirect and rename |
| `noisypigeon/runway` | `RUN-` | 2 | The bootstrap and the hoist |

Four things show the arrangement doesn't fit what a spoke is.

1. **A spoke's decisions are applications of this repo's standards.** Every
   `COM-` and `RUN-` record, and every `DEV-` record written after this hub
   existed, applies one `LIB-` record to one spoke. The blog's hoist (COM-0003)
   and runway's (RUN-0001) both apply LIB-0003's template by the same recipe
   that garden's (DEV-0163) used first. The blog's R2 move (COM-0004) applies
   LIB-0007. Its Scaleway retirement (COM-0005) applies LIB-0005's providers
   map. All of them except COM-0000, which predates the hub, cite the `LIB-`
   record they apply. Reading a standard therefore meant reading up to three
   other repos to learn how it had actually been applied.
2. **The standards themselves cite out.** Library's `main` held 223 citations
   of 33 distinct `DEV-`/`COM-`/`RUN-`/`NPC-` records, across 32 files. Twenty
   of those files are outside `docs/adr/`. They include
   `.github/scripts/root-changelog.sh`, which implements DEV-0160's contract,
   `generate-module-redirects.sh`, the reusable workflows and the `root.hcl`
   template. The hub's own code was documented in a spoke.
3. **`garden/adr/` was never about garden.** It holds the `DEV-` corpus
   because garden was once `pigeon.dev`, the repo that held the modules, the
   theme and the workflows. Those all moved here (LIB-0002). Their decision
   records stayed behind, under a name that now means a website.
4. **Pointers drift across repos.** garden's `CLAUDE.md` still sent readers to
   `RUN-` records in `noisypigeon/willowgraysen`, one rename out of date
   (LIB-0013). pigeon-cli's `CLAUDE.md` sends readers to garden for the
   family's infrastructure records. Each rename has to be chased through every
   repo that says where decisions live.

## Decision

### 1. garden, blog and runway hold no ADRs

They are spokes and depend on library for their design standards. A decision
about one of them is filed **here**:

- as an **amendment** on the `LIB-` record whose standard it applies, when
  there is one;
- as a **new `LIB-` record**, when no existing record covers it.

A spoke's `CLAUDE.md` says where its decisions live, which is here, and names
the records that are load-bearing for it.

### 2. The existing records move here, and their domains close

- **`DEV-` is archived verbatim** in [`archive/`](archive/README.md): all 122
  files, byte-identical to garden at `13bcee9`, filenames unchanged, so their
  relative links still work.
- **`COM-`, `RUN-` and the post-hub `DEV-` records are folded** as amendments.
  Each amendment's heading carries the record's ID and ends with a permalink to
  the original at its repo's last commit:

  | Record | Folded into |
  |---|---|
  | COM-0000, COM-0002, RUN-0000 | LIB-0001 |
  | COM-0001, DEV-0162 | LIB-0002 |
  | COM-0003, RUN-0001, DEV-0163 | LIB-0003 |
  | COM-0005 | LIB-0005 |
  | COM-0004, DEV-0164 | LIB-0007 |
  | COM-0006 | LIB-0008 |
  | DEV-0165 | LIB-0009 |
  | COM-0007 | LIB-0016 |

  DEV-0162 to DEV-0165 are both archived and folded, so the full text stays
  beside the condensed one.
- **`DEV-`, `COM-`, `RUN-` and `NPC-` are closed.** No new number is issued
  in any of them.
- **The spokes delete their `adr/` directories** once this record merges.

### 3. Citations are never rewritten

This is DEV-0160's rule for `ADR-` and COM-0001's for `NPC-`, applied to four
prefixes at once. Every existing citation stays valid because its ID can still
be found here:

- a `DEV-` ID by its archive filename;
- a `COM-` or `RUN-` ID by its amendment heading;
- an `NPC-` ID as `COM-`.

Only the prose that says *where decisions live* changes, in each repo's
`CLAUDE.md` and `README.md`.

### 4. Archiving is not superseding

A record in the archive keeps the `Status` it was filed with. Where nothing
has superseded it, it is still the decision of record. Moving it here is a
change of address, not a change of standing.

### 5. pigeon-cli is exempt

`pigeon-cli` keeps its own `docs/adr/`.

- Its decisions are about its own code: its CLI, its jobs and its data
  handling. They are not applications of this repo's infrastructure
  standards, and it consumes nothing from the hub.
- Its corpus is the model LIB-0001 itself called "the reference
  implementation".

The rule in §1 is for spokes whose shape this repo defines: content or
infrastructure, plus the Terraform and workflows that serve it.

### 6. Out-of-scope issues are filed in this repo

DEV-0031 files a genuinely-deferred `## Out of scope` item as a GitHub issue,
and every domain filed them against `noisypigeon/noisypigeon`, the old
monorepo. That repo no longer exists in that form. The name now holds a
profile README, created on 2026-10-17 with no issues, so every
`noisypigeon/noisypigeon#NNN` link in the corpus now returns 404.

From this record on, those issues are filed in `noisypigeon/library` with the
`out-of-scope` label, since the decisions they defer now live here. The rest
of DEV-0031 is unchanged: a permanent design boundary gets no issue. The dead
links stay as filed, under §3's rule, and the text around each one still says
what was deferred.

## Consequences

- **A spoke change that needs a decision is a two-repo change.** The library PR
  lands first, and the spoke PR cites it. That is the cost the hub already
  charges for every reusable asset (DEV-0162), now charged for decisions too.
- **One place to read a standard, and how it was applied.** A `LIB-` record and
  its amendments are the whole story for every spoke that applied it.
- **The `LIB-` records that host amendments get longer,** LIB-0003 most of all,
  with three hoists. The amendments are condensed, and the originals stay one
  permalink away.
- **`spoke-root-changelog.yml`'s `^adr/=adr` precedence line is dead** in each
  spoke caller. It is harmless, because it never matches.
- **Out-of-scope issues move to this repo** (§6). The deferrals filed before
  this record cannot be followed by their links any more. Their prose is the
  only record of them.

## Out of scope

- **Rewriting any citation, in any repo.** A permanent boundary, per §3.
- **Moving or re-prefixing pigeon-cli's ADRs.** A permanent boundary, per §5.
- **Dropping the dead `^adr/=adr` precedence lines from the spokes' callers.**
  Genuinely deferred. It is three one-line spoke edits with nothing to gain but
  tidiness, and is best done alongside the next change to those callers.
  ([#75](https://github.com/noisypigeon/library/issues/75))
- **Recovering the old monorepo's issues.** They went with the repo, and
  nothing here depends on them still existing. A permanent boundary.

## Verification

1. **The archive is exact.** 122 files, each with a `git hash-object` equal to
   garden's blob SHA at `13bcee9`. No relative link in them points outside
   their own directory, and none dangles inside it.
2. **Every folded record is findable.** Each of the 14 IDs in §2's table
   appears in an amendment heading in the record it names, with a permalink
   that resolves.
3. **Every citation still resolves.** Every `DEV-`/`COM-`/`RUN-`/`NPC-`/`ADR-` ID
   cited in this repo, in garden, blog and runway, and in pigeon-cli's
   `CLAUDE.md` was collected. Each one matched an archive filename or an
   amendment heading here, with `NPC-` read as `COM-` and a bare `ADR-` read as
   `DEV-`. The check ran before this record merged, and again after the spokes
   deleted their `adr/`.
4. **The spokes have no `adr/`.**
   `gh api repos/noisypigeon/<spoke>/contents/adr` returns 404 for garden, blog
   and runway, and each spoke's `CLAUDE.md` names this record.
