# LIB-0032: Move the blog into runway

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-23.
- **Status**: Proposed. Applies LIB-0030 and LIB-0031 to `noisypigeon/blog`.
  Amends LIB-0017, whose spoke list loses blog. Last of three records, with
  LIB-0030 and LIB-0031. LIB-0033 (proposed) would replace §1's hand-made
  Cloudflare token with a minting key and a Terraform-made deployer.

## Context

`noisypigeon/blog` is a full spoke for a small payload:

- **the site,** a Zola tree at `web/` (`config.toml`, `content/`, `static/`,
  `CHANGELOG.md`), deployed to `noisypigeon.com` by `blog-pages.yml`;
- **three zones' leaves,** under `terraform/cloudflare/`:
  - `noisypigeon.com`, with DNS records for GitHub Pages, Bluesky, Proton
    and Google Search verification;
  - `pigeon.dev`, with an apex redirect to `noisypigeon.com` and its mail
    records;
  - `willowgraysen.com`, with an apex redirect to `noisypigeon.com`;
- **its own state apparatus:** an R2 state bucket, a B2 backup bucket and
  key (LIB-0007, LIB-0016), and the CI that plans, applies and backs them up.

LIB-0030 lets a workload own those zones, and LIB-0031 lets a workload be a
site deployed by a shim repo. runway already runs workloads, and
`willowgraysen.com` is runway's own domain. So the blog moves there, as
`workloads/blog/`, and `noisypigeon/blog` becomes the shim.

Two things make this a migration rather than a copy.

- **The DNS is live.** Destroying and recreating the records would take
  `noisypigeon.com` and `pigeon.dev`'s mail down while the apply runs. The
  existing resources have to move into the workload's state, not be
  recreated. LIB-0028's `poc` was recreated because it was disposable; this
  isn't.
- **The leaves change shape.** A hand-written blog leaf calls a module with
  `for_each` over a map of records, under its own address. A workload leaf
  calls one module instance, `module.this`, per record. So a state move is not
  a key-for-key copy as in LIB-0016 §4. Each resource is imported into its new
  address, and removed from the old state.

## Decision

### 1. runway gains Cloudflare and the three zones

- **`spoke.hcl`'s providers map gains `cloudflare = {}`.**
- **`terraform/secrets/cloudflare.enc`** holds the account token and ID
  (LIB-0010, LIB-0012). The owner creates it, encrypted to runway's age
  recipient.
- **`zones.yaml`** (LIB-0030 §2) registers `noisypigeon.com`, `pigeon.dev`
  and `willowgraysen.com` to `blog`.
- **runway takes the `workflows/` and `terragrunt/root-hcl` releases**
  LIB-0030 and LIB-0031 make, in one PR whose plan selects nothing.

### 2. `workloads/blog/` reproduces blog, kind for kind

- **The site:** blog's `web/` contents move as they are: `config.toml`,
  `content/`, `static/` and `CHANGELOG.md`. Zola's build output and the
  fetched theme don't move.
- **`values.yaml`:**
  - `prefix: blog`, `suffix: noisypigeon`;
  - `cloudflare.zone: noisypigeon.com`;
  - one `cloudflare.dnsRecord` entry per record in blog's
    `noisypigeon.com` and `pigeon.dev` leaves, with the same name, type,
    content, TTL, proxying, priority and comment;
  - one `cloudflare.apexRedirect` entry each for `pigeon.dev` and
    `willowgraysen.com`, with the same target and options.
- **No resource changes.** Each entry is written to match what's in
  Cloudflare. The import (§3) proves it: its plan must be `No changes.`

The workload's implicit project, deployer and state bucket (LIB-0028) are
created first, in their usual stages. That's the only thing this migration
creates.

### 3. Resources are imported, never recreated

A new runbook, `docs/runbooks/import-a-leaf-into-a-workload.md`, moves one
hand-written leaf's resources into workload leaves. For each blog leaf:

1. **Apply the workload's bootstrap stages** (project, deployer, state
   bucket), with the blog's entries not yet in `values.yaml`. Nothing
   Cloudflare plans yet.
2. **Add the leaf's entries to `values.yaml`, locally, and generate the
   stubs.**
3. **Import each resource into its new leaf** with `terragrunt import`, by
   its Cloudflare ID, at its `module.this...` address. The workload's own
   `remote_state` (LIB-0028 §5) writes the new state.
4. **Remove each resource from blog's state** with `terragrunt state rm`, in
   the blog checkout, so blog's leaf no longer claims it.
5. **Plan the new leaves.** Each must show `No changes.` If one doesn't, its
   `values.yaml` entry is wrong. Fix the entry, not the resource.

- **Nothing may be applied in blog or runway between step 3 and the PR that
  commits the entries merging,** as LIB-0016 §4's gate has it. An apply in
  between could recreate or destroy a record from a half-moved state.
- **The runway PR that commits the entries** must plan `No changes.` for every
  blog leaf before it merges.
- **The runbook is general.** It's how any hand-written leaf moves into a
  workload, which is the mechanism [#98](https://github.com/noisypigeon/library/issues/98) deferred.

### 4. Cutover, in order

1. **The library:** LIB-0030's and LIB-0031's releases, including the
   `cloudflare/ruleset` release LIB-0030 needs, and garden's build with them,
   so the schemas are published.
2. **runway, bootstrap:** §1, plus `workloads/blog/values.yaml` with only
   `prefix`, `suffix` and `cloudflare.zone`. It applies the bootstrap stages.
3. **The import, by runbook** (§3), with both repos frozen.
4. **runway, entries:** the imported `values.yaml` entries. It plans
   `No changes.` for every blog leaf, and merges.
5. **runway, site:** `workloads/blog/`'s site files, the narrowed gitignore,
   and the site deploy workflow (LIB-0031 §4). Its `BOT_GITHUB_TOKEN` needs
   `actions: write` on `noisypigeon/blog`.
6. **blog, shim:** `noisypigeon/blog` keeps `README.md` and its deploy
   workflow, now building runway's `workloads/blog/` (LIB-0031 §5). Everything
   else goes: `web/`, `terraform/`, the other workflows, `.lib-version`,
   `spoke.hcl`, the generated `root.hcl` and the secrets.
7. **Check the site.** A post merged in runway reaches `noisypigeon.com`, and
   `pigeon.dev` and `willowgraysen.com` still redirect.

### 5. blog's own state apparatus is torn down last

After step 6, blog's leaves are empty except the ones that hold its state:
the R2 state bucket, the B2 backup bucket and its key.

- **They're destroyed by hand, by the owner,** in the order the runbook gives.
  The R2 bucket holds its own state, so Terraform can't destroy it cleanly.
- **Its secrets' credentials are revoked** once nothing uses them: the R2
  token, the B2 key and the age key in blog's `SOPS_AGE_KEY`.
- **Nothing is backed up first.** After the import, blog's state holds
  nothing a restore would need.

### 6. The records follow the repos

- **runway's `CLAUDE.md`** drops "Nothing here is publicly exposed" and says
  the blog lives at `workloads/blog/`. Its rules about secrets, plan output
  and names still apply to everything else.
- **This repo's `CLAUDE.md`** lists blog as a shim repo, not a spoke. Its
  description of the theme release's dispatch to `blog-pages.yml` still
  holds.
- **LIB-0017's spoke list** loses blog. Its COM- records stay where LIB-0017
  §2 put them.

## Consequences

- **One fewer spoke.** blog's state bucket, backup, secrets, CI and changelog
  plumbing go. The blog costs runway one workload.
- **runway is no longer private in spirit.** It's always been a public repo,
  but now it publishes a site and takes posts. A post PR and an infrastructure
  PR share one review queue.
- **`willowgraysen.com`, `pigeon.dev` and `noisypigeon.com` live with the
  site that uses them.**
- **The import runbook exists for the next move.** garden, or any hand-written
  leaf, can follow it.
- **The migration window freezes two repos**, for as long as the import takes.

## Out of scope

- **Moving garden.** LIB-0031 defers it ([#150](https://github.com/noisypigeon/library/issues/150)).
- **Carrying out §§1–6.** The runbook and the runway and blog PRs follow this
  record, once LIB-0030 and LIB-0031 are built
  ([#149](https://github.com/noisypigeon/library/issues/149)).
- **Archiving or renaming `noisypigeon/blog`.** It stays, as the shim that
  Pages needs.
- **Moving runway's other hand-written leaves into workloads.** The runbook
  makes that possible. Each is its own decision, under
  [#98](https://github.com/noisypigeon/library/issues/98).

## Verification

1. **The DNS never changes.** Every blog leaf plans `No changes.` after the
   import, and `dig` for each record returns the same answer before and after
   the cutover.
2. **The site deploys from runway.** A post merged in runway reaches
   `noisypigeon.com` through the shim, and blog's repo holds only its README
   and deploy workflow.
3. **The redirects still redirect.** `pigeon.dev` and `willowgraysen.com`
   answer with their redirect to `noisypigeon.com`.
4. **blog's apparatus is gone.** Its state bucket, backup bucket and key no
   longer exist, and their credentials are revoked.
5. **runway converges.** A re-plan of every leaf in runway shows
   `No changes.`
