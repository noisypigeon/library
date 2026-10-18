# DEV-0158: Move `noisypigeon.com` back to GitHub Pages and decommission its Scaleway blog bucket

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-12.
- **Status**: Accepted.

## Context

ADR-0132 moved `noisypigeon.com` off GitHub Pages onto a dedicated Scaleway
Object Storage bucket (`workloads/noisypigeon.com/terraform/blog/bucket`)
fronted by a Cloudflare-proxied CNAME plus a `cloudflare_ruleset` redirecting
`www` → apex, specifically to make the workload Terraform-self-sufficient —
at the time, that was also a reversal of the site's original, even-earlier
GitHub Pages life (pre-ADR-0132, apex + `www` both DNS-only CNAMEs to
`noisypigeon.github.io`). ADR-0132's own Consequences section already flagged
that GitHub Pages' custom-domain setting for this repo should be disabled
once DNS stopped pointing at it — a manual step tracked separately and, as
far as this ADR can confirm, never actually done.

ADR-0156 (hoisting `pigeon.dev`'s site to `noisypigeon/pigeon.dev` and
serving it via GitHub Pages) re-proved the GitHub Pages path for a Zola site
in this family and built the reusable, OIDC-authenticated
`zola-site-pages.yml` workflow (`noisypigeon/pigeon.dev`, no stored
secrets) that any caller can invoke. Its own Decision section found, by
direct verification rather than assumption, that GitHub Pages redirects
`www` to the apex natively when both records point at the Pages host — the
exact behavior the pre-ADR-0132 `noisypigeon.com` records already relied on
— and that a DNS-only (`proxied = false`) record is required for GitHub's
own Let's Encrypt certificate to issue at all. Its Out of scope section
names this exact follow-up directly: *"Moving `noisypigeon.com` to GitHub
Pages too, which `zola-site-pages.yml` would now make nearly free to do.
Genuinely deferred."*

Unlike `pigeon.dev`, nothing needs to move: `noisypigeon.com`'s Zola source
already lives in this repo (`workloads/noisypigeon.com/src`), so none of
ADR-0156's site-relocation, legacy-tag-freezing, or cross-repo-dispatch work
applies — `actions/deploy-pages` deploys to the *calling* repo, and the
caller already lives in the repo that owns the content. `noisypigeon.com`
also hosts no `modules/<provider>/<module>/vX.Y.Z` redirect pages (that
traffic is entirely `pigeon.dev`'s), so there is no equivalent of ADR-0156's
75-live-`source=`-lines blast radius riding on this cutover. This ADR is
therefore the simplified slice of ADR-0156's pattern that actually applies
here: a new Pages caller workflow, a DNS retarget, and decommissioning the
bucket/IAM leaves that no longer have a consumer.

## Decision

### A `noisypigeon-com-pages.yml` caller, added here

`workloads/noisypigeon.com` needs no cross-repo constraint ADR-0156 §4 had
to work around — the site and the new caller both already live in
`noisypigeon/noisypigeon`, so `noisypigeon-com-pages.yml` calls
`noisypigeon/pigeon.dev/.github/workflows/zola-site-pages.yml@main` the same
way any other reusable-workflow caller in this repo does (ADR-0155 §5):
`src_dir: workloads/noisypigeon.com/src`, its own trigger (`push` to `main`
filtered to that path, plus `workflow_dispatch`), and its own
`permissions`/`concurrency`. No new secrets — Pages deploys via OIDC.

### `blog/dns` retargeted, `blog/dns`'s redirect ruleset deleted

Mirrors ADR-0156 §6 exactly, onto `workloads/noisypigeon.com/terraform/blog/dns/`:

- `cname.tf`: `root_cname`'s `content` becomes `noisypigeon.github.io`,
  `proxied` becomes `false`. `placeholder_www` becomes a real `www_cname`,
  also → `noisypigeon.github.io`, also `proxied = false` — this is exactly
  the pre-ADR-0132 record shape, restored.
- `redirect.tf`: deleted outright. Its `cloudflare_ruleset` existed only to
  work around the Scaleway bucket gateway's Host-header routing; GitHub
  Pages redirects `www` to the apex natively, so there's nothing left for it
  to do.
- A new TXT record, `_github-pages-challenge-noisypigeon`, is added to this
  leaf for GitHub's domain-verification check — in Terraform, not a one-time
  manual click.

Losing the Cloudflare proxy on the apex is the same accepted tradeoff
ADR-0156 took for `pigeon.dev`: no Cloudflare CDN/caching/WAF in front of the
site, and TLS comes from GitHub's own certificate. Accepted because it's the
exact configuration `noisypigeon.com` already ran for its entire pre-ADR-0132
GitHub Pages life.

### `blog/bucket` and `blog/iam` are decommissioned, last

Both leaves are deleted once Pages is confirmed serving. `blog/bucket` is a
bucket literally named `noisypigeon.com` with `enable_website`/
`enable_public_read` set; `blog/iam` exists solely to mint the
`NOISYPIGEON_COM_SCW_ACCESS_KEY`/`SECRET_KEY` pair `zola-sites-deploy.yml`
uses to `aws s3 sync` into it. With the site no longer deploying there,
neither has a consumer left.

`project`, `state/bucket`, `state/iam`, `bluesky/dns`, `google-search/dns`,
and `proton/dns` all stay exactly as they are — ADR-0132's self-sufficiency
pattern still applies to this workload's Terraform state and to its other
DNS leaves, none of which this change touches.

Deleting the leaf directories needs ADR-0128's `--filter-allow-destroy` on
`terragrunt-run.yml`'s `--filter-affected` invocation (already present),
without which the deleted directories would be silently excluded from the
run rather than destroyed. The two `NOISYPIGEON_COM_SCW_*` repo secrets are
retired in the same PR.

### `zola-sites-deploy.yml` drops its `noisypigeon-com` bucket job

Removed once `noisypigeon-com-pages.yml` is confirmed serving: the
`deploy-noisypigeon-com` job, its `workloads/noisypigeon.com/src/**`
push-path filter, and the `noisypigeon.com` option on the `site`
`workflow_dispatch` input. Kept: the `detect` job and the input itself —
`pigeon.dev`'s `template-release.yml` and this repo's `blog-changelog.yml`
both still dispatch against this workflow by name, and narrowing accepted
`site` values is its own cross-repo coordination risk, independent of this
change.

### Three PRs, ordered by blast radius (ADR-0156 §10's pattern)

1. **Here**: add `noisypigeon-com-pages.yml`. Enable Pages on this repo and
   verify the site fully on its `*.github.io` URL while `noisypigeon.com`
   the domain still resolves to the bucket — nothing user-visible moves in
   this PR. Confirm whether this repo's Pages custom-domain setting is still
   latent from before ADR-0132 (per that ADR's own Consequences note) before
   assuming step 2 starts from a clean slate.
2. **Here**: set the Pages custom domain to `noisypigeon.com` *before* the
   DNS flip — it will report a failed DNS check, which is expected and
   harmless, and is what shortens the certificate-issuance exposure window
   in the next step. Then the `blog/dns` retarget, applied through the
   existing `terragrunt apply` PR comment gate. The bucket is still
   populated and still being deployed to at this point, so reverting this
   one PR alone is a complete rollback. Once DNS propagates and GitHub
   issues the certificate, enable Enforce HTTPS in the Pages settings.
3. **Here**: trim `zola-sites-deploy.yml`, retire the
   `NOISYPIGEON_COM_SCW_*` secrets, and delete `blog/bucket` and `blog/iam`.
   Last, and deliberately so — only once Pages has been serving long enough
   to trust, since this step removes the rollback target step 2's ordering
   was protecting.

## Consequences

- No Cloudflare proxy in front of `noisypigeon.com` any more: no CDN,
  caching, or WAF, and GitHub Pages' published soft bandwidth/build limits
  replace a Scaleway bucket's bill-not-cap model.
- `noisypigeon.com` and `pigeon.dev` deploy mechanisms **reconverge**: both
  now ship via `zola-site-pages.yml`, undoing the two-shapes-to-maintain
  divergence ADR-0156's own Consequences section accepted as a tradeoff.
- `workloads/noisypigeon.com`'s "Terraform self-sufficient" bootstrap
  narrows: it keeps its own Project, state bucket, and deployer IAM, but no
  longer owns the resources that actually serve the site — the same shape
  ADR-0156 left `pigeon.dev` in.
- Loses the Scaleway-bucket rollback path once step 3 lands; GitHub Pages
  availability becomes `noisypigeon.com`'s hosting dependency, same as it
  was before ADR-0132.

## Out of scope

- Decommissioning `noisypigeon.com`'s Scaleway Project or its
  `terraform/state/{bucket,iam}` leaves. A permanent boundary, same one
  ADR-0156 drew for `pigeon.dev`'s equivalent leaves: `bluesky/dns`,
  `google-search/dns`, and `proton/dns` still need both.
- Keeping Cloudflare in front of Pages via a proxied record plus a
  documented DNS-only certificate-provisioning window. Deliberate boundary —
  same precedent-backed configuration ADR-0156 §6 chose over one that needs
  a manual dance every time the certificate is reissued.
- Pinning the called workflow to a `workflows/vX.Y.Z` tag instead of
  `@main`. The same genuinely-deferred item ADR-0155 §6 and ADR-0156 already
  raised; reuse that issue via `--issue N` rather than filing a third one for
  the same gap.
- Executing ADR-0156's own remaining runbook steps for `pigeon.dev`. Tracked
  separately, on its own branch.
