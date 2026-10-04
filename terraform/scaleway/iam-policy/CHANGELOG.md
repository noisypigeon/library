# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.1] - 2026-10-04

### Shorten iam-policy generated application name suffix

Changes the generated \`scaleway_iam_application\` name from \`${var.name}-application\` to \`${var.name}-app\`, keeping names shorter and more consistent with other modules' naming conventions.

This updates the application's \`name\` attribute for every existing consumer of this module on next apply — no input or output changes.

[#134](https://github.com/noisypigeon/noisypigeon/pull/134)

## [2.0.0] - 2026-10-02

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

## [1.1.1] - 2026-09-27

### fix(adr-0070): downgrade admin bucket-policy statement to a supported version

## Context

`v1.1.0`'s `admin_project_id` statement (ADR-0069) used `Version = "2023-04-17"`, which rejects `project_id:` principals. The first live field-test (`tofu apply` against `noisypigeon/cli/scratch`) failed:

```
Error: error putting SCW bucket policy: ... MalformedPolicy: project_id Principal is deprecated
and only supported in the bucket-policy version 2012-10-17
```

Confirmed against Scaleway's own `terraform-provider-scaleway` docs: `2012-10-17` accepts the exact same Statement shape (Sid/Effect/Principal/Action/Resource) with a `project_id:` principal; `2023-04-17` only accepts `application_id:`/`user_id:`/wildcard principals. So `admin_project_id`'s mechanism was broken from the start for any bucket-scoped caller that set it.

## Decision

- Downgrade the whole generated policy document to `Version = "2012-10-17"`. No input/output signature change — `admin_project_id`'s name/type/default are untouched.
- `README.md` gets a note explaining the version downgrade and its trade-off (Scaleway documents `2012-10-17` as deprecated; the non-deprecated alternative — naming the deployer's `application_id` instead of its project — is deferred, since it needs new cross-leaf plumbing).
- `cli/scratch/iam.tf` and `vault/email/iam.tf` bump their module `ref` from `v1.1.0` to `v1.1.1`.
- `release:patch` — pure bugfix, no interface change.

Full ADR: [`docs/adr/0070-fix-scaleway-iam-policy-admin-statement-deprecated-version.md`](../blob/adr-0070-fix-scaleway-iam-policy-admin-statement-deprecated-version/docs/adr/0070-fix-scaleway-iam-policy-admin-statement-deprecated-version.md)

## Out of scope

- Switching to an `application_id:`-based admin principal — the non-deprecated alternative, deferred pending new plumbing for the deployer's application id.
- Recovering the already-locked-out `noisypigeon/cli/scratch` bucket — still a separate, pending manual step (owner-credentialed `aws s3api delete-bucket-policy`).

## Test plan

- [x] `terraform validate` passes on the module.
- [x] `terraform fmt -check` passes on all changed files.
- [x] `mise run ci` (Rust gate) passes — unaffected by this change.
- [ ] `terragrunt apply` for `cli/scratch` and `vault/email` with the new ref (requires live Scaleway credentials, and the pending owner-side recovery for `cli/scratch` — to be run after merge).

[#73](https://github.com/noisypigeon/noisypigeon/pull/73)

## [1.1.0] - 2026-09-27

### feat(adr-0069): guard scaleway/iam-policy against bucket-policy self-lockout

## Context

Every `scaleway/*` leaf authenticates as one identity: the `noisypigeon/terraform` leaf's self-managed deployer IAM application. `terraform/modules/scaleway/iam-policy/bucket_access.tf` writes each bucket's `scaleway_object_bucket_policy` naming only the module's own freshly-minted, narrow `scaleway_iam_application` as `Principal`. Scaleway bucket policies are allow-only: the moment any bucket policy exists, every other principal — including the deployer running Terraform — loses access to that bucket unless also named, and only the literal Organization Owner is exempt from that. Applying this module's bucket-scoped grant therefore locks the deployer itself out of the bucket it just configured, recoverable only via owner-credentialed `aws s3api delete-bucket-policy` — exactly what happened against `noisypigeon/cli/scratch`.

This is distinct from ADR-0066, which guards the narrow key's own scope, not the applier's continued access.

## Decision

- Add an optional `admin_project_id` variable to `terraform/modules/scaleway/iam-policy`. When set, `bucket_access.tf` appends a second `Allow` statement (`Principal = { SCW = "project_id:<id>" }`, `Action = ["s3:*"]`) to the generated bucket policy, so any principal with IAM permissions in that project — the deployer included — always retains access.
- Wire `admin_project_id = local.scaleway_project_id_noisypigeon` at both live bucket-scoped consumers (`noisypigeon/cli/scratch`, `noisypigeon/vault/email`), bumping their module `ref` to `v1.1.0`.
- Update the module README's usage example accordingly.
- Additive/backward-compatible (`release:minor`).

Full ADR: [`docs/adr/0069-guard-scaleway-iam-policy-bucket-policy-self-lockout.md`](../blob/adr-0069-guard-scaleway-iam-policy-bucket-policy-self-lockout/docs/adr/0069-guard-scaleway-iam-policy-bucket-policy-self-lockout.md)

## Out of scope

- Recovering the already-locked-out `noisypigeon/cli/scratch` bucket — a one-time manual step (owner-credentialed `aws s3api delete-bucket-policy`, then a clean `terragrunt apply`), independent of this code fix.
- Enforcing `admin_project_id` via validation whenever `bucket_names` is set — left as a documented convention, not a hard requirement.

## Test plan

- [x] `terraform validate` passes on the module.
- [x] `terraform fmt -check` passes on all changed files.
- [x] `mise run ci` (Rust gate) passes — unaffected by this change.
- [ ] `terragrunt plan` for `cli/scratch` and `vault/email` (requires live Scaleway credentials — to be run before merge).

[#71](https://github.com/noisypigeon/pigeon/pull/71)

## [1.0.0] - 2026-09-27

### feat(adr-0066): guard scaleway/iam-policy against bucket-scope widening

## Context

`terraform/modules/scaleway/iam-policy` has supported bucket-scoped access (`bucket_names`/`bucket_actions`) independently of org/project grants since ADR-0049. But the one real prior attempt to use it for a read-only bucket key — the commented-out `terraform/infrastructure/scaleway/fr-par/pigeon.dev/scratch/iam.tf` (merged in verbatim from `pigeon-do` via ADR-0052) — combined `bucket_names` with a blanket project-level `ObjectStorageObjectsRead`/`ObjectStorageObjectsWrite` grant in the same call. Since Scaleway IAM rules are allow-only with no explicit deny (per ADR-0048's own findings), that blanket grant already covers every bucket in the project, making the bucket restriction decorative — exactly the "composition hazard" ADR-0048 documented but explicitly declined to enforce in code.

## Decision

- Add a cross-variable `validation` block on `bucket_names` rejecting any call that combines it with an `ObjectStorage*`-family `organization_permission_sets`/`project_permission_sets` entry — verified against the exact broken prior-art pattern (now correctly rejected at `plan` time), the one live consumer (`noisypigeon.com/terraform/iam.tf`, unaffected since it never sets `bucket_names`), and the intended bucket-scoped read-only pattern (passes cleanly).
- Document the correct bucket-scoped, read-only usage pattern in the module `README.md`.
- Breaking release → `release:major`, next tag `terraform/modules/scaleway/iam-policy/v1.0.0`.
- Full ADR: [`docs/adr/0066-scaleway-iam-policy-prevent-bucket-scope-widening.md`](../blob/adr-0066/scaleway-iam-policy-bucket-scope-guard/docs/adr/0066-scaleway-iam-policy-prevent-bucket-scope-widening.md)

## Also included

- A pre-existing `terraform fmt` alignment fix in `iam_policy.tf` (`dynamic "rule"` blocks), picked up incidentally while format-checking the module — unrelated to the validation change itself.
- A fix to `.mise.toml`: the ADR-0052 merge left `pigeon-do`'s terraform `fmt`/`fmt-check` tasks under the same names as the pre-existing Rust tasks (duplicate TOML keys), which broke `mise`'s ability to parse its own config at all — blocking `mise run ci` and every other `mise run` command repo-wide. Renamed to `fmt-terraform`/`fmt-check-terraform`, matching what `CLAUDE.md`'s Commands section already documented.

## Test plan

- [x] `terraform validate` passes on the module.
- [x] `terraform plan` with the broken prior-art pattern (`bucket_names` + `ObjectStorageObjectsRead`/`Write`) fails validation with the new error message.
- [x] `terraform plan` with the live `noisypigeon.com/terraform/iam.tf` pattern (org/project grants, no `bucket_names`) still plans cleanly.
- [x] `terraform plan` with the intended read-only bucket-scoped pattern (`bucket_names` + `bucket_actions = ["s3:ListBucket", "s3:GetObject"]`, no org/project grant) plans cleanly.
- [x] `mise run ci` passes.

[#64](https://github.com/noisypigeon/pigeon/pull/64)

## [0.1.0] - 2026-09-26

### Consolidate as terraform/modules/scaleway/iam-policy 0.1.0

A Scaleway `scaleway_iam_application` and `scaleway_iam_policy` wrapper that
produces a permission-scoped `scaleway_iam_api_key`. Access can be granted
independently at three scopes — organization (`organization_id` +
`organization_permission_sets`), project (`project_ids` +
`project_permission_sets`), and specific Object Storage buckets
(`bucket_names`, a map of static logical key → bucket name, +
`bucket_actions`, validated against a known set of S3 actions) — with at
least one scope required but none individually mandatory; the underlying
`scaleway_iam_policy` resource and its `rule` blocks are created only when a
scope is fully populated. An optional `expires_at` input sets an expiration
timestamp on the minted API key. Requires Terraform/OpenTofu `>= 1.9.0` for
its cross-variable `validation` block. See
[ADR-0046](../../../../docs/adr/0046-add-scaleway-iam-policy-module.md)
through
[ADR-0049](../../../../docs/adr/0049-scaleway-iam-policy-optional-scopes.md)
for the full set of decisions behind this module's design.

Consolidates this module's prior `pigeon-tf` version history (`v0.1.0`
through `v3.0.1`) into a single 0.1.0 release as part of merging `pigeon-tf`
into this repo — see
[ADR-0037](../../../../docs/adr/0037-merge-pigeon-tf-terraform-modules.md)
for the merge.
