# LIB-0020: Rename `scaleway/pigeon-cluster` to `scaleway/compute-cluster` and `scaleway/object-bucket` to `scaleway/bucket`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Accepted.

## Context

Two of the Scaleway modules have names that don't follow the rest of the
family:

- **`scaleway/object-bucket`** is the odd one out among the three bucket
  modules. `cloudflare/bucket` and `backblaze/bucket` say `bucket`, and
  `cloudflare/bucket`'s README has to explain the mismatch.
- **`scaleway/pigeon-cluster`** is named for its consumer, not for what it is.
  It's the layer that composes the `compute-instance` family (DEV-0153):
  `compute-instance`, `compute-instance-config`, `block-volume` and the IAM
  modules, once per job.

A module's path is public interface (DEV-0093), and under LIB-0004 §1 it is
also the directory of every leaf that calls it, and so part of that leaf's
state key. A rename reaches four places:

| Where | What the rename touches |
| --- | --- |
| This repo | the module directory, its tag track, prose that names it |
| `template-release.yml` | a directory with no tags is versioned `0.1.0`, whatever the label (the hazard DEV-0110 found) |
| `generate-module-redirects.sh` | overview pages read `README.md` at the module's path, and release posts read `CHANGELOG.md` there, for every module that has tags |
| runway | five `object-bucket` leaves and one `pigeon-cluster` leaf, and their state |

garden and blog call neither module, and no hub module sources either one.

## Decision

### 1. The new names

`scaleway/object-bucket` becomes **`scaleway/bucket`**, matching its siblings
on the other providers. `scaleway/pigeon-cluster` becomes
**`scaleway/compute-cluster`**, matching the `compute-instance` family it
composes.

Only the names change. `compute-cluster` is still a cluster of pigeon-cli
jobs, and both modules keep every input, output and resource address.

### 2. Old tags and short URLs stay forever

Tags are never moved or deleted. Every
`noisypigeon.garden/terraform/scaleway/pigeon-cluster/vX.Y.Z` and
`…/object-bucket/vX.Y.Z` URL keeps resolving, because the redirect pages are
generated from tags (LIB-0009). A leaf that hasn't moved yet keeps working.

The old names are retired, as `pigeon-lib` was (LIB-0015 §5). Neither is
reused for another module.

### 3. The old directories become tombstones

Each old directory keeps two files:

- **`README.md`**: one line saying it was renamed to `scaleway/<new>` by
  LIB-0020, with a link. The garden's overview page for the old name takes its
  description from it.
- **`CHANGELOG.md`**: frozen at its last release. The old versions' history
  stays here, and so do the garden's release posts for them.

With no `.tf` and no `versions.tf`, neither is a module directory, so
`template-release.yml` never releases from it.

The new directory gets a fresh `CHANGELOG.md` whose only content below the
standard header is a pointer back to the old one (§4). History isn't copied:
the generator publishes one post per `## [X.Y.Z]` heading per module, so a
copy would publish every old version a second time under the new name, with
links to short URLs that don't exist.

### 4. Version numbers continue

The first release of each new track is a major bump on the old track's last
version:

| Old | Last tag | New | First tag |
| --- | --- | --- | --- |
| `scaleway/pigeon-cluster` | `v4.0.0` | `scaleway/compute-cluster` | `v5.0.0` |
| `scaleway/object-bucket` | `v4.2.0` | `scaleway/bucket` | `v5.0.0` |

Major, because a changed source path is breaking for every consumer (DEV-0093).
Continued rather than reset, because it's the same code with the same history.

DEV-0093 and DEV-0110 did this by hand, with seed tags cut outside the
pipeline. Here the pipeline does it. The new `CHANGELOG.md` names the old
track's last tag in one machine-read line, under a prose pointer:

```markdown
This module continues [`scaleway/object-bucket`](../object-bucket/CHANGELOG.md)
from v4.2.0, under its new name (LIB-0020).

<!-- continues-from: terraform/scaleway/object-bucket/v4.2.0 -->
```

When a changed module has no tags yet, `template-release.yml` takes its
latest version from that line, and only without one starts at `0.1.0`. The
named tag must exist, or the release fails rather than cut a wrong version.
`release:major` then cuts `v5.0.0`. New entries go in above the pointer, so it
stays at the bottom, where the lineage starts. Any later rename works the
same way.

The garden's generator needs no change. It reads only `## [X.Y.Z]` headings,
and the pointer has none.

### 5. The cutover is ordered so nothing is ever unresolvable

1. **Pipeline (library).** This record and §4's `template-release.yml` change.
   A `workflows` minor release. It has to merge first: the rename's own merge
   is versioned by the workflow already on `main`.
2. **The rename (library).** `git mv` both directories' `.tf` files and
   README to the new paths, leave the tombstones (§3), give each new
   directory its pointer `CHANGELOG.md` (§4), and update live prose.
   `release:major` cuts both `v5.0.0` tags and dispatches garden.
3. **Rewire (runway).** Every leaf's `source =` moves to the new module at
   `v5.0.0`, in place. Each must plan no resource add, change or destroy.
4. **Rename (runway).** The leaves `git mv` to `terraform/scaleway/bucket/<instance>`
   and `terraform/scaleway/compute-cluster/pigeon-cli`, and each one's state
   moves to its new key by LIB-0004 §3's runbook: pull in a worktree of `main`,
   confirm the new key is empty, push, plan, then `state rm` the old key.
5. **pigeon-cli's `CLAUDE.md`** names the new leaf paths.

Steps 3 and 4 are LIB-0004 §5's "rewire, then rename", for the same reason: one
failure mode per PR.

### 6. Live prose is updated, history is not

As in LIB-0015 §4: text describing the modules as they are today uses the new
names. ADRs, `CHANGELOG.md` entries, and the tombstones themselves keep the old
ones.

## Consequences

- **Two new major tags** whose code matches the old tracks' last releases.
  Each module's history is split across two files, joined by §4's pointer.
- **One more `workflows` release.** Only this repo's own release runs need it,
  so no spoke has to take it.
- **A short freeze on runway's Terraform PRs** from step 4's first state push
  until its merge, as in LIB-0004's Consequences.
- **`terraform-state` moves its own state.** That leaf's state lives in the
  bucket it manages (LIB-0016). Moving its key within that bucket is an
  ordinary state move. Replacing the bucket would not be, and nothing here
  replaces it.
- **`pigeon-transform` jumps three releases.** It pins `object-bucket/v4.0.0`,
  so rewiring it to `bucket/v5.0.0` also picks up 4.1.1's fix to make the ACL
  and website resources honour `project_id`. If step 3's plan shows a diff,
  it's resolved in that PR, not applied blind.
- **The garden lists four Scaleway bucket and cluster modules,** two of them
  tombstones whose overview pages point to their successors.

## Out of scope

- **Generalizing `compute-cluster` beyond pigeon-cli jobs.** A permanent
  boundary: this record renames, it doesn't redesign.
- **Renaming any other module.**
- **Re-pinning leaves that don't call either module.** Step 3 changes only
  the leaves being moved.
