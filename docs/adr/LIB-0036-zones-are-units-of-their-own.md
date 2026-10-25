# LIB-0036: Zones are units of their own

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-25.
- **Status**: Proposed; amended 2026-10-25 (see `## Amendments`). Amends:
  - LIB-0030, whose root `zones.yaml` (§2) becomes one `zones/<zone>/zone.yaml`
    per zone, whose `cloudflare.zone` (§3) checks against it, and whose
    `ruleset` and `apexRedirect` kinds leave workloads;
  - LIB-0023 §2 and LIB-0028 §4, whose kind table gains a zone column;
  - LIB-0028 §1, whose implicit project, deployer and state bucket a zone gets
    too;
  - LIB-0033 §4, whose workload token loses the ruleset groups, and whose
    implicit token a zone gets too.

## Context

LIB-0030 §2 gave every Cloudflare zone one owner, in a root `zones.yaml`, and
said a workload may act only on zones it owns. That stopped two workloads
colliding in one zone. It also made every record in a zone the owning
workload's, whatever the record is for.

runway's `workloads/blog/values.yaml` shows what that costs. Apart from the two
Pages CNAMEs LIB-0034 implies, nothing it holds is the blog's:

- **noisypigeon.com's mail and identity:** 11 records for Proton's MX, SPF,
  DKIM, DMARC and verification, Bluesky's handle and Google's site
  verification;
- **pigeon.dev's mail:** 6 Fastmail records;
- **two apex redirects,** pigeon.dev and willowgraysen.com to noisypigeon.com.

Those records belong to the domain, not to the site that happens to be served
from it. Holding them in the blog has three effects:

- **Their state is the blog's,** in the blog's bucket (LIB-0028). Removing the
  blog, by LIB-0028 §7's two PRs, would destroy the mail with it.
- **Their credential is the blog's.** LIB-0033 §4's workload token holds *DNS
  Write* and the ruleset groups on all three zones, so the blog's token can
  rewrite mail routing and every redirect.
- **A zone with no site has to borrow one.** pigeon.dev and willowgraysen.com
  serve nothing. They're owned by the blog only because something had to own
  them.

A zone's own records need a home that's controllable in the same way a
workload's are: declared in YAML, planned per leaf, with their own state and
credential.

## Decision

### 1. `zones/<zone>/zone.yaml`

Each zone the spoke acts on gets a directory under `zones/`, named for its apex
as LIB-0011 looks zones up, holding one `zone.yaml`:

```yaml
# zones/noisypigeon.com/zone.yaml
prefix: npc
suffix: noisypigeon
workload: blog
cloudflare:
  dnsRecord:
    proton-mx-primary:
      name: "@"
      type: MX
      content: mx1.alias.proton.me
      priority: 10
```

```yaml
# zones/pigeon.dev/zone.yaml
suffix: noisypigeon
cloudflare:
  apexRedirect:
    main:
      target_url: https://noisypigeon.com
```

- **Only `suffix` is required.** A `zone.yaml` with only a `suffix` is a valid
  zone: it has a project, a deployer, a state bucket and a token (§2), and no
  entries.
- **`name`** is the zone unit's name, and its Scaleway project's. It defaults
  to the directory's apex, such as `noisypigeon.com`. A project name may hold
  dots, so it needs no sanitizing.
- **`prefix`** starts every other resource's name, which can't hold dots. It
  defaults to `name` with each character outside `[a-z0-9-]` turned into `-`,
  such as `noisypigeon-com`. Written, it's used as is, such as `npc`, and must
  match `^[a-z0-9-]+$`.
- **`suffix`** is what a bucket's name carries after its random code, as in a
  workload (LIB-0023 §4). It must be written and non-empty.
- **`workload`** names the one `workloads/<w>/` that may also write records in
  the zone (§3). It's at most one, as LIB-0030 §2's owner was.
- **`cloudflare.dnsRecord`, `cloudflare.ruleset` and `cloudflare.apexRedirect`**
  are LIB-0030's kinds, with LIB-0030 §4's inputs and defaults, except:
  - **`zone` is refused.** The directory names the zone, so an entry can't
    name another.
  - **`comment` defaults to `zones/<zone>`,** the file that owns the record.
- **`scaleway.project`, `scaleway.deployer`, `scaleway.state` and
  `cloudflare.deployer`** override §2's implicit leaves, as they do in a
  workload.
- **The zone resource itself stays outside Terraform,** as LIB-0030 said.
- **A root `zones.yaml` is refused,** by `resolve-workloads.sh` and root.hcl,
  with a message naming this record. It's a directory and not a map so a zone
  can hold entries, and so a zone's leaves sit beside the file that declares
  them, as a workload's do.

### 2. A zone gets what a workload gets

`resolve-workloads.sh` generates, for every `zone.yaml`:

- `zones/<zone>/scaleway/project/main`;
- `zones/<zone>/scaleway/terraform-deployer-iam/main`;
- `zones/<zone>/scaleway/bucket/state`;
- `zones/<zone>/cloudflare/api-token/deployer`;
- one stub per entry, at `zones/<zone>/cloudflare/<module>/<key>/`.

Their names default as below. The example is noisypigeon.com, with
`prefix: npc` and `suffix: noisypigeon`:

| Leaf | Name | Example |
| --- | --- | --- |
| `scaleway/project/main` | `<name>` | `noisypigeon.com` |
| `scaleway/terraform-deployer-iam/main` | `<prefix>-<suffix>-zone-deployer` | `npc-noisypigeon-zone-deployer` |
| `scaleway/bucket/state` | `<prefix>-<code>-zone-terraform-state` | `npc-<code>-zone-terraform-state` |
| `cloudflare/api-token/deployer` | `<prefix>-<suffix>-zone-cloudflare-deployer` | `npc-noisypigeon-zone-cloudflare-deployer` |
| `cloudflare/ruleset/<key>` | `<prefix>-<key>-<suffix>` | `npc-<key>-noisypigeon` |

- **`zone-` marks a zone's implicit resources.** A zone and a workload that
  share a prefix and suffix then never collide on a deployer, a state bucket
  or a token.
- **The state bucket takes no `suffix`,** as a workload's doesn't (LIB-0028
  §2). `zone-terraform-state` is its fixed name after the code, in LIB-0016's
  `<name>-<code>-<role>` shape. A name over 63 characters is refused before
  planning.
- **An entry's resources keep LIB-0030 §4's names,** with no `zone-`: an
  entry's key already tells it apart.

Their other defaults:

- **`scaleway.state.prefix`** is `zones/<zone>/`, so a zone leaf's key is still
  `path_relative_to_include()`'s (LIB-0001 invariant 4).
- **The token** holds *Zone Read* and *DNS Write* on this zone alone, plus the
  ruleset groups only if the zone declares a `ruleset` or an `apexRedirect`.
  `rotation_days` is 30, as a workload token's is.
- **The token is minted with the breakglass token,** as LIB-0033's second
  amendment mints a workload's. root.hcl turns breakglass on for
  `zones/*/cloudflare/api-token/deployer` as it does for the workload path.
- **The guards are a workload's.** LIB-0028's versioning, storage-class and
  `ObjectStorageFullAccess` guards, and its reserved `state` bucket key, apply
  unchanged. So do LIB-0023 §4's, which refuse an empty `suffix`; a `prefix`
  outside `[a-z0-9-]` is refused too.

A zone lands in LIB-0033 §4's five stages: project, deployer, state bucket,
token, entries. A zone is removed as a workload is (LIB-0028 §7).

### 3. A workload writes only records, in the zone that names it

- **A workload may act only on a zone whose `zone.yaml` names it.** That
  applies to `cloudflare.zone` and to an entry's own `zone`. LIB-0030 §§2–3's
  check reads `zones/*/zone.yaml` instead of `zones.yaml`.
- **A workload keeps `dnsRecord` and `bucket`.** `ruleset` and `apexRedirect`
  become zone kinds only. A phase's entrypoint is the zone's, and two owners of
  one could overwrite each other (LIB-0030 Context), so the zone holds it.
- **LIB-0034's `githubPages` records stay the workload's.** They follow from
  the shim that deploys the site, so they're the site's.
- **A workload token loses the ruleset groups.** It holds *Zone Read* and *DNS
  Write* on the zones that name it.
- **LIB-0030 §6's checks cover a zone's file and its workload's together.** One
  name and type, one entrypoint per phase, and an apex redirect's placeholders
  at `@` and `www` (LIB-0030's first amendment, item 1) are checked across
  both, so a workload can't add a record that clashes with its zone's.
- **The kind table gains a zone column,** in all three copies (LIB-0023 §2):
  which kinds a `zone.yaml` takes, and which a `values.yaml` does.

### 4. Hand-written zone leaves are retired

LIB-0030 §2 let `zones.yaml` register a zone to `terraform`, for hand-written
`terraform/cloudflare/<zone>/` leaves (LIB-0008). Every zone is now a
`zone.yaml`, so that mode goes.

- **root.hcl refuses a `terraform/cloudflare/<zone>/` leaf.** runway has none:
  garden's last one left with LIB-0035.
- **The spoke's own Cloudflare token is left as it is.** LIB-0033's second
  amendment gave it *Zone Read* for hand-written leaves, and none remain. This
  record doesn't narrow it further.

### 5. Detection

- **root.hcl reads a zone's file through `mark_as_read`,** for the zone's own
  leaves and for its workload's Cloudflare leaves. A change to one `zone.yaml`
  then re-plans that zone and its workload, not every Cloudflare leaf in the
  spoke as a `zones.yaml` change did.
- **`terragrunt-detect.yml`'s default pattern gains
  `^zones/[^/]+/zone\.yaml$`,** and `terragrunt-run.yml` selects a zone's
  leaves as it does a workload's. A spoke that overrides `leaf_pattern`, as
  runway does, adds the same pattern.
- **The generated stubs are gitignored,** as `zones/*/scaleway/` and
  `zones/*/cloudflare/`, beside the workload lines.
- **A zone has its own schema,** `/schemas/zone/v1.json`, published by
  `generate-module-redirects.sh` beside the workload schema (LIB-0023 §6).

### 6. Release impact

- **`terragrunt/root-hcl` takes a major version.** It refuses `zones.yaml`, a
  workload `ruleset` or `apexRedirect`, and a hand-written zone leaf.
- **`workflows/` takes a major version** for the same refusals in
  `resolve-workloads.sh`, the zone stubs, the detect pattern and the schema.
- **The zone schema reaches the site only through runway.** noisypigeon.garden
  is built from runway's committed pages (LIB-0035 §2), generated at runway's
  `.lib-version`. So runway bumps its pin and regenerates before its first
  `zone.yaml` lands, or `--check` can't fetch the schema.

### 7. runway adopts it, importing and never recreating

Every record and redirect moves by
`docs/runbooks/import-a-leaf-into-a-workload.md`: import at the new address,
plan `No changes.`, then `state rm` the old one. Nothing is applied in runway
between the import and the merge of the PR that moves the entries.

1. **The library ships §§1–6.** runway takes those releases, and its garden
   pages are regenerated.
2. **Bootstrap:** `zones.yaml` gives way to four `zone.yaml` files that hold
   only `suffix` and `workload`:
   - noisypigeon.com and pigeon.dev and willowgraysen.com name `blog`, so the
     blog keeps every zone it acts on today;
   - noisypigeon.garden names `garden`.

   Each zone's four bootstrap stages apply. The workload tokens don't change,
   and no workload leaf does.
3. **The import, with runway frozen:**
   - noisypigeon.com's 11 mail and identity records go to
     `zones/noisypigeon.com/cloudflare/dns-record/<key>/`;
   - pigeon.dev's 6 Fastmail records go to
     `zones/pigeon.dev/cloudflare/dns-record/<key>/`;
   - the two redirects go to `zones/<zone>/cloudflare/apex-redirect/main/`.

   Every record already writes its `comment`, so §1's new default changes
   none of them.
4. **Entries:** the records and redirects leave `workloads/blog/values.yaml`
   and land in their zone's file. pigeon.dev and willowgraysen.com drop
   `workload`. Its plan must be `No changes.` for every moved leaf. The blog's
   token loses two zones and the ruleset groups, which updates it in place.

## Consequences

- **A domain's mail and identity outlive the site.** Removing the blog leaves
  its zones' records, and their state, where they are.
- **A token reaches what its unit owns.** The blog's token reaches
  noisypigeon.com's records only. A zone's token reaches one zone.
- **A zone with no site is a unit,** not something a workload has to own.
- **A zone's project reads as its domain** in the Scaleway console, while its
  buckets and keys carry a short prefix and `zone-`.
- **runway gains four projects, four buckets and four tokens.** Each is cheap,
  and each zone adds four stages when it's created.
- **Ownership checks span two files** for any zone with a workload, so a
  workload's plan reads its zone's file.
- **The kind table has a fourth axis.** It's still three copies that have to
  agree.

## Out of scope

- **Several workloads in one zone.** A zone names at most one, so a record's
  owner is always one file or the other. This is a design boundary, not a
  deferral.
- **Managing the zone resource itself.** Zones stay looked up by apex, as
  LIB-0030 left them. A design boundary.
- **A zone `secrets.yaml`,** as LIB-0025 gives a workload. No zone record is
  secret. A design boundary until one is.
- **Building §§1–7.** The template, scripts, schema and runway's adoption ship
  in later PRs that cite this record. Deferred
  ([#175](https://github.com/noisypigeon/library/issues/175)).

## Verification

Recorded 2026-10-25. Every item passed.

1. **The DNS doesn't change.** Every moved leaf plans `No changes.` in step 4's
   PR, and `dig` for each moved name and type answers the same before and
   after.
   - **Passed:** each of the 17 records and 2 redirects planned `No changes.` in
     its zone leaf before it left blog's state, and all 19 zone leaves did again
     in [runway#72](https://github.com/noisypigeon/runway/pull/72), whose 19
     removed blog stubs changed only their outputs. After runway#72 applied,
     every name and type from 1.1.1.1, and all four apex and `www` redirects,
     matched the snapshot taken before the first import.

2. **Ownership holds.** Each is refused by name, before planning:
   - a workload entry in a zone whose `zone.yaml` doesn't name it;
   - a `zone` in a `zone.yaml` entry;
   - a `zone.yaml` without `suffix`, or with a `prefix` outside `[a-z0-9-]`;
   - a root `zones.yaml`;
   - a workload `ruleset` or `apexRedirect`;
   - a hand-written `terraform/cloudflare/<zone>/` leaf;
   - a workload record that clashes with its zone's.

   - **Passed, on copies of runway's `main` at `workflows/v6.0.0`:**
     `resolve-workloads.sh` refused each, with its own message. root.hcl 6.0.0
     also refused a root `zones.yaml`, a workload ruleset's leaf and a
     hand-written zone leaf when each was rendered.

3. **State lands in the zone's bucket.** A zone leaf's key is under
   `zones/<zone>/`, in that zone's own bucket.
   - **Passed:** a zone leaf's rendered backend keys its state under
     `zones/<zone>/`, in the zone's own bucket: its stub reads the bucket from
     its `state` dependency, the zone's `scaleway/bucket/state`.

4. **Tokens are scoped.** Each zone's token lists only its zone. After step 4,
   the blog's token lists only noisypigeon.com, without the ruleset groups.
   - **Passed:** each of the four zone tokens holds *Zone Read*, *DNS Write* and
     *Dynamic URL Redirects Write* on its own zone and nothing else. blog's
     holds *Zone Read* and *DNS Write* on noisypigeon.com, and garden's the same
     on noisypigeon.garden.
     [runway#72](https://github.com/noisypigeon/runway/pull/72) updated blog's
     in place.

5. **It converges.** A re-plan of every leaf in runway shows `No changes.`
   - **Passed:** [runway#73](https://github.com/noisypigeon/runway/pull/73), the
     bump to `workflows/v6.0.0` and root.hcl 6.0.0, planned all 79 leaves with
     no changes.

## Amendments

### 2026-10-25: what building it changed

§§1–5 ship first in `terragrunt/root-hcl` v5.6.0 and `workflows/v5.2.0`.
Building them changed four things.

1. **The library releases twice: a minor, then a major.** §6 has runway adopt
   one major that refuses workload redirects, but blog's redirects only move in
   §7's step 4, so that major would refuse runway's own bootstrap.
   - The **minor** adds zone units beside `zones.yaml`. A zone in both places
     is refused, and everything a spoke has today plans as before.
   - The **major** then refuses `zones.yaml`, a workload `ruleset` or
     `apexRedirect`, and a hand-written zone leaf. runway takes it last, after
     step 4, and its plan must show `No changes.` (Verification 5).
2. **A zone's token always holds the redirect group,** *Dynamic URL Redirects
   Write*, on its own zone. If it followed the zone's entries, the token would
   lack it when step 3 imports a redirect, and the import would fail. Its
   scope is still one zone.
3. **A workload's token holds that group only if the workload declares a
   `ruleset` or an `apexRedirect`.** This ships in the minor, so garden's token
   loses it at runway's bump, updated in place. blog's loses it in step 4,
   with its two zones.
4. **§6's schema note was wrong.** `resolve-workloads.sh --check` fetches each
   module's `inputs.schema.json` only, never the workload or zone schema. The
   zone schema only feeds editors, through a file's `$schema` line, so it can
   follow runway's first regeneration rather than precede it.

Two smaller things settled on the way:

- **The kind table's fourth axis is a `units` column,** `workload`, `zone` or
  both, in all three copies. root.hcl refuses a leaf whose kind its unit
  doesn't take.
- **The clash checks (LIB-0030 §6) run once per spoke,** across every unit,
  rather than once per file, so a zone's records and its workload's are
  checked together.

### 2026-10-25: what the import taught

§7's step 3 ran as two scripts, one per record and one per redirect, each
following the runbook and removing a resource from blog's state only after
its zone leaf planned `No changes.`. Four things they hit are now in
`docs/runbooks/import-a-leaf-into-a-workload.md`:

1. **A new leaf has no state.** Before its first import, `state list` fails
   with `No state file was found!`, which means empty, not broken.
2. **Terragrunt prefixes Terraform's lines,** so `No changes.` follows
   `<time> STDOUT terraform:`. `plan -detailed-exitcode` is the check to
   trust; a text check must not anchor at the line start.
3. **`state list` lists data sources.** An apex redirect's
   `module.this.data.cloudflare_zone.this` can't be imported and doesn't need
   to be: the new leaf reads its own.
4. **A many-resource leaf moves as one.** A redirect's ruleset, apex and `www`
   records are imported together, planned once, and removed in one `state rm`.

The runbook's sops check was also wrong: the `.enc` files are dotenv, so it
needs `--input-type dotenv --output-type dotenv`.
