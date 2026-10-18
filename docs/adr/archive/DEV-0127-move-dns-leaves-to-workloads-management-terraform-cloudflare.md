# DEV-0127: Move the `dns/` workload's Cloudflare leaves into `workloads/management/terraform/cloudflare/`, decommission `workloads/dns/`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

`workloads/dns/terraform/` groups every Cloudflare-managed DNS leaf by domain (ADR-0105): `noisypigeon.com/{blog,bluesky,fastmail,google}` and `pigeon.dev/{fastmail,redirect}` — six leaves in all (`google`, a site-verification TXT record, was added by PR #148 after ADR-0105 landed, and was never folded into CLAUDE.md/`workloads/README.md`/`docs/USAGE.md`'s prose; fixed here in passing since this move touches the same lines anyway).

`workloads/management/terraform/` (the deployer identity and Terraform state bucket) was deliberately nested one level deeper than strictly needed, under a `scaleway/` segment, when ADR-0124 promoted it to its own top-level workload — "the `scaleway/` segment leaving room for a future non-Scaleway management leaf without a second move." This move exercises exactly that anticipated case: Cloudflare DNS management becomes a `cloudflare/` sibling of `scaleway/` under the single `management/` workload, continuing the same workload-colocation regrouping this repo has done repeatedly (ADR-0106, 0115, 0116, 0117, 0124). With both domain directories gone, `workloads/dns/` has no leaves left and is decommissioned entirely, matching the precedent ADR-0096/0105/0106 set for `email/`/`bluesky/`/`custodian-buckets/`.

The two destinations, `workloads/management/terraform/cloudflare/{noisypigeon.com,pigeon.dev}/`, existed on disk beforehand as empty, untracked, pre-scaffolded placeholders — the same pre-scaffolding pattern ADR-0105/0106/0115/0124 used before their own moves.

This is a pure path relocation: no Cloudflare resource, zone, or record changes. `workloads/root.hcl`'s state-key derivation (`workloads/${path_relative_to_include()}/terraform.tfstate`), leaf-validity check (`path_segments[1] == "terraform"`), and `pigeon.dev`-credential branch (`contains(path_segments, "pigeon.dev")`) are all purely path-segment-derived and already proven correct at this nesting depth by the existing `fastmail`/`redirect` leaves themselves — moving them one level higher changes nothing about how `root.hcl` resolves them, only their state key, which `root.hcl` recomputes automatically from the new path.

This repo now also has `.github/workflows/terragrunt-plan.yml`/`terragrunt-apply.yml` (PR-triggered `terragrunt run --all --filter-affected`, apply gated behind a `terragrunt apply` PR comment). That CI is **not** used to perform this move — applying against the new path before state is migrated would see an empty state there and plan to recreate every DNS record from scratch, while orphaning the real resources still tracked under the old state key. The same manual worktree-based `state pull`/`push` runbook ADR-0094/0106/0115/0116/0117/0124 established still has to run first; the CI plan on the resulting PR then serves only as independent verification that the migration left everything at "No changes."

## Decision

### 1. Directory moves

For each of the six leaves, delete its gitignored `.terraform.lock.hcl`/`.terragrunt-cache/`, then move the whole domain directory in one `git mv` onto its pre-scaffolded (empty, so `rmdir`'d first) placeholder:

```sh
rmdir workloads/management/terraform/cloudflare/noisypigeon.com
git mv workloads/dns/terraform/noisypigeon.com workloads/management/terraform/cloudflare/noisypigeon.com

rmdir workloads/management/terraform/cloudflare/pigeon.dev
git mv workloads/dns/terraform/pigeon.dev workloads/management/terraform/cloudflare/pigeon.dev
```

With both domains gone, `workloads/dns/terraform/` and `workloads/dns/` are empty and removed entirely — `dns/` is decommissioned.

### 2. State migration

Migrated via the same `git worktree add ... HEAD` + `terragrunt state pull`/`push` runbook as every prior move ADR, run from a throwaway worktree with `.env` decrypted fresh from `.env.enc` via the user's `age` key:

```sh
git worktree add -b move-dns-management-leaves /tmp/dns-management-move HEAD
SOPS_AGE_KEY_FILE=~/.config/sops/age/noisypigeon.txt sops --decrypt --input-type dotenv --output-type dotenv .env.enc > /tmp/dns-management-move/.env

# for each leaf, at its OLD path:
terragrunt init -input=false
terragrunt plan -input=false      # baseline -- "No changes" for all six
terragrunt state pull > /tmp/<leaf>.tfstate

# perform the two git mv's above

# for each leaf, at its NEW path:
terragrunt init -input=false
terragrunt state pull             # confirmed empty
terragrunt state push /tmp/<leaf>.tfstate
terragrunt plan -input=false      # "No changes" -- confirmed against the live baseline
```

All six leaves' baseline and post-push plans showed "No changes," with identical resource IDs before and after:

- `noisypigeon.com/blog`: 2 resources (`cloudflare_dns_record.{root_cname,www_cname}`).
- `noisypigeon.com/bluesky`: 1 resource (`cloudflare_dns_record.did`).
- `noisypigeon.com/fastmail`: 6 resources (`cloudflare_dns_record.{spf,mx_primary,mx_secondary,dkim_fm1,dkim_fm2,dkim_fm3}`).
- `noisypigeon.com/google`: 1 resource (`cloudflare_dns_record.site_verification`).
- `pigeon.dev/fastmail`: 6 resources (same shape as `noisypigeon.com/fastmail`).
- `pigeon.dev/redirect`: 3 resources (`cloudflare_dns_record.{placeholder_apex,placeholder_www}`, `cloudflare_ruleset.to_noisypigeon_com`).

The `/tmp/<leaf>.tfstate` files (and the worktree's decrypted `.env`) were deleted immediately after verification. Old-location state objects in the Scaleway state bucket are left as low-priority cleanup, per established precedent.

## Consequences

- `workloads/management/terraform/` now holds `scaleway/` (the deployer identity + state bucket, ADR-0094/0106/0124) and `cloudflare/{noisypigeon.com,pigeon.dev}/` as siblings — the first time the `scaleway/` segment's anticipated future use actually materializes.
- `workloads/dns/` is decommissioned entirely — nothing of it remains anywhere in the repo.
- `CLAUDE.md`, `workloads/README.md`, and `docs/USAGE.md` are updated to describe the new layout, including the previously-undocumented `google` leaf.

## Out of scope

- Cleaning up the six leaves' orphaned state objects at their old keys in the Scaleway state bucket.
