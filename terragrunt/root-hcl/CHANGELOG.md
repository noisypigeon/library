# Changelog

All notable changes to this template are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [8.0.0] - 2026-10-26

### Refuse unwrapped unit files (LIB-0039)

LIB-0039's second release. Every unit file must now hold its content under one key: `zone:` in zone.yaml, and `workload:` in workload.yaml and secrets.workload.yaml. An unwrapped file is refused before planning, by `resolve-workloads.sh` and by the template, with a message naming the file and the key its content belongs under. That also refuses `cloudflare.dnsRecord` at the top of a file: records live at `dnsRecords` under the wrapper, as they have since v7.1.0.

Nothing else changes. A spoke whose files are all wrapped, as v7.1.0 allowed, generates the same leaves and plans `No changes.` on the bump. Take `workflows/v8.0.0` first, then `root_hcl_version` 8.0.0.

`site-dispatch.yml` now reads only the wrapped shape. The older `zone/v1`, `zone/v2`, `workload/v1`, `workload/v2` and `workload/v3` schemas stay published for editors, though this release refuses a file shaped by them.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#203](https://github.com/noisypigeon/library/pull/203)

## [7.1.0] - 2026-10-26

### Wrapped unit files, dnsRecords and zone services (LIB-0039)

LIB-0039's first release. A unit file can now hold its content under one key, `zone:` in zone.yaml and `workload:` in workload.yaml and secrets.workload.yaml, with its records at `dnsRecords` directly under it in place of `cloudflare.dnsRecord`. An unwrapped file still reads exactly as before, so a spoke can take this release with no changes and move its files over at its own pace.

A wrapped zone.yaml can also list `services`. Each of `proton` (Proton Pass aliases), `fastmail`, `googleSearch` and `bluesky` adds its provider's records to `dnsRecords` when `enabled: true`. The records are keyed `<service>-<record>`, with ttl 1 and a fixed comment. The only inputs are the zone's own values: Proton's `verification.pm` and `verification.protonmail`, Google's `verification`, and Bluesky's `did`. A mail service's `dmarc` defaults to `v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s` at `_dmarc`. Set it to another policy string, or to `false` for no DMARC record. A `dnsRecords` entry with the same key as an added record overrides it field by field. The leaves stay `cloudflare/dns-record/<key>`, so moving a hand-written record under a service moves no state, as long as its key matches.

Both `resolve-workloads.sh` and the template refuse each of these by name before planning:
- a key beside the wrapper;
- `cloudflare.dnsRecord` inside a wrapped file;
- `services` or `dnsRecords` in an unwrapped file;
- `services` in a workload;
- an unknown service or service key;
- an enabled service that is missing an input;
- `proton` and `fastmail` both enabled;
- two SPF or two DMARC policies at one name.

`site-dispatch.yml` reads either shape. noisypigeon.garden now also publishes `schemas/zone/v3.json` and `schemas/workload/v4.json` for the wrapped files. The older schemas stay published.

v8.0.0 will refuse the unwrapped shape.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#202](https://github.com/noisypigeon/library/pull/202)

## [7.0.0] - 2026-10-26

### Compose deployers and redirects from single-resource modules (LIB-0038)

This is the major release of `terragrunt/root-hcl` (v7.0.0) and `workflows/` (v7.0.0) that [LIB-0038](docs/adr/LIB-0038-compose-deployers-and-redirects-from-single-resource-modules.md) records. It also carries LIB-0037 §6's refusal of the old workload layout.

## A unit's deployer is three leaves

Every zone and workload now gets `scaleway/iam-application/deployer`, `scaleway/iam-policy/deployer` and `scaleway/iam-api-key/deployer` in place of `scaleway/terraform-deployer-iam/main`.
- **Names stay the same.** The application and policy keep the bundle's names (`<prefix>-<suffix><tag>-deployer`, and `-policy` on the policy).
- **Defaults stay the same.** The policy keeps `ObjectStorageFullAccess` and the key rotates every 30 days, through `iam-api-key`'s new `rotation_days` (v0.3.0).
- **The key signs every unit leaf in.** Every workload-state backend and workload-credentials provider now signs in with `iam-api-key/deployer`'s key.
- **Overrides go under one key per module:** `scaleway.deployer.application`, `.policy` or `.apiKey`. A module input directly under `scaleway.deployer` is refused, and the `ObjectStorageFullAccess` guard now reads `scaleway.deployer.policy.project_permission_sets`.

## `apexRedirect` is a shorthand

A zone's `cloudflare.apexRedirect.<key>` keeps its four inputs: `target_url`, `status_code`, `include_www` and `preserve_query_string`.
- **What it expands into:** `cloudflare.dnsRecord.<key>-apex`, `<key>-www` and `cloudflare.ruleset.<key>`, with exactly the strings `cloudflare/apex-redirect` generated. An explicit entry of the same key is merged over its default, field by field.
- **What it refuses:** any other input, `version` included.
- **The clash checks run on the expanded entries.** A record beside a redirect at `@` or `www` is still refused.

## The retired kinds and the old layout are refused

Each refusal names its record.
- **Retired kinds.** root.hcl refuses a stub under `scaleway/terraform-deployer-iam/` or `cloudflare/apex-redirect/`. The two modules are deprecated, but their tags and short URLs stay.
- **The old layout.** Refused since this release:
  - a `workloads/<w>/values.yaml` or `secrets.yaml`, and a leaf at that depth;
  - a `secrets.yaml` beside a `workload.yaml`;
  - `zone.yaml`'s `workload`;
  - `features`;
  - a workload's `cloudflare.zone`.
- **Old-layout code removed.** Those branches leave root.hcl, `resolve-workloads.sh`, `terragrunt-run.yml`, `site-dispatch.yml` and `site-pages.yml`. `site-pages.yml` now refuses a `workload` that isn't `<zone>/<workload>`. `terragrunt-detect.yml` still matches a `values.yaml`, `secrets.yaml` or root `zones.yaml`, so the run that refuses one runs.

## Schemas

`/schemas/workload/v3.json` and `/schemas/zone/v2.json` describe the new shape. Earlier versions stay published unchanged, and `scaleway/iam-policy`'s per-version input schemas are now published too.

## Adopting it

A spoke takes the workflows pin alone first, then moves each deployer's and redirect's state by LIB-0038 §5, with nothing recreated. Only then does it bump `root_hcl_version` to 7.0.0, in a PR whose plan shows `No changes.` for every moved leaf.

Tested on a copy of runway's `main` after its LIB-0037 teardown:
- **Stubs:** the stubs and `--check` passed against locally generated schemas.
- **Renders:** every leaf rendered with mocked dependencies. The new leaves carry the old names, comments and rules, and every other leaf renders byte-identically to root.hcl 6.1.0.
- **Refusals:** each of the refusals above fired, from `resolve-workloads.sh` and from root.hcl.
- **Lint:** shellcheck, actionlint, `terragrunt hcl fmt` and `node --test` passed.

Part of #192; runway's move closes it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#195](https://github.com/noisypigeon/library/pull/195)

## [6.1.0] - 2026-10-25

### Read workloads that live in their zone (LIB-0037)

A workload can now live in its zone, as LIB-0037 decides, beside the old layout while a spoke moves. Nothing changes for a spoke that keeps `workloads/<workload>/values.yaml`: its stubs come out byte-identical, and its leaves render exactly as on `root-hcl/v6.0.0`.

**The new layout:**

- **Where:** `workloads/<zone>/<workload>/workload.yaml`, with `secrets.workload.yaml` beside it. A workload with no zone lives in `workloads/private/<workload>/`. The directory names the zone, so a `workload.yaml` never writes `cloudflare.zone`, and `name` defaults to the directory.
- **Project:** a zoned workload lives in its zone's Scaleway project by default, with no project leaf of its own. Its deployer and state bucket depend on `zones/<zone>/scaleway/project/main`. `prefix` and `suffix` are the zone's, unless `deployments.scaleway.project` sets `name`, `prefix` or `suffix`, which gives it its own project. A private workload always has its own.
- **Names:** its names carry `name`:
  - deployer `<prefix>-<suffix>-<name>-deployer`;
  - state bucket `<prefix>-<code>-<name>-terraform-state`;
  - token `<prefix>-<suffix>-<name>-cloudflare-deployer`;
  - a bucket's `name_prefix` `<prefix>-<name>-<key>`;
  - IAM application `<prefix>-<suffix>-<name>`.

  Its leaves sit one segment deeper, and its state keys start `workloads/<zone>/<workload>/`.
- **Hosts:** `zone.yaml`'s new `hosts` gives the apex `@` and each subdomain label to one workload in `workloads/<zone>/`.
  - **The workload** writes records only at its host: `@`, `www` and `_` names under them for the apex; the label and names under it for a subdomain. Its token gets *Zone Read* and *DNS Write* on its zone only when it has a host.
  - **The zone** keeps every other name. It can't write under a subdomain host, nor `www` or an A, AAAA or CNAME at `@` beside an apex host, so its MX and TXT records at `@` stay.
  - **Beside `hosts`,** `workload` still names an old-layout workload. So a spoke can create a workload's new deployer, state bucket and token before it moves the records.
- **Pages:** `deployments.githubPages` replaces `features.githubPages`.
  - `username` defaults to the spoke repo's owner: `GITHUB_REPOSITORY_OWNER`, or locally the owner in origin's URL.
  - `shim` defaults to the host as a domain, and `url` to `<username>.github.io`.
  - An apex host gets LIB-0034's two CNAMEs, with the same keys and contents. A subdomain host gets one, `github-pages-cname`.

**Refusals.** `resolve-workloads.sh --check` refuses each of these before planning, and so does this template's guards:

- in a `workload.yaml`:
  - `features`;
  - a top-level `prefix` or `suffix`;
  - `scaleway.project`;
  - any `zone`;
  - a workload named `zone`;
- a `secrets.yaml` beside a `workload.yaml`;
- `githubPages` without a host, or in `private/`;
- a record outside the workload's host;
- a host naming no workload;
- one workload holding two hosts;
- `hosts.@` beside an `apexRedirect`;
- a zone record at a host's name;
- a `values.yaml` under a zone's directory, or a `workload.yaml` at the old depth.

**The reusable CI follows:**

- **`terragrunt-run.yml`** selects a nested workload by its `workload.yaml` or `secrets.workload.yaml`, and every workload in a zone whose `zone.yaml` changed. It masks `secrets.workload.yaml` too.
- **`terragrunt-detect.yml`'s** default `leaf_pattern` gains `^workloads/[^/]+/[^/]+/(workload|secrets\.workload)\.yaml$`.
- **`site-dispatch.yml`** finds sites at both depths, and dispatches a nested site's `<username>/<shim>`.
- **`site-pages.yml`** already accepts `workload: <zone>/<workload>`; only its description changes.
- **A run comment** now says a removed instance was "removed from its unit file".

**Schemas:** the garden publishes `/schemas/workload/v2.json` for `workload.yaml`, and `/schemas/zone/v1.json` gains `hosts`. Workload v1 stays.

**A spoke adopting the new layout:**

- gitignores each provider's stub directory, `/workloads/*/*/scaleway/`, `/workloads/*/*/cloudflare/` and `/workloads/*/*/backblaze/`, never `/workloads/*/*/*/`, which would also hide a site's `content/`, `static/` and `templates/`;
- adds `^workloads/[^/]+/[^/]+/(workload|secrets\.workload)\.yaml$` to its `leaf_pattern` if it overrides it;
- adds `^workloads/[^/]+/[^/]+/secrets\.workload\.yaml$` to `.sops.yaml`.

**Tested on copies of runway's `main`:**

- **The old layout:** `--list` and every stub match `workflows/v6.0.0` byte for byte (55 stubs). 14 leaves across every kind, the zones' and a hand-written one included, render the same hash under the old and new template.
- **The bootstrap layout** (`name`-only `workload.yaml`s, with zones giving each one `@` beside `workload`): it generates exactly a deployer, state bucket and token per workload. The 7 old-layout leaves it touches, both tokens included, render unchanged.
- **The moved blog** renders §2's names, a token scoped to `noisypigeon.com`, and the two CNAMEs with LIB-0034's contents. So do a subdomain workload with its own project and a private one.
- **Refusals:** each of the script's 22 fires, and so does each of the template's 12. The owner fallback was tested with SSH and HTTPS origins and with no origin.
- **Lint and unit tests:** shellcheck, actionlint, `terragrunt hcl fmt` and `node --test` pass. The new schema's structure was checked; no JSON Schema validator ran on it.

Refusing the old layout is the major that follows the move (LIB-0037 §6).

🤖 Generated with [Claude Code](https://claude.com/claude-code)



[#189](https://github.com/noisypigeon/library/pull/189)

## [6.0.0] - 2026-10-25

### Refuse zones.yaml, workload rulesets and redirects, and hand-written zone leaves

A zone's `zones/<zone>/zone.yaml` is now the only way to register a zone, and a zone holds its own rulesets and redirects (LIB-0036 §§1, 3–4, and the record's 2026-10-25 amendment). This is the major release the record's minor (`terragrunt/root-hcl` v5.6.0, `workflows/v5.2.0`) prepared for: everything that minor still accepted for the migration is now refused before anything plans, each with a message naming LIB-0036.

- **A root `zones.yaml` is refused.** `resolve-workloads.sh` stops on it, and so does every leaf `root.hcl` is included from. Move each zone into `zones/<zone>/zone.yaml`, naming there the one workload that may also write in it.
- **A workload's `cloudflare.ruleset` and `cloudflare.apexRedirect` are refused.** Both are zone kinds only now, since a phase has one entrypoint per zone. In the kind table's `units` column they're `z`, in all three copies, and the workload schema at `/schemas/workload/v1.json` no longer lists them. A workload keeps `dnsRecord` and `bucket`.
- **A workload's Cloudflare token never gets *Dynamic URL Redirects Write*.** Only a zone's token holds it, on its own zone. A workload that declared no ruleset or redirect already went without it, so its token doesn't change.
- **A hand-written `terraform/cloudflare/<zone>/` leaf is refused.** Declare its entries in that zone's `zone.yaml` and import them, by `docs/runbooks/import-a-leaf-into-a-workload.md`.
- **Docs:** `terragrunt/root-hcl`'s README gains a v6.0.0 section and marks its `zones.yaml` example as history. The `cloudflare/dns-record`, `ruleset` and `apex-redirect` READMEs describe declaring them in a `zone.yaml` rather than in a hand-written leaf.

A spoke whose zones are all `zone.yaml`s, and whose workloads declare no ruleset or redirect, plans `No changes.` when it bumps. Tested against runway's `main` after its zone entries moved (noisypigeon/runway#72):
- `resolve-workloads.sh` generates the same 55 stubs, byte for byte, as the version before it;
- with this `root.hcl`, 8 leaves render exactly as before: both workload tokens, two zone tokens, a zone redirect, a zone record, a Pages CNAME and a state bucket;
- each refusal fires with its own message: a `zones.yaml`, a workload `ruleset` or `apexRedirect`, a declared workload ruleset's leaf, and a hand-written zone leaf.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#181](https://github.com/noisypigeon/library/pull/181)

## [5.6.0] - 2026-10-24

### Add zone units, zones/<zone>/zone.yaml (LIB-0036)

A zone can now be a unit of its own, beside workloads (LIB-0036). A spoke adds `zones/<zone>/zone.yaml`, named for the zone's apex, for the records and redirects that belong to the domain rather than to a site: mail, verification, identity, apex redirects. Nothing changes for a spoke that adds none.

A zone unit gets what a workload gets, with `zone-` in its names:

- a Scaleway project named `name`, which defaults to the directory and may hold dots, such as `example.org`;
- a deployer `<prefix>-<suffix>-zone-deployer` and a state bucket `<prefix>-<code>-zone-terraform-state`, where `prefix` defaults to `name` with anything outside `a-z0-9-` turned into `-`, and `suffix` is required;
- a Cloudflare token `<prefix>-<suffix>-zone-cloudflare-deployer`, with *Zone Read*, *DNS Write* and *Dynamic URL Redirects Write* on that zone only.

It takes `cloudflare.dnsRecord`, `ruleset` and `apexRedirect`, plus overrides for those four implicit kinds. Its leaves are generated at `zones/<zone>/<provider>/<module>/<instance>/`, and keep their state under `zones/<zone>/` in the zone's own bucket. Its entries never write `zone`, a record's `comment` defaults to `zones/<zone>`, and it has no `secrets.yaml`.

A zone may name one `workload`, which may then write records and buckets in it too. That takes the place of `zones.yaml` for that zone. `zones.yaml` still works in this release, so a spoke can move one zone at a time; a zone in both places is refused. The clash checks (one entrypoint per phase, one record per name and type, an apex redirect's placeholders) now run across the whole spoke, so a zone's records and its workload's are checked together.

One change reaches existing workloads: a workload's own Cloudflare token now gets *Dynamic URL Redirects Write* only if it declares a `ruleset` or an `apexRedirect`. A workload that has neither plans an in-place update to its token, dropping that group.

`terragrunt-run.yml` selects a zone's leaves the way it selects a workload's: a changed `zone.yaml` plans that zone, and its workload at both the PR's base and head. `terragrunt-detect.yml`'s default `leaf_pattern` gains `^zones/[^/]+/zone\.yaml$`; a spoke that overrides it adds the same. A spoke gitignores `/zones/*/scaleway/` and `/zones/*/cloudflare/`. The editor schema `/schemas/zone/v1.json` is generated beside the workload schema, and moving a live record into a zone follows `docs/runbooks/import-a-leaf-into-a-workload.md`, now written for workloads and zones.

A later major release refuses `zones.yaml`, a workload `ruleset` or `apexRedirect`, and hand-written zone leaves. LIB-0036's new amendment explains why this ships as a minor first.

Tested on a scratch copy of runway with throwaway secrets: its 42 workload stubs, `--list` and `--check` output, and 30 of 31 rendered workload configs are byte-identical to v5.5.0. The one difference is garden's token losing the redirect group. Two zone units, one with a `prefix` and one without, rendered the names, token scope, comments and state keys above. Every refusal, in the script and in root.hcl, was triggered by name. Not tested: a real plan, and validating a `zone.yaml` against the generated schema.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#176](https://github.com/noisypigeon/library/pull/176)

## [5.5.0] - 2026-10-24

### A site workload's features.githubPages implies its Pages CNAMEs (LIB-0034)

A workload's `values.yaml` can now say which GitHub Pages shim deploys its site, and gets the site's Pages DNS from that ([LIB-0034](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0034-site-workloads-declare-their-pages-shim.md) §§1–2):

```yaml
features:
  githubPages:
    pagesShim: noisypigeon/noisypigeon.com
    pagesBaseUrl: noisypigeon.github.io
```

- **Two records are implied.** `cloudflare.dnsRecord.github-pages-root-cname` (`@`) and `github-pages-www-cname` (`www`): each is a CNAME to `pagesBaseUrl` with `ttl: 1`, not proxied, and with the comments the blog's records carry today. They land in `cloudflare.zone`, which `githubPages` now requires.
- **An explicit entry under either key overrides its default field by field.** Every other `dnsRecord` entry is untouched.
- **`resolve-workloads.sh` applies the defaults before anything reads `values.yaml`.** So the implied records count toward the stub list, LIB-0030 §6's clash checks, the `type`/`content` check, and the `secrets.yaml` check for undeclared entries. `--check` refuses a malformed stanza, an unknown key under it, or a `githubPages` without `cloudflare.zone`.
- **`root.hcl` is the twin.** It merges the same defaults under `cloudflare.dnsRecord` for a workload leaf's inputs.
- **The workload schema** (`schemas/workload/v1.json`) learns `features.githubPages`.

A workload without `features` is unchanged. For runway's blog, replacing the two hand-written CNAMEs with the stanza produces the same stub list, byte-identical stubs, and the same module inputs. Its plan should therefore be `No changes.`

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#168](https://github.com/noisypigeon/library/pull/168)

## [5.4.0] - 2026-10-23

### A workload's Cloudflare token is minted with the breakglass token (LIB-0033)

Fixes LIB-0033's minting chain, which [runway#59](https://github.com/noisypigeon/runway/pull/59)'s plan showed can't work: Cloudflare won't let a token grant *Account API Tokens Write*. A spoke token minted by the bootstrap token could never mint workload tokens. Nothing was applied.

- **`terragrunt/root-hcl`:** a workload's `cloudflare/api-token/deployer` leaf now signs in with the spoke's Cloudflare breakglass token, wherever the spoke has one, with no `breakglass.leaves` entry. It's tested on the path alone, so it can't depend on the secrets it decides on.
  - Every other leaf, the workload's Cloudflare record, ruleset and bucket leaves included, is unchanged.
  - A spoke without Cloudflare breakglass renders identically to v5.3.0.
- **The spoke's own Cloudflare token no longer needs to mint.** It holds only what hand-written Cloudflare leaves need. The `cloudflare/api-token` README's example drops the token groups (README only, no module release).

LIB-0033 gains a second amendment recording runway#59's answer to its Verification 6: a minted token may hold groups its minter lacks, except the power to mint.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#160](https://github.com/noisypigeon/library/pull/160)

## [5.3.0] - 2026-10-23

### Workloads sign in to Cloudflare with their own token; bootstrap keys only mint (LIB-0033)

Builds [LIB-0033](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0033-self-bootstrapped-cloudflare-and-backblaze-keys.md) (#155).

**`cloudflare/api-token` v0.1.0 (new).** One account-owned token (`cloudflare_account_token`).
- Policies name their permission groups (such as `"DNS Write"`), resolved through the account's permission-groups list.
- Each policy is scoped to `zones` by apex, `all_zones` or the `account`, exactly one.
- An unknown group, or one the signing-in token may not grant (`is_selectable`), fails the plan by name.
- `rotation_days` replaces the token create-before-destroy, as `scaleway/terraform-deployer-iam` does. Otherwise it expires after `expires_on`, or 365 days.
- It outputs `id` and a sensitive `token`.

**`terragrunt/root-hcl`**
- `secrets-schema.json` gains `cloudflare_breakglass` (`CLOUDFLARE_BREAKGLASS_TOKEN`) and `backblaze_breakglass`. They're for hand-made keys that can only mint keys, read only by the leaves `spoke.hcl`'s `breakglass.leaves` allowlists (LIB-0014 §2).
- A workload that owns a zone in `zones.yaml`, or declares a `cloudflare.bucket`, gets `workloads/<w>/cloudflare/api-token/deployer`, minted with the spoke's token. By default it has *Zone Read*, *DNS Write* and *Dynamic URL Redirects Write* on exactly its zones, plus *Workers R2 Storage Write* if it has buckets, and rotates every 30 days. `cloudflare.deployer` overrides any input.
- The four Cloudflare kinds now sign in with that token: `provider "cloudflare"` reads `var.cloudflare_api_token`.
- Every other leaf renders identically to v5.2.0, Scaleway workload credentials included.

**`workflows/`**
- `resolve-workloads.sh` generates the token stub and wires Cloudflare stubs to it. Workload credentials are now per provider, so a Cloudflare leaf never gets Scaleway's variables.
- `generate-module-redirects.sh` publishes the token's schema, without `account_id`, and adds `cloudflare.deployer` to `v1.json`.

LIB-0033 gains an amendment:
- the token is keyed on zone ownership, so it exists before LIB-0032's import;
- the first `cloudflare.enc` holds the bootstrap token as a placeholder;
- the API-token permission group names are confirmed only by the first real plan.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#159](https://github.com/noisypigeon/library/pull/159)

## [5.2.0] - 2026-10-23

### Workloads can own Cloudflare zones, records, rulesets and redirects (LIB-0030)

Builds [LIB-0030](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0030-cloudflare-workload-kinds-and-zone-ownership.md) (#147).

**Workload kinds.** `cloudflare.bucket` (R2), `cloudflare.dnsRecord`, `cloudflare.ruleset` and `cloudflare.apexRedirect`, all maps.
- They sign in with the spoke's Cloudflare token and keep their state in the workload's Scaleway state bucket.
- `cloudflare.zone` fills `zone` for every entry that doesn't set its own.
- A record's `name` defaults to its key, and its `comment` to `workloads/<w>`.
- A bucket's `account_id` comes from `cloudflare.enc` as a sensitive variable, never a literal.

**Zone ownership.** A root `zones.yaml` gives each zone one owner: a workload, or `terraform` for hand-written leaves.
- A workload may act only on its own zones.
- root.hcl refuses a hand-written `terraform/cloudflare/<zone>/` leaf in a zone a workload owns.
- A `zones.yaml` change re-plans every workload leaf and every zone leaf.
- A spoke without `zones.yaml` is unchanged, as is every non-Cloudflare leaf: they render identically to v5.1.0.

**Refused before planning:**
- two rulesets in one zone and phase;
- a redirect-phase ruleset beside an `apexRedirect`;
- two `apexRedirect`s in one zone;
- duplicate records (`MX`, `TXT`, `CAA`, `SRV` and `NS` may repeat with different content);
- an `A`, `AAAA` or `CNAME` at `@`, or anything at `www`, where an `apexRedirect` holds placeholders;
- `account_id` or `zone_id` written;
- a zone not owned;
- an overlong R2 name.

**`cloudflare/ruleset` v0.2.0.** A `zone` input, looked up by apex as `dns-record` does. It's exactly one of `zone` or `zone_id`.

**`workflows/`:**
- `resolve-workloads.sh` and `generate-module-redirects.sh` gain the kinds, with `workload.schema.json` for `cloudflare/bucket` (without `account_id`) and `cloudflare/ruleset` (without `zone_id`).
- `terragrunt-run.yml` and `terragrunt-detect.yml` treat `zones.yaml` like `root.hcl`.

A spoke can declare Cloudflare kinds once garden builds with this `workflows/` release.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#152](https://github.com/noisypigeon/library/pull/152)

## [5.1.0] - 2026-10-22

### Workloads can declare Backblaze buckets and API keys (LIB-0029)

Records and builds [LIB-0029](https://github.com/noisypigeon/library/blob/feat/lib-0029-backblaze-workload-kinds/docs/adr/LIB-0029-backblaze-workload-kinds.md) (Proposed). A workload's `values.yaml` can now declare Backblaze resources beside its Scaleway ones:

```yaml
backblaze:
  bucket:
    archive: {}
  apiKey:
    archive-reader:
      buckets: [archive]
      capabilities: [listBuckets, listFiles, readFiles]
```

- **`backblaze.bucket.<key>` and `backblaze.apiKey.<key>`** sign in with the spoke's Backblaze key, from `backblaze.enc`. They keep their state in the workload's own Scaleway state bucket (LIB-0028), so even a workload with only Backblaze kinds gets its project, deployer and state bucket.
- **An API key reaches only the buckets its `buckets` list names.** Its stub depends on each one and wires their IDs as `bucket_ids`.
  - `bucket_ids` itself can't be set, so a workload can't create an account-wide key.
  - `capabilities` has no default.
- **Names:** a bucket's defaults to `<prefix>-<key>-<code>-<suffix>`, as a Scaleway bucket's does. A key's defaults to `<prefix>-<key>-<suffix>`. A bucket name longer than B2's 50 characters is refused before planning.
- **A workload leaf gets exactly the provider its path names**, when `spoke.hcl`'s `providers` map has it. `leaves` scopes hand-written leaves only. In runway this leaves every existing leaf's render identical. In a spoke where another provider has no `leaves`, Scaleway workload leaves lose that provider block, but no resource changes.
- **`terragrunt/root-hcl`** gains the kinds, the provider rule, and guards for:
  - a spoke without `backblaze`;
  - an empty or unknown `buckets`;
  - `bucket_ids` set directly.
- **`workflows/`:**
  - `resolve-workloads.sh` generates the stubs, with dependency paths now relative to the workload, and checks the same things before planning.
  - `generate-module-redirects.sh` publishes both modules' schemas, plus a `workload.schema.json` per `backblaze/api-key` version: its inputs without `bucket_ids`, with `buckets`.

Take both in one spoke PR; selection doesn't change. A spoke can declare Backblaze kinds only after garden builds with this `workflows/` release, because `--check` fetches the schemas from there.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#145](https://github.com/noisypigeon/library/pull/145)

## [5.0.1] - 2026-10-22

### A workload's state bucket uses the standard storage class (LIB-0028)

Fixes a default in LIB-0028's workload state bucket. It took `scaleway/bucket`'s default `storage_class`, `glacier`, whose lifecycle rule moves every object to `GLACIER` after 90 days. A workload leaf whose state went unwritten that long would then fail at `init`: state in `GLACIER` can't be read without a restore.

- **`terragrunt/root-hcl`:** `scaleway.state` now defaults to `storage_class: standard`, and refuses `glacier`. For a state bucket created on v5.0.0, the next plan is an in-place change that removes the lifecycle rule. Nothing is replaced.
- **`workflows/`:** `resolve-workloads.sh` refuses `scaleway.state.storage_class: glacier` before any plan runs.

LIB-0028 gains an amendment recording it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#143](https://github.com/noisypigeon/library/pull/143)

## [5.0.0] - 2026-10-22

### Workload state moves into each workload's own bucket (LIB-0028)

The template half of [LIB-0028](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0028-workload-projects-and-state-buckets.md) (#139). **Breaking for any spoke with `workloads/`.** Take it only after `workflows/v4.9.0` (#141), whose `resolve-workloads.sh` generates the stubs this version expects. A spoke with no `workloads/` plans `No changes.`: a hand-written leaf renders exactly as it does on v4.5.0.

- **Every workload has a project, a deployer and a state bucket**, whether or not `values.yaml` declares them. `scaleway.project`, `scaleway.deployer` and the new `scaleway.state` only override their inputs.
  - A workload that had no project gains one, and its deployer, on its next plan.
- **The state bucket** is `workloads/<workload>/scaleway/bucket/state`, a `scaleway/bucket` named `<prefix>-<code>-terraform-state`. Its project is the workload's, and it signs in with the deployer's key. Versioning is on, `force_destroy` is off, and the bucket's own state stays in the spoke's bucket, with the project's and the deployer's.
- **Every other workload leaf keeps its state in the workload's bucket**, at `<prefix><provider>/<module>/<instance>/terraform.tfstate`. `<prefix>` is `scaleway.state.prefix`, by default `workloads/<workload>/`, so the default key is unchanged. The stub's own `remote_state` reads `workload_state_key` and `scaleway_state_config` from this template.
  - Existing state for those leaves isn't moved. Destroy them first, or copy their keys across.
- **New refusals:**
  - `scaleway.bucket.state`;
  - a `scaleway.state.prefix` that starts with `/` or doesn't end with one;
  - `scaleway.state.enable_versioning: false`;
  - a `scaleway.deployer.project_permission_sets` without `ObjectStorageFullAccess`;
  - a workload-state stub with no `remote_state`, which is what an older `resolve-workloads.sh` writes.

LIB-0028 gains an amendment recording these three build findings: the reserved `state` key, `state.schema.json`, and the old-stub guard.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#142](https://github.com/noisypigeon/library/pull/142)

## [4.5.0] - 2026-10-21

### Add a workload secrets.yaml in SOPS YAML (LIB-0025)

A workload can now keep secrets in `workloads/<w>/secrets.yaml`, encrypted with sops as YAML, beside its `values.yaml` (LIB-0025). This releases `terragrunt/root-hcl` and `workflows/` together.

**`terragrunt/root-hcl`:**
- **Decryption:** root.hcl decrypts a workload's `secrets.yaml` for that workload's leaves only. A file that won't decrypt fails the run.
- **Secret inputs,** under the same kind paths as `values.yaml`, become sensitive `string` variables. Their values arrive through the template's inputs and are never written into a generated file, so plans show them as `(sensitive value)`.
- **`{ secretRef: NAME }`:** any `values.yaml` input written this way is resolved from `secrets.yaml`'s `env` map. The whole map is also passed to the workload's leaves as `var.workload_env`.
- **Guards** fail on an input set in both files, a `secretRef` to a missing name, and a list or map value.
- A workload without `secrets.yaml`, and every hand-written leaf, behave as before.

**`workflows/`:**
- **`resolve-workloads.sh --check`** checks `secrets.yaml` without decrypting it. It refuses a file with no `sops` metadata or any plaintext value, unknown keys, a secret for an instance `values.yaml` doesn't declare, an input set in both files, an unknown input, and an unresolvable `secretRef`.
- **`terragrunt-run.yml`** re-plans a workload when only its `secrets.yaml` changes, and masks every decrypted value in the job log.
- **`module-inputs-schema.sh`** accepts `{ secretRef: NAME }` as any input's value in the published schemas.

**Taking it:** add `^workloads/[^/]+/secrets\\.yaml$` to the spoke's `.sops.yaml` with its age recipient. Take this `workflows/` version alone first (LIB-0024 §5), then root-hcl 4.5.0.

Proved on noisypigeon/runway#39, a plan-only draft pinned to this branch. Secrets reached the plan as `(sensitive value)`, and no dummy secret appeared in the comment or the job log.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#119](https://github.com/noisypigeon/library/pull/119)

## [4.4.0] - 2026-10-20

### Give each workload its own deployer, and stage its applies (LIB-0024)

Every workload with a project now bootstraps its own Terraform deployer, and CI applies a workload's leaves in stages, so a new `values.yaml` lands in one PR (LIB-0024). This releases `terragrunt/root-hcl` and `workflows/` together, since their kind tables must agree.

**`terragrunt/root-hcl`:**
- **An implicit deployer kind.** A workload with a `scaleway.project` gets `scaleway/terraform-deployer-iam` at `workloads/<w>/scaleway/terraform-deployer-iam/main`. It's scoped to that project, with `ObjectStorageFullAccess`, and rotates its key every 30 days. An optional `scaleway.deployer` entry overrides its inputs.
- **Each kind says whose credentials it signs in with.** Projects, deployers and IAM objects use the spoke's key. Buckets use the workload deployer's, which root.hcl takes from two sensitive variables the stub sets: `scaleway_access_key` and `scaleway_secret_key`.
- **Typed wiring.** The deployer's `project_ids` is a `list(string)`.
- Hand-written leaves render exactly as before.

**`workflows/`:**
- **`resolve-workloads.sh`** generates the deployer stub, and the bucket's dependency on it. `--check` accepts and validates `scaleway.deployer`.
- **`terragrunt-run.yml`** plans workload leaves one at a time, in dependency order. It defers any whose workload dependencies are new or changing, and lists them in the PR comment. An apply that leaves units deferred keeps `terragrunt/apply` pending and doesn't auto-merge; a `terragrunt plan` comment plans the next stage.
- **`generate-module-redirects.sh`** publishes `terraform-deployer-iam`'s per-version input schemas, and adds `scaleway.deployer` to the workload schema.

**Taking it:** because an `issue_comment` apply runs the default branch's callers, a spoke takes this `workflows/` version alone first, in a PR that changes only `.lib-version` and the callers and so selects nothing. It takes root-hcl 4.4.0 and any workload changes after that (LIB-0024 §5). `resolve-workloads.sh --check` needs the deployer's schema on noisypigeon.garden, so garden takes this version before any spoke checks a workload with it.

Proved on noisypigeon/runway#36, a plan-only draft pinned to this branch. It planned the POC's new deployer and deferred its bucket.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#114](https://github.com/noisypigeon/library/pull/114)

## [4.3.1] - 2026-10-20

### Stop telling spokes to commit workload stubs

When a workload leaf has no entry in its `values.yaml`, root.hcl's error used to say to run `resolve-workloads.sh` and commit the result. Workload stubs are now generated, never committed (LIB-0023's second amendment, `workflows/v4.2.0`), so the message says to run `resolve-workloads.sh`, which generates them from `values.yaml`. Nothing else changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#106](https://github.com/noisypigeon/library/pull/106)

## [4.3.0] - 2026-10-20

### Support workload leaves in the root.hcl template (LIB-0023)

The template now accepts a second kind of leaf, a workload leaf at `workloads/<workload>/<provider>/<module>/<instance>/`, generated by `resolve-workloads.sh` (`workflows/v4.1.0`) from `workloads/<workload>/values.yaml` at the spoke's root. Its state goes in the same bucket as every other leaf's, keyed by its path.

For a workload leaf, the template:

- reads the leaf's entry in `values.yaml` and marks the file read. A PR that edits only `values.yaml` still plans every leaf that reads it.
- defaults names from `prefix` and `suffix`: the project and IAM application are named `<prefix>-<suffix>`, and a bucket is named `<prefix>-<key>`…`<suffix>`.
- resolves the module version at every plan. `version: "X.Y.Z"` pins exactly, `"X.Y"` or `"X"` takes the newest release within it, and no `version` takes the newest release.
- writes `workload_generated.tf`. That file is a `module "this"` call at the resolved short URL with the entry's inputs as literals. Wiring inputs (a bucket's `project_id`, an API key's `default_project_id` and `application_id`) are variables the stub sets from its dependencies. The whole module is exposed as `output "module"`.
- fails the run with a clear message when `values.yaml` is missing or invalid, the kind is unknown, the stub has no entry, `prefix` or `suffix` is empty, or no release matches the pin.

Every other leaf gets a one-line comment in `workload_generated.tf` and otherwise behaves exactly as on v4.2.0, so a spoke with no `workloads/` plans `No changes.`. This release includes v4.2.0's state lockfile, so a Scaleway spoke should take it only after LIB-0022's Scaleway lock check.

The PR also corrects LIB-0023's amendment: inputs are literals, not variables.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#104](https://github.com/noisypigeon/library/pull/104)

## [4.2.0] - 2026-10-20

### feat(root-hcl): lock Terraform state on both backends (LIB-0022)

Every leaf's state is now locked while Terraform writes it, on both state backends (LIB-0022 §4). The template sets `use_lockfile = true` in the Scaleway and the R2 backend config. Terraform then takes the lock with a conditional write of `<state key>.tflock` next to the state, and removes it when the run finishes. A second plan or apply of the same leaf fails with `Error acquiring the state lock` instead of writing the state at the same moment.

Nothing a spoke sets changes, and state keys stay the same, so every leaf should plan `No changes.` after the bump. Rendered against garden (R2) and runway (Scaleway), each leaf checked gains only `use_lockfile` in its `remote_state` config.

**If a run dies holding a lock,** that leaf stays locked until it is released by hand. The new runbook, `docs/runbooks/release-a-stuck-state-lock.md`, covers checking that nothing still holds the lock and then running `terragrunt force-unlock`.

**Scaleway spokes should wait.** The lock is only as good as the backend's conditional writes. R2 evaluates them atomically. On Scaleway that is still to be proved (LIB-0022 Verification 1), so runway takes this version only after that.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#91](https://github.com/noisypigeon/library/pull/91)

## [4.1.1] - 2026-10-17

### Name the hub noisypigeon/library

This repo is now `noisypigeon/library`, renamed from `noisypigeon/pigeon-lib` (LIB-0015).

- **`generate-module-redirects.sh`** defaults `TAG_REPO` to `noisypigeon/library`. Once a site takes this `workflows` release, every module short URL's `terraform-get` meta resolves to `git::https://github.com/noisypigeon/library.git//…`, and the overview and release links name the new repo too. The old `pigeon-lib.git` sources keep working through GitHub's redirect in the meantime. The short URLs themselves don't change.
- **The theme's `homepage`** points at the new repo.
- **Docs.** The `root.hcl` template header, the READMEs (including the raw dashboard URLs), CLAUDE.md and the release-pr skill now name the library. ADRs and changelogs keep the old name as history.

No inputs, outputs or behaviour change for any consumer.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#70](https://github.com/noisypigeon/library/pull/70)

## [4.1.0] - 2026-10-17

### Add per-leaf breakglass credentials to root.hcl and check-secrets

A spoke can now give chosen leaves a second, hand-made credential for a provider (LIB-0014). It is for a leaf that manages the key every other leaf deploys with, such as `scaleway/terraform-deployer-iam`: that leaf must not authenticate with the key it rotates.

**Enabling it.** Add `breakglass` to the provider's entry in `spoke.hcl`, with the leaves allowed to use it:

```hcl
providers = {
  scaleway = {
    breakglass = { leaves = ["terraform/scaleway/terraform-deployer-iam/"] }
  }
}
```

Then commit `terraform/secrets/scaleway_breakglass.enc` holding `SCALEWAY_BREAKGLASS_ACCESS_KEY_ID` and `SCALEWAY_BREAKGLASS_ACCESS_KEY`.

**What it does.** Only a listed leaf decrypts that file. It reads `SCALEWAY_PROVIDER_ACCESS_KEY(_ID)` from the breakglass key, and so does `TERRAFORM_STATE_ACCESS_KEY(_ID)` when `state_backend` is `scaleway`. The organization and project IDs still come from `scaleway.enc`. As everywhere else, an environment variable under the regular name overrides both.

**Schema-driven and generic.** `secrets-schema.json` gains a `scaleway_breakglass` file, required under `breakglass.scaleway`. Its `replaces` and `replaces_state` maps say which credentials it stands in for. Every provider's credential lookup goes through the same mechanism, so Cloudflare or Backblaze breakglass would need only a schema entry.

**Guards.** The render fails on:
- `breakglass` without a non-empty `leaves`;
- a prefix without a trailing `/`;
- breakglass for a provider the schema has no breakglass file for.

`check-secrets.sh` requires the file spoke-wide once `spoke.hcl` enables it.

**No change unless you opt in.** For a spoke that doesn't set `breakglass`, rendering is byte-for-byte the same as v4.0.0.

Tested against a sops/age fixture spoke:
- the allowlisted leaf took its provider and backend credentials from the breakglass file;
- a non-allowlisted leaf rendered with the breakglass file corrupted, so it never decrypted it;
- each guard fired;
- `check-secrets.sh` failed without the file and passed with it;
- the script still parses runway's current `spoke.hcl`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#67](https://github.com/noisypigeon/pigeon-lib/pull/67)

## [4.0.0] - 2026-10-17

### Split spoke secrets into one sops file per concern

A spoke's secrets now live in one sops dotenv file per concern under `terraform/secrets/`, instead of all in `terraform/secrets.enc` (LIB-0012). Each leaf decrypts only the files it needs, and each file holds exactly its own keys, so a value under the wrong key or in the wrong file fails before any plan. This is a breaking release of both the `root.hcl` template and the reusable workflows. Spokes move one PR each. The values and their names don't change (except `env.enc` dropping `ENV_`), so every leaf should plan `No changes.`

**`root.hcl` v4.0.0**

- **The files.**

  | File | Required when | Keys, exactly |
  | --- | --- | --- |
  | `terraform.enc` | always | `TERRAFORM_STATE_{BUCKET_NAME,ACCESS_KEY_ID,ACCESS_KEY}`, plus `TERRAFORM_STATE_BACKUP_{BUCKET_NAME,ACCESS_KEY_ID,ACCESS_KEY}` if and only if `state_backup = true` |
  | `cloudflare.enc` | `providers.cloudflare` | `CLOUDFLARE_PROVIDER_{ACCOUNT_ID,TOKEN}` |
  | `scaleway.enc` | `providers.scaleway` | `SCALEWAY_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY,ORGANIZATION_ID,PROJECT_ID}` |
  | `backblaze.enc` | `providers.backblaze` | `BACKBLAZE_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY}` |
  | `env.enc` | optional | any `^[A-Z][A-Z0-9_]*$` key |

  A required file must exist and hold exactly its keys, each non-empty. A file for a provider the spoke doesn't enable is ignored, never decrypted.
- **Least-privilege decryption.** A leaf runs `sops` only on:
  - `terraform.enc`;
  - `cloudflare.enc` when the backend is `cloudflare`, for the R2 endpoint;
  - each provider file whose provider is on for that leaf, honouring `leaves` scoping;
  - `env.enc` if it exists.

  willowgraysen's Grafana leaf decrypts `terraform.enc`, `scaleway.enc` and `env.enc`, and never `backblaze.enc`. An environment variable still overrides any value (`get_env`).
- **`env.enc` has no prefix.** Its key `FOO_BAR` becomes `local.foo_bar` in every leaf, in `env_secrets_generated.tf` as before. A key fails the render when:
  - its local would shadow a generated one: `cloudflare_account_id`, `cloudflare_zone`, `scaleway_organization_id`, `scaleway_project_id`, `scaleway_s3_provider_name` or `grafana_auth_token`;
  - another file owns that name, such as `BACKBLAZE_PROVIDER_ACCESS_KEY`.
- **`spoke.hcl` gets `state_backup`.** It defaults to `false`; `true` adds the backup keys to `terraform.enc` and turns on `state-backup.yml`. `state_backend = "cloudflare"` now requires `state_backup = true`, because R2 can't version objects (LIB-0007). It still requires `providers.cloudflare`.
- **The schema is per file.** In `secrets-schema.json`, `files.<name>` has `required_when` (a list of conditions, any of which requires the file), `keys`, and `keys_when` (keys added under a condition). `files.env` has its `pattern` and `reserved` local names. The render fails on a missing file, a missing or empty key, a key outside its file, or a reserved `env.enc` name. Each error names the file and key, never a value.

**`workflows/` v3.0.0**

- **`check-secrets.sh` checks per file,** spoke-wide, from plaintext key names, with no `SOPS_AGE_KEY`. It fails on:
  - a missing required file;
  - a file that doesn't hold exactly its keys (backup keys without `state_backup` say so);
  - a `.enc` the schema doesn't know;
  - a leftover `terraform/secrets.enc`;
  - the two R2 guards.

  It reports an ignored file without failing. It takes no file argument any more.
- **New `split-secrets.sh`,** the one-time migration a spoke's owner runs. It turns `terraform/secrets.enc` into the per-concern files.
  - It pipes `sops -d` through a filter into `sops -e`, so only ciphertext touches disk and no value is printed.
  - It encrypts each file to the source file's own age recipients, whatever `.sops.yaml` says.
  - It strips `ENV_` for `env.enc`. It stops before writing anything if a key has no owner, and refuses to overwrite a file.
  - It ends by running `check-secrets.sh`.
- **`terragrunt-run.yml` masks every `terraform/secrets/*.enc` by default.** `secrets_files` now defaults to empty, meaning those files, instead of `.env.enc`.
- **`state-backup.yml` reads only `terraform.enc` and `cloudflare.enc`,** and does nothing unless `spoke.hcl` sets `state_backup = true`.
- **`terragrunt-detect.yml`'s default leaf pattern covers `terraform/secrets/`.**

**Migrating a spoke.** `terragrunt/root-hcl/README.md` has the steps:

1. The owner runs `.lib-src/.github/scripts/split-secrets.sh` with the hub at `workflows/v3.0.0`.
2. The spoke's PR:
   - runs `git rm terraform/secrets.enc` and adds `terraform/secrets/*.enc`;
   - sets `.sops.yaml`'s rule to `path_regex: ^terraform/secrets/[a-z]+\.enc$`;
   - makes `mise run secrets-edit <file>` take a file name;
   - sets `state_backup = true` on an R2 spoke;
   - bumps `root_hcl_version` to `"4.0.0"` and `/.lib-version` to `workflows/v3.0.0`, and commits both generated files;
   - pins `@workflows/v3.0.0`, and deletes `secrets_files: terraform/secrets.enc` from the `terragrunt-run.yml` callers.
3. Every leaf plans `No changes.`

The B2 restore runbook loads its keys from the split files.

**Verified against all three spokes,** using LIB-0010's method. garden, blog and willowgraysen were copied to a scratch dir with fake values encrypted to a throwaway age key; no real secrets file was decrypted.

- **Parity.** v4's copies were made by running `split-secrets.sh` on each fake v3 file. All 32 leaves rendered under v3 and v4. `remote_state`, inputs and every generated file are byte-identical; `env_secrets_generated.tf` is identical in all 18 willowgraysen leaves. The only difference is the one-line comment written when a spoke has no `env.enc` (garden and blog).
- **Least privilege.** A `sops` wrapper logged every file decrypted. The Grafana leaf decrypted only `terraform.enc`, `scaleway.enc` and `env.enc`, and no leaf outside `terraform/backblaze/` decrypted `backblaze.enc`. An ignored `cloudflare.enc` in willowgraysen was never read.
- **Guards.** Each fires and names its file and key:
  - a missing required file;
  - a missing key, and an empty key (which an environment variable then fills);
  - a Cloudflare key in `scaleway.enc`;
  - backup keys without `state_backup`, willowgraysen's earlier mistake;
  - a reserved `env.enc` name, an `env.enc` key another file owns, and a lowercase `env.enc` key;
  - R2 without `state_backup`, and R2 without `providers.cloudflare`.

  A missing `backblaze.enc` fails only the Backblaze leaves.
- **`check-secrets.sh`.** It passes on each split copy, with no age key and no `sops` on `PATH`. It fails on every case above, on an unknown `.enc`, on a plaintext file, and on each real spoke as it stands today.
- **Workflows.** `state-backup.yml`'s steps ran against the fake copies. garden's loaded only `terraform.enc` and `cloudflare.enc`, and willowgraysen's skipped. `terragrunt-run.yml`'s default masked every split file. `actionlint` passes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#62](https://github.com/noisypigeon/pigeon-lib/pull/62)

## [3.0.0] - 2026-10-16

### Fixed secret names checked against a schema (root.hcl v3, workflows v2)

Every spoke secret now has one fixed name, the same in every spoke, and which names a spoke needs follows from its `spoke.hcl` (LIB-0010). This is a breaking release of both the `root.hcl` template and the reusable workflows. Spokes move one PR each, renaming their `secrets.enc` keys; values don't change, so every leaf should plan `No changes.`

**`root.hcl` v3.0.0**

- **Fixed names.** Secrets are read by fixed names with `get_env(NAME, secrets.enc[NAME])`.
  - State: `TERRAFORM_STATE_{BUCKET_NAME,ACCESS_KEY_ID,ACCESS_KEY}`, for both backends.
  - B2 backup: `TERRAFORM_STATE_BACKUP_*`.
  - Providers: `CLOUDFLARE_PROVIDER_{ACCOUNT_ID,TOKEN}`, `SCALEWAY_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY,ORGANIZATION_ID,PROJECT_ID}` and `BACKBLAZE_PROVIDER_{ACCESS_KEY_ID,ACCESS_KEY}`.
  - State never borrows a provider's key. A Scaleway-backed spoke holds its key under both names.
- **The schema.** `secrets-schema.json` lists the required keys per condition (`always`, `backend.cloudflare`, `provider.<name>`) and the allowed `^ENV_[A-Z0-9_]+$` pattern. The template reads it from beside itself. It fails the render, naming the key and never its value, when a required key is missing or empty, or when `secrets.enc` holds a key outside the schema.
- **`spoke.hcl` changes.** `state_bucket_secret` is gone, and the template fails if a spoke still sets it. `state_backend = "cloudflare"` now requires `providers.cloudflare`, because the R2 endpoint is built from `CLOUDFLARE_PROVIDER_ACCOUNT_ID`.
- **One `ENV_` prefix.** `ENV_<NAME>` becomes `local.<name>` in every leaf, whatever its providers, in `env_secrets_generated.tf`. It replaces `ENV_SW_`/`ENV_CF_`, and the locals keep their names. `env_scaleway_secrets_generated.tf` is still written, as a comment, so a stale copy can't define the same locals twice.
- **No zone IDs.** `ENV_CF_ZONE_ID_*`, `local.cloudflare_zone_id` and its guard are removed. Zone leaves keep `local.cloudflare_zone`, and `cloudflare/dns-record` v1 looks the zone up by apex (LIB-0011).
- **Unchanged locals.** `local.cloudflare_account_id`, `local.scaleway_organization_id` and `local.scaleway_project_id` are still generated.

**`workflows/` v2.0.0**

- **`state-backup.yml` takes no name inputs.** Its `state_bucket_secret`, `backup_bucket_secret`, `backup_key_id_secret` and `backup_key_secret` inputs are gone. It reads `TERRAFORM_STATE_*` and `TERRAFORM_STATE_BACKUP_*`, and builds the R2 endpoint from `CLOUDFLARE_PROVIDER_ACCOUNT_ID`. Delete those inputs from its callers. `terragrunt-run.yml` never had them, so it's unchanged.
- **`resolve-root-hcl.sh` copies the schema too.** It writes `secrets-schema.json` beside `root.hcl` at the pinned version, and `--check` verifies both files. For a version before v3.0.0 it removes a stale copy.
- **New `check-secrets.sh`.** It reads the key names from `terraform/secrets.enc` without decrypting (sops dotenv keeps them in plaintext), and `state_backend` and `providers` from `spoke.hcl`. It exits 1 listing missing and unknown keys. It needs no `SOPS_AGE_KEY`. Spokes append it to `prepare_cmd`: `… resolve-root-hcl.sh --check && .lib-src/.github/scripts/check-secrets.sh`.
- **Wider release predicate.** A change to `terragrunt/root-hcl/secrets-schema.json` now releases the template, in `template-release.yml` and its twin in `root-changelog.yml`.

**Migrating a spoke.** `terragrunt/root-hcl/README.md` has the old-to-new key map and the steps:

1. Rename the keys.
2. Delete `state_bucket_secret`.
3. Set `root_hcl_version = "3.0.0"`, with `/.lib-version` at `workflows/v2.0.0` or later, and commit both generated files.
4. Pin `@workflows/v2.0.0` and add `check-secrets.sh` to `prepare_cmd`.

The B2 restore runbook uses the new names.

**Verified against all three spokes.** garden, blog and willowgraysen were copied to a scratch dir, with fake values under the real key names.

- **Parity.** All 34 leaves rendered under v2.2.1 (old names) and v3 (new names). `remote_state`, inputs and every provider file are byte-identical. The only differences are the dropped zone-ID locals, the `env_scaleway_secrets` comment, and the new `env_secrets_generated.tf`, whose locals match v2's `ENV_SW_` set exactly.
- **Guards.** Each fires on its case: a missing key, an empty key, unknown keys (`CLOUDFLARE_TOKEN`, `ENV_lower`), R2 without the Cloudflare provider, and a leftover `state_bucket_secret`. A missing key supplied through the environment passes.
- **`check-secrets.sh`.** It passes on each renamed copy and fails on each real `secrets.enc` as it stands today. It ran with no age key and no sops on `PATH`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#59](https://github.com/noisypigeon/pigeon-lib/pull/59)

## [2.2.1] - 2026-10-16

### Drop pigeon.dev from comments and docs

Comments and docs across the hub now describe the current architecture only. `pigeon.dev` is gone from them: the site repo is `noisypigeon/garden`, and module sources are `https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z`.

- **`terragrunt/root-hcl`:** the template's header drops how it was generalized from the monorepo's per-domain roots, and its example secret is a real current one. Only comments change, so every leaf renders exactly as it did under v2.2.0, and a spoke can take this version as a no-op.
- **`scaleway/project`:** the header comment drops the module's relocation history. No inputs, outputs or resources change.
- **`generate-module-redirects.sh`:** a comment change only.
- **Docs:** `CLAUDE.md`, `terraform/README.md`, `terragrunt/root-hcl/README.md`, `zola-site/README.md` and the `release-pr` skill name `noisypigeon/garden` and the current host, without the pigeon.dev history.
- **LIB-0009** gets an amendment line. `pigeon.dev` redirects to `https://noisypigeon.com`, not the garden (noisypigeon/noisypigeon.com#33).

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#55](https://github.com/noisypigeon/pigeon-lib/pull/55)

## [2.2.0] - 2026-10-16

### Zone leaves at terraform/cloudflare/<zone>/<module>/<instance>/, with their zone ID from the template (LIB-0008)

A spoke's Cloudflare leaves that write to a zone can now say which zone in their path, and `root.hcl` hands them that zone's ID ([LIB-0008](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0008-cloudflare-zone-leaves.md)).

### The layout

A leaf calling a zone-scoped Cloudflare module (`cloudflare/dns-record` or `cloudflare/ruleset`) lives at `terraform/cloudflare/<zone>/<module>/<instance>/`, for example `terraform/cloudflare/noisypigeon.com/dns-record/proton`. `<zone>` is the zone's apex domain.

- The module's short URL doesn't change.
- Account-level modules such as `cloudflare/bucket` keep `terraform/cloudflare/<module>/<instance>/`.
- This is the one exception to LIB-0004's three segments, and LIB-0004 carries an amendment line saying so.

### What the template adds

A zone leaf now gets two locals:
- `local.cloudflare_zone`, the zone's apex domain;
- `local.cloudflare_zone_id`, read from `ENV_CF_ZONE_ID_<ZONE>` in `secrets.enc` (`noisypigeon.com` → `ENV_CF_ZONE_ID_NOISYPIGEON_COM`).

Write `zone_id = local.cloudflare_zone_id` in the leaf. If the secret is missing, the run fails with a message naming the expected key, instead of planning records into the wrong zone.

**Nothing changes until a leaf moves.** The existing `local.zone_id_<zone>` locals still render, and every non-zone leaf's generated files are byte-identical to v2.1.0's.

### Moving a leaf on R2

LIB-0008 §3 updates LIB-0004's state-move runbook for the R2 backend: copy the state object to the new key byte for byte, check serial and lineage, plan, then `state rm` the old key. `terraform state push` into an empty R2 key adopts a new lineage (COM-0004).

The module READMEs now say which modules are zone-scoped (`dns-record`, `ruleset`) and which are account-level (`bucket`). noisypigeon.com adopts first. The redirector moves and noisypigeon.garden are tracked in noisypigeon/noisypigeon#320, #321 and #322.

Verified by rendering all 32 leaves across the three spokes under v2.1.0 and this template: everything apart from `locals` hashed identically. A zone leaf rendered the right zone and ID, and a zone with no secret failed with the expected message.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#47](https://github.com/noisypigeon/pigeon-lib/pull/47)

## [2.1.0] - 2026-10-15

### State backend selectable in spoke.hcl: Scaleway or Cloudflare R2 (LIB-0007)

`root.hcl` can now keep a spoke's Terraform state in Cloudflare R2 as well as in Scaleway Object Storage. [LIB-0007](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0007-terraform-state-on-r2-with-offsite-backup.md) records why and how.

### `state_backend` in `spoke.hcl`

```hcl
locals {
  root_hcl_version    = "2.1.0"
  state_bucket_secret = "NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME"
  state_backend       = "cloudflare"   # or "scaleway", the default
}
```

- **Leave it out and nothing changes.** `"scaleway"` is the default, and a spoke that doesn't set it renders exactly what v2.0.0 rendered.
- **`"cloudflare"`** points the S3 backend at the account's EU-jurisdiction R2 endpoint, `https://<account_id>.eu.r2.cloudflarestorage.com` (LIB-0006), with `region = "auto"`, path-style addressing and `skip_s3_checksum`. It also tells Terragrunt not to enable versioning on, or otherwise update, the bucket: R2 has no object versioning.
- **Any other value fails the run** with a message naming the known ones.

The state key is `terraform/<leaf>/terraform.tfstate` on either backend. Moving a spoke between them copies objects; it changes no keys.

### R2 credentials

Cloudflare has no Terraform resource for R2's S3 keys. Create an R2 API token with *Object Read & Write*, scoped to the state bucket, in the dashboard. Store its keys in the spoke's `secrets.enc` as `CLOUDFLARE_R2_ACCESS_KEY_ID` and `CLOUDFLARE_R2_SECRET_ACCESS_KEY`. The account ID is the existing `CLOUDFLARE_ACCOUNT_ID`.

### Offsite backup

Because R2 can't version, LIB-0007 also pairs an R2 state bucket with a versioned Backblaze B2 copy, made by the reusable `state-backup.yml` workflow. That ships in its own PR as `workflows/v1.4.0`.

Verified by rendering every `pigeon.dev` leaf under v2.0.0 and under this template. With no `state_backend`, everything apart from `locals` hashed identically. The `"cloudflare"` render and the guard were checked too.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#39](https://github.com/noisypigeon/pigeon-lib/pull/39)

## [2.0.0] - 2026-10-15

### Providers enabled and configured in spoke.hcl (LIB-0005)

`terragrunt/root-hcl` v2.0.0 makes a spoke's `spoke.hcl` the one place that turns providers on and configures them. Recorded in [LIB-0005](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0005-providers-configured-in-spoke-hcl.md).

### The `providers` map

```hcl
providers = {
  cloudflare = {}
  scaleway   = { region = "fr-par", zone = "fr-par-1" }
  backblaze  = { leaves = ["terraform/backblaze/bucket/"] }
  grafana    = { leaves = ["terraform/grafana/dashboard/"] }
}
```

- **Required.** A provider not in the map is off for every leaf.
- **`leaves` is optional.** It takes path prefixes, each ending in `/`, and limits the provider to leaves under them. Under LIB-0004's layout that's usually `terraform/<provider>/<module>/`.
- **Scaleway's `region`/`zone`** move here from the old per-leaf `scaleway_config.hcl`. The defaults are unchanged.
- **Grafana keeps its contract.** An enabled leaf defines `local.grafana_auth_token`. It needs Scaleway on for the same leaf.

### Breaking changes

- **`backblaze = true` and `grafana = true` in `spoke.hcl` are now an error.**
- **`scaleway_config.hcl`, `backblaze_config.hcl` and `grafana_config.hcl` are no longer read.**
- **Each provider gets its own `provider_<name>_generated.tf`.** The one `required_providers` block stays in `provider_generated.tf` and lists only the providers the leaf gets. A provider that's off for a leaf leaves a one-line comment file, so it overwrites any stale v1 file in `.terragrunt-cache`.

The template also fails loudly on:

- an unknown provider key;
- a prefix without its trailing slash;
- Grafana without Scaleway.

The state backend and state keys don't change.

### Migrating a spoke

1. Add `providers`, with `cloudflare = {}` and `scaleway = {}` for v1's defaults.
2. Turn any `backblaze`/`grafana` bool into an entry whose `leaves` covers the leaves that had a `*_config.hcl`.
3. Delete those files.
4. Bump `root_hcl_version` to `"2.0.0"` and regenerate `root.hcl`.

### Verified against all three spokes

All 30 leaves (`pigeon.dev` 4, `noisypigeon.com` 6, `willowgraysen.com` 20) were checked with exactly that migration applied temporarily:

- **Renders:** identical to their current `root.hcl` (v1.0.1, v1.0.1, v1.2.0) in every key and in every non-comment generated line, state keys included.
- **Plans:** `No changes.` on every leaf.

Each new guard was also checked: it fails the render with its own message.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#36](https://github.com/noisypigeon/pigeon-lib/pull/36)

## [1.2.0] - 2026-10-15

### A latent Scaleway Cockpit Grafana provider in the root.hcl template

`terragrunt/root-hcl` gains a latent Grafana provider, shaped like the Backblaze one. A leaf that manages Grafana dashboards then needs no provider block or data source of its own, and can be a single module call, as [LIB-0004](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0004-normalized-terraform-leaf-layout.md) requires.

### How a leaf opts in

1. `grafana = true` in the spoke's `spoke.hcl`.
2. A sibling `grafana_config.hcl` with `enabled = true` in each leaf that uses it.

### What an enabled leaf gets

- **`grafana/grafana ~> 4.0`** in its `required_providers`.
- **A generated `data "scaleway_cockpit_grafana" "grafana"`** for the project's Grafana URL.
- **A generated `provider "grafana"`**, authenticated with **`local.grafana_auth_token`**. The leaf must define that local: the IAM API key secret, usually passed in from another leaf's output.

A leaf in a Grafana-enabled spoke that hasn't opted in gets a comment-only file. A spoke without `grafana = true` gets nothing.

### Verified

I rendered every leaf of all three spokes (24 leaves) under its current `root.hcl` and under this template. The only differences are added generate entries with `disable: true`, which write no file. State keys are unchanged everywhere. LIB-0003 records this as its third amendment.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#32](https://github.com/noisypigeon/pigeon-lib/pull/32)

## [1.1.0] - 2026-10-15

### Optional extra providers and Backblaze support in the root.hcl template

The `root.hcl` template gains two optional `spoke.hcl` settings, which `willowgraysen.com` needs before its Terraform can move into its own repo. Both are off by default, and a spoke that sets neither gets no new file.

### `extra_required_providers`

A map of `{ source, version }` entries, appended to the one `required_providers` block:

```hcl
extra_required_providers = {
  grafana = { source = "grafana/grafana", version = "~> 4.0" }
}
```

A provider's own configuration, if it needs one, still lives in the leaf that uses it.

### `backblaze = true`

This turns on the latent Backblaze B2 provider from DEV-0148, unchanged in behaviour:

- A leaf opts in by dropping a sibling `backblaze_config.hcl` with `enabled = true`. It then gets the `b2` required-provider entry and a `provider "b2"` block configured from `BACKBLAZE_APPLICATION_KEY_ID` and `BACKBLAZE_APPLICATION_KEY`.
- Other leaves in that spoke get a comment-only `provider_backblaze_generated.tf`.
- In a spoke without `backblaze = true`, that generate block is disabled, so the file is never written.

### Verified with `terragrunt render --format=json`

- **`willowgraysen.com`'s 14 hoistable leaves:** compared against their current root, each differs in one key, the generated provider file, and only in whitespace. The original root left a blank indented line where the Backblaze entry would go. State keys are equal.
- **`pigeon.dev`'s 4 leaves and `noisypigeon.com`'s 6:** compared against `v1.0.1`, each differs only by the disabled Backblaze generate block (`disable: true`, `if_disabled: skip`), which writes nothing.

[LIB-0003](docs/adr/LIB-0003-terragrunt-root-hcl-template-and-spoke-terragrunt-ci.md) records this as its second amendment.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#21](https://github.com/noisypigeon/pigeon-lib/pull/21)

## [1.0.1] - 2026-10-15

### Mark the root.hcl template as generated and committed in spokes

Only the template's header comment changes. The configuration it produces is identical to `v1.0.0`.

The header used to say a spoke never commits `root.hcl`. Spokes now must commit it. Terragrunt's `[main...HEAD]` git filter plans inside git worktrees that contain only tracked files, so a gitignored copy made every leaf fail with `Could not find a root.hcl`. The header is what a spoke commits, so it now reads "GENERATED in a spoke -- do not edit there". It says how to change the template (change it in `pigeon-lib`, then bump `root_hcl_version`), and that CI runs `resolve-root-hcl.sh --check` against it. The `--check` mode shipped in `workflows/v1.3.1`.

Also updated:

- the template's `README.md`: consumption steps and the reasons for committing;
- the hub's `CLAUDE.md`;
- the root `CHANGELOG.md` header, which now lists the `terragrunt/root-hcl` and `terragrunt` tags;
- [LIB-0003](docs/adr/LIB-0003-terragrunt-root-hcl-template-and-spoke-terragrunt-ci.md): a dated `## Amendments` section recording the dry run that failed and the one that passed. Its date is also corrected to 2026-10-15.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#18](https://github.com/noisypigeon/pigeon-lib/pull/18)

## [1.0.0] - 2026-10-15

### Add the spokes' Terragrunt root.hcl template

The first version of `terragrunt/root-hcl/root.hcl`: the Terragrunt root every spoke in this family will share, replacing the per-domain `root.hcl` copies in `noisypigeon/noisypigeon`. Recorded in [LIB-0003](docs/adr/LIB-0003-terragrunt-root-hcl-template-and-spoke-terragrunt-ci.md).

### What it does

For every leaf under a spoke's `terraform/`, it:

- decrypts `terraform/secrets.enc` in memory with sops/age, and exposes `ENV_SW_*`/`ENV_CF_*` keys as locals;
- generates the Cloudflare and Scaleway providers, honouring a leaf's optional `scaleway_config.hcl`;
- excludes anything outside `terraform/`;
- keeps state in the spoke's own bucket at `terraform/<leaf>/terraform.tfstate`. That is byte-identical to the per-domain roots, so adopting the template moves no state.

### Consuming it

A spoke never commits `root.hcl`. It commits a `spoke.hcl`:

```hcl
locals {
  root_hcl_version    = "1.0.0"
  state_bucket_secret = "PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME"
}
```

It gitignores `/root.hcl` and runs `.lib-src/.github/scripts/resolve-root-hcl.sh` (shipped in `workflows/v1.3.0`) from its repo root before Terragrunt. The script copies the template at the pinned version. A missing `spoke.hcl`, or a missing `state_bucket_secret`, stops the run instead of guessing a bucket. See [`terragrunt/root-hcl/README.md`](terragrunt/root-hcl/README.md) for why the template is copied rather than included or symlinked.

### Verified against the root it replaces

I rendered `pigeon.dev`'s four hoistable leaves with `terragrunt render --format=json`, once under the monorepo's `pigeon.dev/root.hcl` and once under this template. After normalizing the two trees' absolute paths, the renders differ in **zero** keys, including all four `generate` blocks and the backend. The state keys are literally the same in both.

The hub's `CLAUDE.md`, `README.md` and `release-pr` skill now list four release tracks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#16](https://github.com/noisypigeon/pigeon-lib/pull/16)
