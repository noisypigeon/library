# LIB-0001: a composable hub-and-spoke repo architecture, and the `LIB-` ADR domain

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-13.
- **Status**: Accepted.

## Context

Over three days — PD-0154 through PD-0160, plus `noisypigeon/noisypigeon#289` —
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
  PD-0157 counted "four distinct kinds of thing … plus its own site" as a
  consequence worth noting; it has not gone down since.
- **`noisypigeon`** holds three domains' Terraform (`noisypigeon.com/`,
  `pigeon.dev/`, `willowgraysen.com/`) and none of their content. PD-0154 called
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
  conversation PD-0157 had about where ADRs belong. It is the one repo already
  shaped the way this ADR argues every repo should be.

Four concrete symptoms, all verified against the live tree rather than against
prior prose.

### 1. "Reusable" and "mine" are mixed in one repo, and the seams show

`pigeon.dev` has ten workflows. Six are pure `workflow_call` reusables and
**five of those have no caller in the repo at all** — they exist solely to serve
`noisypigeon` and `noisypigeon.com`. The other four are repo-local. Nothing in
the layout distinguishes them; you find out by reading `on:`.

`zola-site-deploy.yml:60` runs `noisypigeon.com/fetch-templates.sh` — a path
into a *caller's* checkout, hardcoded, left behind when PD-0159 moved that file
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
well-formed, wrong answer. PD-0156 collapsed these couplings by colocation; that
worked, and it is also why they are now invisible.

### 3. Three `root.hcl` files are near-copies of each other and of a fourth

`noisypigeon.com/root.hcl`, `pigeon.dev/root.hcl` and
`willowgraysen.com/root.hcl` are 5877, 5857 and 8080 bytes. They differ in
exactly six ways: which `secrets.enc` they read, an `is_valid_leaf` segment
index, the state-bucket key name, whether the state key carries a `workloads/`
prefix, `willowgraysen.com`'s latent Backblaze provider (PD-0148), and its extra
`grafana/grafana` requirement. Everything else — the sops decryption dance, the
`ENV_SW_`/`ENV_CF_` prefix-stripping, the four `generate` blocks, the `exclude`
block, the `scaleway_config.hcl` override — is duplicated prose.

PD-0059 declined to template this, and was right to: there was one of them. Its
own words were "`root.hcl` for a new account is still a real file a human
writes", and PD-0053 said plainly that "if a second domain or DO team is added
later, revisit this decision rather than retrofitting it silently." There are
now four. The duplication has already decayed: the shared `root.hcl` still keys
state on `workloads/${path_relative_to_include()}` though `workloads/` was
deleted, and its `is_pigeon_dev_leaf` branch computes a condition whose two
arms are character-for-character identical — a per-domain token split that the
comment above it still describes and the code no longer does.

### 4. The frozen tag arm is one no-op bump away from being deletable

PD-0154 split module tags across two repos and PD-0156 froze the older arm into
a committed list, `pigeon.dev/legacy-module-tags.txt`, rather than "shelling into
a repo it no longer has local access to" — safe, it argued, "specifically
*because* ADR-0154 established the set as frozen and permanently unable to grow".
The generator's own comment puts the reason plainly: the list exists "since this
repo has no other way to know about tags that live in a different one."
PD-0154 then drew a **permanent boundary** around those 20 tags: deleting them
"would break live infrastructure", because one of them was still pinned.

Checked against the live tree, that is true of exactly one version — and it was
already true when PD-0156 checked, which recorded `scaleway/project/v1.0.0` as
"the only legacy tag among the 75 live `source =` lines' pinned versions". The
line count has since fallen to 32, with the flatten and the bucket
decommissions, but the conclusion is unchanged: 31 of those pins resolve through
the `templates/terraform` arm, and one does not. It is pinned in
`noisypigeon.com/terraform/project/project.tf`,
`pigeon.dev/terraform/project/project.tf` and
`willowgraysen.com/terraform/project/project.tf`.

And `templates/terraform/scaleway/project/v2.0.0` already exists. It is one of
PD-0110's bookkeeping seed tags, cut because a path move is breaking by
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

This is the pattern NPC-0000 established and PD-0160 generalized — "a future
domain picks its own prefix and its own sequence" — exercised for the third
domain and the first one whose subject repo does not exist yet. The house format
is unchanged: no frontmatter, an H1 plus `Author`/`Date`/`Status` bullets,
`## Context` / `## Decision` / `## Consequences` / `## Out of scope` with an
optional `## Verification`, no index to update, and the author line PD-0160 made
canonical. Per PD-0031, genuinely-deferred `## Out of scope` items are filed as
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

"Hub" is a role, not a privilege: `pigeon-lib` is closed to this family. PD-0155
rejected "a general-purpose shared-CI repo for arbitrary repos or orgs" as a
deliberate boundary and that judgment carries over unchanged — see
`## Out of scope`.

### 3. The five invariants

These are the contract. Everything else in this ADR is a consequence of them.

1. **The hub owns every reusable asset.** A spoke contains no scripts and no
   workflow bodies — only thin callers, content, and its own Terraform.
2. **The hub publishes versions; spokes consume versions, never branches.** Each
   spoke declares one hub version, the way a site already declares
   `[extra].theme_version` (PD-0114), and the deploy fetches that ref into a
   gitignored directory before building. This generalizes the mechanism
   `fetch-templates.sh` and `.templates-src/` already implement for the theme,
   and makes it the only way in.
3. **Public interfaces are decoupled from internal layout.**
   `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` is permanent regardless of
   which repo, directory, or tag shape backs it. PD-0110 called the line that
   holds `url_path` literal "the entire stable-URL guarantee"; it stays literal.
   Tag shape is private to the hub.
4. **A spoke's Terraform state keys do not change when it moves.** A spoke keeps
   `root.hcl` at its repo root with leaves under `terraform/` and secrets at
   `terraform/secrets.enc`. This is load-bearing arithmetic, not taste: the
   per-domain key is `"${path_relative_to_include()}/terraform.tfstate"`, so a
   leaf at `<domain>/terraform/state/bucket` under `<domain>/root.hcl` and a leaf
   at `terraform/state/bucket` under a repo-root `root.hcl` both resolve to
   `terraform/state/bucket/terraform.tfstate`. Put `root.hcl` *inside*
   `terraform/` instead and every key silently shortens — PD-0059 hit exactly
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
> inference is recorded here rather than hidden. The ordering constraint PD-0154
> already identified survives the change and gets worse: a dispatch that fails is
> "the one piece that fails silently … the release still cuts its tag and the
> site simply never redeploys, leaving a version whose short URL 404s."

### 5. One tag rule, not a mapping

The brief settles the question PD-0154 and PD-0156 had to work around: tag
organization is **private to the hub**, because `pigeon.dev` is its only
consumer, and it may be reorganized freely so long as the short URL is stable.
Invariant 3 is what makes that safe.

So the end state is a single rule rather than a growing table. All module tags
live in `pigeon-lib`, shaped `terraform/<provider>/<module>/vX.Y.Z` and
`zola-site/vX.Y.Z` — dropping the `templates/` segment that only ever existed to
keep a previous move's blast radius down. This is the flatten PD-0154 deferred
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

To be precise about PD-0154's boundary rather than brushing past it: that
boundary was "deleting or rewriting any tag in `noisypigeon`", justified
because "§2 and §3 both depend on all 105 existing tags staying exactly where
they point" and because one was live-pinned. Bumping the pin removes the
justification, and this ADR does not need the boundary lifted anyway — dropping
the *mapping arm* requires no tag in `noisypigeon` to be touched. The 20 tags
can stay where they are forever, unreferenced.

### 6. `root.hcl` becomes a versioned template

`templates/terragrunt/root-hcl/` joins the hub as a third `templates/<kind>/` —
the sibling PD-0154 explicitly left room for. A spoke's `root.hcl` becomes a
thin instance declaring only the six things `## Context` §3 measured as
genuinely varying, with everything else coming from the pinned template.

The constraint to design against is Terragrunt's, not ours: PD-0059 found that
"Terragrunt does not support nested includes" and that a `common.hcl` local
cannot forward-reference `root.hcl`'s own `local.secrets`. So the template is
materialized into the spoke at build/plan time by the pinned hub fetch, not
`include`d — the same shape `resolve-theme.sh` already uses for the theme, and
the reason that script resolves its root from `${BASH_SOURCE[0]}` rather than
`git rev-parse` (PD-0154).

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

- **Step 1 cannot move `pigeon-dev-pages.yml`'s caller.** PD-0156 established
  that `actions/deploy-pages` targets the calling repo — "not a style choice, a
  constraint" — so the thin caller stays in the repo whose Pages site it deploys.
  The same is already true of `noisypigeon.com`'s caller.
- **Step 1 precedes step 2**, because the generator cannot be taught to read the
  hub's tags before the hub holds them.
- **Steps 2 and 3 are independent and must not be combined.** PD-0110 made
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

Verified present in all three. PD-0130, PD-0132 and PD-0133 each call this
permanent, for a good reason: an IAM-rotation leaf must not depend on the
credential it itself manages. PD-0133 records the consequence — the pre-PD-0133
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
PD-0106: `terragrunt init -migrate-state` does not work across a directory move,
so the `state pull`/`push`-via-worktree runbook applies. PD-0130, the sharper
one: "migrating state into a new location is not complete until the old
location's state is also emptied, not merely orphaned" — with
`--filter-allow-destroy` active, a leaf whose directory disappears from a branch
still gets planned and applied, and stale resource IDs in the old key mean real
destroy calls against live infrastructure.

## Consequences

- **This reverses PD-0159's permanent boundary, and that is the whole point.**
  That ADR drew a line at "moving `noisypigeon.com/terraform/**`, `root.hcl`, or
  `secrets.enc`", on the grounds that "the new repo holds published/served
  content, not a Terraform-self-sufficient workload." The spoke role asserts the
  opposite: a repo should hold a thing *and* the infrastructure that serves it,
  and the split PD-0159 preserved is why `noisypigeon` is now a repo of other
  repos' plumbing. PD-0159 is not wrong about its own step — it was moving
  content out of a monorepo and had nowhere coherent to put Terraform — it is
  wrong as a destination. Nothing here renumbers or edits it.
- **The hub adopts the posture PD-0155 refused.** That ADR rejected composite
  actions and a shared-CI repo as deliberate boundaries. The letter survives —
  both were about *`pigeon.dev`'s* scope, and `pigeon-lib` is a different repo
  with a stated purpose — but the spirit does not, and pretending otherwise would
  be dishonest. The mitigation is that the hub stays closed to this family.
- **`web/` discards a rationale PD-0156 chose deliberately.** `pigeon.dev/src`
  was picked to mirror the then-`workloads/<name>/src` convention and to "leave
  room for a second site later without a rename." The convention it mirrored no
  longer exists, and a content-only repo does not need room for a second site.
  It also silently breaks PD-0160's root-changelog tag precedence, which keys on
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
  PD-0157, PD-0159, NPC-0000, PD-0160 and this ADR.
- **`pigeon-cli` is reclassified without being touched.** Its 118-record
  `docs/adr/` stops being an anomaly and becomes the reference implementation. Its
  numbering overlaps the `PD-` sequence (both run past `0100`), which the prefixes
  make harmless and which nothing else resolves.
- **The `adr/<domain>/` tree now describes an end state it contradicts.** Three
  domains live in `pigeon.dev` while invariant 5 says each spoke owns its own
  `docs/adr/`. `LIB-` records will have to move to `pigeon-lib/docs/adr/` once
  that repo exists, so this domain is transitional by construction — and
  `adr-new.sh`, already broken against the renamed `adr/infrastructure/`
  (PD-0160), will be wrong in a second way.

## Out of scope

- **Any actual migration.** Permanent boundary for this ADR specifically: no repo
  is created, no file moves, no tag is cut or deleted, no caller is repointed.
  Each step in §7 is its own ADR in its own domain.
- **Choosing the `state/iam` resolution.** Genuinely deferred, deliberately, per
  §8. Needs an issue.
- **Making `pigeon-lib` a general-purpose shared-CI or template repo for
  arbitrary repos or orgs.** Permanent boundary, inherited verbatim from PD-0155.
  The hub serves this family; nothing in it is designed for an unknown caller.
- **Renumbering or re-prefixing any existing ADR domain.** Permanent boundary.
  `LIB-` is a new domain taking a new prefix, exactly as PD-0160 provided for;
  it obliges `PD-`, `NPC-` and `pigeon-cli`'s bare `NNNN` to change nothing.
- **`willowgraysen.com`'s role beyond "spoke and orchestration layer".**
  Genuinely deferred — more is coming on that repo, and this ADR deliberately
  records only what its directory already proves.
- **The `willowgraysen.com` → `noisypigeon.com` redirect's mechanism.** Recorded
  as a documentation gap rather than a decision: no ADR in the corpus describes
  it. The only traces are PD-0133's relocation of a `redirect/dns` leaf "unchanged"
  and a parenthetical. Read the leaf, not an ADR. Needs an issue.
- **Fixing `adr-new.sh`, `fetch-adrs.sh` and `adr-issue.sh`.** Genuinely
  deferred; all three target the `adr/infrastructure/` path PD-0160 renamed, all
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
   the module's `CHANGELOG.md` has no `[2.0.0]` entry — a seed, as PD-0110
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
