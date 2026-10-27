# LIB-0039: Mail and identity services in zone.yaml, and wrapped unit files

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-26.
- **Status**: Proposed; amended 2026-10-26 (see `## Amendments`). Amends:
  - LIB-0036 §§1–3, whose `zone.yaml` moves under one `zone` key and gains
    `services` and `dnsRecords`;
  - LIB-0037 §§1–4, whose `workload.yaml` moves under one `workload` key;
  - LIB-0030 §§1, 4 and 6, whose `cloudflare.dnsRecord` becomes `dnsRecords`;
  - LIB-0038 §3, whose `apexRedirect` now expands into `dnsRecords`;
  - LIB-0023 §2 and LIB-0028 §4, whose kind table names the new key.

## Context

A zone that receives mail, or proves who owns it, spells out its provider's
DNS records by hand under `cloudflare.dnsRecord`. runway's noisypigeon.com
has eleven: Proton's MX, DKIM, SPF, DMARC and two verification records, a
Google Search verification record and Bluesky's handle. pigeon.dev has six,
for Fastmail. Each provider's records are almost all the same in every zone:
only a verification token, a DID, or the zone's own name in a DKIM target
differs.

Writing them by hand costs three things.

- **They drift.** noisypigeon.com's third Proton DKIM record is commented
  "fastmail tertiary dkim" and its DMARC record "proton spf verification".
  Its Google record alone has a ttl of 3600 and no comment, and one leaf is
  keyed `proton-proton-spf`.
- **A new zone copies an old one.** Moving a domain to a provider means
  copying six to ten records from another zone and editing the right parts of
  them.
- **A zone's file doesn't say what it uses.** "This domain receives mail at
  Proton" is eleven records deep.

Separately, both unit files grew their keys one record at a time. A
zone.yaml and a workload.yaml are told apart only by name, and an editor
that opens one bare can't tell which schema applies. `dnsRecord` sits under
`cloudflare` beside kinds of a different nature (a bucket, a ruleset, a
deployer), though a record is the one thing both a zone and a workload
declare by hand most often.

## Decision

### 1. Each unit file has one root key

A zone's file is `zones/<zone>/zone.yaml`, with all of its content under
`zone`. A workload's file is `workloads/<zone>/<workload>/workload.yaml`,
with all of its content under `workload`.

```yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/zone/v3.json
zone:
  name: noisypigeon.com
  prefix: npc
  suffix: noisypigeon
  hosts:
    "@": blog
  services:
    proton:
      enabled: true
      verification:
        pm: <token>
        protonmail: <token>
  dnsRecords:
    <key>: { name, type, content, ... }
  cloudflare:
    apexRedirect: { ... }
```

```yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/workload/v4.json
workload:
  name: blog
  deployments:
    githubPages: {}
  dnsRecords: { ... }
```

- Everything else under the wrapper keeps its LIB-0036 and LIB-0037 meaning
  and path: `zone.cloudflare.apexRedirect` is the old
  `cloudflare.apexRedirect`.
- A file with any top-level key other than its wrapper is refused by name. So
  is a file without its wrapper, from §4's major on.
- A workload's `secrets.workload.yaml` is wrapped the same way, under
  `workload`. Its `cloudflare.dnsRecord` becomes `dnsRecords`, so a secret
  still sits at its entry's path.
- New schemas, `schemas/zone/v3.json` and `schemas/workload/v4.json`, describe
  the wrapped files. Earlier schemas stay published.

### 2. `dnsRecords` replaces `cloudflare.dnsRecord`

`dnsRecords` sits directly under the wrapper, in both files. Each entry is
what a `cloudflare.dnsRecord` entry was: the same `cloudflare/dns-record`
kind, the same inputs and defaults (LIB-0030 §4), and the same leaf,
`cloudflare/dns-record/<key>`. Renaming the key moves no state.

Three things expand into `dnsRecords`:
- a host's Pages records (LIB-0037 §4);
- an `apexRedirect`'s placeholders (LIB-0038 §3);
- §3's service records.

An explicit entry of the same key merges over each expansion, field by
field, as LIB-0038 §3 already does. LIB-0030 §6's checks, one record per name
and type, run over the merged map.

### 3. `services`

`zone.services` names the providers a zone uses. Each is a mapping with
`enabled`, `false` by default; a disabled or absent service implies nothing.
An enabled one implies the `dnsRecords` below, keyed `<service>-<record>`,
each with `ttl: 1` and the comment shown. The services, and their keys:

**`proton`**: Proton Pass custom-domain aliases, at `alias.proton.me`.
Requires `verification.pm` and `verification.protonmail`.

| Key | Name | Type | Content | Comment |
| --- | --- | --- | --- | --- |
| `proton-mx-primary` | `@` | MX, priority 10 | `mx1.alias.proton.me` | proton primary mx |
| `proton-mx-secondary` | `@` | MX, priority 20 | `mx2.alias.proton.me` | proton secondary mx |
| `proton-dkim-primary` | `dkim._domainkey` | CNAME, unproxied | `dkim._domainkey.alias.proton.me` | proton primary dkim |
| `proton-dkim-secondary` | `dkim02._domainkey` | CNAME, unproxied | `dkim02._domainkey.alias.proton.me` | proton secondary dkim |
| `proton-dkim-tertiary` | `dkim03._domainkey` | CNAME, unproxied | `dkim03._domainkey.alias.proton.me` | proton tertiary dkim |
| `proton-spf` | `@` | TXT | `v=spf1 include:alias.proton.me ~all` | proton spf |
| `proton-dmarc` | `_dmarc` | TXT | see `dmarc` below | proton dmarc |
| `proton-pm-verification` | `@` | TXT | `pm-verification=<verification.pm>` | proton pm verification |
| `proton-protonmail-verification` | `@` | TXT | `protonmail-verification=<verification.protonmail>` | proton protonmail verification |

**`fastmail`**: no required inputs.

| Key | Name | Type | Content | Comment |
| --- | --- | --- | --- | --- |
| `fastmail-mx-primary` | `@` | MX, priority 10 | `in1-smtp.messagingengine.com` | fastmail primary mx |
| `fastmail-mx-secondary` | `@` | MX, priority 20 | `in2-smtp.messagingengine.com` | fastmail secondary mx |
| `fastmail-dkim-fm1` | `fm1._domainkey` | CNAME, unproxied | `fm1.<zone>.dkim.fmhosted.com` | fastmail primary dkim |
| `fastmail-dkim-fm2` | `fm2._domainkey` | CNAME, unproxied | `fm2.<zone>.dkim.fmhosted.com` | fastmail secondary dkim |
| `fastmail-dkim-fm3` | `fm3._domainkey` | CNAME, unproxied | `fm3.<zone>.dkim.fmhosted.com` | fastmail tertiary dkim |
| `fastmail-spf` | `@` | TXT | `"v=spf1 include:spf.messagingengine.com ?all"` | fastmail spf |
| `fastmail-dmarc` | `_dmarc` | TXT | see `dmarc` below | fastmail dmarc |

**`googleSearch`**: requires `verification`.

| Key | Name | Type | Content | Comment |
| --- | --- | --- | --- | --- |
| `googlesearch-site-verification` | `@` | TXT | `"google-site-verification=<verification>"` | google search site verification |

**`bluesky`**: requires `did`.

| Key | Name | Type | Content | Comment |
| --- | --- | --- | --- | --- |
| `bluesky-did` | `_atproto` | TXT | `did=<did>` | bluesky domain handle |

- **A mail service's `dmarc`** is `true` by default, which gives
  `v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s`. A string sets the whole
  policy, and `false` implies no DMARC record.
- **Each content is exactly what runway's records hold today,** quoting
  included, so taking a service changes only what §5 says it normalizes. The
  generated key for Google is lowercase, `googlesearch`, as every leaf key is.
- **Refused by name, before planning:**
  - a service other than the four;
  - a key inside a service other than its own;
  - a missing or empty required input on an enabled service;
  - `proton` and `fastmail` both enabled, since both claim MX and SPF at `@`;
  - a `dnsRecords` entry that holds the same name and type as an enabled
    service's record, other than that record's own key. That is LIB-0030
    §6's rule, with the service's records marked as its own, as an
    `apexRedirect`'s are.

The expansion has three copies, which the three twins keep in step (LIB-0038
§4): `resolve-workloads.sh`'s `expand_zone`, root.hcl's `workload_cf_*`
locals, and the zone schema `generate-module-redirects.sh` writes.

### 4. Release impact

The record ships in three releases. LIB-0024 §5 has a spoke take a
workflows change alone, before anything that needs it, so nothing can refuse
a file runway hasn't rewritten yet.

1. **`terragrunt/root-hcl` v7.1.0 and `workflows/v7.1.0`, a minor.**
   - Both twins read a wrapped file and an unwrapped one. A file holding its
     wrapper beside other top-level keys is refused.
   - `services` and `dnsRecords` are read only in a wrapped file.
     `cloudflare.dnsRecord` is read only in an unwrapped one, and refused in a
     wrapped one, naming `dnsRecords`.
   - `generate-module-redirects.sh` adds `zone/v3` and `workload/v4`.
2. **runway moves onto the minor** (§5).
3. **`terragrunt/root-hcl` v8.0.0 and `workflows/v8.0.0`, a major.**
   - Refuses an unwrapped `zone.yaml`, `workload.yaml` or
     `secrets.workload.yaml`, and `cloudflare.dnsRecord` anywhere, each
     naming this record.
   - The unwrapped branches leave both twins.
   - runway takes it pins first, then `root_hcl_version`, and its plan is
     `No changes.`

### 5. runway moves

1. **Pins:** `.lib-version` and every `@workflows/` ref to `workflows/v7.1.0`,
   alone. Once it merges, dispatch `garden-generate.yml`, since the next
   step's files point at schemas only that regeneration publishes (LIB-0038's
   2026-10-26 amendment, item 4).
2. **Move two leaves, with runway frozen.** `proton-proton-spf` becomes
   `proton-spf`, and `google-search-site-verification` becomes
   `googlesearch-site-verification`. Each moves by LIB-0038 §5 and its
   amendment, with nothing recreated:
   - back up the old state;
   - check the new backend is empty;
   - push the state to the new leaf;
   - rewrite its outputs;
   - plan only step 3's in-place update for that leaf;
   - empty the old leaf.
3. **Commit:**
   - `root_hcl_version` 7.1.0 and the regenerated `root.hcl`;
   - every zone and workload file wrapped, its `$schema` line at `zone/v3`
     or `workload/v4`;
   - noisypigeon.com's eleven records give way to `services.proton`,
     `services.googleSearch` and `services.bluesky`;
   - pigeon.dev's six give way to `services.fastmail` with `dmarc: false`,
     since it has no DMARC record today.

   Its plan may show only in-place updates, for these normalizations, and
   creates, destroys or replaces nothing:
   - the comments on `proton-mx-primary`, `proton-mx-secondary`,
     `proton-dkim-tertiary`, `proton-spf`, `proton-dmarc`,
     `proton-pm-verification` and `proton-protonmail-verification`;
   - the comment and ttl on `googlesearch-site-verification`.
4. **Take v8:** pins to `workflows/v8.0.0`, alone, then `root_hcl_version`
   8.0.0. Its plan shows `No changes.`

## Consequences

- **A zone says what it uses.** noisypigeon.com's file names three services,
  in about twelve lines, where it held eleven records in about seventy.
- **A provider's records live in one place.** A fixed comment, or a provider
  that changes its DKIM targets, is a library release, reaching every zone at
  its next plan.
- **Adding a provider is a library change,** to three twins. A zone that needs
  something no service offers declares it in `dnsRecords`, as before, or
  overrides one implied record by its key.
- **Every unit file is rewritten twice in two weeks:** once to wrap it, on the
  minor, and its `$schema` line again if a later schema moves. An editor
  pointed at an old schema flags a wrapped file until its line is updated.
- **A wrapped file names its kind,** so an editor or a reviewer can tell a
  zone's file from a workload's without its path.

## Out of scope

- **Proton Mail, as opposed to Proton Pass aliases,** whose MX is
  `mail.protonmail.ch` and whose DKIM targets differ per domain. Deferred
  ([#197](https://github.com/noisypigeon/library/issues/197)).
- **Turning off one record a service implies,** short of overriding it by key.
  Only DMARC can be turned off. Deferred
  ([#198](https://github.com/noisypigeon/library/issues/198)).
- **`services` in workload.yaml.** A workload that needs a provider's records
  declares them in its own `dnsRecords`. Deferred
  ([#199](https://github.com/noisypigeon/library/issues/199)).
- **Providers beyond the four,** such as Google Workspace mail. Each is a
  library change to §3's table when a zone needs it, not a design question.
- **Building §§1–5.** The template, scripts, schemas and runway's move ship
  in later PRs that cite this record. Deferred
  ([#200](https://github.com/noisypigeon/library/issues/200)).

## Verification

1. **Nothing renders differently.** Under v7.1.0, every leaf of an unwrapped
   copy of runway renders byte-identically to 7.0.0. A wrapped copy with
   services renders each service record as its explicit entry did, apart
   from §5's normalizations.
2. **Each is refused by name, before planning,** in both
   `resolve-workloads.sh` and root.hcl: every case §§1–4 lists.
3. **State moved, not recreated.** Both renamed leaves planned only §5's
   in-place updates before their old leaves were emptied.
4. **runway's move plans only §5's updates,** and after v8 a re-plan of every
   leaf shows `No changes.`
5. **DNS answers as before.** That means MX, SPF, DKIM and DMARC for both mail
   zones, Bluesky's `_atproto` and Google's verification record.

## Amendments

### 2026-10-26: what moving runway found

The library shipped in two releases: `terragrunt/root-hcl/v7.1.0` and
`workflows/v7.1.0` (#202), then `v8.0.0` of both (#203). runway moved under
§5 in four PRs:
- noisypigeon/runway#83 took `workflows/v7.1.0` alone;
- noisypigeon/runway#84 took `root_hcl_version` 7.1.0, wrapped all six files
  and declared both zones' services;
- noisypigeon/runway#85 took `workflows/v8.0.0`;
- noisypigeon/runway#86 took `root_hcl_version` 8.0.0.

The Verification held:

1. **Nothing renders differently.** Under 7.1.0, all 61 leaves of an
   unwrapped copy of runway rendered byte-identically to 7.0.0. The wrapped
   copy's leaf set differed only by §5's two renames. Its renders differed
   only in §5's comments and Google's ttl, with every record's content,
   quoting included, unchanged. Under 8.0.0 the wrapped copy rendered
   byte-identically to 7.1.0.
2. **Each is refused by name, before planning,** in both
   `resolve-workloads.sh` and root.hcl, on a copy of runway. That covers every
   case in §§1–3, and from 8.0.0 an unwrapped zone.yaml, workload.yaml and
   secrets.workload.yaml.
3. **State moved, not recreated.** Both new keys were empty before the push.
   After it, `proton-spf` planned only its comment and
   `googlesearch-site-verification` its comment and ttl, both in place, with
   their outputs unchanged. Then the old leaves were emptied, their outputs
   included.
4. **runway's move planned only §5's updates.** runway#84 changed eight
   noisypigeon.com records in place: seven comments, and Google's comment and
   ttl. 81 leaves had no changes, nothing was created, destroyed or replaced,
   and pigeon.dev's six records were unchanged. After v8, runway#86's plan
   shows `No changes.` on all 87 leaves, with none failed.
5. **DNS answers as before.** After the apply, both mail zones' MX, SPF and
   DKIM, noisypigeon.com's DMARC, Bluesky's `_atproto` and Google's
   verification each answer with the same content as before. pigeon.dev
   still serves no DMARC.

Building it changed one rule in §3. The refusal of "a `dnsRecords` entry
that holds the same name and type as an enabled service's record" would
have refused a zone's own TXT at `@`, beside its verification records. What
shipped is LIB-0030 §6's clash rule unchanged, plus one per-name rule: a
name holds at most one `v=spf1` TXT and one `v=DMARC1` TXT, whoever declares
them. So a second SPF or DMARC policy is refused, and any other extra record
beside a service's is allowed. A `dmarc` string must begin `v=DMARC1` in
both twins and the schema.

Moving it confirmed LIB-0038's 2026-10-26 amendment. The two old leaves
kept their outputs after `state rm` and were cleared the same way. garden
needed a dispatch of `garden-generate.yml` after runway#83 merged before
`schemas/zone/v3.json` and `schemas/workload/v4.json` resolved. The move
needed no output rewrite, because a `dns-record` leaf has no dependents.
