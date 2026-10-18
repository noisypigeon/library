# DEV-0105: consolidate fastmail, bluesky, and blog DNS leaves under `workloads/dns/terraform/`, add a pigeon.dev→noisypigeon.com redirect

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

This ADR groups every Cloudflare-managed DNS leaf in this repo under a single domain-first `dns/` workload, `workloads/dns/terraform/<domain>/<leaf>/`, replacing several leaves that previously lived scattered across their own workloads:

1. `workloads/email/terraform/fastmail/{noisypigeon.com,pigeon.dev}/` (moved there by ADR-0096) → `workloads/dns/terraform/{noisypigeon.com,pigeon.dev}/fastmail/`.
2. `workloads/bluesky/terraform/noisypigeon.com/` → `workloads/dns/terraform/noisypigeon.com/bluesky/`.
3. `workloads/blog/terraform/` → `workloads/dns/terraform/noisypigeon.com/blog/` (leaving `workloads/blog/` as `src/`-only).
4. A **new** leaf, `workloads/dns/terraform/pigeon.dev/redirect/`, redirecting `pigeon.dev` to `noisypigeon.com` — the only piece here that isn't a pure relocation.

(1)-(3) are pure relocations — no `.tf` resource content changes, no cloud resource created/destroyed. This ADR was originally written and applied covering only (1); it was then extended, in the same sitting, to also cover (2)-(4), rather than filed as a separate ADR, since all four are the same `dns/` consolidation effort.

**Research confirmed, verbatim, before planning anything:**

- `workloads/root.hcl`'s leaf-depth `exclude` guard (`is_valid_leaf = length(path_segments) >= 2 && path_segments[1] == "terraform"`, widened by ADR-0096) already accepts any depth under `<name>/terraform/`. Every new path here (`dns/terraform/noisypigeon.com/{fastmail,bluesky,blog}`, `dns/terraform/pigeon.dev/{fastmail,redirect}`) has `path_segments[1] == "terraform"` — already valid. **No `root.hcl` change needed for any of them.**
- The Cloudflare credential branch (`is_pigeon_dev_leaf = contains(path_segments, "pigeon.dev")`, added by ADR-0096) matches on *any* path segment equal to `pigeon.dev`, not a fixed prefix — it fires correctly regardless of how deep the `pigeon.dev` segment sits, and correctly stays on the `noisypigeon.com` credentials for the three `noisypigeon.com`-rooted leaves. **No change needed.**
- None of the five leaves has (or needs) a `workload_definition.hcl` — all stay on the default `fr-par`/`fr-par-1`.
- A repo-wide grep for `dependency`/`dependencies` Terragrunt blocks found none referencing any of these leaves' outputs — safe to move independently.
- Every destination directory for (1)-(3) already existed on disk, empty and untracked (scaffolded ahead of time for this `dns/` reorg). Per the ADR-0098 gotcha, `git mv sourcedir destdir` nests the source *inside* an existing `destdir` rather than renaming onto it — each placeholder was `rmdir`'d (after confirming empty) immediately before its `git mv`, one leaf at a time, each verified with `find` immediately after.
- Moving the fastmail leaves out leaves `workloads/email/` with zero files; moving the bluesky leaf out leaves `workloads/bluesky/` with zero files. Consistent with every prior ADR in this repo that emptied out a workload/provider root (ADR-0096's decommission of `terraform/infrastructure/cloudflare/`, ADR-0098's decommission of `terraform/`), both are decommissioned entirely rather than left as dangling, doc-referenced-but-empty workloads. `workloads/blog/` is different: it keeps its `src/` sibling (the Zola site), so it survives as a `src/`-only workload rather than being decommissioned.
- **The `pigeon.dev` redirect needs more than a redirect rule.** A live `dig pigeon.dev` / `dig www.pigeon.dev` confirmed **no apex or `www` A/AAAA/CNAME record exists at all** (only MX, for Fastmail; NS confirms the zone is on Cloudflare). Cloudflare only intercepts HTTP(S) traffic for a hostname that has a *proxied* DNS record — without one, there's no traffic for any redirect rule to ever act on. The leaf therefore needs a proxied placeholder record at apex and `www` (an `A` record to `192.0.2.1`, a reserved documentation-only IP — Cloudflare's edge intercepts and redirects before ever reaching that non-existent backend) in addition to the redirect rule itself.
- No existing pattern for this exists anywhere in the repo (a grep for `page_rule`/`ruleset`/redirect-as-a-mechanism found nothing). Cloudflare provider v5 (pinned `~> 5` in `workloads/root.hcl`, resolving to 5.26–5.27 across sibling leaves) **removed `cloudflare_page_rule` entirely** — confirmed directly against the real v5.27.0 provider schema (via `terraform providers schema -json` after `terragrunt init` in the new leaf) that the correct v5 resource is `cloudflare_ruleset`, `kind = "zone"`, `phase = "http_request_dynamic_redirect"`, with `rules` as a list of objects (not nested blocks) and the redirect action's shape at `rules[*].action_parameters.from_value.{status_code,target_url.value,preserve_query_string}` — every attribute name in the leaf below was checked against that schema before being written, not assumed.
- Redirect behavior (apex + `www` scope, flat redirect to the `noisypigeon.com` homepage rather than path/query-preserving, 302 rather than 301) was an open design decision with no prior ADR or code precedent anywhere in this repo — resolved by asking the user directly rather than guessing.

## Decision

### Move, one leaf at a time, verified after each

```sh
rmdir workloads/dns/terraform/noisypigeon.com/fastmail
git mv workloads/email/terraform/fastmail/noisypigeon.com workloads/dns/terraform/noisypigeon.com/fastmail
# verified: terragrunt.hcl, cname.tf, mx.tf, txt.tf, .terraform.lock.hcl -- flat, not double-nested

rmdir workloads/dns/terraform/pigeon.dev/fastmail
git mv workloads/email/terraform/fastmail/pigeon.dev workloads/dns/terraform/pigeon.dev/fastmail
# verified: same five files, flat
```

Done one at a time rather than batched, per the `git mv` double-nesting gotcha ADR-0097/ADR-0098 both hit live. Each leaf's `terragrunt.hcl` is this repo's unchanged boilerplate (`include "root" { path = find_in_parent_folders("root.hcl") }`), which resolves correctly at the new depth exactly as it did at the old one.

With both leaves moved out, `workloads/email/` has no tracked files left (confirmed via `git ls-files workloads/email` returning empty) — nothing further to `git rm`, since git doesn't track empty directories; the directory simply ceases to exist as a meaningful path.

### Move the bluesky leaf, same pattern

```sh
rmdir workloads/dns/terraform/noisypigeon.com/bluesky
git mv workloads/bluesky/terraform/noisypigeon.com workloads/dns/terraform/noisypigeon.com/bluesky
# verified: terragrunt.hcl, txt.tf, .terraform.lock.hcl -- flat
```
A stale, gitignored `.terragrunt-cache/` rode along with the `git mv` (a filesystem-level directory rename carries untracked files too) — removed, so the new location gets a clean `terragrunt init` rather than one pointed at a now-wrong cached path. `workloads/bluesky/` has no tracked files left afterward — decommissioned, same treatment as `workloads/email/` above.

### Move the blog terraform leaf, same pattern

```sh
rmdir workloads/dns/terraform/noisypigeon.com/blog
git mv workloads/blog/terraform workloads/dns/terraform/noisypigeon.com/blog
# verified: terragrunt.hcl, cname.tf, .terraform.lock.hcl -- flat
```
Same stale-cache cleanup as bluesky. Unlike `email`/`bluesky`, `workloads/blog/` is **not** decommissioned — its `src/` sibling (the Zola site) is untouched and `workloads/blog/` now exists as a `src/`-only workload, a shape the existing convention already supports (the mirror image of `scaleway/`/`pigeon-cli/` being `terraform/`-only).

### Add the new pigeon.dev redirect leaf

Three new files, written directly into the leaf (not a `git mv`, since this is new content):

`workloads/dns/terraform/pigeon.dev/redirect/terragrunt.hcl` — the repo's standard boilerplate.

`workloads/dns/terraform/pigeon.dev/redirect/dns.tf` — the placeholder proxied records:
```hcl
resource "cloudflare_dns_record" "placeholder_apex" {
  zone_id = local.cloudflare_pigeon_dev_zone_id
  name    = "@"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
  ttl     = 1
  comment = "placeholder so Cloudflare intercepts apex traffic for the noisypigeon.com redirect"
}

resource "cloudflare_dns_record" "placeholder_www" {
  zone_id = local.cloudflare_pigeon_dev_zone_id
  name    = "www"
  type    = "CNAME"
  content = "pigeon.dev"
  proxied = true
  ttl     = 1
  comment = "placeholder so Cloudflare intercepts www traffic for the noisypigeon.com redirect"
}
```

`workloads/dns/terraform/pigeon.dev/redirect/redirect.tf` — the redirect rule:
```hcl
resource "cloudflare_ruleset" "to_noisypigeon_com" {
  zone_id = local.cloudflare_pigeon_dev_zone_id
  name    = "pigeon.dev to noisypigeon.com redirect"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    expression  = "(http.host eq \"pigeon.dev\") or (http.host eq \"www.pigeon.dev\")"
    description = "redirect pigeon.dev and www to the noisypigeon.com homepage"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code = 302
        target_url = {
          value = "https://noisypigeon.com"
        }
        preserve_query_string = false
      }
    }
  }]
}
```

Both `local.cloudflare_pigeon_dev_zone_id` and the `is_pigeon_dev_leaf` credential branch were already available/correct with zero `root.hcl` changes (confirmed above). `terragrunt init` followed by `terraform providers schema -json` against the real v5.27.0 schema confirmed every attribute name above (`kind`, `phase`, `rules` as a list, `action_parameters.from_value.{status_code,target_url.value,preserve_query_string}`) before trusting it. `terragrunt plan` against this leaf succeeded — **3 to add, 0 to change, 0 to destroy** — confirming the configuration is syntactically and semantically valid, though it also surfaced a non-fatal warning: the `cloudflare_ruleset`'s optional server-side dry-run validation call got a `403 request is not authorized` from `CLOUDFLARE_TOKEN`. The DNS-record portion of the plan resolved fine, so the token has zone/DNS access; it may be missing the Rulesets edit permission scope needed to actually create the ruleset on `apply`. Not fixed here — a token-permission change in the Cloudflare dashboard, left to the user.

### No `workloads/root.hcl` changes, for any of the five leaves

Confirmed above: the leaf-depth guard and the `pigeon.dev` credential branch are both already path-segment-generic, not fixed-prefix or fixed-depth — none of these moves or the new leaf needed any change, unlike every prior leaf-move ADR in this repo's history.

### Documentation

- `workloads/README.md`'s tree example: the `email/` block was replaced with a `dns/` block in the first pass; extended here to list `bluesky/`, `blog/`, and `redirect/` under their respective domains, to show `blog/` as `src/`-only, and to add `dns/` to the list of infrastructure-only (no-`src/`) workloads.
- `CLAUDE.md`'s workloads description paragraph and ADR index updated to describe the full `workloads/dns/terraform/` layout (all five leaves) and cite this ADR, while still recording which earlier ADR originally moved each leaf into the `workloads/` convention in the first place.
- `docs/USAGE.md`'s `workloads/dns/terraform/` bullet broadened to describe all five leaves; the `workloads/blog/terraform/` bullet removed (that leaf no longer exists at that path).

### The actual state migration — performed live, every moved leaf verified clean

Same runbook as ADR-0094/0096/0097/0098 — plain `terragrunt init`/`init -migrate-state` does not work across a directory move (Terragrunt's local init-pointer lives in a `.terragrunt-cache/<hash-of-path>/` directory keyed by filesystem path), so each move went through `terraform state pull`/`push` via a temporary worktree at `HEAD` (each move was staged but uncommitted at migration time, so `HEAD` still reflected the pre-move layout). The fastmail leaves, shown below, were run once per domain; bluesky and blog were run the same way afterward, each pulling its real state (1 resource for bluesky's TXT record, 2 for blog's apex+www CNAMEs) and each verified clean. The new `pigeon.dev/redirect` leaf has no prior state to migrate — it's new resources, not a move, and its `terragrunt apply` is deliberately not run here (see Out of scope).

```bash
git worktree add /tmp/old-fastmail-leaf HEAD
cp .env /tmp/old-fastmail-leaf/.env   # gitignored, not checked out by worktree add

cd /tmp/old-fastmail-leaf/workloads/email/terraform/fastmail/noisypigeon.com
terragrunt init -input=false
terragrunt state pull > /tmp/fastmail-noisypigeon-com.tfstate

cd /Users/pigeon/Developer/noisypigeon/workloads/dns/terraform/noisypigeon.com/fastmail
terragrunt init -input=false
terragrunt state pull   # confirmed empty before pushing
terragrunt state push /tmp/fastmail-noisypigeon-com.tfstate

terragrunt plan -input=false   # "No changes. Your infrastructure matches the configuration."

cd /Users/pigeon/Developer/noisypigeon
git worktree remove /tmp/old-fastmail-leaf
rm /tmp/fastmail-noisypigeon-com.tfstate
```

Repeated identically for `pigeon.dev`. Neither `state pull` nor `state push` talks to the Cloudflare API — only `plan`'s refresh step does, which is also what would have surfaced the `pigeon.dev` token-scoping issue ADR-0096 hit live, had it regressed; it did not, confirming the credential branch's path-segment-generic design holds at the new depth. Both leaves showed "No changes" after their push.

Every moved leaf's old-backend-key state object (`workloads/email/terraform/fastmail/<domain>/terraform.tfstate`, `workloads/bluesky/terraform/noisypigeon.com/terraform.tfstate`, `workloads/blog/terraform/terraform.tfstate`) becomes orphaned by its move — the real Cloudflare DNS records are completely untouched, only the old Terraform-tracked state entries are abandoned. Same accepted, low-priority treatment every prior ADR here has given its own orphaned state object.

## Consequences

- `workloads/dns/terraform/{noisypigeon.com,pigeon.dev}/fastmail/`, `workloads/dns/terraform/noisypigeon.com/{bluesky,blog}/` are live and runnable immediately — state migrated and verified via `terragrunt plan` showing "No changes" for each, in this session.
- `workloads/dns/terraform/pigeon.dev/redirect/` exists with valid, schema-checked configuration and a verified `plan` (3 to add), but is not yet live — no `apply` has been run, and the `CLOUDFLARE_TOKEN`'s Rulesets permission scope should be checked before attempting one.
- `workloads/email/` and `workloads/bluesky/` no longer exist in this repo. `workloads/blog/` still exists, now as `src/`-only.
- `workloads/dns/` now holds five live/ready leaves across both domains, consolidating what used to be three separate workloads (`email`, `bluesky`, and `blog`'s DNS half) plus one brand-new redirect leaf.
- The old leaves' `terraform.tfstate` objects at their pre-move backend keys are now orphaned (their content was copied, not moved — `state pull` doesn't delete the source). Low-priority cleanup, left for later; S3 versioning on the state bucket remains an independent safety net regardless.

## Out of scope

- Running `terragrunt apply` for the new `pigeon.dev/redirect` leaf — making it live affects real traffic for a real domain, a bigger blast radius than migrating existing leaves' state, and is left for a deliberate follow-up rather than bundled into this ADR.
- Widening `CLOUDFLARE_TOKEN`'s permissions in the Cloudflare dashboard, which the redirect leaf's `plan` output suggests may be needed before that `apply` can succeed.
- Deleting the orphaned old-backend-key state objects — optional cleanup, left to the user's discretion and timing, same treatment every prior ADR here has given its own orphaned state object.
