# DEV-0163: hoist `pigeon.dev`'s Terraform into this repo, leaving `state/iam` behind

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted.
- **Amended 2026-10-16**: DEV-0164 moved the state to R2 and retired the Scaleway project, the
  state bucket and `state/iam`'s deploy key. The arrangement below is historical.

## Context

LIB-0001 §7 step 3 gives this repo its own `terraform/`, `root.hcl`,
`terraform/secrets.enc` and `.sops.yaml`. That is the other half of the spoke
role DEV-0162 began: content *and* the infrastructure that serves it. It was
blocked on LIB-0001 §8.

Checked against `noisypigeon/noisypigeon@ff2f4e2`, this domain has five leaves
there, under `pigeon.dev/terraform/`. They split cleanly by which root they use.

- **Four of them** (`fastmail/dns`, `project`, `state/bucket`, `wiki/dns`) include
  `pigeon.dev/root.hcl` through `find_in_parent_folders`. They read
  `pigeon.dev/secrets.enc`, and keep state in this domain's own bucket
  (ADR-0130, ADR-0137) under the key
  `${path_relative_to_include()}/terraform.tfstate`.
- **`state/iam`** includes `${get_repo_root()}/root.hcl`, the monorepo's shared
  root. It authenticates with the shared deployer credentials in that repo's
  `.env.enc` and keeps state in the old shared bucket under
  `workloads/pigeon.dev/terraform/state/iam/terraform.tfstate`. It mints the
  `pigeon-dev-terraform-deploy` API key that the other four authenticate with.
  DEV-0130 and DEV-0133 made that separation permanent: an IAM-rotation leaf must
  not depend on the credential it manages.

`${get_repo_root()}` cannot cross a repository boundary. That is §8's whole
problem, and LIB-0001 left the choice to the spoke.

## Decision

### 1. `state/iam` stays in `noisypigeon` (LIB-0001 §8, option 1)

The other two options both cost more than they buy.

- **A second, bootstrap root in this repo** would copy the organisation-level
  shared deployer credentials and the shared bucket's name into this repo's sops
  file. One leaf would get a second blast radius.
- **Accepting the self-reference** would reverse DEV-0130/0133's rule. It would
  also move state between buckets, from the shared bucket into this domain's own.

Leaving the leaf where it is moves no credential and no state. The cost falls on
LIB-0001 step 6: `noisypigeon` cannot become content-only while it still runs
this leaf.

Rotating the deploy key stays a two-repo operation. It is a PR in `noisypigeon`
that applies `pigeon.dev/terraform/state/iam`, then a `mise run secrets-edit`
here to paste the new key into `terraform/secrets.enc`.

### 2. The other four move with their history, and their state does not move

The leaves were imported with one `git filter-repo` pass over a throwaway clone
of `noisypigeon`.

- **Kept:** this domain's own paths, `pigeon.dev/` and `workloads/pigeon.dev/`.
- **Renamed:** `…/terraform/` → `terraform/` and `…/secrets.enc` →
  `terraform/secrets.enc`.
- **Dropped:** `terraform/state/iam/`. Tags were dropped before filtering, so
  none leaked in.

The result was 15 files and 12 commits. It was merged with
`--allow-unrelated-histories`, the recipe ADR-0154 and ADR-0156 used. History
from before `workloads/pigeon.dev/` existed lived under paths shared with other
domains, and stays in `noisypigeon`. The imported tree is byte-identical to the
source, and `secrets.enc` is unchanged byte-for-byte; sops metadata does not
encode the file's path.

**State does not move.** `root.hcl` sits at this repo's root and the leaves sit
under `terraform/`, so `path_relative_to_include()` and every key are unchanged.
This is LIB-0001 invariant 4's arithmetic, written out rather than asserted:

| Leaf | Key in `noisypigeon` (under `pigeon.dev/root.hcl`) | Key here (under `/root.hcl`) |
| --- | --- | --- |
| `fastmail/dns` | `terraform/fastmail/dns/terraform.tfstate` | `terraform/fastmail/dns/terraform.tfstate` |
| `project` | `terraform/project/terraform.tfstate` | `terraform/project/terraform.tfstate` |
| `state/bucket` | `terraform/state/bucket/terraform.tfstate` | `terraform/state/bucket/terraform.tfstate` |
| `wiki/dns` | `terraform/wiki/dns/terraform.tfstate` | `terraform/wiki/dns/terraform.tfstate` |

The bucket is the same too: `PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME`, read
from the same encrypted file.

### 3. `root.hcl` comes from pigeon-lib's template, committed

`root.hcl` is pigeon-lib's `terragrunt/root-hcl` template (LIB-0003) at the
version `spoke.hcl` pins, currently `1.0.1`. `resolve-root-hcl.sh` copies it,
and this repo commits the copy. `spoke.hcl` also names
`state_bucket_secret`, which is the one value this spoke varies.

It is committed rather than ignored because Terragrunt's `[main...HEAD]` filter
plans inside git worktrees, which hold only tracked files. A dry run of this
very hoist with the copy ignored failed on all four leaves, and LIB-0003's
amendment records it. CI runs the resolver with `--check`, so drift fails the plan.

The template's renders for these four leaves matched the old
`pigeon.dev/root.hcl` with zero differing keys (LIB-0003 Verification 2).

### 4. CI and the merge gate come with it

- **`terragrunt-plan.yml` and `terragrunt-apply.yml`** are thin callers of
  pigeon-lib's `terragrunt-detect.yml` and `terragrunt-run.yml` at
  `workflows/v1.3.1`. They are `noisypigeon`'s callers plus three inputs:
  - `leaf_pattern`: `^terraform/`, `root.hcl`, `spoke.hcl` and `.sops.yaml`;
  - `secrets_files: terraform/secrets.enc`;
  - `prepare_cmd`: the fetch, then `resolve-root-hcl.sh --check`.
- **`SOPS_AGE_KEY`** is a repo secret here, holding the same age key as
  `noisypigeon`'s. `.sops.yaml` carries the same recipient, with one rule:
  `^terraform/secrets\.enc$`.
- **`main` gets `noisypigeon`'s ruleset (ADR-0129):** no force-push, and a
  required `terragrunt/apply` status, with the owner and the bot as bypass
  actors. It is created after this record's PR merges, so the import itself is
  not gated. This partly resolves
  [noisypigeon/noisypigeon#295](https://github.com/noisypigeon/noisypigeon/issues/295).
- **`root-changelog.yml`** tags `terraform/`, `root.hcl`, `spoke.hcl` and
  `.sops.yaml` changes as `terraform`.

### 5. Removing the leaves from `noisypigeon` is never applied

This is the hazard that matters. The `noisypigeon` PR that deletes the four
leaves (plus `pigeon.dev/root.hcl`, `pigeon.dev/secrets.enc` and the stale
generator copy) **will plan four destroys**. Its CI plans removed units from a
worktree of `main`, with `--filter-allow-destroy`, against the same bucket and
the same keys this repo now owns.

- **Applying it would destroy live infrastructure.** That PR is merged through
  the ruleset's owner bypass, and `terragrunt apply` is never commented on it.
- **DEV-0130's rule must not be followed here, and the reason is exact.** The
  rule says "migrating state … is not complete until the old location's state is
  also emptied". It assumes the old and new locations differ. Here they are the
  same object, so a `state rm` against the "old" location would orphan live
  resources from their only owner.

### 6. The import merges as a merge commit, once

This repo allows only squash merges, which would have flattened the imported
history into one commit, and `terragrunt-run.yml`'s auto-merge squashes. So for
this PR alone:

1. Merge commits were enabled.
2. The PR was merged with `--merge` after its CI plan showed `No changes.` on all
   four leaves.
3. Merge commits were disabled again.

The apply was skipped because it would have been a no-op whose only effect was
the squash. The next Terraform PR here exercises the full apply and auto-merge
path.

## Consequences

- **This repo now runs real infrastructure, so a bad merge here can break DNS.**
  The ruleset and the apply gate are the controls.
- **Two repos can plan the same state during the cutover.** Between this PR
  merging and `noisypigeon`'s deletion merging, both see the four leaves. The
  S3 backend's lock protects a concurrent apply, but not ownership confusion, so
  the deletion follows immediately.
- **`noisypigeon` keeps `pigeon.dev/terraform/state/iam/` indefinitely,** and
  with it the shared root, the shared bucket and its `.env.enc`. LIB-0001
  step 6 inherits that.
- **A template bump is a three-file diff:** `spoke.hcl`, `root.hcl` and the plan
  that results. Every leaf replans when `root.hcl` changes, which is the point.
- **The leaves' history starts at noisypigeon#195.** Older history is under
  shared paths in `noisypigeon`.
- **The imported commits cite `noisypigeon` PR numbers.** GitHub autolinks
  `#NNN` against this repo, so those links point at the wrong PRs. ADR-0154's
  import had the same cost.

## Out of scope

- **Hoisting `state/iam`.** A permanent boundary for this spoke, per §1, until
  something changes DEV-0130/0133's reasoning.
- **`noisypigeon.com`'s and `willowgraysen.com`'s Terraform hoists.** Their own
  steps. Template `v1.0.1` serves `noisypigeon.com` unchanged.
- **Rewriting the output descriptions that say "pigeon.dev/secrets.enc".** Left
  as imported, to keep the hoist a pure move. Updating them is a separate,
  reviewable Terraform PR.
- **Branch protection on `pigeon-lib` and `noisypigeon.com`.** Still #295.

## Verification

1. **The import is exact.**
   - `diff -rq` of the filtered tree against `noisypigeon@ff2f4e2:pigeon.dev/terraform/`
     differs only in `secrets.enc`'s new location and the excluded `state/iam/`.
   - `cmp` of the two `secrets.enc` files is silent.
   - `git tag -l` here is still 53.
2. **The plan is a no-op.**
   - Locally, `terragrunt-run.yml`'s exact filter construction against this
     branch planned `No changes.` for all four leaves, with zero errors.
   - This PR's CI plan must show the same.
3. **The keys are unchanged:** the table in §2, with keys taken from both renders.
4. **After `noisypigeon`'s deletion merges:**
   - A plan there touching `pigeon.dev/terraform/state/iam` is clean.
   - A trivial Terraform PR here is planned, applied, gated and auto-merged
     entirely in this repo.
