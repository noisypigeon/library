# DEV-0132: `workloads/noisypigeon.com` Terraform self-sufficiency and GitHub Pages cutover

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-05.
- **Status**: Accepted.

## Context

ADR-0130/0131 gave `pigeon.dev` the first dedicated Terraform bootstrap in this repo (own state bucket, own deployer IAM, own Scaleway project, own `root.hcl`/`secrets.enc`), explicitly scoped to `pigeon.dev` only. `noisypigeon.com` — the actual blog, previously `workloads/blog/src/` plus four Cloudflare DNS leaves under the shared `workloads/management/terraform/cloudflare/noisypigeon.com/`, hosted on GitHub Pages — is the second adopter of that same pattern, unlike `pigeon.dev` it moves a workload with real, live production traffic and live email, not a fresh build-out.

Unlike `pigeon.dev`, `noisypigeon.com` gets a genuinely **new** dedicated Scaleway project (`noisypigeon-com`) rather than reusing an existing one, and its `terraform/` tree groups by sub-service (`blog`, `bluesky`, `proton`, `google-search`) instead of the resource-type grouping the shared bootstrap used.

## Decision

### Dedicated bootstrap: `workloads/noisypigeon.com/terraform/{project,state/bucket,state/iam}`

Same shape as `pigeon.dev`'s to start: `project` creates a fresh Scaleway project (`noisypigeon-com`), resolving via plain `find_in_parent_folders("root.hcl")` throughout (shared root before this workload's own `root.hcl` exists, then automatically the dedicated one once it does — no state migration needed at creation time, only once, after `root.hcl` lands — see below). `state/iam` deliberately keeps the **explicit** `include { path = "${get_repo_root()}/workloads/root.hcl" }` (not `find_in_parent_folders`), staying pinned to the shared bootstrap forever: it manages only IAM resources (application/policy/API-key), authorized via ordinary org-level IAM policy grants the shared deployer already has, so there's no reason to move it and no circularity concern either way. Its deployer gets `ObjectStorageFullAccess` scoped to the new project plus `ProjectManager`/`IAMManager`/`IAMApplicationManager` at the organization level — baked in from the start this time, since ADR-0130's PR #205 already found this necessary for the identical pattern.

`state/bucket` initially followed the same explicit-shared-root pin as `pigeon.dev`'s equivalent leaf — but this turned out to be a real bug, not just an accepted gap; see below for why it was changed to resolve via `find_in_parent_folders` instead, same as `project`.

### New `workloads/noisypigeon.com/root.hcl` + `secrets.enc`

Line-for-line the same structure as `pigeon.dev`'s: plain `scaleway_project_id` local, `remote_state.key` with no `workloads/` prefix, `is_valid_leaf` one path segment shallower than the shared root, no per-domain Cloudflare credential branching (single-domain root). `secrets.enc` uses the same age recipient as every other `workloads/*/secrets.enc` — `.sops.yaml`'s existing generic creation rule already covered a second consumer, no change needed there.

### A real, pre-existing bug found — and fixed, for this workload

Creating `state/bucket`'s bucket via the shared deployer failed with `AccessDenied` on `CreateBucket` until the shared deployer's `project_ids` temporarily included the new project (reverted immediately after, mirroring `pigeon.dev`'s PR #204→#206 two-phase approach). More significantly: even after that grant, every subsequent S3-level read (`HeadBucket`, `GetBucketCors`) against the new bucket kept failing with `403 Forbidden` using the shared deployer's credentials — not a propagation delay (confirmed via direct `curl` against the IAM API that the policy update had taken effect immediately), but a structural limitation: the shared deployer's `iam-api-key` (module `v0.1.0`, no `default_project_id`) is bound to exactly one project for S3 purposes, and IAM policy `project_ids` grants don't override that for actual S3 REST calls — only for control-plane actions like `CreateBucket`. A freshly-minted key with `default_project_id` set to the new project (the `iam-api-key/v0.2.0` behavior `state/iam` and `blog/iam` both use) worked immediately against the same bucket. Confirmed this is not new: `pigeon.dev`'s own `workloads/pigeon.dev/terraform/state/bucket` leaf, re-plan'd live during this work, fails identically with the shared deployer today — a latent gap in ADR-0130's own bootstrap that nobody had re-triggered since.

This surfaced as more than a cosmetic gap: this repo's `terragrunt-apply.yml` required status check (ADR-0129) actually tried to apply `state/bucket` against the PR and failed outright with the same `CreateBucket` `AccessDenied`, since the leaf's own state had no record of the bucket at all. The fix: the explicit shared-root pin only exists to avoid a circular backend dependency *before* the dedicated bucket exists — once it exists (it does, created live during this bootstrap), storing `state/bucket`'s own state *inside the bucket it manages* is no longer circular; it's the exact same self-referential pattern the repo-wide shared bootstrap leaf (`workloads/management/terraform/scaleway/`) already uses for itself. So `state/bucket`'s `terragrunt.hcl` was switched from the explicit include to plain `find_in_parent_folders("root.hcl")` (same as `project`), its `bucket.tf`'s `project_id` reference updated from the shared root's suffixed `local.scaleway_project_id_noisypigeon_com` to the dedicated root's plain `local.scaleway_project_id`, and its pre-existing state (just `random_string.suffix`, since every import attempt against the bucket itself had failed) migrated from the shared bucket into the dedicated one it now governs. The bucket then imported cleanly on the first attempt using the dedicated deployer, no further workarounds needed. `state/iam` needed no equivalent change — see above.

An earlier attempt at a different fix (keeping the shared-root pin for backend, while adding a leaf-local `generate "provider"` block to override just the credentials) turned out to be a dead end: Terragrunt hard-errors on a child `generate` block sharing a label with one inherited from its `include` (`Detected generate blocks with the same name`, confirmed via its own source, `pkg/config/errors.go`) — contrary to what its own documentation implies, this is not overridable via `merge_strategy`.

The identical fix (switching its `state/bucket` to `find_in_parent_folders` plus a one-time state migration) would resolve `pigeon.dev`'s equivalent gap too — not done here, out of scope, since that workload wasn't otherwise touched by this PR.

### `blog/bucket`, `blog/iam`

`blog/bucket`: `object-bucket/v4.1.1`, `exact_name = "noisypigeon.com"` (must match exactly — Scaleway's bucket-website gateway resolves by `Host` header), `enable_website`/`enable_public_read`. `blog/iam`: a deploy-scoped application/policy/key (`ObjectStorageFullAccess` on the new project only), separate from `state/iam`'s full Terraform-deployer key — mirrors `pigeon.dev/terraform/wiki/iam` exactly. Its key's access/secret became the `NOISYPIGEON_COM_SCW_ACCESS_KEY`/`SECRET_KEY` GitHub Actions secrets.

### GitHub Pages → Scaleway bucket cutover

`.github/workflows/blog-pages.yml` (two-job GitHub Pages deploy) replaced by `.github/workflows/noisypigeon-com-deploy.yml`, a single job mirroring `pigeon-dev-pages.yml`'s shape (`zola build` → `aws s3 sync public s3://noisypigeon.com ... --acl public-read --delete`) plus the two blog-specific build steps (`resolve-theme.sh`, `generate-module-redirects.sh`) `blog-pages.yml` already had. The `--acl public-read` flag is carried over deliberately — easy to miss, and the exact fix `pigeon.dev`'s own deploy needed after its bucket ACL alone didn't propagate to synced objects (commit `8e8ee08`).

Sequenced to avoid downtime: the bucket was populated and verified correct via its own website endpoint (`curl -H "Host: noisypigeon.com" http://noisypigeon.com.s3-website.fr-par.scw.cloud/`) entirely before touching DNS — zero production exposure until the DNS leaf itself was applied.

### `blog/dns` cutover — content change, not just a move

Mirrors `pigeon.dev/terraform/wiki/dns` exactly: apex becomes a Cloudflare-**proxied** CNAME → the bucket's website endpoint (the endpoint has no valid TLS cert for the custom hostname, so Cloudflare must terminate TLS), replacing the former DNS-only CNAME to `noisypigeon.github.io`. `www` becomes a placeholder proxied CNAME → the apex itself, plus a new `cloudflare_ruleset` (`http_request_dynamic_redirect` phase) 301-redirecting `www.noisypigeon.com` → `https://noisypigeon.com` — a direct `www` CNAME to the website endpoint would 404 with `NoSuchBucket`, since Scaleway resolves the bucket from the `Host` header, not the CNAME target (the same finding ADR-0130 made for `pigeon.dev`).

The state migration for this leaf used `terraform state mv` to rename the pulled `cloudflare_dns_record.www_cname` → `cloudflare_dns_record.placeholder_www` *before* pushing, so the live apply was two clean in-place attribute updates (same resource IDs throughout) plus one new ruleset — never a destroy+recreate. Verified live post-apply: `noisypigeon.com` resolves through Cloudflare and serves the site (HTTP 200); `www.noisypigeon.com` 301s to the apex.

### Safety procedure (ADR-0130's documented lesson, applied again)

For all four migrated leaves (`bluesky/dns`, `google-search/dns`, `proton/dns`, `blog/dns`) — pulled state from the old `workloads/management/terraform/cloudflare/noisypigeon.com/*` path, pushed to the new path, verified a clean plan at the new path (identical resource IDs, no destroy/recreate), then pushed an empty Terraform state into the *old* path and verified its plan showed `0 to destroy` before deleting the old directory. `proton/dns` additionally needed a `terraform state replace-provider` (`registry.opentofu.org/cloudflare/cloudflare` → `registry.terraform.io/cloudflare/cloudflare`) — a legacy artifact of that one leaf having been applied with raw `tofu` at some earlier point, unrelated to this migration but discovered while performing it.

### `workloads/blog/` fully decommissioned

`src/`, `CHANGELOG.md`, and `generate-module-redirects.sh` all moved into `workloads/noisypigeon.com/`; `.mise.toml`'s `blog-build`/`blog-serve` tasks, `.gitignore`'s blog-scoped entries, and root `CHANGELOG.md`'s link updated accordingly. `.github/workflows/blog-changelog.yml`'s path filter and internal paths updated to the new location; its and `template-release.yml`'s `gh workflow run blog-pages.yml` calls retargeted at `noisypigeon-com-deploy.yml`.

### Shared `management/terraform/scaleway/iam.tf` needed no permanent change

Unlike `pigeon.dev` (which had an actual grant to remove from the shared deployer's policy once self-sufficient), `noisypigeon.com`'s DNS leaves had never held any Scaleway resource under the shared project — only Cloudflare DNS records. The only touch to this file was the temporary bootstrap grant described above, reverted in the same session.

## Consequences

- `noisypigeon.com` can rotate its own deployer credentials, resize or relocate its own state bucket and content bucket, and manage its own secrets independently of every other workload.
- `state/bucket` and `state/iam` end up on *different* roots (self-governing and shared-forever, respectively) — a deliberate asymmetry, not an inconsistency, following from the different resource types each leaf manages.
- `noisypigeon.com` is now served from a Scaleway Object Storage bucket behind Cloudflare, not GitHub Pages — GitHub Pages' custom-domain setting for this repo should be disabled now that DNS no longer points at it (manual, GitHub-settings-level step, tracked separately; confirmed no other workload in this repo uses GitHub Pages).
- `workloads/blog/` no longer exists.

## Out of scope

- Fixing the shared deployer's underlying `iam-api-key`/S3-cross-project-access limitation itself (upgrading its module version, or any change to `workloads/management/terraform/scaleway/`) — `noisypigeon.com`'s own `state/bucket` leaf worked around it by moving to self-governance instead; the shared deployer's limitation remains, pre-existing and unrelated to this workload specifically.
- Retroactively repairing `pigeon.dev/terraform/state/bucket`'s identical gap using the same fix — straightforward to apply there too, not done here since that workload wasn't otherwise touched by this PR.
- Retrofitting any other workload with this self-sufficiency pattern.
