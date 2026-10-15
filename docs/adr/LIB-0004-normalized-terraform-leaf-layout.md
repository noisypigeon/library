# LIB-0004: a normalized Terraform leaf layout, `terraform/<provider>/<module>/<instance>/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted.

## Context

After DEV-0163, COM-0003 and RUN-0001, every spoke keeps its Terraform under a
repo-root `terraform/`, which LIB-0001 invariant 4 requires. Nothing governs what
goes *below* `terraform/`. Each spoke organized its leaves by purpose, at
whatever depth it liked:

- `pigeon.dev`: `fastmail/dns`, `wiki/dns`, `project`, `state/bucket`.
- `noisypigeon.com`: `blog/dns`, `bluesky/dns`, `google-search/dns`,
  `proton/dns`, `project`, `state/bucket`.
- `willowgraysen.com`: `cold/<name>`, `pigeon-cli/bucket/pigeon/deduplicate`,
  `pigeon-cli/shared/reports/phase-transform`, `pigeon-cli/cluster`,
  `redirect/dns`, `project`, `state/bucket`.

Three costs follow, all checked against the live trees.

1. **A path says nothing about what the leaf is.** `fastmail/dns` and
   `wiki/dns` are raw `cloudflare_dns_record` resources. `state/bucket` is the
   `scaleway/object-bucket` module, and `project` is `scaleway/project`. Finding
   every consumer of a module, which is what a module release's blast radius
   *is*, means grepping `source =` lines across three repos.
2. **The layout is part of the state contract, by accident.** A leaf's state key
   is `"${path_relative_to_include()}/terraform.tfstate"`
   (`terragrunt/root-hcl`, LIB-0001 invariant 4), so every path is a key. The
   layout cannot be tidied later without a state move per leaf. That makes it
   worth settling while there are three spokes, not ten.
3. **The family already has a canonical namespace and doesn't use it here.**
   The hub's modules live at `terraform/<provider>/<module>/`, tagged
   `terraform/<provider>/<module>/vX.Y.Z`, and are consumed as
   `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` (DEV-0109/0110). It's a
   stable, public, well-understood coordinate, but spokes ignore it when naming
   the leaves that call those modules.

## Decision

### 1. Every leaf lives at `terraform/<provider>/<module>/<instance>/`

- **`<provider>/<module>`** is **exactly** the pigeon-lib module the leaf calls:
  the same two segments as the hub's `terraform/<provider>/<module>/` and the
  `pigeon.dev/modules/<provider>/<module>` short URL.
- **`<instance>`** is a kebab-case name for what this instance is *for*. It is
  unique within its `<provider>/<module>` in that spoke.
- **Exactly three segments below `terraform/`.** No more, no less.
- **The state key follows from the path,** with no change to the template:
  `terraform/<provider>/<module>/<instance>/terraform.tfstate`.

The path now answers "which module, which provider, which instance" without
opening a file. And "every consumer of `scaleway/object-bucket`" becomes
`ls terraform/scaleway/object-bucket/` in each spoke.

### 2. One leaf calls exactly one pigeon-lib module

A leaf may call its module once or many times through `for_each`, but it calls
only that one module. Two consequences follow.

- **Raw provider resources get a thin wrapper module in the hub.** A leaf that
  manages `cloudflare_dns_record` resources directly has no `<module>` segment
  to file under. So the hub gains `cloudflare/dns-record`, a thin wrapper over a
  single `cloudflare_dns_record` that passes arguments through unchanged and
  leaves `for_each` to the caller. Other raw resources get wrappers the same
  way, as spokes reach them.
- **A leaf that composes several modules is split into one leaf per module.**
  For example, a bucket plus an API key for it becomes a bucket leaf and a key
  leaf. They are wired together with Terragrunt `dependency` blocks where one
  needs another's outputs. This is accepted for now. It means more leaves, and
  dependency edges that were implicit inside one state file become explicit
  between two. A split moves resources between state files, so it is a state
  move like any rename (§3).

### 3. Adopting the layout moves state and files, never resources

Migrating a leaf to this layout must not change any real resource. The proof is
a plan of `0 to add, 0 to change, 0 to destroy` on every path involved.

- **Address changes within one state** use `moved {}` blocks, committed in
  config, so the history of the address is reviewable. Switching a leaf from raw
  resources to a wrapper module is the first such case.
- **Moving a leaf to a new key** uses DEV-0106's worktree `state pull`/`push`
  runbook: pull from the old path in a worktree of `main`, confirm the new key is
  empty, push, then plan the new path, which must show `No changes`.
- **The old key is then emptied,** not merely orphaned (DEV-0130), with
  `state rm` of every address it held. `terragrunt-run.yml` plans with
  `--filter-allow-destroy`, so a leaf directory removed in a PR is planned
  against its old state. Left full, that state would put a destroy of live
  resources one `terragrunt apply` comment away.
- **Splitting a leaf** pulls its state once and pushes each module's resources
  to its own new key, by `state mv -state-out` against the pulled file. The
  same gates apply.

### 4. A convention now, a contract once every spoke conforms

`pigeon.dev` adopts first. Until `noisypigeon.com` and `willowgraysen.com` also
conform, this is a convention: nothing rejects a non-conforming path. Once every
spoke conforms, it becomes a **contract**, enforced in a later `LIB-` record. The
likely mechanism is a major `terragrunt/root-hcl` version whose `is_valid_leaf`
requires exactly three segments below `terraform/`, which a spoke takes by
bumping `root_hcl_version`.

### 5. `pigeon.dev`'s adoption

| Today | Becomes | Module |
| --- | --- | --- |
| `terraform/fastmail/dns` | `terraform/cloudflare/dns-record/fastmail` | `cloudflare/dns-record` (new) |
| `terraform/wiki/dns` | `terraform/cloudflare/dns-record/github-pages` | `cloudflare/dns-record` (new) |
| `terraform/project` | `terraform/scaleway/project/dev` | `scaleway/project` |
| `terraform/state/bucket` | `terraform/scaleway/object-bucket/terraform-state` | `scaleway/object-bucket` |

It runs in two PRs, following DEV-0110's "pure rename first, rewiring second",
and keeps one failure mode per PR. The order is reversed here, because rewiring
is what makes the rename's paths true.

1. **Rewire, without renaming.** The two DNS leaves adopt `cloudflare/dns-record`
   in place, with one `moved` block per record. The plan shows only moves, and
   the apply rewrites state addresses and nothing else.
2. **Rename.** All four leaves `git mv` to their new paths, and each leaf's state
   moves to its new key per §3.

## Consequences

- **Every existing leaf in the family moves once.** That is a state move per
  leaf, each with its own window: between a state move and the merge that
  follows it, `main` still points at the old, now-empty key. A concurrent PR
  touching that leaf would plan creates. Each adoption PR therefore needs a
  short freeze on Terraform PRs in that spoke.
- **More leaves, more `dependency` edges.** Splitting multi-module leaves turns
  one `terragrunt apply` into several ordered ones, and turns implicit
  in-config references into Terragrunt outputs. That is real complexity, taken
  on deliberately in exchange for paths that mean something.
- **The hub grows thin wrapper modules.** Each is a pass-through that adds a
  release track and a module page on `pigeon.dev`, but no logic.
  `cloudflare/dns-record` is the first.
- **Paths get longer and less personal.** `terraform/cloudflare/dns-record/fastmail`
  says less about *why* than `fastmail/dns` did. The `<instance>` segment carries
  all of the purpose now, so it has to be chosen well.

## Out of scope

- **`noisypigeon.com`'s adoption.** Genuinely deferred, a fast follow, tracked
  as noisypigeon/noisypigeon#313.
  - Its four raw-DNS leaves would become `cloudflare/dns-record/<instance>`, for
    example `github-pages`, `bluesky`, `google-search` and `proton`.
  - `project` and `state/bucket` would become `scaleway/project/<instance>` and
    `scaleway/object-bucket/terraform-state`.
  - The instance names are that spoke's to choose.
- **`willowgraysen.com`'s adoption.** Genuinely deferred, a fast follow, and
  the first spoke with splits. Tracked as noisypigeon/noisypigeon#314. Shallowly:
  - **`terraform/scaleway/pigeon-cluster/`.** `pigeon-cluster` is a composite
    hub module, but it is still one module, so `pigeon-cli/cluster` becomes
    `scaleway/pigeon-cluster/<instance>` with no split. Composition inside a hub
    module is the hub's business. The rule only splits compositions that a
    *leaf* performs.
  - **`terraform/backblaze/bucket/`.** Each `cold/<name>` leaf's bucket becomes
    `backblaze/bucket/<name>`.
  - **`terraform/backblaze/api-key/`.** Each `cold/<name>` leaf also declares a
    B2 key (currently commented out). Under §1 that is a separate
    `backblaze/api-key/<name>` leaf, depending on the bucket leaf. It is named
    for the hub module, `backblaze/api-key`, not for a provider service family
    such as `iam`.
  - The `pigeon-cli/shared/grafana` and `bucket/pigeon/deduplicate` leaves each
    compose IAM modules with their primary one, so they split too.
- **The three `state/iam` leaves in `noisypigeon/noisypigeon`.** A permanent
  boundary for this record. They sit on the monorepo's shared root under its
  `workloads/`-prefixed keys (LIB-0001 §8), not in a spoke.
- **Enforcement.** Genuinely deferred to the `LIB-` record that turns §4's
  convention into a contract.
- **Re-pinning module versions while moving.** A permanent boundary for any
  adoption PR: moves change paths and state addresses only. A version bump is
  its own PR with its own plan.

## Verification

All checked on 2026-10-15, as `pigeon.dev` adopted the layout.

1. **The wrapper module.** `cloudflare/dns-record` (pigeon-lib#24) was tagged
   `terraform/cloudflare/dns-record/v0.1.0`. `terraform validate` passed. Its
   short URL, `pigeon.dev/modules/cloudflare/dns-record/v0.1.0/`, returned 200
   and named `pigeon-lib.git//terraform/cloudflare/dns-record?ref=terraform/cloudflare/dns-record/v0.1.0`.
   It was the first `cloudflare/` module the redirect generator served, and it
   needed no change.
2. **The rewire (noisypigeon/pigeon.dev#28).** The local and CI plans showed
   exactly 6 and 2 `has moved to` lines, with `0 to add, 0 to change, 0 to
   destroy`, on the two DNS leaves. The apply reported `0 added, 0 changed,
   0 destroyed`. `dig` returned the same MX, SPF, DKIM and `www` records
   afterwards.
3. **The rename (noisypigeon/pigeon.dev#29).** The §3 runbook ran per leaf, in
   order: `fastmail`, `github-pages`, `dev`, then `terraform-state`.
   - It pulled 6, 2, 1 and 2 resources.
   - Each new key was empty before its push and held the same count after.
   - Each new path planned `No changes`.
   - Each old key was emptied with `state rm`.

   The PR's re-run CI plan showed:
   - `No changes.` on all four new paths;
   - "No objects need to be destroyed" on the removed DNS leaves;
   - only stale *output* removals on the removed `project` and `state/bucket`
     leaves. `state rm` does not clear outputs, and Terraform labels those
     changes "without changing any real infrastructure".

   Every unit applied `0 added, 0 changed, 0 destroyed`.
4. **After the merge.** `mise run plan` on `main` gave `No changes.` on all four
   leaves. `https://pigeon.dev/` returned 200, and MX and `www` resolved as
   before. The state keys are now exactly:
   - `terraform/cloudflare/dns-record/fastmail/terraform.tfstate`
   - `terraform/cloudflare/dns-record/github-pages/terraform.tfstate`
   - `terraform/scaleway/project/dev/terraform.tfstate`
   - `terraform/scaleway/object-bucket/terraform-state/terraform.tfstate`
5. **A runbook note for the next spoke.** A removed leaf that had `output`s plans
   "Changes to Outputs" against its emptied key, even after `state rm`. That's
   expected, and harmless: those are output removals, not resource changes. The
   gate is "no resource add/change/destroy", not "the words No changes".
