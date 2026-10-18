# DEV-0092: move the GitHub Pages Cloudflare leaf to `workloads/blog/terraform`, add `workloads/root.hcl`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`terraform/infrastructure/` is provider-rooted (ADR-0061): one `root.hcl` per provider, each covering many domains/leaves. This ADR starts a second, parallel convention for `workloads/`: terraform colocated with the resource it belongs to — `workloads/<name>/terraform/` sitting next to `workloads/<name>/src/` (ADR-0091 already established the `src/` half for the blog). This is that convention's first leaf.

**What moved**: `terraform/infrastructure/cloudflare/global/noisypigeon.com/github/` → `workloads/blog/terraform/`. Two files, unchanged in content — `terragrunt.hcl` (standard boilerplate) and `cname.tf` (two `cloudflare_dns_record` resources, apex + `www` → `noisypigeon.github.io`, referencing `local.cloudflare_noisypigeon_com_zone_id`, a local injected by the provider root rather than defined in the leaf itself).

**Two things discovered only during implementation, not anticipated in planning:**

1. **Terragrunt's `skip` attribute is deprecated and no longer accepted inside an included config in this repo's Terragrunt version (v1.1.6).** The original plan used `skip = !local.is_valid_leaf` in `workloads/root.hcl` to enforce the `workloads/*/terraform` convention; this failed outright with "An argument named `skip` is not expected here." Confirmed via Terragrunt's own docs: `skip` was replaced by an `exclude { if = ...; actions = [...] }` block, which — confirmed by direct testing — **does** work correctly when set inside a `root.hcl` included by leaf `terragrunt.hcl` files, and is honored by `terragrunt run --all` (not by a direct single-unit invocation, which is the intended scope here: the whole point is protecting `mise run plan`/`apply`'s repo-wide sweep, not blocking someone deliberately `cd`-ing into a bad directory).

2. **The shared secrets file wasn't actually at the "true repo root."** Research during planning (incorrectly) reported `.env`/`.env.example` living at the true repo root per ADR-0063's text. Direct verification during implementation found the real files at `terraform/infrastructure/.env`/`.env.example` instead — ADR-0063's "repo root" language was accurate when written (as `pigeon-do`'s own, then-standalone ADR), but was never re-contextualized after ADR-0052 merged that repo in as `terraform/infrastructure/`, which mechanically shifted what was "pigeon-do's repo root" one level deeper. Since `workloads/` is a sibling of `terraform/`, not nested under it, `workloads/root.hcl`'s upward directory walk (`find_in_parent_folders(".env", "")`) never passes through `terraform/infrastructure/` and couldn't find the file there. Raised with the user directly: move `.env`/`.env.example` to the actual true repo root now, finally realizing what ADR-0063 originally intended, rather than having `workloads/root.hcl` reach across trees via an explicit path.

**A related gap found and fixed while moving the file**: the real `.env` was protected from accidental `git add` only by a `*.env` rule in a separate, nested `terraform/infrastructure/.gitignore` — not by the root `.gitignore`, which had no `.env` pattern at all. Moving `.env` out of that directory would have left it with zero gitignore protection at its new location; the root `.gitignore` gained a `*.env` line to cover it.

## Decision

### Move `.env`/`.env.example` to the true repo root

`mv terraform/infrastructure/.env .env` (untracked, plain `mv`) and `git mv terraform/infrastructure/.env.example .env.example`. No code changes needed in `cloudflare/root.hcl` or `scaleway/root.hcl` — both already use `find_in_parent_folders(".env", "")`, which simply walks one level further up now and finds the same file at its new location. Root `.gitignore` gains `*.env`; `terraform/infrastructure/.gitignore`'s own `*.env` line is left in place (harmless, covers any stray future file there).

### New `workloads/root.hcl`

Mirrors `cloudflare/root.hcl`'s secrets-loading/`generate`/`remote_state` shape, simplified: no pigeon.dev branching (workloads/ is inherently noisypigeon.com-scoped), no Scaleway provider block (nothing under `workloads/` needs it yet — add when a future workload does, per this repo's established "add a knob only when something needs it" pattern). Reuses the same Scaleway S3-compatible backend as `terraform/infrastructure/`, under a `workloads/` state-key prefix instead of `cloudflare/`.

The path-enforcement rule, using `exclude` (not the deprecated `skip`):

```hcl
locals {
  path_segments = split("/", path_relative_to_include())
  is_valid_leaf = length(local.path_segments) == 2 && local.path_segments[1] == "terraform"
}

exclude {
  if      = !local.is_valid_leaf
  actions = ["all_except_output"]
}
```

**Confirmed working by direct test**, not assumed: a disposable `workloads/blog/wrongdir/terragrunt.hcl` was created, and `terragrunt run --all -- plan` (run with fake, non-functional credentials — no real secrets or infrastructure touched) showed `blog/terraform` in the run queue and attempting to execute (it failed on a 403 from the fake credentials, as expected), while `blog/wrongdir` never appeared in the queue at all — confirming the `exclude` guard correctly filters non-conforming leaves out of `run --all`. The disposable directory was deleted immediately after.

### Move the leaf

`git mv terraform/infrastructure/cloudflare/global/noisypigeon.com/github workloads/blog/terraform` — both files move unchanged. `terraform/infrastructure/cloudflare/global/noisypigeon.com/` keeps its other leaf (`fastmail/`).

### Documentation

- **`workloads/README.md`** (new) — documents the `workloads/<name>/src/` + `workloads/<name>/terraform/` convention and the `exclude`-based path guard.
- **`CLAUDE.md`** — repo-description paragraph extended to describe the `workloads/` convention generally (not just the blog's `src/`); new ADR-0092 index bullet.
- **`docs/USAGE.md`** — structure list gains `workloads/` (with both `blog/src/` and `blog/terraform/` as examples).
- **`terraform/infrastructure/README.md`** — Secrets/Getting-started sections corrected for the `.env` move; also fixed an unrelated-but-adjacent staleness found while editing (it claimed "`terraform`/`terragrunt` aren't yet wired into this repo's root `.mise.toml`," which is false — `mise run plan`/`apply` already exist); added a cross-reference to the new `workloads/` tree.

## Consequences

- `workloads/` is now a second, independent Terragrunt tree. `mise run plan`/`apply` (bare `terragrunt run --all` from repo root, no path scoping) automatically discover both trees — this is intended, not incidental.
- **Live state migration is required and is explicitly not performed here.** Moving the leaf's directory changes its backend state key (`cloudflare/global/noisypigeon.com/github/terraform.tfstate` → `workloads/blog/terraform/terraform.tfstate`). The actual DNS records are live and serving `noisypigeon.com` today. This needs `terragrunt init -migrate-state` (or `-reconfigure`) run by the user, with real credentials, against production state — same precedent as every prior live-state move in this repo's history (ADR-0052, ADR-0060 Part 2). Until that migration runs, a `plan` against the new location would show both DNS records as not-yet-created (even though they exist), since no state file exists yet at the new key.
- Anyone with a pre-existing shell override of `SCALEWAY_TERRAFORM_STATE_BUCKET_NAME`/Cloudflare tokens pointed at the old `.env` path is unaffected — nothing about the *contents* changed, only the file's location, and lookup is purely `find_in_parent_folders`-based (no hardcoded path anywhere).

## Out of scope / manual steps

- Running the actual `terragrunt init -migrate-state` against live Cloudflare DNS state — the user's job, not performed in this session.
- Wiring Scaleway (or any other provider) into `workloads/root.hcl` — deferred until a future workload actually needs it.
- Migrating any other existing `terraform/infrastructure/` leaf into the `workloads/` convention — this ADR covers exactly the one leaf requested.
- Rewriting ADR-0063's own text to reflect the ADR-0052 merge's path-shifting effect — left as an accurate historical record of what it decided at the time it was written, consistent with this repo's precedent of not rewriting history (ADR-0086, ADR-0089).
