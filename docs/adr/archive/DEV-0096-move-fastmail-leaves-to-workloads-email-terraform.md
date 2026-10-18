# DEV-0096: move the fastmail leaves to `workloads/email/terraform/fastmail/<domain>`, delete the zone leaves, decommission `terraform/infrastructure/cloudflare/`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`terraform/infrastructure/cloudflare/global/{noisypigeon.com,pigeon.dev}/fastmail/` are two Cloudflare leaves, each holding one domain's Fastmail SPF/DKIM/MX records (`txt.tf`, `cname.tf`, `mx.tf`), plus a sibling `zone/` leaf per domain that just provisions the bare `cloudflare_zone` resource. The user wanted the two `fastmail/` leaves relocated into the `workloads/<name>/terraform/` convention (ADR-0092/0094/0095) as `workloads/email/terraform/fastmail/`, and the two `zone/` leaves deleted from the repo outright, with no replacement — this is a pure organizational move, not a change to any live Cloudflare resource.

The user also noted, mid-move: `pigeon.dev` has since been moved onto the **same Cloudflare account** as `noisypigeon.com`. Previously (ADR-0064) the two domains lived in separate Cloudflare accounts, which is why `terraform/infrastructure/cloudflare/root.hcl` branches `cloudflare_api_token`/`cloudflare_account_id` per-leaf on an `is_pigeon_dev_leaf` check (`startswith(path_relative_to_include(), "global/pigeon.dev/")`). The initial assumption was that this branching was now unnecessary for anything moving into `workloads/` — **disproven live during the state migration, see Decision below**: the API token is still zone-scoped per domain even though the zone's owning account changed, so the branching stays, just re-keyed for the new path shape.

**Research confirmed, verbatim, before planning anything:**

- Both `fastmail/` leaves' resources collide by address if merged into one flat Terraform module: `cloudflare_dns_record.spf`, `.mx_primary`, `.mx_secondary`, `.dkim_fm1/2/3` are defined identically in both domains' `txt.tf`/`mx.tf`/`cname.tf`. A flat merge would require renaming every resource label and `terraform state mv`-ing each one — real state surgery that risks destroy/recreate if done wrong, and arguably "touches the resource" despite leaving its attributes alone. Keeping the two leaves separate, nested under a shared `fastmail/` parent by domain, avoids this entirely: every file moves byte-for-byte, no resource address changes.
- A repo-wide grep for `dependency`/`dependencies` blocks under `terraform/infrastructure/cloudflare/` found **none** — no other leaf reads either `zone/` leaf's outputs. Both `zone/`-adjacent `fastmail/` leaves (and everything else) resolve their `zone_id` independently from `.env`/env vars (`CLOUDFLARE_ZONE_ID_NOISYPIGEON_COM`, `CLOUDFLARE_ZONE_ID_PIGEON_DEV`), not from a Terragrunt dependency on the zone resource's output. Deleting `zone/` is safe with zero knock-on config changes.
- Once `fastmail/` moves out and `zone/` is deleted, `terraform/infrastructure/cloudflare/global/{noisypigeon.com,pigeon.dev}/` have no leaves left at all — these were each domain's *only* two leaves. That leaves `terraform/infrastructure/cloudflare/root.hcl` with zero consumers.
- `workloads/root.hcl`'s existing `is_valid_leaf` check (added by ADR-0092) requires the leaf's path relative to `root.hcl` to be *exactly* two segments, `<name>/terraform`. A domain-nested leaf like `email/terraform/fastmail/noisypigeon.com` is 4 segments — it would fail this check and get `exclude`d from `terragrunt run --all`.

## Decision

### Domain-nested leaves, not a flat merge

```
workloads/email/terraform/
  fastmail/
    noisypigeon.com/
      terragrunt.hcl
      txt.tf
      cname.tf
      mx.tf
    pigeon.dev/
      terragrunt.hcl
      txt.tf
      cname.tf
      mx.tf
```

Each is its own Terragrunt leaf (own state), moved via `git mv` with zero content changes. Each leaf's `terragrunt.hcl` is the same boilerplate every leaf in this repo uses (`include "root" { path = find_in_parent_folders("root.hcl") }`), which already resolves correctly at this depth — it walks up to the nearest `root.hcl` regardless of how many directories separate it.

### Widened `workloads/root.hcl` leaf-depth convention

`is_valid_leaf` changed from `length(path_segments) == 2 && path_segments[1] == "terraform"` to `length(path_segments) >= 2 && path_segments[1] == "terraform"` — i.e. any leaf nested at any depth under `<name>/terraform/` is now valid, not just a leaf directly at `<name>/terraform`. This keeps `blog/terraform` and `scaleway/terraform` valid unchanged, and newly admits `email/terraform/fastmail/noisypigeon.com` and `email/terraform/fastmail/pigeon.dev`.

### `workloads/root.hcl` gains `cloudflare_pigeon_dev_zone_id` and keeps per-leaf credential branching

The `generate "cloudflare_ids"` block gains a second zone id, read the same way as the existing `cloudflare_noisypigeon_com_zone_id` — `get_env("CLOUDFLARE_ZONE_ID_PIGEON_DEV", lookup(local.secrets, "CLOUDFLARE_ZONE_ID_PIGEON_DEV", ""))`.

The initial draft of this change dropped `is_pigeon_dev_leaf`-style credential branching entirely, on the assumption that — per the user — `pigeon.dev`'s zone now lives in the same Cloudflare account as `noisypigeon.com`, so every leaf could share one token. **This was tested live during the state migration below and found wrong**: `terragrunt plan` against the new `fastmail/pigeon.dev` leaf using `CLOUDFLARE_TOKEN` failed outright with a Cloudflare API "Authentication error" (code 10000) trying to read that zone's DNS records; re-running with `CLOUDFLARE_TOKEN` succeeded immediately (`No changes`). The account-level move doesn't change the API token's scope — the token remains zone-scoped per domain regardless of which account owns the zone. So `workloads/root.hcl` keeps the same per-leaf branching the old `terraform/infrastructure/cloudflare/root.hcl` used (ADR-0064), just re-keyed: `is_pigeon_dev_leaf = contains(local.path_segments, "pigeon.dev")` (any path segment, not a fixed `global/pigeon.dev/` prefix, since `workloads/` leaves can nest a domain segment at any depth) selects `CLOUDFLARE_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` instead of the `noisypigeon.com` pair.

### `terraform/infrastructure/cloudflare/` deleted entirely

With `global/noisypigeon.com/` and `global/pigeon.dev/` both losing their only two leaves, the whole provider root is orphaned — `root.hcl` has nothing left to configure. Deleted outright (`root.hcl` plus the now-empty `global/` tree), same spirit as ADR-0086's DigitalOcean decommission: no dead provider roots left lying around. `terraform/infrastructure/scaleway/` is untouched. A future Cloudflare leaf under `terraform/infrastructure/` (as opposed to `workloads/`) would need to recreate a provider root from scratch — not expected, since `workloads/<name>/terraform/` is now this repo's pattern for Cloudflare-managed DNS (blog, email).

### Documentation

- `workloads/README.md` gains an `email/` entry in its tree example and the convention paragraph is reworded to describe "any depth under `<name>/terraform/`" instead of "exactly `<name>/terraform`."
- `terraform/infrastructure/README.md`'s "Structure" section drops its `cloudflare/` block entirely (describing `terraform/infrastructure/` as Scaleway-only now) and its "Getting started" per-leaf example swaps from the now-deleted `cloudflare/global/noisypigeon.com/fastmail` to a still-live Scaleway leaf, same swap ADR-0094 made for its own edit.
- `docs/USAGE.md` and `CLAUDE.md` gain bullets/mentions for `workloads/email/terraform/fastmail/`, mirroring the existing `blog/`/`scaleway/` entries.

### The actual state migration — performed live, both leaves verified clean

At the user's explicit request, the state migration was executed directly in this session (unlike ADR-0094, which deferred it to the user). Same constraint as ADR-0094 found: plain `terragrunt init`/`init -migrate-state` does **not** work across a directory move, because Terragrunt's local init-pointer lives in a `.terragrunt-cache/<hash-of-path>/` directory keyed by filesystem path. The working runbook, run once per domain (since the move itself hadn't been committed yet, `git worktree add <path> HEAD` was sufficient to get a checkout of the pre-move layout — no need to locate an earlier commit):

```bash
# 1. Worktree at HEAD (the pre-move commit, since the move was staged but uncommitted).
cd /Users/pigeon/Developer/noisypigeon
git worktree add /tmp/old-fastmail-leaf HEAD
cp .env /tmp/old-fastmail-leaf/.env   # gitignored, not checked out by worktree add

# 2. Init against the OLD backend and pull its real, current state.
cd /tmp/old-fastmail-leaf/terraform/infrastructure/cloudflare/global/noisypigeon.com/fastmail
terragrunt init -input=false
terragrunt state pull > /tmp/fastmail-noisypigeon-com.tfstate   # 6 resources confirmed present

# 3. Confirm the NEW backend key is empty before overwriting anything.
cd /Users/pigeon/Developer/noisypigeon/workloads/email/terraform/fastmail/noisypigeon.com
terragrunt init -input=false
terragrunt state pull   # 0 resources, confirmed empty

# 4. Push the pulled state content to the NEW backend key.
terragrunt state push /tmp/fastmail-noisypigeon-com.tfstate

# 5. Verify -- showed "No changes. Your infrastructure matches the configuration."
terragrunt plan -input=false

# 6. Clean up.
cd /Users/pigeon/Developer/noisypigeon
git worktree remove /tmp/old-fastmail-leaf
rm /tmp/fastmail-noisypigeon-com.tfstate
```

Repeated identically for `pigeon.dev/fastmail`. Neither `state pull` nor `state push` talks to the Cloudflare API or touches any real DNS record — they only move the state file's content between backend keys. `pigeon.dev`'s first `plan` attempt (step 5) failed with a Cloudflare "Authentication error" using `CLOUDFLARE_TOKEN` — this is what surfaced the credential-branching fix above. After fixing `workloads/root.hcl`, the re-run showed "No changes" for both domains, confirming the new backend keys' state agrees with reality and no DNS record was destroyed, recreated, or modified.

The two `zone/` leaves' state objects (at their old backend keys under `cloudflare/global/<domain>/zone/terraform.tfstate`) become orphaned by this ADR — the `cloudflare_zone` resources themselves are completely untouched in Cloudflare, only their Terraform-tracked state entries are abandoned, since the leaves managing them no longer exist in the repo. This is an accepted, low-priority cleanup, same treatment ADR-0094 gave its own orphaned state object.

## Consequences

- Both `workloads/email/terraform/fastmail/{noisypigeon.com,pigeon.dev}` leaves are live and runnable immediately — state migrated and verified via `terragrunt plan` showing "No changes" for each, in this session.
- `terraform/infrastructure/cloudflare/` no longer exists in this repo. Cloudflare-managed DNS now lives entirely under `workloads/<name>/terraform/` leaves.
- `workloads/root.hcl`'s leaf-depth convention is now "any depth under `<name>/terraform/`," not "exactly `<name>/terraform`" — this applies repo-wide, so a future workload can nest leaves similarly (e.g. by domain, by subcomponent) without a further convention change.
- `workloads/root.hcl` still branches Cloudflare credentials per-leaf (`is_pigeon_dev_leaf`) despite the account merge — the zone-scoped token didn't become account-wide just because its owning account changed. If `pigeon.dev` is ever given full account-wide token access (or split back into its own account), re-evaluate this branching, but don't remove it on account-merge grounds alone — verify live against the actual token first.
- The old `cloudflare/global/{noisypigeon.com,pigeon.dev}/fastmail/terraform.tfstate` state objects are now orphaned (their content was copied, not moved — `state pull` doesn't delete the source). Low-priority cleanup, left for later; S3 versioning on the state bucket is an additional safety net regardless.

## Out of scope

- Deleting the orphaned `zone/` and old `fastmail/` leaves' stale state objects at their old backend keys — optional cleanup, left to the user's discretion and timing, same as ADR-0094's treatment of its own orphaned state object.
