# DEV-0098: move the custodian buckets to `workloads/custodian-buckets/terraform/`, decommission `terraform/` entirely

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

Two Scaleway leaves were the last ones left anywhere under `terraform/infrastructure/scaleway/` — every other leaf had already moved into `workloads/` across ADR-0094, ADR-0096, and ADR-0097:

- `fr-par/noisypigeon/custodian/dhj` — a glacier-class object-storage bucket plus IAM application/policy/key. Its `compute.tf` is entirely commented out, but the comment describes a sync job copying `dhj`'s bucket (source) to a second bucket (destination) over `s3.nl-ams.scw.cloud`, naming that destination via `local.custodian_dj_bucket_name` — i.e. `dhj` is the import/source side of a cross-region backup pair.
- `nl-ams/custodian/dj` — the destination side: same bucket/IAM shape, in Scaleway's `nl-ams` region (added to this repo by ADR-0080), and the only leaf in this repo's history to use a region other than `fr-par`.

The user wanted both relocated into `workloads/custodian-buckets/terraform/` as `duck-jellyfish-import` (was `dhj`) and `duck-jellyfish` (was `dj`), with both files and state migrated in the same pass (not deferred), and asked specifically that the nl-ams region be "respected" via a `workload_definition.hcl`-style per-leaf override file — `workloads/root.hcl`'s Scaleway provider block has been hardcoded to `fr-par`/`fr-par-1` since ADR-0094, on the stated assumption that no `workloads/*/terraform` leaf needed a different region yet. With both leaves gone, `terraform/infrastructure/scaleway/root.hcl` had zero remaining consumers, and the user asked for the entire `terraform/` directory to be removed — completing the migration arc this session's ADR-0092→0097 chain had been building toward.

**Research confirmed, verbatim, before planning anything:**

- `dhj`'s active resources only need `local.scaleway_project_id`, already wired by ADR-0094. Its commented-out `compute.tf` references `local.custodian_dj_bucket_name` and `local.ssh_key_public_key` — moved unchanged; dead code either way, nothing to resolve.
- `dj`'s `bucket.tf` actively sets `name = local.custodian_dj_name` — a real gap. That local is produced only by `terraform/infrastructure/scaleway/root.hcl`'s generic `generate "bucket_names"` block (every `ENV_SW_*`-prefixed `.env` var becomes a lowercased, prefix-stripped Terraform local), a mechanism ADR-0094 deliberately never ported to `workloads/root.hcl` ("kept out... to stay minimal"). Porting the *whole* generic mechanism now would have collided: `ENV_SW_SSH_KEY_ALIAS`/`ENV_SW_SSH_KEY_PUBLIC_KEY` are also `ENV_SW_*`-prefixed, and `workloads/root.hcl` already hand-generates `ssh_key_alias`/`ssh_key_public_key` as locals elsewhere — the generic mechanism would redefine them a second time in a different generated file, a genuine Terraform "duplicate local" error. So only the one concrete local actually needed, `custodian_dj_name`, was added, consistent with the existing "wire only what's needed" philosophy.
- A repo-wide grep for `dependency`/`dependencies` Terragrunt blocks found none referencing either leaf's outputs.
- Neither `modules/scaleway/object-bucket` nor `modules/scaleway/iam-policy` hardcodes a region or zone internally — both inherit entirely from the configured provider, so fixing the **provider** block per leaf was sufficient; no module changes needed.
- `workloads/root.hcl`'s `remote_state` block's own `region = "fr-par"` is the **state bucket's** fixed location (same today for every leaf regardless of the leaf's own resource region) — unrelated to a leaf's provider region and left untouched.
- Deleting `terraform/.gitignore` and `terraform/infrastructure/.gitignore` would have silently dropped two patterns the root `.gitignore` didn't already carry: `.terraform/` and `*.tfstate*` (it already had `.terraform.lock.hcl` and `.terragrunt-cache/`, which match at any depth regardless of which `.gitignore` declares them). Both were ported into the root `.gitignore` before deleting the nested ones.

## Decision

### Domain-nested... no — leaf-sibling override: `workload_definition.hcl`

```
workloads/custodian-buckets/terraform/
  duck-jellyfish-import/   # fr-par, no override file -- default applies
    terragrunt.hcl bucket.tf iam.tf compute.tf (commented)
  duck-jellyfish/
    workload_definition.hcl   # <- new
    terragrunt.hcl bucket.tf iam.tf
```

`workload_definition.hcl` is a plain Terragrunt-config-shaped file — just a `locals` block, no `include`/`terraform` block needed — sitting directly in the leaf's own directory:

```hcl
locals {
  scaleway_region = "nl-ams"
  scaleway_zone   = "nl-ams-1"
}
```

`workloads/root.hcl` reads it via Terragrunt's built-in `read_terragrunt_config(path, default)`, which returns the given default untouched if the path doesn't exist — no error, zero behavior change for every leaf that doesn't have one:

```hcl
workload_dir             = dirname(find_in_parent_folders("root.hcl"))
workload_definition_path = "${local.workload_dir}/${path_relative_to_include()}/workload_definition.hcl"
workload_definition      = read_terragrunt_config(local.workload_definition_path, { locals = {} })
scaleway_region          = lookup(local.workload_definition.locals, "scaleway_region", "fr-par")
scaleway_zone            = lookup(local.workload_definition.locals, "scaleway_zone", "fr-par-1")
```

The leaf's absolute directory is deliberately computed from two primitives already proven correct elsewhere in this exact file — `find_in_parent_folders("root.hcl")` (used for `.env` discovery) and `path_relative_to_include()` (used for the remote-state key) — rather than `get_terragrunt_dir()`, whose behavior when called from *within* an included root config (parent-scope vs. child-scope) wasn't confidently known and wasn't worth risking getting wrong here. The existing `generate "provider"` block's `provider "scaleway"` now reads `zone = "${local.scaleway_zone}"` / `region = "${local.scaleway_region}"` instead of the old hardcoded `"fr-par-1"`/`"fr-par"`.

This is a generically reusable pattern, not special-cased to region/zone — a future leaf needing some other per-leaf override can drop its own `workload_definition.hcl` and have `workloads/root.hcl` read additional keys from it the same way.

**Verified, not assumed**: `terragrunt init` on an untouched leaf (`workloads/blog/terraform`) still rendered `zone = "fr-par-1"` / `region = "fr-par"` (no regression). `terragrunt init` on `duck-jellyfish` rendered `zone = "nl-ams-1"` / `region = "nl-ams"` (override working). Both checked by grepping only the `zone`/`region` lines out of the generated `provider_generated.tf` — **a first attempt at this check accidentally also printed the real `access_key`/`secret_key` lines into the session**, a genuine credential-exposure slip consistent with the kind this session has otherwise been careful to avoid; caught immediately, the values were this repo's own Scaleway deployer credentials (not a third-party leak), and every check after that one scoped the grep to `^\s*(zone|region)\s*=` only.

### `custodian_dj_name` added to `workloads/root.hcl`

Folded into the existing `generate "scaleway_ids"` block, not a new mechanism:
```hcl
custodian_dj_name = "${get_env("ENV_SW_CUSTODIAN_DJ_NAME", lookup(local.secrets, "ENV_SW_CUSTODIAN_DJ_NAME", ""))}"
```

### The move

```sh
git mv terraform/infrastructure/scaleway/fr-par/noisypigeon/custodian/dhj workloads/custodian-buckets/terraform/duck-jellyfish-import
git mv terraform/infrastructure/scaleway/nl-ams/custodian/dj             workloads/custodian-buckets/terraform/duck-jellyfish
```
Both one at a time, each verified with `find` immediately after — per ADR-0097's documented gotcha. This time a *second*, related gotcha surfaced: `workloads/custodian-buckets/terraform/{duck-jellyfish,duck-jellyfish-import}` already existed on disk as empty, untracked directories (left over from outside this session, unrelated to any tool call here) *before* either `git mv` ran. Since `git mv sourcedir destdir` nests the source inside an **existing** `destdir` rather than renaming onto it, these had to be `rmdir`'d first — confirmed empty, so safe — before the moves, or the same double-nesting bug from ADR-0097 would have recurred, this time for a different root cause (pre-existing directory, not a batching/ordering issue).

### State migration — both leaves, performed live

Same worktree-based `state pull`/`push` runbook as ADR-0094/0096/0097 (worktree at HEAD, `.env` copied in, new key confirmed empty before pushing). Both leaves pulled 5 resources each (`random_string`, `scaleway_object_bucket`, `scaleway_iam_api_key`, `scaleway_iam_application`, `scaleway_iam_policy`) and both showed **"No changes."** after the push — for `duck-jellyfish` specifically, this is also the strongest possible proof the region/zone override actually works end-to-end against the real Scaleway API: a wrong region would have made the API fail to find the bucket/IAM resources at all (a 404/not-found class of error), not merely show a diff.

### `terraform/` deleted entirely

```sh
git rm terraform/.gitignore terraform/infrastructure/.gitignore terraform/infrastructure/README.md terraform/infrastructure/scaleway/root.hcl
```
(after porting `.terraform/` and `*.tfstate*` into the root `.gitignore`, see above). With both custodian leaves moved out, `scaleway/fr-par/noisypigeon/custodian/` and `scaleway/nl-ams/custodian/` were already empty; removing the four remaining tracked files and their now-empty parent directories leaves nothing under `terraform/` at all — confirmed via `git ls-files terraform` (empty) and the directory itself absent from disk.

## Consequences

- `workloads/` (alongside `modules/`) is now this repo's entire live Terraform/Terragrunt surface. `mise run plan`/`apply`'s `terragrunt run --all` from the repo root now only ever sweeps `workloads/`.
- Any future need for a Scaleway region other than `fr-par` or `nl-ams` is just another `workload_definition.hcl` — no further `workloads/root.hcl` change required.
- `CLAUDE.md`, `docs/USAGE.md`, `modules/README.md`, and `workloads/README.md` all needed their `terraform/infrastructure/` references fixed or removed (done as part of this change) — historical ADR-summary bullets describing what earlier ADRs did at the time were left untouched.
- The two leaves' old-backend-key state objects (`scaleway/fr-par/noisypigeon/custodian/dhj/terraform.tfstate`, `scaleway/nl-ams/custodian/dj/terraform.tfstate`) are now orphaned — the real Scaleway resources themselves are completely untouched; only their old Terraform-tracked state entries are abandoned.

## Out of scope

- Deleting the two leaves' orphaned old-backend-key state objects — optional cleanup, left to the user's discretion and timing, same treatment every prior ADR here has given its own orphaned state object.
- Uncommenting `duck-jellyfish-import`'s dormant `compute.tf` sync job — unchanged, still dead code, not something this move touches.
