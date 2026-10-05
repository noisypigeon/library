# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [4.1.0] - 2026-10-05

### Add exact_name, website hosting, and public-read ACL to object-bucket

Adds three independent, backwards-compatible capabilities to `object-bucket`, all off by default:

- **`exact_name`**: bypasses the `name_prefix`/random-suffix/`name_suffix` naming scheme entirely for buckets whose name must match something external — most notably Scaleway bucket-website hosting, where the bucket name has to match a custom domain. A validation block enforces that you set either `exact_name`, or both `name_prefix` and `name_suffix` — never a mix. The underlying `random_string.suffix` resource moves from a singleton to a `count`-based one (only created when `exact_name` is unset), with a `moved` block so existing consumers using the prefix/suffix scheme see no plan diff.
- **`enable_website`** (plus `website_index_document`/`website_error_document`, and a new `website_endpoint` output): configures the bucket for static website hosting via `scaleway_object_bucket_website_configuration`.
- **`enable_public_read`**: grants the bucket a `public-read` ACL via `scaleway_object_bucket_acl`, needed for a website-hosting bucket's objects to actually be servable.

Also adds an optional `project_id` input (defaults to the provider's own project when unset), for buckets that need to live in a specific project.

None of this changes any existing consumer's behavior — every new input defaults to `null`/`false`, and the `moved` block keeps the `name_prefix`/`name_suffix` naming path's plan clean.

[#194](https://github.com/noisypigeon/noisypigeon/pull/194)

## [4.0.0] - 2026-10-04

### Rename object-bucket's namespace/name to name_prefix/name_suffix, default storage_class to glacier

Renames `object-bucket`'s `namespace`/`name` inputs to `name_prefix`/`name_suffix`, matching the convention ADR-0118 already applied to `compute-instance` — same `"${var.name_prefix}-${random_string.suffix.result}-${var.name_suffix}"` naming scheme, just call-site names that read correctly (`name_prefix = "job-${local.namespace}"` instead of pairing a generic `namespace` variable with an already-namespace-shaped value).

Also flips `storage_class`'s default from `"standard"` to `"glacier"`. Nearly every real consumer of this module is cold/archival data (`poisoned/*`, `email`, `media`, `macbook-scratch`, `backblaze`), so the new default matches what most callers actually want instead of requiring each to opt in by hand.

Both changes are breaking: existing callers must rename their `namespace`/`name` arguments, and any caller relying on the implicit `"standard"` default now needs to set `storage_class = "standard"` explicitly to keep that behavior.

See docs/adr/0119-decouple-scaleway-iam-application-api-key-rename-object-bucket.md for the full decision record (this PR covers only the `object-bucket` half of that ADR).

[#161](https://github.com/noisypigeon/noisypigeon/pull/161)

## [2.0.0] - 2026-10-04

### Fix object-bucket endpoint output to use the regional host, not the bucket vhost

The \`endpoint\` output previously returned \`scaleway_object_bucket.bucket.endpoint\`, which Scaleway's provider resolves to a bucket-specific virtual-hosted URL (bucket name baked into the host). Every known consumer of this output (e.g. the \`rclone\` wiring in \`scaleway/compute-instance\`) expects a bare regional S3 endpoint, with the bucket name supplied separately — so the old value didn't actually work for that use case.

This output is now computed directly from \`scaleway_object_bucket.bucket.region\` instead, returning \`https://s3.<region>.scw.cloud\`.

Any consumer that was relying on the bucket name being embedded in this URL will need to append it themselves going forward.

[#135](https://github.com/noisypigeon/noisypigeon/pull/135)

## [1.0.0] - 2026-10-02

### Move scaleway modules to top-level modules/, major release each

Moves `terraform/modules/scaleway/*` to top-level `modules/scaleway/*` and cuts a major release for every module, fixing the stale `noisypigeon/pigeon.git` repo name (a prior name of this same repo) to the real current name, `noisypigeon/noisypigeon.git`, in every source string along the way.

**Version bumps** (next available major per module, not a blanket v1.0.0 — two modules were already past 1.0):

| Module | Before | After |
|---|---|---|
| `project` | 0.2.1 | **1.0.0** |
| `object-bucket` | 0.2.0 | **1.0.0** |
| `iam-policy` | 1.1.1 | **2.0.0** |
| `compute-instance` | 0.9.1 | **1.0.0** |
| `block-volume` | 1.0.0 | **2.0.0** |

To make the existing automation compute these correctly (its version lookup is tag-prefix-based and all 22 existing tags live under the old `terraform/modules/scaleway/*` prefix), 5 bookkeeping-only seed tags mirroring each module's current version were pushed directly to origin under the new prefix before this PR — no GitHub Release, no CHANGELOG entry, just enough for `module-release.yml`'s `$LATEST` lookup to find a baseline.

**All 16 live consumers** across `terraform/infrastructure/scaleway/**` updated to the new repo name, new path, and new major tag — this also converges pre-existing version drift (`iam-policy` had one consumer on v0.1.0 against five on v1.1.1; `object-bucket` had three different pinned versions across seven consumers). Verified safe: every variable beyond the always-supplied required ones has a default in both modules, so no consumer needs a new argument added.

Also: `module-release.yml`/`module-docs.yml`'s hardcoded `terraform/modules/scaleway` paths, the `release-pr` skill's path references, `modules/README.md` (moved, repo name and tag-scheme examples fixed), and `terraform/README.md` deleted (its "two independent trees" premise no longer holds once `modules/` isn't under `terraform/`).

Checked every other repo in the `noisypigeon` org (`pigeon-cli`, `pigeon-os`, `dotfiles`) for external consumers — none found.

Full rationale in [ADR-0093](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0093-move-scaleway-modules-to-top-level-modules.md).

## Test plan
- [x] `terraform fmt -check -recursive` clean on `modules/` and `terraform/infrastructure/scaleway/`
- [x] `terragrunt hcl format --check` clean on `modules/`
- [x] `grep -rn "terraform/modules/scaleway\|noisypigeon/pigeon\.git"` returns nothing outside historical ADRs/CHANGELOGs
- [x] All 16 consumer leaves + 1 dead/commented reference verified updated
- [ ] User to run `terragrunt init` on affected leaves to confirm the new module source resolves correctly (not performed here — would need real credentials)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#120](https://github.com/noisypigeon/noisypigeon/pull/120)

## [0.2.0] - 2026-09-30

### Add force_destroy input to object-bucket

Adds a `force_destroy` input to the `scaleway/object-bucket` module, wired straight through to `scaleway_object_bucket`'s `force_destroy` argument. When set to `true`, this allows Terraform to delete all objects in the bucket (including locked objects) as part of destroying the bucket itself, rather than failing because the bucket isn't empty.

Defaults to `false`, matching the underlying provider's default, so existing callers of this module are unaffected unless they opt in.

[#101](https://github.com/noisypigeon/noisypigeon/pull/101)

## [0.1.1] - 2026-09-27

### fix(adr-0072): raise GLACIER transition to Scaleway's 90-day minimum

## Context

ADR-0044 designed `storage_class = \"glacier\"` as an immediate (`days = 0`) `lifecycle_rule` transition to `GLACIER`. Applying it against the one live consumer (`noisypigeon/vault/email`) fails outright:

```
Error: error applying lifecycle configuration to bucket vault-5t39z4-email:
... api error InvalidArgument: Transition rule for storage-class "GLACIER" must be at least 90 days
```

Scaleway rejects a `days = 0` GLACIER transition outright — the API enforces a 90-day minimum. `storage_class = "glacier"` never actually worked.

## Decision

- Set `transition.days = 90` in `bucket.tf` — the minimum Scaleway's API accepts.
- No input/output signature change — `release:patch`.

Full ADR: [`docs/adr/0072-fix-scaleway-object-bucket-glacier-transition-minimum-days.md`](../blob/fix-scaleway-object-bucket-glacier-transition-minimum-days/docs/adr/0072-fix-scaleway-object-bucket-glacier-transition-minimum-days.md)

## Test plan

- [x] `terraform validate` passes on the module.
- [x] `terraform fmt -check` passes.
- [x] `mise run ci` (Rust gate) passes — unaffected by this change.
- [ ] `terragrunt apply` for `vault/email` with the new module version (to be run after merge, with live credentials).

[#77](https://github.com/noisypigeon/noisypigeon/pull/77)

## [0.1.0] - 2026-09-26

### Consolidate as terraform/modules/scaleway/object-bucket 0.1.0

A Scaleway Object Storage bucket (`scaleway_object_bucket`) with a
namespaced, randomized name (`{namespace}-{random}-{name}`, matching
`standard-storage-bucket`'s scheme), a versioning toggle
(`enable_versioning`), and a `storage_class` input (`standard`/`glacier`,
implemented via an immediate `lifecycle_rule` transition when set to
`glacier`). See
[ADR-0044](../../../../docs/adr/0044-add-scaleway-object-bucket-module.md)
and
[ADR-0045](../../../../docs/adr/0045-scaleway-object-bucket-namespaced-naming.md)
for the full set of decisions behind this module's design.

Consolidates this module's prior `pigeon-tf` version history (`v0.1.0`,
`v1.0.0`) into a single 0.1.0 release as part of merging `pigeon-tf` into
this repo — see
[ADR-0037](../../../../docs/adr/0037-merge-pigeon-tf-terraform-modules.md)
for the merge.
