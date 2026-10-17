# LIB-0013: Rename `noisypigeon/willowgraysen` to `noisypigeon/runway`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-17.
- **Status**: Accepted.

## Context

LIB-0001 made `willowgraysen.com` a spoke: the orchestration layer for
`pigeon-cli`, and the largest consumer of this repo's modules. The repo was
created as `noisypigeon/willowgraysen.com`, after the domain it served, and
LIB-0008 Verification 6 renamed it to `noisypigeon/willowgraysen` before its
redirect moved out.

The domain is gone from the repo now. COM-0006 and LIB-0008 moved the
`willowgraysen.com` redirect into noisypigeon.com, where it lives under
`terraform/cloudflare/willowgraysen.com/`. That domain is an alias of the
noisypigeon.com identity, nothing more. What the spoke holds is `pigeon-cli`'s
infrastructure and the data-ops projects: its buckets, its Grafana leaf, its
cluster. So the remaining name describes a person, not the repo.

The ADR domain already made this choice. LIB-0001 Amendment 1 named `RUN-`
"for what the namespace holds … rather than for the domain". The repo name
should follow the same rule.

There is a precedent for the rename mechanics. When the repo dropped `.com`, it
"kept its ID, ruleset and secrets, and no state key changed" (LIB-0008
Verification 6). A leaf's state key is `path_relative_to_include()` against the
spoke's own `root.hcl` (`terragrunt/root-hcl/root.hcl`, LIB-0001 invariant 4).
That is a path inside the checkout, and the repo's name is not part of it.

## Decision

### 1. The spoke is renamed `noisypigeon/runway`

The name says what the repo is: the runway `pigeon-cli` and the data-ops
projects take off from, which is the infrastructure they run on. The rename is
GitHub's own repo rename. The repo keeps its ID, its issues and PRs, its
ruleset, its Actions secrets and variables, and its sops-encrypted
`terraform/secrets/*.enc` (LIB-0012). GitHub redirects the old name, for web
links and for git remotes.

### 2. Nothing keyed on the spoke changes

- **State keys** stay as they are, because they are relative to `root.hcl`
  (§Context). So do the state bucket, the backend and the B2 backup
  (LIB-0007).
- **`spoke.hcl`, the generated `root.hcl` and `secrets-schema.json`** are not
  touched. The pinned `terragrunt/root-hcl` and `workflows` versions stay too.
- **Secret names stay** (LIB-0010). None of them contains the repo name.
- **The `willowgraysen.com` domain** and noisypigeon.com's leaves under
  `cloudflare/willowgraysen.com/` belong to another repo, and the domain is
  still the identity's alias. This record renames a repo, not a domain.

### 3. `RUN-` keeps its prefix and its numbers

`RUN-` already describes the namespace, not the repo, so the rename leaves it
as it is. Every `RUN-NNNN` stays valid. This hub cites the domain as
`RUN-` in `noisypigeon/runway`.

### 4. Live prose is updated, history is not

Where text names the repo as it is today, it now says `noisypigeon/runway`:
this repo's `CLAUDE.md` and `README.md`, and the `release-pr` skill's spoke
list. Records of what happened keep the name the repo had then: ADRs,
`CHANGELOG.md` entries, and citations like `noisypigeon/willowgraysen#16`.
That is the treatment DEV-0160 gave `ADR-` and LIB-0001 gave `NPC-`. GitHub's
redirect keeps those links working.

### 5. The rename is done in the spoke, then recorded here

The owner renames the repo in its GitHub settings and runs
`git remote set-url origin` in each local clone. The spoke's own prose (its
`README.md`, `CLAUDE.md` and badges) is changed in a PR in the spoke. Then
`## Verification` below is filled in.

## Consequences

- **No hub automation changes.** `template-release.yml` dispatches only to
  `noisypigeon/garden` and `noisypigeon/blog`, so `BOT_GITHUB_TOKEN` needs no
  new scope. `.github/scripts/` never names the spoke.
- **Old links and clones keep working, but only through GitHub's redirect.**
  That redirect breaks if a new repo named `noisypigeon/willowgraysen` is ever
  created. The name is therefore retired and must not be reused.
- **The prose splits by tense.** History says `willowgraysen`, the present says
  `runway`. Anyone reading an old ADR needs this record to connect the two,
  just as with the earlier `.com` rename.

## Out of scope

- **Renaming or retiring the `willowgraysen.com` domain**, or noisypigeon.com's
  `cloudflare/willowgraysen.com/` leaves. That is a permanent boundary: the
  domain is the identity's alias, and moving it is noisypigeon.com's call.
- **Rewriting earlier ADRs and changelogs** to the new name. That is a permanent
  boundary too (§4).
- **Moving or splitting the spoke's leaves.** A repo rename leaves the tree as
  it is.

## Verification

To fill in at rollout:

1. `noisypigeon/willowgraysen` renamed to `noisypigeon/runway`, with the same
   repo ID; `gh repo view noisypigeon/willowgraysen` resolves to it.
2. The spoke's CI on `main` plans `No changes.` on every leaf, which confirms
   that no state key moved.
3. The spoke's own prose has been updated (PR in `noisypigeon/runway`).
4. This repo's `CLAUDE.md`, `README.md` and `release-pr` skill name
   `noisypigeon/runway` (the PR that filed this record).
