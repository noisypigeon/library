# LIB-0001: a composable hub-and-spoke repo architecture, and the `LIB-` ADR domain

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-13.
- **Status**: Accepted; amended 2026-10-15, 2026-10-17, 2026-10-19 and 2026-10-20 (see `## Amendments`). Invariant 5 is reversed for garden, blog and runway by LIB-0017. LIB-0031 adds a second shape beside the spoke: a shim repo that only deploys a spoke workload's site to Pages. blog is one since LIB-0032.

## Context

Over three days — DEV-0154 through DEV-0160, plus `noisypigeon/noisypigeon#289` —
this family of repos dispersed hard. `templates/` left the monorepo, then the
reusable workflows, then the `pigeon.dev` site, then the whole ADR corpus, then
the blog; then `workloads/` was flattened away. Every one of those decisions was
argued well, and every one was argued *against the step immediately before it*.
None of them named the shape the family was converging on, because none of them
had to.

The result is six repos with no consistent notion of what a repo is for:

- **`pigeon.dev`** holds four unrelated kinds of thing — 13 Terraform modules, a
  Zola theme, six reusable workflows, and 118 ADRs across two domains — *plus*
  its own website, *plus* the short-URL redirect layer that serves the modules.
  DEV-0157 counted "four distinct kinds of thing … plus its own site" as a
  consequence worth noting; it has not gone down since.
- **`noisypigeon`** holds three domains' Terraform (`noisypigeon.com/`,
  `pigeon.dev/`, `willowgraysen.com/`) and none of their content. DEV-0154 called
  it "a repo whose contents are entirely things it runs". After the flatten it is
  a repo whose contents are entirely things *other repos* run.
- **`noisypigeon.com`** holds content but not the infrastructure that serves it.
  Its two workflows are callers into `pigeon.dev`; its theme arrives by a
  blobless clone of `pigeon.dev` into a gitignored `.templates-src/`.
- **`willowgraysen.com`** is not a repo at all. It is a directory in the monorepo
  — `gh repo view noisypigeon/willowgraysen.com` is a 404 — despite owning 15
  Terraform leaves, the largest share of module consumption, and this family's
  only non-trivial orchestration.
- **`pigeon-cli`** has had its own `docs/adr/` all along: 118 records, `0001`
  through `0150`, never hoisted, never renumbered, and entirely absent from the
  conversation DEV-0157 had about where ADRs belong. It is the one repo already
  shaped the way this ADR argues every repo should be.

Four concrete symptoms, all verified against the live tree rather than against
prior prose.

### 1. "Reusable" and "mine" are mixed in one repo, and the seams show

`pigeon.dev` has ten workflows. Six are pure `workflow_call` reusables and
**five of those have no caller in the repo at all** — they exist solely to serve
`noisypigeon` and `noisypigeon.com`. The other four are repo-local. Nothing in
the layout distinguishes them; you find out by reading `on:`.

`zola-site-deploy.yml:60` runs `noisypigeon.com/fetch-templates.sh` — a path
into a *caller's* checkout, hardcoded, left behind when DEV-0159 moved that file
to another repo. `zola-site-pages.yml` already fixed the same bug properly, as
an `inputs.fetch_templates_script` parameter. One reusable workflow is correct
and its sibling is broken, and the difference is invisible from the directory.

### 2. The site cannot be separated from the modules, and the coupling is silent

`pigeon.dev/generate-module-redirects.sh` has four hard dependencies on
`templates/` living in the same repo: an `exit 1` guard if
`$REPO_ROOT/templates/terraform` is missing (`:50`), four `git tag --list` reads
against `$REPO_ROOT` (`:79`, called at `:129`/`:145`/`:156`/`:254`), direct disk
reads of each module's `README.md` (`:161`) and `CHANGELOG.md` (`:282`), and
theme resolution through a sibling relative path (`.mise.toml:14`).

Three of those fail loudly. The fourth does not. `repo_for_prefix()` (`:56-65`)
maps a tag prefix to a **literal repo slug**, and two further slugs are
hardcoded at `:182` and `:236`. Move the modules to another repo while leaving
the prefix unchanged and the generator keeps emitting
`git::https://github.com/noisypigeon/pigeon.dev.git//…` — a plausible,
well-formed, wrong answer. DEV-0156 collapsed these couplings by colocation; that
worked, and it is also why they are now invisible.

### 3. Three `root.hcl` files are near-copies of each other and of a fourth

`noisypigeon.com/root.hcl`, `pigeon.dev/root.hcl` and
`willowgraysen.com/root.hcl` are 5877, 5857 and 8080 bytes. They differ in
exactly six ways: which `secrets.enc` they read, an `is_valid_leaf` segment
index, the state-bucket key name, whether the state key carries a `workloads/`
prefix, `willowgraysen.com`'s latent Backblaze provider (DEV-0148), and its extra
`grafana/grafana` requirement. Everything else — the sops decryption dance, the
`ENV_SW_`/`ENV_CF_` prefix-stripping, the four `generate` blocks, the `exclude`
block, the `scaleway_config.hcl` override — is duplicated prose.

DEV-0059 declined to template this, and was right to: there was one of them. Its
own words were "`root.hcl` for a new account is still a real file a human
writes", and DEV-0053 said plainly that "if a second domain or DO team is added
later, revisit this decision rather than retrofitting it silently." There are
now four. The duplication has already decayed: the shared `root.hcl` still keys
state on `workloads/${path_relative_to_include()}` though `workloads/` was
deleted, and its `is_pigeon_dev_leaf` branch computes a condition whose two
arms are character-for-character identical — a per-domain token split that the
comment above it still describes and the code no longer does.

### 4. The frozen tag arm is one no-op bump away from being deletable

DEV-0154 split module tags across two repos and DEV-0156 froze the older arm into
a committed list, `pigeon.dev/legacy-module-tags.txt`, rather than "shelling into
a repo it no longer has local access to" — safe, it argued, "specifically
*because* ADR-0154 established the set as frozen and permanently unable to grow".
The generator's own comment puts the reason plainly: the list exists "since this
repo has no other way to know about tags that live in a different one."
DEV-0154 then drew a **permanent boundary** around those 20 tags: deleting them
"would break live infrastructure", because one of them was still pinned.

Checked against the live tree, that is true of exactly one version — and it was
already true when DEV-0156 checked, which recorded `scaleway/project/v1.0.0` as
"the only legacy tag among the 75 live `source =` lines' pinned versions". The
line count has since fallen to 32, with the flatten and the bucket
decommissions, but the conclusion is unchanged: 31 of those pins resolve through
the `templates/terraform` arm, and one does not. It is pinned in
`noisypigeon.com/terraform/project/project.tf`,
`pigeon.dev/terraform/project/project.tf` and
`willowgraysen.com/terraform/project/project.tf`.

And `templates/terraform/scaleway/project/v2.0.0` already exists. It is one of
DEV-0110's bookkeeping seed tags, cut because a path move is breaking by
convention rather than by content — its `main.tf`, `inputs.tf`, `outputs.tf` and
`versions.tf` are **byte-identical** to the legacy `v1.0.0`, and the consumers
pass only `name`, which has the same type and default in both. Three one-line
`source =` edits make the boundary's premise false, at the cost of a `plan` that
reports no changes.

## Decision

Adopt a **hub-and-spoke** architecture: one repo owns everything reusable and
versioned, every other repo is content plus the infrastructure that serves it,
and spokes consume the hub **by version**. Adoption is per repo, in the order
§6 gives, and **this ADR migrates nothing**.

### 1. Open `adr/pigeon-lib/` with `LIB-`-prefixed IDs

`pigeon-lib` ADRs are filed at `adr/pigeon-lib/LIB-NNNN-<slug>.md`, numbered
from `0001` with their own sequence: next number is max+1 **within that
directory**. This file is `LIB-0001`.

This is the pattern NPC-0000 established and DEV-0160 generalized — "a future
domain picks its own prefix and its own sequence" — exercised for the third
domain and the first one whose subject repo does not exist yet. The house format
is unchanged: no frontmatter, an H1 plus `Author`/`Date`/`Status` bullets,
`## Context` / `## Decision` / `## Consequences` / `## Out of scope` with an
optional `## Verification`, no index to update, and the author line DEV-0160 made
canonical. Per DEV-0031, genuinely-deferred `## Out of scope` items are filed as
issues against `noisypigeon/noisypigeon`.

### 2. Repo roles

| Repo | Holds | Role |
| --- | --- | --- |
| **`pigeon-lib`** (new) | `templates/terraform/`, `templates/zola-site/`, `templates/terragrunt/`, the reusable workflows, `.github/scripts/`, `docs/adr/` | **Hub.** Every reusable asset, all release automation, all versioning. No content, no deployed infrastructure. |
| **`pigeon.dev`** | `web/`, `terraform/`, `root.hcl`, `docs/adr/` | Spoke. Also the module short-URL host. **No scripts, no workflow bodies.** |
| **`noisypigeon.com`** | `web/`, `terraform/`, `root.hcl`, `docs/adr/`, `docs/blog/{posts,media}` | Spoke, identical shape. |
| **`willowgraysen.com`** (new) | `terraform/`, `root.hcl`, `docs/adr/` | Spoke. Orchestration layer for `pigeon-cli`; its HTTPS endpoint redirects to `noisypigeon.com`. The largest module consumer. |
| **`pigeon-cli`** | source, `docs/adr/` | Spoke. Already conformant; consumes nothing from the hub today. |
| **`noisypigeon`** | content | The default home for content. No ADRs of its own; its three domain directories leave. |

"Hub" is a role, not a privilege: `pigeon-lib` is closed to this family. DEV-0155
rejected "a general-purpose shared-CI repo for arbitrary repos or orgs" as a
deliberate boundary and that judgment carries over unchanged — see
`## Out of scope`.

### 3. The five invariants

These are the contract. Everything else in this ADR is a consequence of them.

1. **The hub owns every reusable asset.** A spoke contains no scripts and no
   workflow bodies — only thin callers, content, and its own Terraform.
2. **The hub publishes versions; spokes consume versions, never branches.** Each
   spoke declares one hub version, the way a site already declares
   `[extra].theme_version` (DEV-0114), and the deploy fetches that ref into a
   gitignored directory before building. This generalizes the mechanism
   `fetch-templates.sh` and `.templates-src/` already implement for the theme,
   and makes it the only way in.
3. **Public interfaces are decoupled from internal layout.**
   `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` is permanent regardless of
   which repo, directory, or tag shape backs it. DEV-0110 called the line that
   holds `url_path` literal "the entire stable-URL guarantee"; it stays literal.
   Tag shape is private to the hub.
4. **A spoke's Terraform state keys do not change when it moves.** A spoke keeps
   `root.hcl` at its repo root with leaves under `terraform/` and secrets at
   `terraform/secrets.enc`. This is load-bearing arithmetic, not taste: the
   per-domain key is `"${path_relative_to_include()}/terraform.tfstate"`, so a
   leaf at `<domain>/terraform/state/bucket` under `<domain>/root.hcl` and a leaf
   at `terraform/state/bucket` under a repo-root `root.hcl` both resolve to
   `terraform/state/bucket/terraform.tfstate`. Put `root.hcl` *inside*
   `terraform/` instead and every key silently shortens — DEV-0059 hit exactly
   that and recorded the "Backend configuration changed" failure it produces.
5. **Each spoke owns its own `docs/adr/`,** with its own prefix and sequence.

### 4. The hub owns the release; the spoke rebuilds

A merged PR in `pigeon-lib` does the whole release act in one place: compute the
bump from its `release:*` label, write the changed unit's `CHANGELOG.md` and the
root rollup line, create the tag, cut the GitHub Release. It then dispatches the
affected spoke, which regenerates its derived content — redirect pages and
release posts for `pigeon.dev` — and deploys.

**A spoke never writes a tag.** That follows from invariant 1 (a repo with no
scripts cannot own a release) and from go-getter: a `git::` source has to name a
ref in the repo whose tree it resolves to, which is the hub.

> This is the one part of the architecture inferred rather than stated. The
> brief said a hub change "triggers a workflow in `pigeon.dev` to release the new
> tags/blog post", which reads as the spoke doing the tagging. That cannot work
> as written, so it is resolved in the direction the invariants force, and the
> inference is recorded here rather than hidden. The ordering constraint DEV-0154
> already identified survives the change and gets worse: a dispatch that fails is
> "the one piece that fails silently … the release still cuts its tag and the
> site simply never redeploys, leaving a version whose short URL 404s."

### 5. One tag rule, not a mapping

The brief settles the question DEV-0154 and DEV-0156 had to work around: tag
organization is **private to the hub**, because `pigeon.dev` is its only
consumer, and it may be reorganized freely so long as the short URL is stable.
Invariant 3 is what makes that safe.

So the end state is a single rule rather than a growing table. All module tags
live in `pigeon-lib`, shaped `terraform/<provider>/<module>/vX.Y.Z` and
`zola-site/vX.Y.Z` — dropping the `templates/` segment that only ever existed to
keep a previous move's blast radius down. This is the flatten DEV-0154 deferred
and costed as "new tag prefixes, a third allowlist arm in the generator, and
ADR-0093's major-re-seed argument"; under invariant 3 the first two are the point
and the third does not apply, because the *public* path is not moving.
`repo_for_prefix()` collapses to one arm and the three hardcoded slugs become one
input.

"All" means all: the 49 existing `templates/terraform/*` tags and the four
`templates/zola-site/*` ones travel with the history and are re-cut under the new
shape, so one rule covers every version rather than a rule for new versions and a
table for old ones. That is safe for the same reason tag shape is private —
`filter-repo` preserves the `templates/` subtree byte-for-byte, so an old
version's `git::` source resolves to identical module content at a differently
named ref, and invariant 3 keeps the short URL that consumers actually wrote
unchanged. The tags left behind in `pigeon.dev` become unreferenced, like the 20
in `noisypigeon`.

Retiring the frozen arm is the prerequisite, and `## Context` §4 establishes it
is free: bump the three `scaleway/project` pins from `v1.0.0` to the
content-identical `v2.0.0`, after which nothing resolves through
`legacy-module-tags.txt` and both it and its mapping arm are deleted.

To be precise about DEV-0154's boundary rather than brushing past it: that
boundary was "deleting or rewriting any tag in `noisypigeon`", justified
because "§2 and §3 both depend on all 105 existing tags staying exactly where
they point" and because one was live-pinned. Bumping the pin removes the
justification, and this ADR does not need the boundary lifted anyway — dropping
the *mapping arm* requires no tag in `noisypigeon` to be touched. The 20 tags
can stay where they are forever, unreferenced.

### 6. `root.hcl` becomes a versioned template

`templates/terragrunt/root-hcl/` joins the hub as a third `templates/<kind>/` —
the sibling DEV-0154 explicitly left room for. A spoke's `root.hcl` becomes a
thin instance declaring only the six things `## Context` §3 measured as
genuinely varying, with everything else coming from the pinned template.

The constraint to design against is Terragrunt's, not ours: DEV-0059 found that
"Terragrunt does not support nested includes" and that a `common.hcl` local
cannot forward-reference `root.hcl`'s own `local.secrets`. So the template is
materialized into the spoke at build/plan time by the pinned hub fetch, not
`include`d — the same shape `resolve-theme.sh` already uses for the theme, and
the reason that script resolves its root from `${BASH_SOURCE[0]}` rather than
`git rev-parse` (DEV-0154).

Adopting it also fixes the two decayed spots §3 names — the dead
`is_pigeon_dev_leaf` branch and the shared root's stale `workloads/` key prefix —
because a template has one copy of each to be wrong in.

### 7. Rollout order

Per-repo, each step its own ADR in its own domain, each landing independently.

0. **Prerequisite** — bump the three `scaleway/project` pins; delete
   `legacy-module-tags.txt` and its mapping arm. No new repo, no new mechanism.
1. **Create `pigeon-lib`** — move `templates/`, the reusable workflows and the
   scripts with history and tags; repoint the three `noisypigeon` callers and the
   two `noisypigeon.com` callers off `noisypigeon/pigeon.dev/…@main`.
2. **`pigeon.dev` content split** — `pigeon.dev/src` → `web/`; the deploy fetches
   the hub at its pinned version. Cuts all four couplings in `## Context` §2.
3. **`pigeon.dev` Terraform hoist** — `terraform/`, `root.hcl`,
   `terraform/secrets.enc`, and a `.sops.yaml`. Blocked on §8.
4. **`noisypigeon.com`** — the same two steps, in the same order.
5. **`willowgraysen.com`** — create the repo, hoist its 15 leaves. Last because
   it is the largest consumer and the least documented.
6. **`noisypigeon`** — what remains is content.

Three ordering constraints, all of them external to preference:

- **Step 1 cannot move `pigeon-dev-pages.yml`'s caller.** DEV-0156 established
  that `actions/deploy-pages` targets the calling repo — "not a style choice, a
  constraint" — so the thin caller stays in the repo whose Pages site it deploys.
  The same is already true of `noisypigeon.com`'s caller.
- **Step 1 precedes step 2**, because the generator cannot be taught to read the
  hub's tags before the hub holds them.
- **Steps 2 and 3 are independent and must not be combined.** DEV-0110 made
  "pure rename first, rewiring second" the established pattern for a move the
  release pipeline could misread as a content change, and a PR that both renames
  `src` → `web` and relocates a live Terragrunt tree has two unrelated failure
  modes in one diff.

### 8. The open problem: `state/iam` and the shared root

Each domain's `state/iam` leaf pins the monorepo's shared `root.hcl` by absolute
in-repo path:

```hcl
include {
  path = "${get_repo_root()}/root.hcl"
}
```

Verified present in all three. DEV-0130, DEV-0132 and DEV-0133 each call this
permanent, for a good reason: an IAM-rotation leaf must not depend on the
credential it itself manages. DEV-0133 records the consequence — the pre-DEV-0133
shared state bucket and deployer IAM "remain alive and unmanaged, permanently
load-bearing" for exactly these leaves.

`${get_repo_root()}` cannot cross a repo boundary. **This ADR does not resolve
it**, because the resolution is a per-spoke decision and resolving it here would
pre-empt three ADRs that have more context than this one. The candidates are:
leave `state/iam` behind in `noisypigeon` as the last thing it runs; give each
spoke a second, local bootstrap root distinct from its workload root; or accept
the self-reference and document the rotation runbook. Step 3 is blocked until a
spoke picks one.

Two safety rules carry forward verbatim into every step that moves a leaf.
DEV-0106: `terragrunt init -migrate-state` does not work across a directory move,
so the `state pull`/`push`-via-worktree runbook applies. DEV-0130, the sharper
one: "migrating state into a new location is not complete until the old
location's state is also emptied, not merely orphaned" — with
`--filter-allow-destroy` active, a leaf whose directory disappears from a branch
still gets planned and applied, and stale resource IDs in the old key mean real
destroy calls against live infrastructure.

## Consequences

- **This reverses DEV-0159's permanent boundary, and that is the whole point.**
  That ADR drew a line at "moving `noisypigeon.com/terraform/**`, `root.hcl`, or
  `secrets.enc`", on the grounds that "the new repo holds published/served
  content, not a Terraform-self-sufficient workload." The spoke role asserts the
  opposite: a repo should hold a thing *and* the infrastructure that serves it,
  and the split DEV-0159 preserved is why `noisypigeon` is now a repo of other
  repos' plumbing. DEV-0159 is not wrong about its own step — it was moving
  content out of a monorepo and had nowhere coherent to put Terraform — it is
  wrong as a destination. Nothing here renumbers or edits it.
- **The hub adopts the posture DEV-0155 refused.** That ADR rejected composite
  actions and a shared-CI repo as deliberate boundaries. The letter survives —
  both were about *`pigeon.dev`'s* scope, and `pigeon-lib` is a different repo
  with a stated purpose — but the spirit does not, and pretending otherwise would
  be dishonest. The mitigation is that the hub stays closed to this family.
- **`web/` discards a rationale DEV-0156 chose deliberately.** `pigeon.dev/src`
  was picked to mirror the then-`workloads/<name>/src` convention and to "leave
  room for a second site later without a rename." The convention it mirrored no
  longer exists, and a content-only repo does not need room for a second site.
  It also silently breaks DEV-0160's root-changelog tag precedence, which keys on
  a literal `pigeon.dev/` prefix and would reclassify every site PR as `repo`.
- **Three near-identical `root.hcl` files become one template plus three
  instances — and one template is a single point of failure.** A bad hub version
  can break every spoke's plan at once, which is precisely why invariant 2 pins
  rather than tracking `main`.
- **Every spoke needs its own `.sops.yaml`.** None of the three existing spoke
  repos has one. The *rule* carries over unchanged, which is easy to get wrong in
  the reassuring direction: the monorepo's `^[^/]+/secrets\.enc$` does match
  `terraform/secrets.enc`, so no regex edit is needed — but a missing
  `.sops.yaml` means `sops` cannot encrypt a new value at all.
- **More repos means more cross-repo dispatches that nothing enforces.** The
  release chain already has one silent failure mode; this adds spokes to it.
  Branch protection and merge-order enforcement have now been deferred by
  DEV-0157, DEV-0159, NPC-0000, DEV-0160 and this ADR.
- **`pigeon-cli` is reclassified without being touched.** Its 118-record
  `docs/adr/` stops being an anomaly and becomes the reference implementation. Its
  numbering overlaps the `DEV-` sequence (both run past `0100`), which the prefixes
  make harmless and which nothing else resolves.
- **The `adr/<domain>/` tree now describes an end state it contradicts.** Three
  domains live in `pigeon.dev` while invariant 5 says each spoke owns its own
  `docs/adr/`. `LIB-` records will have to move to `pigeon-lib/docs/adr/` once
  that repo exists, so this domain is transitional by construction — and
  `adr-new.sh`, already broken against the renamed `adr/infrastructure/`
  (DEV-0160), will be wrong in a second way.

## Out of scope

- **Any actual migration.** Permanent boundary for this ADR specifically: no repo
  is created, no file moves, no tag is cut or deleted, no caller is repointed.
  Each step in §7 is its own ADR in its own domain.
- **Choosing the `state/iam` resolution.** Genuinely deferred, deliberately, per
  §8. Needs an issue.
- **Making `pigeon-lib` a general-purpose shared-CI or template repo for
  arbitrary repos or orgs.** Permanent boundary, inherited verbatim from DEV-0155.
  The hub serves this family; nothing in it is designed for an unknown caller.
- **Renumbering or re-prefixing any existing ADR domain.** Permanent boundary.
  `LIB-` is a new domain taking a new prefix, exactly as DEV-0160 provided for;
  it obliges `DEV-`, `NPC-` and `pigeon-cli`'s bare `NNNN` to change nothing.
- **`willowgraysen.com`'s role beyond "spoke and orchestration layer".**
  Genuinely deferred — more is coming on that repo, and this ADR deliberately
  records only what its directory already proves.
- **The `willowgraysen.com` → `noisypigeon.com` redirect's mechanism.** Recorded
  as a documentation gap rather than a decision: no ADR in the corpus describes
  it. The only traces are DEV-0133's relocation of a `redirect/dns` leaf "unchanged"
  and a parenthetical. Read the leaf, not an ADR. Needs an issue.
- **Fixing `adr-new.sh`, `fetch-adrs.sh` and `adr-issue.sh`.** Genuinely
  deferred; all three target the `adr/infrastructure/` path DEV-0160 renamed, all
  three live in `noisypigeon`, and §2 moves their eventual home again. Folding
  this into the existing `noisypigeon/noisypigeon#293` is likely better than a
  second issue.
- **`module-docs.yml`'s hardcoded `working-dir` list,** which names 10 of 13
  modules — `grafana-dashboard`, `iam-api-key` and `iam-application` get no
  generated input/output table. Genuinely deferred, and it should be dynamic
  discovery like `template-release.yml`'s rather than a corrected list. Needs an
  issue.
- **Branch protection or enforcing the cross-repo merge order.** Permanent
  boundary for now, raised for the fifth time.

## Verification

This ADR ships no mechanism, so most of what follows verifies the claims it
rests on. Each is reproducible today.

1. The frozen arm has exactly one live consumer. Cross-referencing every
   `source = "https://pigeon.dev/modules/…"` pin in `noisypigeon` against
   `git tag -l 'templates/terraform/*'` and `legacy-module-tags.txt` leaves
   `scaleway/project/v1.0.0` as the sole pin served only by the legacy list, in
   three files, and reports no pin served by neither arm.
2. Retiring it is free: `git show` of `main.tf`, `inputs.tf`, `outputs.tf` and
   `versions.tf` at legacy `modules/scaleway/project/v1.0.0` and at
   `templates/terraform/scaleway/project/v2.0.0` is identical in all four, and
   the module's `CHANGELOG.md` has no `[2.0.0]` entry — a seed, as DEV-0110
   described. After the bump, a `plan` on the three leaves reports no changes.
3. Invariant 4's arithmetic holds: `pigeon.dev/root.hcl` keys state on
   `"${path_relative_to_include()}/terraform.tfstate"`, so a repo-root `root.hcl`
   with leaves under `terraform/` yields byte-identical keys. The pre-move and
   post-move key for each leaf should be written out and compared literally
   before step 3 runs, not asserted.
4. §8's blocker is real: all three `*/terraform/state/iam/terragrunt.hcl` include
   `"${get_repo_root()}/root.hcl"` at line 2.
5. The `.sops.yaml` claim cuts both ways and both halves should be checked:
   `terraform/secrets.enc` matches `^[^/]+/secrets\.enc$`, and no `.sops.yaml`
   exists in `pigeon.dev`, `noisypigeon.com` or `pigeon-cli`.
6. Every boundary this ADR crosses or inherits is quoted verbatim from the ADR
   cited, and each cited file contains the quoted sentence.
7. Format: `ls adr/pigeon-lib/` holds this file alone; its H1 is `# LIB-0001:`,
   matching the filename; the author line is byte-identical to every other
   post-2026-10-03 record; sections run in house order.
8. On merge, `root-changelog.yml` writes exactly one `- [adr] …` line — the
   changed paths are under `adr/`, which the precedence resolves to `adr` — and
   `template-release.yml` does not run, since no `.tf` and no theme asset
   changes. No `release:*` label is needed and no tag should be cut.

## Amendments

### 2026-10-15: where the implementation deviated

Everything above is left as filed. Each entry below names the section it
corrects and the record or PR that caused the deviation, checked against the
live trees on this date. Where an entry and the text above disagree, the entry
describes what is actually true.

1. **ADR homes (§1, §2, invariant 5; Verification 7).**
   - `LIB-` records live in `pigeon-lib/docs/adr/`, not `adr/pigeon-lib/`
     (LIB-0002). Verification 7's `ls adr/pigeon-lib/` is stale.
   - The spokes keep their records **flat in `adr/`**, not `docs/adr/`:
     `pigeon.dev` since DEV-0161, and `noisypigeon.com` since COM-0002
     (noisypigeon/noisypigeon.com#11).
   - The `noisypigeon.com` domain is **`COM-`**, not `NPC-` (COM-0001). Existing
     `NPC-NNNN` citations, including this record's, are aliases and are never
     rewritten, the same treatment DEV-0160 gave `ADR-`.
   - `willowgraysen.com` opened a fourth spoke domain, **`RUN-`** (RUN-0000). It
     is named for what the namespace holds, `pigeon-cli` and the data-ops
     projects, rather than for the domain.
2. **The role table (§2).**
   - The hub's roots are flat: `terraform/`, `zola-site/`, `terragrunt/root-hcl/`
     and `.github/`. There is no `templates/` segment on directories or tags
     (LIB-0002 §1, LIB-0003).
   - **`pigeon.dev`** holds `web/` (DEV-0162), `adr/`, `terraform/`, `spoke.hcl`
     and a **generated, committed** `root.hcl` (DEV-0163, LIB-0003). It holds no
     `docs/adr/`.
   - **`noisypigeon.com`** holds `web/`, including the blog's long-form
     `web/CHANGELOG.md`, and `adr/` (COM-0001, COM-0002), plus `terraform/`,
     `spoke.hcl` and a generated, committed `root.hcl` (COM-0003). There is no
     `docs/blog/{posts,media}`; posts and media are `web/content/` and
     `web/static/`.
   - **`willowgraysen.com`** holds `terraform/`, `spoke.hcl`, a generated,
     committed `root.hcl` and `adr/` (RUN-0000, RUN-0001). It has no `web/`,
     because the domain's only web presence is the redirect it manages. The
     table's `docs/adr/` became `adr/`, like the other spokes.
3. **Invariant 1 has exactly one exception: `fetch-lib.sh`** (DEV-0162).
   - A spoke cannot fetch its own fetcher.
   - Every other spoke workflow is now a thin caller, including the root
     changelog writer, through the reusable `spoke-root-changelog.yml`
     (pigeon-lib#14; DEV-0162, COM-0002).
   - `zola-site-deploy.yml` was deleted, not moved (LIB-0002 §2).
4. **Invariant 2's mechanism.** A spoke pins **two kinds** of version.
   - `/.lib-version` names a `workflows/vX.Y.Z` tag. That is a third release
     track this record did not foresee, versioning `.github/workflows/` and
     `.github/scripts/` together (LIB-0002 §3). `fetch-lib.sh` materializes it
     into `.lib-src/`.
   - Per-asset pins sit beside it: `[extra].theme_version` for the theme, and
     `root_hcl_version` in `spoke.hcl` for the `terragrunt/root-hcl/vX.Y.Z`
     template, a fourth track (LIB-0003).
5. **Invariant 4 and §6, as realized.**
   - Secrets live at `terraform/secrets.enc`, with `.sops.yaml` rule
     `^terraform/secrets\.enc$`.
   - The template is materialized, not `include`d, by
     `.github/scripts/resolve-root-hcl.sh`, as §6 said. It is also **committed**,
     because Terragrunt's `[main...HEAD]` filter plans inside git worktrees that
     hold only tracked files. CI runs the resolver with `--check` to catch drift
     (LIB-0003 and its amendment).
   - A spoke's `spoke.hcl` carries the state-bucket secret name, not §3's six
     differences; the rest belonged to the monorepo's shared root, which no spoke
     inherits. `willowgraysen.com` also sets the two optional extensions that
     template `v1.1.0` added for it: `backblaze = true` and a `grafana` entry in
     `extra_required_providers` (LIB-0003's second amendment).
   - The key arithmetic held exactly. DEV-0163 §2, COM-0003 §2 and RUN-0001 §2
     tabulate 24 unchanged keys between them, and no hoist planned a destroy.
   - **A leaf's state can be ahead of its committed config.** RUN-0001 §6 found an
     IAM policy and API key in `willowgraysen.com`'s
     `pigeon-cli/bucket/pigeon/deduplicate` state, applied from a worktree that
     was never committed, and planned for destruction. It was brought into
     config rather than deleted. Before a hoist, plan each leaf from a clean
     environment; a shell with exported credentials can plan something different
     from what CI sees.
6. **Rollout (§7).**
   - Steps 1 and 2 shipped as one effort, because neither could land alone
     (LIB-0002).
   - Step 3 is done for `pigeon.dev` (DEV-0163, noisypigeon/pigeon.dev#25,
     noisypigeon/noisypigeon#307).
   - Step 4 is done. The content half is COM-0001 and COM-0002. The Terraform
     half is COM-0003 (noisypigeon/noisypigeon.com#13, noisypigeon/noisypigeon#311),
     which reused template `v1.0.1` and `workflows/v1.3.1` with no hub change.
   - Step 5 is done. `noisypigeon/willowgraysen.com` was created and
     bootstrapped (RUN-0000, noisypigeon/willowgraysen.com#1), and fourteen of
     its fifteen leaves were hoisted (RUN-0001, noisypigeon/willowgraysen.com#2,
     noisypigeon/noisypigeon#312). The repo is public, by choice, with the
     shared age key and a `contributors_only` interaction limit; RUN-0000 §1
     records what that accepts.
   - Step 6 is not done, and §7 below explains why it cannot be done as written:
     `noisypigeon` still runs three `state/iam` leaves.
   - §7's "steps 2 and 3 must not be combined" held.
7. **§8, for all three spokes: option 1.** Every domain's `state/iam` leaf stays
   in `noisypigeon/noisypigeon`, on the shared root, `.env.enc` and shared
   bucket (DEV-0163 §1, COM-0003 §1, RUN-0001 §1). That is now the **only**
   Terraform in `noisypigeon`. Step 6 therefore cannot leave `noisypigeon`
   content-only while that choice stands; its realistic end state is "content
   plus the three bootstrap leaves". noisypigeon/noisypigeon#308 is closed.
8. **Consequences, corrected.**
   - "`web/` … silently breaks DEV-0160's root-changelog tag precedence" was
     fixed when it happened: `^web/` is labelled `pigeon.dev` (DEV-0162).
   - "Every spoke needs its own `.sops.yaml`" is now true of all three spokes
     (DEV-0163, COM-0003, RUN-0001).
   - "Branch protection … deferred" was never true of `noisypigeon`, which has
     had a ruleset requiring the `terragrunt/apply` status since ADR-0129.
     All three spokes gained a copy of it with their Terraform (DEV-0163,
     COM-0003, RUN-0001), resolving noisypigeon/noisypigeon#295. Only
     `pigeon-lib` remains unprotected.
   - The hub ended with two cross-repo dispatches, as LIB-0002 recorded, and with
     **four** copies of the release predicates in two files, not three
     (LIB-0003; noisypigeon/noisypigeon#301).
9. **Out-of-scope items now tracked.**
   - `state/iam` resolution: noisypigeon/noisypigeon#308, now closed (§7).
   - The `willowgraysen.com` → `noisypigeon.com` redirect documentation gap:
     noisypigeon/noisypigeon#309.
   - `module-docs.yml`'s hand-maintained list: noisypigeon/noisypigeon#302.
   - The ADR scripts: noisypigeon/noisypigeon#293, as suggested.
   - Found while verifying step 3, and new: the Terragrunt apply flow's
     auto-merge has never worked, because the job token lacks
     `contents: write`. Tracked as noisypigeon/noisypigeon#310.

### 2026-10-17: LIB-0017 reverses invariant 5 for garden, blog and runway

LIB-0017 decides that `garden`, `blog` and `runway` hold no ADRs. They are
spokes, and the design standards they follow are this repo's. That reverses
three things above:

- **Invariant 5** ("Each spoke owns its own `docs/adr/`") for those three
  spokes. `pigeon-cli` keeps its own `docs/adr/` (LIB-0017 §5).
- **The `docs/adr/` entries** for `pigeon.dev`, `noisypigeon.com` and
  `willowgraysen.com` in §2's role table.
- **Item 1 of the 2026-10-15 amendment**, which recorded the spokes' flat
  `adr/` homes and their `COM-` and `RUN-` domains.

A decision about one of those spokes is now filed here. The `DEV-` corpus is
archived verbatim under [`archive/`](archive/README.md). The `COM-` and `RUN-`
records, and the four `DEV-` records written after this hub existed
(DEV-0162 to DEV-0165), are folded into the `LIB-` records whose standards
they apply, as amendments whose headings carry their IDs. No new `DEV-`,
`COM-`, `RUN-` or `NPC-` number will be issued.

The three entries below fold in the records that belong to this ADR: the two
spoke bootstraps, and the blog's ADR and changelog layout.

### 2026-10-17: COM-0000, bootstrap the `noisypigeon.com` repo (folded from `noisypigeon/blog`)

Filed 2026-10-13 as `NPC-0000` in `noisypigeon/noisypigeon.com`, the day
before this record. Accepted.

**Why.** DEV-0159 moved the blog's source into its own repo and stopped there.
The repo held four non-content files and no `CLAUDE.md`, `README.md`,
`.gitignore` or `.mise.toml`. Zola's version was pinned only in the monorepo,
the build tasks pointed at a path the new repo didn't have, and the generated
`.templates-src/`, theme symlink and `public/` had no ignore rule. The reusable
`blog-changelog.yml` also wrote a root rollup line the repo had no file for,
so its next content PR would have failed.

**Decision.**

1. **A prefixed ADR domain.** `adr/noisypigeon.com/` opened with `NPC-` IDs
   numbered from `0000`. It was the first per-repo prefixed domain, the
   precedent DEV-0160 generalized and §1 above used. Prefixing an existing
   domain was declared out of bounds.
2. **The rollup became optional.** `blog-changelog.yml` gained an optional
   `changelog_path`. `root_changelog_tag` defaulted to empty, meaning no
   rollup, and the rollup gained the create-if-missing guard it lacked.
3. **The changelog moved to the repo root,** byte for byte. Its five-line
   header is structural, because CI splices on `head -n 5`.
4. **The repo became buildable from a clean clone.** `.mise.toml` pins
   `zola = "0.23.6"` and runs the hub fetch as a `postinstall` hook, so
   `mise install` alone is enough. `.gitignore` covers the three generated
   paths, and `CLAUDE.md` and `README.md` say where every dependency lives.

**Still true.** The blog's long-form changelog keeps its inherited monorepo
history, deliberately not rewritten. `mise install` needs the network.

**Later.** COM-0001 renamed the domain `COM-`, moved the site to `web/`, and
adopted DEV-0160's one-line root changelog. COM-0002 flattened the ADRs to
`adr/`, and LIB-0017 removed them. Its out-of-scope issues were
noisypigeon/noisypigeon#292 (the flatten, answered by COM-0001's `web/`),
#293 (`adr-new.sh`), #294 (stale ADR pointers) and #295 (branch protection,
partly resolved by the spoke rulesets in LIB-0003's amendments).

Original: [COM-0000](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0000-bootstrap-noisypigeon-com-repo.md).

### 2026-10-17: COM-0002, flat `adr/` and the reusable root changelog (folded from `noisypigeon/blog`)

Filed 2026-10-15. Accepted.

**Decision.**

1. **ADRs moved to `adr/`.** `docs/adr/` became `adr/` (noisypigeon.com#11) as
   a pure move, as DEV-0161 did for `pigeon.dev`. That is the layout item 1 of
   the 2026-10-15 amendment records, and LIB-0017 has since removed it.
2. **`root-changelog.yml` became a thin caller** of the hub's
   `spoke-root-changelog.yml` (pigeon-lib#14, `workflows/v1.2.0`). The
   reusable takes the tag precedence as ordered `<ERE>=<tag>` lines, first
   match wins, plus a `fallback_tag` that defaults to `repo`. The blog passes
   `^web/=blog`, `^adr/=adr` and `^\.github/=ci`. The caller keeps only what
   cannot live in the hub: the trigger, the merged-only gate, permissions,
   concurrency and the precedence. With that, `fetch-lib.sh` is invariant 1's
   only exception (item 3 of the 2026-10-15 amendment). It closed
   noisypigeon/noisypigeon#306.
3. **The root writer got its own concurrency group.** It moved to
   `main-writer-rollup`, and `blog-changelog.yml` stays in `main-writer`. A
   shared group keeps at most one pending run and cancels the earlier one,
   which lost a hub release before (pigeon-lib#9). The reusable instead
   retries a rejected push five times, rebasing each time, and fails outright
   on a rebase conflict.

**Still true.** Changing a spoke's precedence is a one-line caller edit.
Changing how precedence is interpreted is a hub PR and a pin bump. A blog
PR's two bot commits can now race for `main`, and the retry absorbs that.

**Later.** COM-0003 added `terraform` tagging. Since LIB-0017, the `^adr/=adr`
line matches nothing.

Original: [COM-0002](https://github.com/noisypigeon/blog/blob/a25084ae1e8f70afcd6eb72fadb88815b48b15f1/adr/COM-0002-flatten-adr-and-call-the-reusable-root-changelog.md).

### 2026-10-17: RUN-0000, bootstrap the `willowgraysen.com` repo (folded from `noisypigeon/runway`)

Filed 2026-10-15 in `noisypigeon/willowgraysen.com`, which was later renamed
`willowgraysen` and then `runway` (LIB-0013). This is the first half of §7
step 5. Accepted.

**Context.** This spoke differs from the other two in three ways:

- It has no website. The domain's HTTPS endpoint was a redirect to
  `noisypigeon.com`, so there is no `web/`, no Pages deploy and no
  blog-changelog.
- It is a namespace for what *runs*, `pigeon-cli` and the data-ops projects,
  rather than a site.
- It is the family's most sensitive account. Its secrets include third-party
  storage credentials, and its buckets hold custodial and archival data.

**Decision.**

1. **Public, deliberately.**
   - Costs accepted: every Terraform plan is posted publicly (values masked,
     structure visible), the imported history is public in a second place,
     and the repo shares one age key with the other spokes.
   - Private was rejected because a ruleset on a private repo needs a paid
     plan on a personal account, which would have made the `terragrunt/apply`
     merge gate advisory.
   - Mitigations: `CLAUDE.md` opens with the sensitivity rules (everything
     pushed is public and permanent, no resource names in prose, read the
     whole plan before applying). Records describe resources by role, not by
     name, and **that rule now binds any `LIB-` record about this spoke**.
     The repo also has a `contributors_only` interaction limit, RUN-0001's
     comment-gated apply, and the ruleset.
2. **A `RUN-` domain,** named for what the namespace holds rather than for the
   domain.
3. **Everything but the Terraform.** `fetch-lib.sh` and `.lib-version`
   (`workflows/v1.3.1` then), `.mise.toml`, a `.gitignore` that does not
   ignore `root.hcl`, a thin root-changelog caller, a thin
   `interaction-limits-renew.yml` caller, `CLAUDE.md` and `README.md`. The
   Terraform was RUN-0001's.
4. **The provisioning checklist,** recorded because no runbook had one and
   LIB-0002 found a new repo's first runs fail without it:
   - repo secrets `BOT_GITHUB_TOKEN`, `GH_ADMIN_TOKEN` and `SOPS_AGE_KEY`,
     each with the same value as `noisypigeon`'s;
   - the bot account as a write collaborator, invitation accepted;
   - the interaction limit, applied once by dispatching
     `interaction-limits-renew.yml` and renewed monthly after that;
   - merge commits enabled only until the Terraform import merges.

**Out of scope, and still permanent for now.**

- A dedicated age key and credential rotation. The existing ciphertext is
  already public under the shared key, so real isolation would also mean
  rotating the credentials.
- Further Actions hardening: required approval for fork-PR workflows, and
  read-only default token permissions. Fork PRs get no secrets either way, and
  every workflow declares its own permissions.

Original: [RUN-0000](https://github.com/noisypigeon/runway/blob/2ab560c516d76c90482ad963c62525f800e923fe/adr/RUN-0000-bootstrap-willowgraysen-com-repo-and-open-the-run-domain.md).

### 2026-10-19: pigeon-cli consumes the hub (CLI-0161)

§2's pigeon-cli row ("Already conformant; consumes nothing from the hub
today") is no longer true. [CLI-0161](https://github.com/noisypigeon/pigeon-cli/blob/5aecb66458f766946fe1f976d249b2c91e9b522a/docs/adr/0161-align-with-hub-and-spoke.md) aligns pigeon-cli with this
architecture:

- Its release workflow body and all four of its scripts move here, as the
  reusable `rust-crate-release.yml` and `.github/scripts/crate-*.sh` plus
  `adr-issue.sh`, on the `workflows/vX.Y.Z` track. pigeon-cli keeps a thin
  caller and pins the library through `fetch-lib.sh` and `.lib-version`, the
  same way blog and runway do.
- Its local observability stack moves here as `observability/pigeon-cli/`,
  versioned as `observability/pigeon-cli/vX.Y.Z`, and loads
  `grafana-dashboards/pigeon-cli` instead of keeping its own copy.
- Its `analyze-job-run` skill moves here as a Claude Code plugin,
  `claude-plugins/pigeon-cli/`, versioned as `claude-plugins/pigeon-cli/vX.Y.Z`.
- Its corpus moves to a flat `adr/` with the prefix **`CLI-`**.

The row now reads: **`pigeon-cli`** holds source, `adr/` (`CLI-`), a thin
release caller, `fetch-lib.sh` and `.lib-version`. It is a spoke that consumes
the hub's workflows, scripts, observability stack and skills plugin.

pigeon-cli departs from this record in exactly these ways, recorded in
CLI-0161 §6:

- **It writes its own tags.** §4 says "a spoke never writes a tag", but a crate's
  `vX.Y.Z` tags must point at the crate's own commits. Its release commit,
  `CHANGELOG.md` bump and crates.io publish stay there too. The hub provides
  the mechanism, and the release act is the spoke's.
- **It keeps its own ADRs, changelog convention and `Dockerfile`** (LIB-0017's
  2026-10-19 amendment).

### 2026-10-20: LIB-0023 relaxes invariants 2 and 4 for workload leaves

LIB-0023, if accepted, adds workload leaves, generated from a spoke's
`workloads/<workload>/values.yaml`. It makes two bounded exceptions for them.

**Invariant 2.** A workload leaf may leave a module's `version` unpinned, or
pin only its major or minor. The template then resolves the newest matching
`terraform/<provider>/<module>/v*` tag at every plan.

- It is still a tag, never a branch.
- Every other pin stays exact: `/.lib-version`, `root_hcl_version`, and every
  hand-written leaf.
- It rests on LIB-0022: apply runs only the saved plan for the PR's head, so a
  release that lands after the plan cannot reach state unreviewed.

**Invariant 4.** Leaves may also live under `workloads/` at the repo root,
beside `terraform/`. The arithmetic is unchanged: a workload leaf's key is
`path_relative_to_include()`, in the spoke's one state bucket. Its key never
moves unless its path does, and it can't collide with a `terraform/` key,
because the first segment differs.
