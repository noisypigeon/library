# LIB-0030: Cloudflare kinds, and zones a workload owns

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-23.
- **Status**: Proposed. Amends LIB-0023, whose §2 kind table gains Cloudflare
  rows and whose §4 gains their defaults, and LIB-0028, whose §4 table gains
  the same rows. First of three records, with LIB-0031 and LIB-0032, that
  move the blog into runway.

## Context

LIB-0029 gave workloads Backblaze kinds, and left #96 open for Cloudflare and
Grafana. Cloudflare is the one that matters next: LIB-0032 moves the blog,
whose Terraform is all Cloudflare, into a runway workload.

The blog spoke's Cloudflare leaves cover three zones:

- `noisypigeon.com`, with DNS records for GitHub Pages, Bluesky, Proton and
  Google Search verification;
- `pigeon.dev`, with an apex redirect and mail records;
- `willowgraysen.com`, with an apex redirect.

Cloudflare differs from Scaleway and Backblaze in two ways that shape this
record.

- **One credential reaches everything.** The provider signs in with one
  account-wide API token from `terraform/secrets/cloudflare.enc` (LIB-0010,
  LIB-0012). As with Backblaze, there's no per-workload unit to scope a
  credential to.
- **Some modules own a whole zone.** A zone has one entrypoint ruleset per
  phase. `cloudflare/ruleset` declares one, and `cloudflare/apex-redirect`
  declares one in `http_request_dynamic_redirect`. Two workloads that each
  wrote a ruleset for the same zone and phase would overwrite each other on
  every apply. `dns-record` and `bucket` are per resource, but two owners of
  one zone can still collide on a record.

So Cloudflare kinds need what Scaleway's project gave for free: a boundary.
A zone needs exactly one owner, and the spoke has to say who that is.

## Decision

### 1. Four Cloudflare kinds

| YAML key | Module | Shape | Credentials | State |
| --- | --- | --- | --- | --- |
| `cloudflare.bucket.<key>` | `cloudflare/bucket` | map | spoke | workload |
| `cloudflare.dnsRecord.<key>` | `cloudflare/dns-record` | map | spoke | workload |
| `cloudflare.ruleset.<key>` | `cloudflare/ruleset` | map | spoke | workload |
| `cloudflare.apexRedirect.<key>` | `cloudflare/apex-redirect` | map | spoke | workload |

- **Leaves are `workloads/<w>/cloudflare/<module>/<key>/`.** That's LIB-0023
  §1's shape. LIB-0008's zone leaves, `terraform/cloudflare/<zone>/...`, are
  for hand-written leaves only; a workload names its zone in the file.
- **"Spoke" credentials** means `cloudflare.enc`'s account token.
- **"Workload" state** means LIB-0028's Scaleway bucket, even in a spoke whose
  own backend is R2. That bucket is versioned, so it needs no B2 copy.
- **Provider and secrets follow LIB-0029 §4.** A Cloudflare workload leaf
  gets the Cloudflare provider and decrypts `cloudflare.enc`; no other kind
  does. A guard fails a Cloudflare workload leaf in a spoke whose providers
  map has no `cloudflare`.
- **The kind table gains these rows** in all three copies.

### 2. A root `zones.yaml` gives every zone one owner

```yaml
# zones.yaml, at the spoke's root
noisypigeon.com:
  workload: blog
pigeon.dev:
  workload: blog
example.net:
  workload: terraform   # hand-written zone leaves, not a workload
```

- **Each key is a zone's apex**, as LIB-0011 looks zones up. The zone itself
  stays outside Terraform; this file only says which zones the spoke acts on,
  and who acts.
- **`workload`** names one `workloads/<w>/`, or `terraform` for hand-written
  `terraform/cloudflare/<zone>/` leaves.
- **A `dnsRecord`, `ruleset` or `apexRedirect` entry may only name a zone
  registered to its own workload.** `resolve-workloads.sh` refuses anything
  else before planning, and root.hcl refuses it at plan time.
- **A hand-written zone leaf may only use a zone registered to `terraform`,
  or not registered at all.** root.hcl refuses a
  `terraform/cloudflare/<zone>/` leaf for a zone registered to a workload. So
  a zone can't have two owners, even across the two homes.
- **An R2 bucket has no zone**, and isn't gated.
- **The file is optional.** A spoke without one has no zones a workload can
  use.
- **It's YAML at the root, not a map in `spoke.hcl`,** because
  `resolve-workloads.sh` must read it before planning, and bash reads YAML
  already but not HCL.
- **root.hcl marks it read.** A change to `zones.yaml` re-plans every
  workload leaf and every zone leaf, the way a change to `root.hcl` does.
  `terragrunt-detect.yml`'s default pattern gains `^zones\.yaml$`.

### 3. `cloudflare.zone`, a workload default

- **An optional `cloudflare.zone`** fills `zone` for every `dnsRecord`,
  `ruleset` and `apexRedirect` entry that doesn't set its own.
- **It must be a zone `zones.yaml` registers to this workload.**
- **An entry with neither is refused.**
- Like `scaleway.state.prefix`, it's the workload's own field, not a module
  input.

### 4. Inputs and defaults

Each default applies only when the input is absent, as LIB-0023 §4's do.

- **`cloudflare.bucket.<key>`:**
  - `name_prefix` = `<prefix>-<key>`, and `name_suffix` = `<suffix>`;
  - a generated name over R2's 63 characters is refused before planning;
  - `account_id` comes from `cloudflare.enc`, passed by root.hcl as a
    variable, and can't be written. The token reaches only the spoke's
    account. R2 buckets are EU-jurisdiction already (LIB-0006).
- **`cloudflare.dnsRecord.<key>`:**
  - `name` = `<key>`. The apex and multi-label names set `name` themselves,
    such as `name: "@"`.
  - `comment` = `workloads/<w>`, so a record in Cloudflare's dashboard names
    the file that owns it.
- **`cloudflare.ruleset.<key>`:** `name` = `<prefix>-<key>-<suffix>`.
  `kind`, `phase` and `rules` have no default.
- **`cloudflare.apexRedirect.<key>`:** no defaults beyond the zone.
  `target_url` must be written.

### 5. `cloudflare/ruleset` looks its zone up by apex

`cloudflare/ruleset` takes `zone_id`, the only Cloudflare module that does.
It gains `zone`, looked up with a `cloudflare_zone` data source as
`dns-record` v1 and `apex-redirect` do (LIB-0011), in a minor release.

- **`zone_id` stays, for hand-written leaves.** Setting both is refused by
  the module.
- **A workload entry uses `zone`.** `zone_id` is refused in `values.yaml`, so
  ownership is always checked against a name.

### 6. One entrypoint per zone and phase, one record per name and type

Refused before planning, across every workload file in the spoke:

- **two `ruleset` entries for one zone and phase;**
- **a `ruleset` in `http_request_dynamic_redirect`** for a zone that also has
  an `apexRedirect` entry, since the redirect owns that phase's entrypoint;
- **two `apexRedirect` entries for one zone;**
- **two `dnsRecord` entries with one zone, name and type**, unless the type
  allows several records per name (`MX`, `TXT`, `CAA`, `SRV`, `NS`) and their
  `content` differs.

Zone ownership (§2) puts every one of these inside a single workload's file,
so the check is a per-file one in practice.

### 7. The schema

- **The workload schema gains `cloudflare`**, with `zone` and the four maps of
  kebab-case keys.
- **`cloudflare/bucket` versions publish a `workload.schema.json`** without
  `account_id`, and **`cloudflare/ruleset` versions** one without `zone_id`.
  That's LIB-0029 §6's pattern.
- **`dns-record` and `apex-redirect`** use their plain inputs schemas. `zone`
  isn't required there, because the workload default can fill it.

### 8. Stages and release impact

- **No new stage.** Cloudflare leaves depend on the state bucket, so they plan
  in LIB-0028's last stage.
- **`terragrunt/root-hcl` takes a minor version:** the kinds, `zones.yaml`,
  the account variable and the guards. The hand-written zone-leaf guard
  changes nothing in a spoke without `zones.yaml`.
- **`workflows/` takes a minor version:** stubs, refusals, schema, and the
  detect pattern.
- **`cloudflare/ruleset` takes a minor version** for `zone`.
- **garden builds with the new `workflows/` before a spoke adopts**, so
  `--check` can fetch the new schemas (LIB-0029's amendment).

## Consequences

- **A workload can own Cloudflare zones**, with their records, rulesets and
  redirects, plus R2 buckets.
- **Zone ownership is explicit and checked.** It's the first spoke-level file
  a workload depends on besides `spoke.hcl`.
- **Isolation is by registration, not by credential.** The account token can
  still reach every zone. A zone left out of `zones.yaml` is invisible to the
  checks, so a hand-written leaf in another spoke can still collide with it.
- **A `zones.yaml` change re-plans every Cloudflare leaf in the spoke.**
- **The kind table now spans three providers.**

## Out of scope

- **Managing the zone resource itself.** Zones stay looked up by apex. A
  permanent boundary for now, so no issue.
- **A per-workload Cloudflare token**, scoped to the zones a workload owns.
  Extends [#109](https://github.com/noisypigeon/library/issues/109).
- **Grafana kinds.** [#96](https://github.com/noisypigeon/library/issues/96)
  stays open for them.
- **Building §§1–8.** The module release, template, scripts and schema ship in
  later PRs that cite this record ([#147](https://github.com/noisypigeon/library/issues/147)).

## Verification

Run against LIB-0032's migration of the blog.

1. **Imported records plan clean.** Every record and redirect from the blog
   spoke, once imported into the `blog` workload, plans `No changes.`
2. **Ownership holds.** Each of these is refused, by name, before planning:
   - a record naming a zone that `zones.yaml` registers to another workload;
   - a hand-written leaf under a zone registered to `blog`;
   - a record with no zone and no `cloudflare.zone`;
   - `account_id` or `zone_id` written in `values.yaml`.
3. **Entrypoints hold.** A second `apexRedirect` for one zone, and a
   `http_request_dynamic_redirect` ruleset beside one, are refused.
4. **Other leaves don't change.** Scaleway and Backblaze workload leaves, and
   runway's hand-written leaves, render identically.
5. **It converges.** After the migration, a re-plan of every leaf in runway
   shows `No changes.`
