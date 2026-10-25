# LIB-0037: Workloads live in their zone

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-25.
- **Status**: Proposed. Amends:
  - LIB-0023 §§1, 4 and LIB-0025 §2, whose `workloads/<w>/values.yaml` and
    `secrets.yaml` become `workloads/<zone>/<w>/workload.yaml` and
    `secrets.workload.yaml`;
  - LIB-0028 §§1–2, whose workload project becomes its zone's by default, and
    whose state bucket gains the workload's name;
  - LIB-0030 §3, whose `cloudflare.zone` the directory replaces;
  - LIB-0034 §§1–2, whose `features.githubPages` becomes
    `deployments.githubPages`, with defaults, and whose records follow the
    workload's host;
  - LIB-0036 §§1, 3 and its Out of scope, whose `workload` key becomes
    `hosts`, so a zone holds several workloads.

## Context

LIB-0036 made a zone a unit, but a workload still sits beside it. Four
things follow from that.

- **A workload's zone is a key, not a place.** `workloads/blog/values.yaml`
  names `cloudflare.zone: noisypigeon.com`, and the zone's `zone.yaml` names
  `workload: blog` back. Each file has to agree with the other, and nothing in
  the tree shows which workloads a zone holds.
- **A zone holds at most one workload.** LIB-0036 made that a design boundary,
  so a record's owner was always one file or the other. It also means a
  subdomain can't be its own site: `docs.noisypigeon.com` would need a second
  workload in noisypigeon.com.
- **Every workload has its own Scaleway project.** blog's project,
  `blog-noisypigeon`, holds only its deployer and its state bucket. Its zone,
  noisypigeon.com, has a project of its own beside it. That makes two
  projects, two prefixes (`blog` and `npc`) and two places to look for one
  site.
- **`features.githubPages` restates what's already known.** runway's blog
  writes `pagesShim: noisypigeon/noisypigeon.com` and
  `pagesBaseUrl: noisypigeon.github.io`. The owner is the spoke repo's owner,
  the shim is named for the domain, and the Pages host is the owner's
  `github.io`.

The file names are a smaller annoyance. `values.yaml` and `secrets.yaml` sit
beside a site's `config.toml` and `content/`, and say nothing about what they
configure.

## Decision

### 1. `workloads/<zone>/<workload>/workload.yaml`

A workload lives under its zone:

```
workloads/noisypigeon.com/blog/workload.yaml
workloads/noisypigeon.com/blog/secrets.workload.yaml
workloads/noisypigeon.com/blog/<provider>/<module>/<instance>/terragrunt.hcl
```

- **`workload.yaml` replaces `values.yaml`,** with LIB-0023's kinds and
  defaults except as below. **`secrets.workload.yaml` replaces
  `secrets.yaml`,** with LIB-0025's shape. The spoke's `.sops.yaml` rule
  becomes `^workloads/[^/]+/[^/]+/secrets\.workload\.yaml$`.
- **The directory names the zone.** `<zone>` must be an apex domain with a
  `zones/<zone>/zone.yaml`, and `cloudflare.zone` is refused, as it is in a
  zone's file (LIB-0036 §1). Every zone kind acts on that zone.
- **`name`** defaults to the workload's directory, as a zone's does. It's the
  workload's part in every name (§2), so it must be kebab-case, and it can't
  be `zone`, which LIB-0036 §2 reserves for a zone's own resources.
- **A leaf is six segments deep:**
  `workloads/<zone>/<workload>/<provider>/<module>/<instance>/`. Its state
  key is still its path relative to `root.hcl` (LIB-0001 invariant 4).
- **The old names are refused,** each with a message naming this record:
  a `workloads/<w>/values.yaml`, a `secrets.yaml` beside a `workload.yaml`,
  and a `workload.yaml` at the old depth.

#### `workloads/private/<workload>/`

A workload with no zone lives under the reserved `workloads/private/`.

- **`private` can't be a zone,** since a zone's directory always has a dot.
- **A private workload has its own project,** as every workload has today
  (§2). It has no host (§3), no `deployments.githubPages` (§4) and no zone
  kinds. It may still declare an R2 `cloudflare.bucket`, and then gets a
  Cloudflare token with R2 access only.

### 2. `deployments.scaleway.project`: a workload lives in its zone's project

By default a workload's Scaleway resources live in its zone's project. It
has no project leaf of its own.

```yaml
# workloads/noisypigeon.com/blog/workload.yaml
name: blog              # default: the directory
deployments:
  scaleway:
    project: {}         # default: the zone's project
```

- **`prefix` and `suffix` default to the zone's.** They move from
  `workload.yaml`'s top level into `deployments.scaleway.project`, where a
  zoned workload rarely writes them.
- **Setting any of `name`, `prefix` or `suffix` there gives the workload its
  own project,** as LIB-0028 §1 does today, with the project's other inputs
  under the same key. A private workload always has its own, so it must set
  `prefix` and `suffix`.
- **The workload keeps its own deployer and state bucket,** in whichever
  project it's in. Its state never mixes with its zone's or a sibling's.

Its implicit resources are named as below, for blog in noisypigeon.com
(`prefix: npc`, `suffix: noisypigeon`):

| Leaf | Name | Example |
| --- | --- | --- |
| `scaleway/project/main` | only with its own project: `<prefix>-<suffix>` | none |
| `scaleway/terraform-deployer-iam/main` | `<prefix>-<suffix>-<name>-deployer` | `npc-noisypigeon-blog-deployer` |
| `scaleway/bucket/state` | `<prefix>-<code>-<name>-terraform-state` | `npc-<code>-blog-terraform-state` |
| `cloudflare/api-token/deployer` | `<prefix>-<suffix>-<name>-cloudflare-deployer` | `npc-noisypigeon-blog-cloudflare-deployer` |

- **`<name>` keeps siblings apart.** Two workloads in one zone share its
  prefix and suffix, so the name is what tells their resources apart. A zone's
  own resources carry `zone` in the same place.
- **The state bucket's name is one rule everywhere,** in the zone's project or
  its own. A name over 63 characters is refused before planning. Its key
  prefix is `workloads/<zone>/<workload>/`.
- **The deployer is scoped to the project it's in.** Scaleway's IAM policies
  scope to a project, not a bucket, so a deployer in the zone's project can
  reach the zone's state bucket and its siblings'. That's the price of one
  project per zone. A workload that needs a hard boundary sets its own
  project. LIB-0028 §5's `ObjectStorageFullAccess` guard applies unchanged.
- **A workload's other entries follow LIB-0023 §4 with `<name>` added:** a
  bucket's `name_prefix` is `<prefix>-<name>-<key>`, and the IAM application
  is `<prefix>-<suffix>-<name>`.
- **The project leaf depends on the zone's.** A zoned workload's leaves take
  the zone's `scaleway/project/main` as their `project` dependency, so a
  workload plans after its zone's project exists, in LIB-0033 §4's stage order.

### 3. `zone.yaml`'s `hosts` says who serves what

`hosts` replaces LIB-0036's `workload` key. It maps each host in the zone to
the one workload that serves it:

```yaml
# zones/noisypigeon.com/zone.yaml
hosts:
  '@': blog        # noisypigeon.com and www.noisypigeon.com
  docs: docs-site  # docs.noisypigeon.com
```

- **The zone is the source of truth.** A workload can't claim a host, or
  override the one it's given. A workload under `workloads/<zone>/` with no
  host is allowed: it has no DNS and no Pages deployment.
- **`@` is the apex and `www`.** Any other key is one DNS label, a
  subdomain.
- **A workload holds at most one host,** since a Pages site serves one custom
  domain (§4).
- **Each is refused before planning:**
  - a host naming a workload with no `workloads/<zone>/<workload>/`;
  - one workload holding two hosts;
  - `@` in a zone that also declares an `apexRedirect`, since both claim the
    apex and `www`;
  - a zone record whose name is a host, or under a subdomain host.
- **A workload's own `cloudflare.dnsRecord` entries stay at its host:**
  - **a subdomain's owner** writes at its label or under it, such as
    `_acme-challenge.docs` for `docs`;
  - **the apex owner** writes at `@` and `www`, and at `_`-prefixed service
    labels directly under them, such as `_github-pages-challenge-noisypigeon`.
    Anything under the apex is the whole zone, so the apex owner can't take
    everything under its host.

  Any other name is refused, with a message naming the zone that holds it.
  LIB-0036 §3's clash checks still run across the zone and all its workloads.
- **A workload's token** holds *Zone Read* and *DNS Write* on its zone when it
  has a host. A workload with no host and no R2 bucket gets no Cloudflare
  token. Rulesets and redirects stay the zone's (LIB-0036 §3).

### 4. `deployments.githubPages` replaces `features.githubPages`

```yaml
# workloads/noisypigeon.com/blog/workload.yaml
deployments:
  githubPages: {}
```

That's the whole entry for blog and garden. Each field defaults:

| Field | Default | blog |
| --- | --- | --- |
| `username` | the spoke repo's owner | `noisypigeon` |
| `shim` | the workload's host as a domain: the zone for `@`, `<label>.<zone>` otherwise | `noisypigeon.com` |
| `url` | `<username>.github.io` | `noisypigeon.github.io` |

- **The shim repo is `<username>/<shim>`,** so blog's is
  `noisypigeon/noisypigeon.com`, as LIB-0034 wrote by hand.
- **`username` comes from the spoke.** It's `GITHUB_REPOSITORY_OWNER` in CI,
  and locally the owner in `git remote get-url origin`. The two must agree, so
  a plan and its apply resolve one name.
- **It needs a host.** `githubPages` in a workload with no host is refused, as
  is one in `workloads/private/`.
- **Its records follow the host:**
  - **an apex host** gets LIB-0034 §2's two CNAMEs, with the same keys,
    `github-pages-root-cname` and `github-pages-www-cname`, the same contents,
    and `url` in place of `pagesBaseUrl`;
  - **a subdomain host** gets one, `github-pages-cname`, at its label.

  LIB-0034's field-by-field override applies to each.
- **`site-dispatch.yml`** reads each site's shim from these defaults (LIB-0034
  §3).
- **`features` is refused,** with a message naming this record.

### 5. Detection, schemas and the three twins

- **`terragrunt-detect.yml`'s default pattern** replaces
  `^workloads/[^/]+/(values|secrets)\.yaml$` with
  `^workloads/[^/]+/[^/]+/(workload|secrets\.workload)\.yaml$`. A spoke that
  overrides `leaf_pattern`, as runway does, changes it too.
- **`terragrunt-run.yml` selects a workload's leaves by its
  `workload.yaml`,** and plans a removed instance's destroy from the base, as
  it does today. A change to a zone's `hosts` re-plans that zone and every
  workload under it.
- **The generated stubs are gitignored** as `/workloads/*/*/*/`.
- **The schemas:** `/schemas/workload/v2.json` describes `workload.yaml`, and
  the zone schema gains `hosts`. v1 stays published for anything still
  pinned to it.
- **The kind table's three copies change together** (LIB-0023 §2):
  `resolve-workloads.sh`'s KINDS, root.hcl's `workload_kinds` and
  `generate-module-redirects.sh`'s schema list.

### 6. Release impact

- **`terragrunt/root-hcl` and `workflows/` each take a major,** for the new
  layout and its refusals.
- **A minor may come first,** accepting both layouts while a spoke moves, as
  LIB-0036's did. §7 needs one only if a spoke can't move every workload in
  one PR. The build decides, and an amendment records it.

### 7. runway moves, never recreating

runway has blog and garden under zones, and poc with none.

1. **Snapshot** every public DNS answer and Pages URL, as LIB-0036 §7 did.
2. **Bootstrap** each workload's new deployer, state bucket and token,
   under `workloads/<zone>/<w>/`. Their names don't collide with the old ones
   (§2).
3. **Move each other leaf's state** to its new key in its new bucket, by
   `terragrunt state pull` from the old leaf and `state push` to the new one.
   The resource addresses don't change, only the leaf's path and backend, so
   nothing is imported. runway is frozen from the first push until the PR
   that commits the move merges, as
   `docs/runbooks/import-a-leaf-into-a-workload.md` requires. Each new leaf
   must plan `No changes.` before its old state is deleted.
4. **Commit the move:** `hosts` in noisypigeon.com and noisypigeon.garden,
   `deployments.githubPages: {}` in blog and garden, and poc under
   `workloads/private/poc/`. Its plan must show `No changes.` for every moved
   leaf. The old tokens are left to step 5, since step 2 minted the new ones.
5. **Tear down** each old project, deployer, state bucket and token, once
   nothing's state is in them. That's the owner's, by hand, as LIB-0032's
   teardown was.
6. **Check:** DNS and every Pages URL match step 1's snapshot, and a re-plan
   of every leaf shows `No changes.`

## Consequences

- **The tree shows a zone's whole picture.** Everything noisypigeon.com
  serves is under `zones/noisypigeon.com/` and `workloads/noisypigeon.com/`,
  and its `hosts` says who serves what.
- **A subdomain can be its own site,** in its own workload, with its Pages
  records made from its host.
- **A zone has one project.** blog's project and its `blog` prefix go away;
  blog's resources carry `npc` and `blog` instead.
- **Workloads in one project aren't isolated from each other's state.** That's
  §2's trade-off, and its opt-out is a workload's own project.
- **Every workload's state moves once,** to a new key in a new bucket. The
  move is a state push, and nothing is recreated.
- **Every spoke migrates.** Every path, file name and pattern changes, so
  every workload moves in its own spoke's PR.

## Out of scope

- **A workload with several hosts.** One host is what a Pages site serves.
  Deferred until a workload needs a second.
- **Wildcard hosts,** such as `*.example.org`. Deferred.
- **Deployments other than `githubPages`,** under `deployments`. The key is
  there so they can be added. Deferred.
- **Per-bucket isolation inside a shared project.** Scaleway's IAM can't scope
  to one bucket. A design boundary until it can.
- **Building §§1–7.** The template, scripts, schemas and runway's move ship
  in later PRs that cite this record. Deferred.

## Verification

1. **Names resolve as §2 says.** blog's deployer, state bucket and token carry
   `npc`, `noisypigeon` and `blog`, in noisypigeon.com's project, and poc's
   are in its own.
2. **Each is refused by name, before planning:**
   - a `values.yaml`, a `secrets.yaml`, or a `workload.yaml` at the old depth;
   - a `cloudflare.zone` in a `workload.yaml`;
   - a workload named `zone`;
   - `features`;
   - a host naming no workload, or one workload with two hosts;
   - `@` beside an `apexRedirect`;
   - a workload record outside its host, and a zone record at a host;
   - `githubPages` without a host, or in `workloads/private/`.
3. **Defaults fill in.** `githubPages: {}` gives blog the shim
   `noisypigeon/noisypigeon.com` and the URL `noisypigeon.github.io`, and a
   subdomain host gets one CNAME at its label.
4. **State moved, not recreated.** Every moved leaf planned `No changes.` in
   its new bucket before its old state was deleted, and DNS and Pages answer
   as step 1's snapshot.
5. **It converges.** A re-plan of every leaf in runway shows `No changes.`
