# LIB-0003: a versioned `root.hcl` template, and Terragrunt CI a spoke can call

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted; amended 2026-10-15, three times, and 2026-10-17 (see `## Amendments`). The per-leaf `*_config.hcl` opt-ins its amendments added are superseded by LIB-0005.

## Context

LIB-0001 §6 said `root.hcl` should become a versioned template, with a spoke's
copy reduced to the values that genuinely vary. LIB-0002 deferred it because it
only served the Terraform hoist (LIB-0001 §7 step 3), which was blocked on §8.
For `pigeon.dev`, DEV-0163 now unblocks that step by leaving `state/iam` in
`noisypigeon`. So the template is needed now, not eventually.

Checked against `noisypigeon@origin/main`, the three per-domain roots are 5857,
5877 and 8080 bytes.

- **`pigeon.dev/root.hcl` and `noisypigeon.com/root.hcl` differ only in the name
  of the state-bucket secret.** That is
  `PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME` against
  `NOISYPIGEON_COM_TERRAFORM_STATE_BUCKET_NAME`, plus the ADR cited in one
  comment.
- **`willowgraysen.com/root.hcl` adds two things.** A latent Backblaze provider
  that a leaf opts into through `backblaze_config.hcl` (DEV-0148), and a
  `grafana/grafana` provider requirement.

Of the six differences LIB-0001 §3 counted, the other three belonged to the
monorepo's shared `root.hcl`, which no spoke inherits. Those were the `.env.enc`
path, the two-segment leaf check, and the `workloads/` key prefix. In a spoke,
one value varies today.

The hub's Terragrunt CI also could not serve a spoke. `terragrunt-run.yml` masked
secrets by decrypting a hardcoded `.env.enc`, and it had no step to fetch the
library or produce a `root.hcl` before running.

## Decision

### 1. `terragrunt/root-hcl/root.hcl`, tagged `terragrunt/root-hcl/vX.Y.Z`

This is the fourth release track. The template is `pigeon.dev/root.hcl` with
one change: the state-bucket secret name is read from the spoke's `spoke.hcl`
through `read_terragrunt_config("${get_parent_terragrunt_dir()}/spoke.hcl")`.
A missing `spoke.hcl`, or one without `state_bucket_secret`, is a hard error.
Guessing a bucket is how a plan lands in the wrong one.

`template-release.yml` cuts the track when `terragrunt/root-hcl/root.hcl` changes.
The first version is `1.0.0`. It writes the unit's `CHANGELOG.md` and a
`[terragrunt/root-hcl]` root line. The hub's `root-changelog.yml` gained the
matching stand-down arm in the same PR (pigeon-lib#15), so there are now four
duplicated predicates. That is #301's risk, carried forward deliberately.

### 2. Materialized, never included or symlinked

`.github/scripts/resolve-root-hcl.sh` runs from a spoke's root. It reads
`root_hcl_version` from `spoke.hcl` and copies the template to `./root.hcl`,
either at the tag or from the working tree for `"main"`. The spoke gitignores
`/root.hcl`. This is the shape `resolve-theme.sh` already has, and LIB-0001 §6
named it for this reason. Three constraints force it:

- **Terragrunt does not support nested includes (DEV-0059).** A spoke-owned
  `root.hcl` cannot `include` the template on a leaf's behalf.
- **The state key would change.** `path_relative_to_include()` is relative to the
  included file's directory. A `root.hcl` anywhere but the spoke's root would
  shorten every key, which is DEV-0059's "Backend configuration changed".
- **A symlink would point at the wrong repo.** `get_parent_terragrunt_dir()`
  would resolve into the library clone and look for `spoke.hcl` there.

The script lives under `.github/scripts/`, not `terragrunt/root-hcl/`, so the
`workflows/` track versions it. `resolve-theme.sh` sits under `zola-site/`, where
no release predicate covers it, and that gap is not repeated here.

### 3. Spoke-callable Terragrunt CI (`workflows/v1.3.0`)

`terragrunt-run.yml` gained two inputs, and both defaults reproduce its old
behaviour exactly:

- `secrets_files`: the sops files to mask, defaulting to `.env.enc`.
- `prepare_cmd`: a command run before Terragrunt, defaulting to none. A spoke
  passes `./fetch-lib.sh && .lib-src/.github/scripts/resolve-root-hcl.sh`.

`terragrunt-detect.yml` already took `leaf_pattern`.

## Consequences

- **A broken template breaks every spoke that bumps to it, at once.** LIB-0001
  predicted this. The mitigation is invariant 2: each spoke opts in by changing
  `root_hcl_version`, and that bump is a PR whose plan shows the consequence.
- **Two pins govern a spoke's Terraform.** `/.lib-version` picks the resolver and
  `root_hcl_version` picks the template. A template change needs only the
  second; a resolver change needs only the first.
- **Local Terraform work in a spoke needs the library first.** `mise run plan`
  fetches it and resolves `root.hcl` before Terragrunt runs. A fresh clone with
  neither has no `root.hcl` at all, and Terragrunt fails loudly rather than
  finding some other root.
- **The release predicates now live in four places in two files.** #301 is
  unchanged, and this makes it worse by one.

## Out of scope

- **`willowgraysen.com`'s providers.** Genuinely deferred to that spoke's hoist.
  The extension point is additive, so it is a minor bump: an optional
  `extra_required_providers` in `spoke.hcl`, and the latent per-leaf
  `backblaze_config.hcl` lifted from `willowgraysen.com/root.hcl`. It is not
  shipped now because nothing here can plan-verify it.
- **`noisypigeon.com`'s hoist.** Template `v1.0.0` already serves it unchanged;
  the hoist is that spoke's own step.
- **Templating the monorepo's shared `root.hcl`.** Permanent boundary. It serves
  only the `state/iam` leaves left behind under LIB-0001 §8, and it is not a spoke.
- **Fixing #301.** Genuinely deferred; tracked.

## Verification

1. **The resolver, against a scratch library repo.**
   - A pinned version writes the tagged file, and `"main"` writes the working
     tree as a regular file, not a symlink.
   - An unknown version exits 1 with `Unknown tag terragrunt/root-hcl/v9.9.9`.
   - A missing `spoke.hcl` exits 1, and so does running inside the library.
2. **The template, against the root it replaces.**
   - For `pigeon.dev`'s four hoisted leaves (`fastmail/dns`, `project`,
     `state/bucket`, `wiki/dns`), `terragrunt render --format=json` was run under
     the monorepo's `pigeon.dev/root.hcl` and under this template with
     `spoke.hcl`.
   - After normalizing the two trees' absolute paths, the renders have **zero**
     differing keys.
   - The state keys are literally `terraform/<leaf>/terraform.tfstate` in both.
     The renders contain decrypted secrets, so they were compared structurally
     and deleted.
3. **The release.**
   - pigeon-lib#15 cut `workflows/v1.3.0`.
   - This record's PR changes `terragrunt/root-hcl/root.hcl`, so its merge should
     cut `terragrunt/root-hcl/v1.0.0` and write one `[terragrunt/root-hcl]` root
     line, with no second line from `root-changelog.yml`.

## Amendments

### 2026-10-15: the spoke commits `root.hcl`; CI verifies it

§2 said the spoke gitignores the materialized `root.hcl`. That does not survive
contact with the CI. Running `terragrunt-run.yml`'s exact filter construction
against the `pigeon.dev` hoist branch failed on all four leaves with:

```
Could not find a root.hcl in any of the parent folders of
…/terragrunt-worktree-HEAD-…/terraform/fastmail/dns/terragrunt.hcl
```

Terragrunt 1.1.6's `[main...HEAD]` git filter plans every unit inside temporary
git worktrees of both refs, and a worktree contains only tracked files. With
the materialized copy committed on that same branch, the identical command
planned `No changes.` for all four leaves against live state.

So the spoke **commits** the generated `root.hcl`, and the resolver gains a
`--check` mode that writes nothing and exits 1 unless `./root.hcl` is
byte-identical to the template at the pinned version. A spoke's CI runs
`--check` through `prepare_cmd`. A hand edit or a forgotten re-run therefore
fails the plan instead of reaching `main`. The template's own header now says
"GENERATED in a spoke -- do not edit there", since that header is what the
spoke commits.

This is better than the gitignored design on its own terms. The base ref's
worktree has the `root.hcl` it was planned with, so a leaf removed from a spoke
still plans its destroy. A gitignored copy would have made that path fail too.

What does not change: the template is still copied, never included or
symlinked, for §2's other two reasons.

The fix shipped as `workflows/v1.3.1` (the resolver) and
`terragrunt/root-hcl/v1.0.1` (the header).

### 2026-10-15: the providers extension point ships as `v1.1.0`

`## Out of scope` deferred `willowgraysen.com`'s providers to that spoke's hoist.
They are needed now, so `v1.1.0` adds two optional `spoke.hcl` locals, both off
by default:

- **`extra_required_providers`** is a map of `{ source, version }`, appended
  line by line to the single `required_providers` block. An empty map adds
  nothing, not even a blank line.
- **`backblaze = true`** enables DEV-0148's latent mechanism, lifted from
  `willowgraysen.com/root.hcl`:
  - the `BACKBLAZE_APPLICATION_KEY*` locals;
  - a per-leaf `backblaze_config.hcl` read;
  - a conditional `b2` required-provider entry;
  - `generate "provider_backblaze"`.

  When it is unset, that generate block is `disable`d, so no file is written.

Verified by `terragrunt render --format=json` against three baselines:

- **All 14 of `willowgraysen.com`'s hoistable leaves,** under its monorepo root
  versus this template with `backblaze = true` and a `grafana` entry. Each
  differs in exactly one key, `generate.provider.contents`, and only in
  whitespace: the original emitted a blank indented line where its Backblaze
  entry would go. State keys are equal.
- **`pigeon.dev`'s 4 leaves and `noisypigeon.com`'s 6,** under `v1.0.1` versus
  `v1.1.0`. Each differs in exactly one key: an added `generate.provider_backblaze`
  with `disable: true` and `if_disabled: skip`, which writes nothing. Neither
  spoke needs to bump, but either can.

### 2026-10-15: a latent Grafana provider ships as `v1.2.0`

`willowgraysen.com`'s adoption of LIB-0004 needed its Grafana leaf to hold one
module and nothing else. That leaf carried a `provider "grafana"` block and a
`scaleway_cockpit_grafana` data source as glue. `v1.2.0` moves both into the
template, as a latent feature shaped like DEV-0148's Backblaze one:

- **Two opt-ins.** `grafana = true` in `spoke.hcl`, then `grafana_config.hcl`
  with `enabled = true` per leaf.
- **What an enabled leaf gets:** the `grafana/grafana ~> 4.0` requirement, the
  data source, and the provider.
- **The one contract on the leaf:** it defines `local.grafana_auth_token`.
- **What everything else gets:** a comment-only file, or nothing at all when
  the spoke doesn't set `grafana`.

The first-access curl hook the same leaf carried moved into
`scaleway/grafana-dashboard` v0.2.0 instead.

Verified by rendering every leaf of all three spokes (24 leaves) under its
committed `root.hcl` and under `v1.2.0`. The only differences are added `generate`
entries with `disable: true`: `provider_grafana` everywhere, plus `provider_backblaze`
on the two spokes still at `v1.0.1`. State keys are equal throughout.

### 2026-10-17: the three spoke hoists, folded in by LIB-0017

Each spoke consumed this template by hoisting its Terraform out of
`noisypigeon/noisypigeon`. The three records below were filed in the spokes
and are folded in here. They share one recipe, stated once:

1. **`state/iam` stays behind** (LIB-0001 §8, option 1). A bootstrap root
   would have copied the organisation-level shared deployer credentials into
   the spoke. Accepting the self-reference would have reversed
   DEV-0130/0133's rule and moved state between buckets. Leaving the leaf
   where it was moves neither. All three spokes chose this, which settled the
   choice in noisypigeon/noisypigeon#308.
2. **The other leaves move with their history.** One `git filter-repo` pass
   over a fresh clone does it:
   - keep the domain's own paths;
   - rename `…/terraform/` to `terraform/`, and `…/secrets.enc` to
     `terraform/secrets.enc`;
   - drop `terraform/state/iam/`, after dropping tags.

   The result merges with `--allow-unrelated-histories`, byte-identical to the
   source. sops metadata does not encode the file's path.
3. **State does not move.** With `root.hcl` at the repo root and the leaves
   under `terraform/`, every key stays `terraform/<leaf>/terraform.tfstate` in
   the same bucket (LIB-0001 invariant 4). Each spoke wrote this out per leaf
   rather than asserting it.
4. **`root.hcl` is generated and committed,** pinned in `spoke.hcl` and checked
   with `--check`, as the first amendment above requires. Each leaf was
   rendered under the old root and the template before any PR.
5. **CI and the gate.**
   - Thin callers of `terragrunt-detect.yml`/`terragrunt-run.yml` with
     `leaf_pattern` (`^terraform/`, `root.hcl`, `spoke.hcl`, `.sops.yaml`),
     `secrets_files` and a `prepare_cmd` that fetches the hub and runs
     `--check`.
   - `SOPS_AGE_KEY` is the family's shared age key, and `.sops.yaml` has one
     rule.
   - `main` gets `noisypigeon`'s ruleset (DEV-0129): no force-push, a required
     `terragrunt/apply` status, and the owner and bot as bypass actors. It is
     created after the import merges. A non-Terraform PR gets the status
     straight away from the detect job.
   - `root-changelog.yml` tags `terraform/`, `root.hcl`, `spoke.hcl` and
     `.sops.yaml` changes as `terraform`.
6. **The deletion in the source repo is never applied. This is the hazard
   that matters for any future hoist.**
   - The PR that deletes the moved leaves from the source repo plans destroys
     against the very bucket and keys the spoke now owns. It merges through
     the ruleset's owner bypass, and `terragrunt apply` is never commented on
     it.
   - DEV-0130's "empty the old location's state" must **not** be followed
     here. It assumes the old and new locations differ, and here they are the
     same object, so a `state rm` would orphan live resources from their only
     owner.
7. **The import merges as a merge commit, once,** to keep its history, after
   CI shows `No changes.` everywhere. The apply is skipped, because it would be
   a no-op whose only effect is a squash.

Since then, LIB-0012 split `terraform/secrets.enc` into per-concern files
under `terraform/secrets/`, and LIB-0007 moved the spokes' state to R2. So
the secret paths and buckets in the entries below are as of filing.

### 2026-10-17: DEV-0163, hoist `pigeon.dev`'s Terraform (folded from `noisypigeon/garden`)

Filed 2026-10-15. This was LIB-0001 §7 step 3, the first hoist. Accepted, and
amended 2026-10-16 when DEV-0164 retired its `state/iam` arrangement. The full
text is also archived as
[`archive/DEV-0163`](archive/DEV-0163-hoist-pigeon-dev-terraform.md).

- **Scope.**
  - Five leaves at `noisypigeon@ff2f4e2`. Four moved: `fastmail/dns`,
    `project`, `state/bucket`, `wiki/dns`.
  - The import was 15 files and 12 commits, starting at noisypigeon#195.
- **Template.** `1.0.1`, with zero differing render keys (Verification 2
  above). It was the dry run of this hoist that found the worktree problem
  the first amendment records.
- **Workflows.** `workflows/v1.3.1`. The ruleset partly resolved
  noisypigeon/noisypigeon#295.
- **One-time merge commit.** The repo allowed only squash merges, so merge
  commits were enabled for this PR alone and then disabled again.
- **Still true.**
  - A template bump is a three-part diff: `spoke.hcl`, `root.hcl` and the
    replan of every leaf.
  - Between a hoist merging and the source deletion merging, two repos can
    plan the same state. The backend lock covers a concurrent apply but not
    the confusion over ownership, so the deletion follows straight away.
  - Imported commits cite `noisypigeon` PR numbers, which GitHub autolinks
    against the wrong repo.
- **Later.** DEV-0164 retired `state/iam`'s deploy key, so key rotation by a
  `noisypigeon` PR followed by `mise run secrets-edit` no longer applies here.

Original: [DEV-0163](https://github.com/noisypigeon/garden/blob/13bcee9a79c86a3a0054ebda7cd6d7fa7c238df2/adr/DEV-0163-hoist-pigeon-dev-terraform.md).

### 2026-10-17: COM-0003, hoist `noisypigeon.com`'s Terraform (folded from `noisypigeon/blog`)

Filed 2026-10-15. This is the Terraform half of LIB-0001 §7 step 4. Accepted.

- **Scope.**
  - Seven leaves at `noisypigeon@87a5089`. Six moved: the GitHub Pages CNAMEs
    that put the site online, **every mail record for the domain**, two
    verification-TXT leaves, `project` and `state/bucket`.
  - The import was 21 files and 7 commits, starting at noisypigeon#208.
- **Template.** `1.0.1`, with zero differing render keys and literally equal
  state keys.
- **Workflows.** All six workflow refs and `.lib-version` moved from
  `v1.2.0` to `v1.3.1`, which changed nothing the Pages and changelog callers
  use.
- **Hazard specifics.** Applying the source deletion would have taken the blog
  offline and broken the domain's email.
- **Merge.** The repo already allowed merge commits, so no settings toggle was
  needed.
- **Still true.**
  - Every blog PR gets a `terragrunt/apply` status that turns green without
    running anything. A failing detect job would therefore block a post.
  - The apply flow's auto-merge never worked
    (noisypigeon/noisypigeon#310), so an applied Terraform PR is merged by
    hand until that is fixed.
- **Later.** COM-0004 moved the state to R2, and COM-0005 retired the
  Scaleway pieces, including `state/iam`'s deploy key.

Original: [COM-0003](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0003-hoist-noisypigeon-com-terraform.md).

### 2026-10-17: RUN-0001, hoist `willowgraysen.com`'s Terraform (folded from `noisypigeon/runway`)

Filed 2026-10-15. This is the second half of LIB-0001 §7 step 5, and the last
hoist. Accepted. Described by role, per RUN-0000's rule.

- **Scope.**
  - Fifteen leaves at `noisypigeon@219706e`. Fourteen moved: cold-storage
    buckets, `pigeon-cli`'s job and report buckets, its cluster,
    observability and IAM application, the redirect, `project` and
    `state/bucket`.
  - The import was 52 files and 26 commits, starting at noisypigeon#209.
- **Template.** `1.1.0`, the version that added this spoke's needs:
  `backblaze = true` and a `grafana` entry in `extra_required_providers`.
  Rendered against the old root, each leaf differed in one key: whitespace in
  the generated provider file, where the old root left a blank line for the
  Backblaze entry. Every state key matched.
- **Apply gate.** The apply is gated on a fixed comment from an OWNER, MEMBER
  or COLLABORATOR. Merge commits were disabled after the import merged.
- **Hazard specifics.** Applying the source deletion would have destroyed the
  cold-storage buckets, **whose contents are custodial and unrecoverable**.
  It would also have taken the job and report buckets, observability, the
  IAM application, the redirect, the project and the state bucket.
- **State ahead of config: caught up, not destroyed.**
  - One `pigeon-cli` bucket leaf's state held three resources that no
    committed config described: an IAM policy, an API key and the key's
    `time_static`. An uncommitted worktree had applied them, and a running
    job was using that key.
  - Planned as orphans, they would have been destroyed, revoking that job's
    credentials. The fix was configuration, not `import`, because the
    resources were already in state.
  - The leaf gained `iam.tf` (`iam-policy/v4.0.0` and `iam-api-key/v0.2.0`)
    and a sensitive `outputs.tf`, and then planned `No changes.`.
  - Identifiers come from existing secrets, so nothing is written into the
    public repo. The key expires after the module's default 30 days, and
    renewing it is a replace of `module.iam_api_key`.
  - **The general lesson: in a hoist, a planned destroy of resources nothing
    describes means state is ahead of config. Describe them; never let them
    go.**
- **Verification.** One observability leaf planned an in-place dashboard
  update that it also planned under the old layout. It was pre-existing drift,
  left for its own PR. No leaf planned a destroy.
- **Out of scope.**
  - Documenting the redirect (noisypigeon/noisypigeon#309); COM-0006 later
    moved it.
  - Re-enabling the cluster module, which is `pigeon-cli`'s decision.
- **Later.** The repo was renamed `noisypigeon/runway` (LIB-0013), and its
  state bucket name follows the repo (LIB-0016).

Original: [RUN-0001](https://github.com/noisypigeon/runway/blob/2ab560c516d76c90482ad963c62525f800e923fe/adr/RUN-0001-hoist-willowgraysen-com-terraform.md).
