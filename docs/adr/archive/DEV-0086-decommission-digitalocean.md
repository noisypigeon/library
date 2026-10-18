# DEV-0086: decommission DigitalOcean, complete the migration to Scaleway

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-01.
- **Status**: Accepted.

## Context

[ADR-0060](DEV-0060-scaleway-provider.md) added Scaleway as a third provider alongside DigitalOcean and Cloudflare, and explicitly deferred actually decommissioning DigitalOcean: "Decommissioning `pigeon.dev`'s DigitalOcean leaves/state bucket — being handled separately by the user, not by this ADR." Before that decommission could happen, Scaleway needed module-level parity with what DigitalOcean's modules already provided — over the following days `terraform/modules/scaleway/` grew `iam-policy` (hardened by [ADR-0066](DEV-0066-scaleway-iam-policy-prevent-bucket-scope-widening.md), [ADR-0069](DEV-0069-guard-scaleway-iam-policy-bucket-policy-self-lockout.md), [ADR-0070](DEV-0070-fix-scaleway-iam-policy-admin-statement-deprecated-version.md)), `object-bucket` (fixed by [ADR-0072](DEV-0072-fix-scaleway-object-bucket-glacier-transition-minimum-days.md)), `compute-instance` ([ADR-0079](DEV-0079-add-scaleway-compute-instance-module.md), extended by [ADR-0081](DEV-0081-add-cloud-init-rclone-bucket-access-to-scaleway-compute-instance.md)), and `block-volume` ([ADR-0085](DEV-0085-add-scaleway-block-volume-module.md)).

With that parity in place, the actual migration executed as a short, git-visible arc:

- `d25ecee` — Scaleway destination buckets created ahead of data migration.
- `66ec18e` / `10fc42c` — temporary DigitalOcean droplets stood up specifically to move data off DO.
- `5d606d9` — first DigitalOcean leaf decommissioned (`macbook-scratch`), superseded by a Scaleway equivalent.
- `c2fdbd3` — `chore(digitalocean): decommission backblaze-import bucket; migrated to scaleway`.
- `c278947` — `chore(scaleway): more bootstrapping` — the Scaleway-side replacement for what `backblaze-import`/`macbook-scratch` had been doing (`custodian/dhj` compute, `job/deduplication/macbook-scratch` bucket + compute).
- `59c5f8b` — `chore(digitalocean): decommission digital ocean; all resources on scaleway` — deleted the remaining DigitalOcean infrastructure leaves (`root.hcl`, `env.tf`, and the last `data/project`, `management/project`, `management/terraform` leaves).
- `8a201ed` — `chore(digitalocean): delete modules` — deleted all 6 `terraform/modules/digitalocean/*` reusable modules.

None of these four commits carries an extended rationale body beyond their subject line — this ADR is the durable record of why and what changed, since the git history alone only shows *what*.

## Decision

### What was deleted

`terraform/modules/digitalocean/` (all 6 modules, 880 lines):

- `access-key`, `standard-storage-bucket`, `cold-storage-bucket`, `project`, `droplet`, `block-storage-volume`.

`terraform/infrastructure/digitalocean/` (the entire provider root and its remaining leaves, 165+64 lines across the two decommission commits):

- `root.hcl`, `env.tf`.
- `global/noisypigeon.com/data/project/`, `global/noisypigeon.com/management/project/`.
- `tor1/noisypigeon.com/management/terraform/` (bucket + access key).
- `tor1/noisypigeon.com/data/backblaze-import/` (bucket + droplet + access key).

### Current provider surface

This repo's live infrastructure (`terraform/infrastructure/`) now spans exactly two providers: **Scaleway** (compute, object storage, block storage, IAM) and **Cloudflare** (DNS). `terraform/modules/` mirrors this — only `scaleway/*` modules remain, documented in `terraform/modules/README.md`.

### Fix stale documentation and CI

The decommission commits above deleted the Terraform code but left prose documentation and two CI workflows describing the old, now-nonexistent DigitalOcean surface. Fixed as part of this ADR:

- `CLAUDE.md`, `terraform/README.md`, `docs/USAGE.md` — each described `terraform/modules/` as holding "DigitalOcean, Scaleway" modules; corrected to "Scaleway" only.
- `terraform/modules/README.md` — dropped the 6 `digitalocean/*` rows from the module table, and fixed the local-clone consuming example (previously pointing at the now-deleted `digitalocean/access-key`).
- `terraform/infrastructure/README.md` — dropped DigitalOcean from the intro's provider list, removed the `digitalocean/` block from the structure diagram, and swapped the "Getting started" per-provider example from `cd digitalocean` to `cd scaleway`.
- `.github/workflows/module-release.yml` — the changed-module-detection `find` command referenced `terraform/modules/digitalocean`, a nonexistent path; dropped.
- `.github/workflows/module-docs.yml` — `working-dir` listed six `terraform/modules/digitalocean/*` paths that no longer exist, which would have made the `terraform-docs` step fail outright on its next run; dropped, leaving only the five live `scaleway/*` module paths.

Historical ADRs (0037-0085) and `CHANGELOG.md` are untouched — they accurately describe DigitalOcean as it existed when each was written, and remain correct historical records rather than stale current-state claims.

## Consequences

- This repo is single-cloud-provider (Scaleway) plus Cloudflare for DNS, going forward — any new provider addition follows the same pattern DigitalOcean/Scaleway did (add module(s) under `terraform/modules/<provider>/`, wire a provider root under `terraform/infrastructure/<provider>/`, add it to both workflow files' module lists).
- `terraform/modules/README.md`'s module table and count (now 5 Scaleway modules) is the accurate reflection of what's actually releasable; `module-release.yml`/`module-docs.yml` no longer reference deleted paths.
- Any external consumer of this repo's `terraform/modules/digitalocean/*` modules (tagged releases prior to `8a201ed`) is unaffected — module release tags are immutable; only the `main`-branch module source was removed, consistent with how this repo has always handled module deletion (no module in this repo has been deleted before this ADR, so there's no established precedent beyond "old tags still resolve").

## Out of scope

- Amending historical ADRs (0037-0085) that describe DigitalOcean as it existed at the time they were written — those remain accurate historical records and are deliberately not updated.
- Any further DigitalOcean-vs-Scaleway cost/feature rationale beyond what's verifiable from the commits and ADR-0060's context — the decommission commits themselves carry no extended rationale body, and none is reconstructed here beyond what's evidenced.
- Formally deprecating/archiving the now-unused `digitalocean/*` module tags on GitHub (e.g. marking releases as deprecated) — left as-is; they remain resolvable for any historical consumer.
