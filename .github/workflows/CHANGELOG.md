# Changelog

All notable changes to the reusable CI are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [9.0.2] - 2026-10-28

### Leave earlier stages' destroys out of a staged replan or apply comment

A staged plan applies a removed workload leaf's outputs-only destroy with its first stage (LIB-0042 §2). Every later stage, the automatic replan and its apply, still read the PR's destroys from \`destroy-units.txt\`, but never ran them, so the PR comment listed each one as \`destroy (removed from its unit file) no result found\` and counted it under "failed to plan" or "failed to apply". The runs themselves succeeded and the infrastructure was right; only the report was wrong. Since those rows weren't "unchanged", a last replan with nothing left to apply also couldn't count as settled, so it didn't merge by itself. LIB-0044's results amendment describes the case.

\`render-run-comments.js\`'s \`render()\` now takes a \`stage\` input, the units the stage planned or applied. When it's set, destroys outside the stage are left out of the summary, the detail comments and the counts. \`terragrunt-run.yml\` passes the same stage file its run step reads: the replan's \`stage.txt\` for a plan, the saved plan's for an apply. A run that isn't a stage still reports a destroy with no result as a failure, as before.

\`render-run-comments.test.js\` covers a stage plan and a stage apply, using the new fixtures \`plan-stage-after-destroy.txt\` and \`apply-stage-after-destroy.txt\`, as well as a last stage that settles and the case with no stage.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#229](https://github.com/noisypigeon/library/pull/229)

## [9.0.1] - 2026-10-28

### Honour apexRedirect include_www: false in the resolver's clash check

`resolve-workloads.sh` now honours `cloudflare.apexRedirect.<key>.include_www: false` in its record clash check (LIB-0030 §6). Before, the check read the flag with jq's `// true`, which turns `false` into `true`. As a result, a zone that turned the `www` placeholder off and declared its own `www` record was refused, with "the apexRedirect … already holds a placeholder CNAME record at www". That happened even though no such placeholder is generated, and root.hcl would have planned the zone fine. The list of an apexRedirect's own implied records got the same fix, so `<key>-www` only counts as the redirect's own when `include_www` isn't `false`.

The stubs themselves were already right: with `include_www: false` there is still no `<key>-www` leaf. When the flag is `true` or unset, a `www` record beside the redirect is still refused.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#228](https://github.com/noisypigeon/library/pull/228)

## [9.0.0] - 2026-10-28

### Scaleway compute kinds in resolve-workloads.sh, and workload schema v5

`resolve-workloads.sh` now generates the stubs for LIB-0043's Scaleway compute kinds, and checks the rules that keep them consistent before anything plans. A workload can describe instances, their network, volumes, Cockpit and credentials in its `workload.yaml`, with each Scaleway resource in a leaf and a state of its own.

**Breaking:** `scaleway.iam.apiKey` is now a mapping of key names, like `backblaze.apiKey`, and each key is its own leaf at `scaleway/iam-api-key/<key>`. A file that still declares one key's inputs directly under `scaleway.iam.apiKey` is refused, with a message telling you to move them under a name, for example `scaleway.iam.apiKey.main`. Pin `terragrunt/root-hcl` v9.0.0 alongside this release, because its `workload_kinds` is this script's twin.

New kinds, each one leaf per entry:

- `scaleway.iam.policy.<key>`: a policy on the workload's one application. `application_id` and `project_ids` are wired from the workload.
- `scaleway.blockVolume.<key>`, `scaleway.cockpit` and `scaleway.privateNetwork`: the project is wired.
- `scaleway.publicGateway`: the gateway, attached to the private network.
- `scaleway.instance.<key>`: a `compute-instance` and the `compute-instance-config` that renders its cloud-init. It takes:
  - `network.privateNetwork`, `network.publicIpv4` and `network.sshViaGateway`;
  - `volumes`, `cockpit`, `transcoding` and `selfDelete`;
  - `commands` and `keyring`, plus `scaleway.sharedKeyring` merged underneath.
  - `selfDelete: true` implies the instance's own IAM application, policy (`InstancesFullAccess`) and key, at `self-delete-<key>`, so the workload's own keys never carry that grant.
  - `sshViaGateway` implies a `gateway-pat-rule`.
  - A keyring bucket entry that names a `scaleway.bucket` key, or an `apiKey`, gets its name and credentials wired from those leaves through `keyring_wiring`.

`privateNetwork` and `publicGateway` each take `enabled: false`. That removes the leaf and keeps the settings in the file. With the gateway off or absent, every instance must say `network.publicIpv4: true` itself. A default doesn't count, so turning the gateway off fails until each instance is edited on purpose (E2).

The script refuses LIB-0043's rules, each with a message citing its section:

- E1: an instance with no way out.
- E3: a gateway without the private network.
- E5: `sshViaGateway` off the network, or a port two instances share.
- E6: an instance on a network that's off.
- I1: a policy or key with no `iam.application`.
- I2: a reserved or wired name.
- S1: more than one volume on an instance, a volume shared by two instances, or an unknown volume key.
- Keyring entries missing their fields or credentials, or whose `secretRef` isn't in `secrets.workload.yaml`.
- M1: `transcoding` on an arm64 type.
- M2: `cockpit` without `scaleway.cockpit`.
- M3: an instance name that isn't kebab-case or runs past 40 characters.
- A `${keyring.<alias>.alias}` in `commands` naming an alias the instance doesn't have.

A policy granting `InstancesFullAccess` is a warning, not an error (I5).

`generate-module-redirects.sh` publishes inputs schemas for the seven new kinds' modules and `schemas/workload/v5.json`. That schema adds:

- the new kinds, with `iam.policy` and `iam.apiKey` as mappings;
- a keyring entry schema;
- E2 and E3 as `if`/`then`, so an editor flags them.

It also accepts `deployments.scaleway.project`'s `prefix` and `suffix` (LIB-0037 §2), which v2 to v4 wrongly refuse. v1 to v4 are published unchanged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#225](https://github.com/noisypigeon/library/pull/225)

## [8.2.0] - 2026-10-28

### Plan workload leaves in waves, and replan only the stage left

`terragrunt-run.yml` now plans a spoke's workload leaves in parallel waves rather than one at a time. A staged apply's replan now plans only what that apply left deferred, and every run shares a provider cache (LIB-0042).

**Workload leaves plan in waves (LIB-0042 §1).** A wave is every selected unit whose workload dependencies have all settled. Each wave is planned by one parallel `terragrunt run --all`, so there is one invocation per DAG level instead of one per leaf. On runway that is about 6 invocations instead of about 72.

Deferral keeps LIB-0024 §3's rule: a unit is deferred if any of its workload dependencies changed or is deferred. Whether a unit changed is now read from its JSON plan, by the same count the PR comment uses, rather than from `-detailed-exitcode`. The `=== <unit>: deferred until … is applied ===` lines and the comment are unchanged. The new `plan-waves.js` picks each wave and classifies its units; its tests run in `scripts-test.yml`.

**A replan plans only the stage that's left (LIB-0042 §2).** The plan archive now records the units a plan deferred. When a staged apply's replan finds that record, and the PR still selects what was planned, it plans only those units. Its hand-written leaves and destroys were all applied with the earlier stage, so they aren't planned again.

The archive also marks a plan as one stage. That stage's apply skips the hand-written leaves and destroys, and reports only the stage's own units as deferred.

A `terragrunt plan` comment still plans everything. So does a replan of an archive from before this version.

**A shared provider cache (LIB-0042 §3).** The run step sets `TG_PROVIDER_CACHE=1`, and `actions/cache` keeps the cache directory between runs, keyed on `root.hcl`. Parallel inits need this cache to be safe, and it saves the provider download on each one. It holds provider packages only: `.terragrunt-cache`, whose generated files can hold decrypted values, is still cleared and never cached.

**One tag list per run (LIB-0042 §4).** "Select units" lists the library's `terraform/*` tags once and exports the list as `LIB_TAG_LIST`. From root.hcl v8.2.0, a workload leaf reads its module's version from that list, instead of running `git ls-remote` on every parse. An older root.hcl ignores it.

**Taking it.** A spoke bumps its callers to `workflows/v8.2.0`, and its `root.hcl` to v8.2.0 for the tag list. `plan-archive.sh pack` takes optional extra files, which is backward compatible.

**Checked locally** by running the step's own script on a terragrunt tree with a 9-link chain and a diamond:
- With no changes, waves plan the same units as the serial loop.
- With two units changed, waves defer the same seven units, with the same lines.
- A stage replan planned only those seven units, and its apply applied only them.
- A second init with the provider cache took 0.6s, against 1.8s for the first.

LIB-0042 is now Accepted.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#216](https://github.com/noisypigeon/library/pull/216)

## [8.1.0] - 2026-10-28

### A workload's own Backblaze key, and providers with no spoke-wide credentials

A workload with Backblaze buckets or keys now gets its own Backblaze key, and a spoke can keep no spoke-wide Backblaze key or Cloudflare token at all (LIB-0041).

**A workload's own Backblaze key.** Any workload that declares a `backblaze.bucket` or `backblaze.apiKey` gets an implicit leaf, `backblaze/api-key/deployer`, the Backblaze twin of its Cloudflare token.
- It's minted with the spoke's Backblaze breakglass key where the spoke has one, and with `backblaze.enc`'s key otherwise.
- It's account-wide, since B2 can't confine a key to buckets that don't exist yet.
- It rotates every 30 days, and each key expires a week after its rotation.
- It's named `<prefix>-<suffix><unit tag>-backblaze-deployer`. `backblaze.deployer` overrides any of its inputs, and `backblaze.apiKey.deployer` is reserved.

**The workload's Backblaze leaves sign in with it.** Each `backblaze/bucket` and `backblaze/api-key` stub now depends on the key and passes its ID and secret to `provider "b2"`. Taking the bump plans `+1` per such workload. Its Backblaze leaves are deferred until the key applies, then plan `No changes.`, since only their provider's credentials change.

**`workloads_only`.** A Cloudflare or Backblaze entry in `spoke.hcl`'s `providers` may set `workloads_only = true` with `breakglass = {}`.
- No hand-written leaf turns the provider on.
- `backblaze.enc`, and `cloudflare.enc`'s `CLOUDFLARE_PROVIDER_TOKEN`, are no longer required. Any that remain are refused.
- The breakglass key mints every unit's own key or token.

The secrets schema expresses this as a new condition, `spoke_credentials.<name>`. Both root.hcl and `check-secrets.sh` enforce it. root.hcl now checks a file's keys against the spoke-wide conditions, as `check-secrets.sh` does, so a leaf that reads `cloudflare.enc` only for the R2 backend no longer flags a key another leaf needs. A spoke that doesn't set `workloads_only` needs no changes.

**`terraform/backblaze/api-key`** gains `rotation_days`. It replaces the key create-before-destroy on that schedule, and each key expires a week later. It overrides `valid_duration_in_seconds`, and it defaults to null, so existing callers keep their fixed expiry. Each existing caller does plan one new `terraform_data.rotation` resource on upgrade, as `cloudflare/api-token` did.

**The published workload schema** gains `backblaze.deployer`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#208](https://github.com/noisypigeon/library/pull/208)

## [8.0.1] - 2026-10-27

### A workload in its own project doesn't repeat its name in its resources

A workload in a project of its own no longer carries its name in its implicit resources' names. LIB-0037 §2's name tag keeps sibling workloads apart in their zone's project. A private workload, or a zoned one that sets its own project, has no siblings there, and its project's suffix already names it, so the tag only repeated it: `workloads/private/cold-storage/` with suffix `cold-storage` named its deployer `wg-cold-storage-cold-storage-deployer`. Such a workload now gets `<prefix>-<suffix>-deployer` and a state bucket ending in `-terraform-state`, as a top-level workload does.

Both twins change: root.hcl's `workload_name_tag` and `resolve-workloads.sh`'s `tag`. A workload in its zone's project keeps its tag, so its names don't change. A spoke with an existing workload in its own project sees its deployer's IAM application and policy renamed in place; its existing state bucket would be replaced, so pin that bucket's name under `scaleway.state` before taking the bump. LIB-0040's 2026-10-27 amendment records the rule.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#206](https://github.com/noisypigeon/library/pull/206)

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

## [5.4.0] - 2026-10-24

### Announce a staged apply's next-stage plan as it starts

After a staged apply leaves leaves deferred, the automatic re-plan of the next stage (LIB-0027) now says so on the PR as soon as it starts. Until now nothing appeared for the 5–10 minutes it took to plan.

Its first step after resolving the head posts this:

> ### ⏳ Terragrunt plan
> _The previous stage's apply left leaves deferred, so the next stage of `<sha>` is planning now. Its plan replaces this comment._ [Run](…)

The announcement carries the plan comments' marker. So when the re-plan's result posts, the result step hides it as outdated, along with every earlier plan comment, whether the re-plan succeeded, failed or was cancelled. The PR keeps one live plan comment.

Only a re-plan started by a `terragrunt apply` comment posts it. A `terragrunt plan` comment already gets its 👀, and a push plan has no stage before it. A spoke needs no change beyond the `@workflows/` bump, since its replan job already calls `terragrunt-run.yml`.

LIB-0027 has a 2026-10-25 amendment recording this.

Linted with actionlint. The step's script ran against a stub, and the body above is its output. A comment-triggered run uses the default branch's workflow files, so a spoke sees this only once the bump is on its `main`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#180](https://github.com/noisypigeon/library/pull/180)

## [5.3.0] - 2026-10-24

### Acknowledge a terragrunt comment at once, outside the PR's queue

A `terragrunt apply` or `terragrunt plan` comment can now get its 👀 right away, even while another plan or apply is running on the same PR.

The 👀 used to come only from `terragrunt-run.yml`'s first step, and that job doesn't start until it holds the PR's concurrency group, `terragrunt-pr-<n>`, which a spoke's plan, apply and re-plan jobs share. A comment made while one of them was running got its 👀 only when that run finished. On noisypigeon/runway#70, two apply comments made during a plan and during a staged apply's re-plan waited 7½ and 3½ minutes. The workflow hadn't changed; the staged bootstrap's automatic re-plans just made it common.

The new reusable `terragrunt-ack.yml` only reacts 👀 to the triggering comment. To use it, a spoke adds one job per comment-triggered run job. That job gets the same `if` as the run job and no `concurrency`:

```yaml
  ack:
    if: <the apply or plan job's comment gate>
    uses: noisypigeon/library/.github/workflows/terragrunt-ack.yml@workflows/v5.3.0
```

A re-plan job has no comment of its own, so it needs no ack. `terragrunt-run.yml` still reacts 👀 itself, so a spoke that doesn't add the job behaves exactly as before. GitHub keeps one reaction per user and content, so a spoke that adds it isn't reacted to twice. The 👍 or 👎 still comes when the run ends, and plans and applies still queue as before.

LIB-0022 has a 2026-10-25 amendment recording this.

Linted with actionlint. A comment event always runs the default branch's workflow files, so this can't be exercised from a branch. It gets tested in runway once a spoke calls it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#179](https://github.com/noisypigeon/library/pull/179)

## [5.2.2] - 2026-10-24

### Auto-merge only after an apply that ran and succeeded

`terragrunt-run.yml` could merge a PR whose apply never ran. Its Auto-merge step checked `steps.run.outputs.exit_code == '0'`. When the apply step is skipped, that output is null, and an Actions expression's loose equality treats `null == '0'` as true. So an apply that was refused, because there was no saved plan for the head or its selected units differed from the plan's, merged the PR anyway with `BOT_GITHUB_TOKEN`. Only after that did the job fail. noisypigeon/runway#69 merged this way, with nothing applied.

Auto-merge now also requires `steps.run.outcome == 'success'`, so it merges only after an apply that ran and succeeded with nothing deferred. The plan's "Pack saved plan" and "Upload saved plan" steps get the same guard on their `exit_code` check. No other step compares a step output to `'0'`. The `== 'true'` and `!= ''` checks elsewhere already behave as intended when an output is null.

Tested on GitHub with a throwaway workflow on a scratch branch, since deleted. With the apply step skipped, the old condition merged and the new one doesn't. Both merge after a successful run, and neither merges after a failed or deferred one.

A spoke takes this by bumping its `@workflows/` refs. The apply side only gets the fix once the bump is on the spoke's `main`, because a `terragrunt apply` comment runs the workflow file from `main`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#178](https://github.com/noisypigeon/library/pull/178)

## [5.2.1] - 2026-10-24

### Fix resolve-workloads.sh --list failing in a spoke without zones

Since `workflows/v5.2.0`, `resolve-workloads.sh --list` printed the right stubs but then exited 1 in any tree with a `workloads/` directory and no `zones/` directory. It listed both roots with one `find`, which fails on a root that doesn't exist, and the script runs under `pipefail`.

`terragrunt-run.yml`'s "Select units" runs `--list` at the PR's base too. So a spoke's plan failed, with no error message, whenever either side of the PR had no zone units. That includes a spoke's first PR that adds them, since its base has none yet. The fix lists only the roots that exist, the way the script's stub cleanup already did.

Checked by exit code, for every mode (write, `--list` and `--check`), on a spoke with workloads only, one with workloads and zones, and one with zones only. I also replayed "Select units" on runway's zone bootstrap branch against its `main`: both lists succeed, and it plans no destroys.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#177](https://github.com/noisypigeon/library/pull/177)

## [5.2.0] - 2026-10-24

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

## [5.1.1] - 2026-10-24

### A release regenerates noisypigeon.garden in runway (LIB-0035)

A library release no longer dispatches `garden-pages.yml` in `noisypigeon/garden`. That workflow is gone, because the repo is now the `noisypigeon/noisypigeon.garden` Pages shim. Instead, every release dispatches `garden-generate.yml` in `noisypigeon/runway` (LIB-0035 §4).

That workflow regenerates noisypigeon.garden's module redirect pages, overview pages, theme-version pages, release posts and schemas. It commits them under runway's `workloads/garden/`, and that commit deploys itself through runway's `sites.yml` and the shim. A release that changes no page commits nothing and deploys nothing.

- **The dispatch now runs on every release,** under the same condition as the tagging step. Before, it ran only for module and theme releases. LIB-0035 §4 asks for every release, and generating with nothing to change is a no-op.
- **The noisypigeon.com dispatch doesn't change:** a theme release still rebuilds the blog's shim.
- **It still needs `BOT_GITHUB_TOKEN`,** now with `actions: write` on `noisypigeon/runway`, and it still fails loudly without it.
- **`generate-module-redirects.sh`'s header, `CLAUDE.md`, `README.md`, the `release-pr` skill and the theme README** now say that the generator runs in a spoke's generation, that runway is the one spoke, and that noisypigeon.com and noisypigeon.garden are shims.

This is LIB-0035's step 8. Its merge ends the freeze on library releases that the cutover needed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#173](https://github.com/noisypigeon/library/pull/173)

## [5.1.0] - 2026-10-24

### Reusable site-generate.yml and site-pages.yml (LIB-0035)

Two new reusable workflows for site workloads ([LIB-0035](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0035-move-garden-into-runway.md) §§2–3). Existing callers don't change.

- **`site-generate.yml`** regenerates a site workload's generated files and commits them to the caller's `main`.
  - Inputs: `src_dir` and `generate_cmd`.
  - It fetches the library at the caller's pin with every tag, installs terraform-docs, and runs the command.
  - It commits only what changed under `src_dir`. If nothing changed, it makes no commit and so triggers no deploy.
  - It pushes with `BOT_GITHUB_TOKEN`, so the push starts the caller's `sites.yml` and the site's shim deploys it.
  - The caller holds the `main-writer` concurrency group, as `blog-changelog.yml`'s caller does.
- **`site-pages.yml`** is a Pages shim's whole deploy.
  - Inputs: `spoke` and `workload`.
  - It builds `<spoke>/workloads/<workload>` at the spoke's `main` through `zola-site-pages.yml`, with the standard fetch and theme scripts and the commit stamp.
  - A shim's `pages.yml` then names only those two inputs, and must grant `pages: write` and `id-token: write`.
  - This closes #164 once both shims use it.

garden's move into runway comes next: its generation runs through `site-generate.yml`, and its shim through `site-pages.yml`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#172](https://github.com/noisypigeon/library/pull/172)

## [5.0.1] - 2026-10-24

### A theme release dispatches pages.yml in noisypigeon/noisypigeon.com (LIB-0034)

The blog's Pages shim is now `noisypigeon/noisypigeon.com`, renamed from `noisypigeon/blog`, and its deploy workflow is `pages.yml` ([LIB-0034](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0034-site-workloads-declare-their-pages-shim.md) §§4, 6). A `zola-site` release now dispatches it there by that name, rather than relying on GitHub's rename redirect (as COM-0007 had it).

`CLAUDE.md`, `README.md` and the `release-pr` skill name the renamed shim too.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#169](https://github.com/noisypigeon/library/pull/169)

## [5.0.0] - 2026-10-24

### Read each site's Pages shim from values.yaml and write the blog changelog one line per PR

Implements the workflow half of [LIB-0034](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0034-site-workloads-declare-their-pages-shim.md) (§3 and §5).

**`site-dispatch.yml` can find the sites itself.** `site_repo` and `workflow` are now optional. A caller that still passes them dispatches exactly as before. A caller that passes neither names no workload: on a push, the workflow diffs the push and keeps every `workloads/<w>/` that has a change outside `values.yaml` and `secrets.yaml` and holds a `config.toml`. On `workflow_dispatch`, or a push with no usable `before` (a new branch or a force-push), it takes every site workload. For each one it reads `features.githubPages.pagesShim` from the workload's `values.yaml` and dispatches `pages.yml` on `main` in that shim. A site with no `pagesShim` fails the run, citing LIB-0034 §1, once the other sites have been dispatched. A failed dispatch fails it too, with the same `BOT_GITHUB_TOKEN` error as before. A push that changes no site logs that and succeeds. So one spoke caller covers every site, and a second site needs no new workflow.

**`blog-changelog.yml` writes the blog's `CHANGELOG.md` one line per PR.** Each merged PR now adds `- [blog] <title> ([#N](<url>))` under its `## YYYY-MM-DD` heading, newest first, the same format as every root changelog. It no longer adds a heading, the PR body and a link. The line is written by `root-changelog.sh`, which the workflow fetches with the caller's `fetch-lib.sh`, as `spoke-root-changelog.yml` already does. There are three new inputs: `changelog_tag` (default `blog`), `fetch_script` (default `fetch-lib.sh`) and `changelog_script` (default `.lib-src/.github/scripts/root-changelog.sh`). The optional root rollup and the daily digest post are unchanged. When there is no blog changelog yet, the script creates one with the marker.

**Breaking:** `root-changelog.sh` places the line below the `<!-- entries below; newest first -->` marker and refuses a file that lacks it. A caller whose blog `CHANGELOG.md` is still in the old Keep-a-Changelog shape must convert it, marker included, in the same change that takes this version. The caller also needs a `fetch-lib.sh` at its root, or must pass `fetch_script`.

`root-changelog.sh` drops its note that `blog-changelog.yml` can't use it, which is no longer true. A changelog it creates now opens with "One line per PR, sectioned by date, newest first.", since it no longer always covers a whole repo.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#167](https://github.com/noisypigeon/library/pull/167)

## [4.14.0] - 2026-10-24

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

## [4.13.1] - 2026-10-23

### resolve-workloads.sh --check accepts a Cloudflare stub's workload token

Fixes a bug from LIB-0033's build (#159), found in LIB-0032's import preflight (#149).

A Cloudflare workload stub passes its workload token, `cloudflare_api_token`, to root.hcl, which signs the provider in with it, as a Scaleway stub passes its deployer key. `--check` skipped only the Scaleway names when checking that a stub's wiring exists at the module's version. So every Cloudflare entry failed with "has no input(s) cloudflare_api_token … pin a newer version", and with it any spoke's plan.

`--check` now skips `cloudflare_api_token` too. A real missing input is still caught: a `cloudflare.ruleset` pinned to `0.1` still fails for `zone`. Against the blog workload's 21 transcribed entries, it now passes all 22 of its Cloudflare stubs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#162](https://github.com/noisypigeon/library/pull/162)

## [4.13.0] - 2026-10-23

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

## [4.12.0] - 2026-10-23

### Site workloads deploy through a Pages shim repo (LIB-0031)

Builds [LIB-0031](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0031-site-workloads-and-pages-shim-repos.md) (#148): a spoke workload can carry a Zola site, deployed by a shim repo that holds only a README and its Pages deploy workflow.

- **`zola-site-pages.yml`** gains `repository` and `ref`. A shim repo passes the spoke and `main`, and `src_dir: workloads/<w>`, to build the spoke's site and deploy it to its own Pages domain. Both default to empty, so existing callers build their own repo as before.
- **`site-dispatch.yml`** (new, reusable) is called by the spoke when its site changes. It dispatches the shim's deploy workflow with `BOT_GITHUB_TOKEN`, which needs `actions: write` on the shim, and fails loudly if it can't.
- **`blog-changelog.yml`** gains `deploy_repo`, so a site's daily changelog digest dispatches the shim instead of the caller. Empty keeps today's behaviour.
- **`terragrunt-detect.yml`**'s default pattern narrows `^workloads/` to a workload's `values.yaml` and `secrets.yaml`, so a post doesn't start a plan. A caller that overrides `leaf_pattern`, as runway does, narrows its own.

LIB-0031 gains an amendment recording `site-dispatch.yml` and the override.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#153](https://github.com/noisypigeon/library/pull/153)

## [4.11.0] - 2026-10-23

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

## [4.10.1] - 2026-10-22

### Comment-triggered runs check out the PR's head commit from the API

Fixes a `terragrunt apply` that fails at checkout, before anything runs. Every spoke's apply caller passed `checkout_ref: refs/pull/<n>/head`, and GitHub sometimes never creates that ref. On [runway#56](https://github.com/noisypigeon/runway/pull/56) it was missing while `refs/pull/56/merge` existed, and the apply only worked after a new push made GitHub write it.

- **`terragrunt-run.yml`:** on `issue_comment` with no `checkout_ref`, a new first step reads the PR's `head.sha` from the API and checks that commit out. `pull_request` runs still use the event's own SHA, and an explicit `checkout_ref` still wins.
- **Callers:** a spoke's `terragrunt-apply.yml` should drop its two `checkout_ref: refs/pull/${{ github.event.issue.number }}/head` lines, on `apply` and `replan`. Until it does, it keeps the old behaviour. `terragrunt plan` comments never set `checkout_ref`, so they get the lookup with no caller change.
- **Saved plans are bound as before.** Apply downloads the plan artifact for the commit it checked out, so a push between plan and apply still refuses (LIB-0022 §3).

LIB-0022 gains an amendment recording it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#146](https://github.com/noisypigeon/library/pull/146)

## [4.10.0] - 2026-10-22

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

## [4.9.1] - 2026-10-22

### A workload's state bucket uses the standard storage class (LIB-0028)

Fixes a default in LIB-0028's workload state bucket. It took `scaleway/bucket`'s default `storage_class`, `glacier`, whose lifecycle rule moves every object to `GLACIER` after 90 days. A workload leaf whose state went unwritten that long would then fail at `init`: state in `GLACIER` can't be read without a restore.

- **`terragrunt/root-hcl`:** `scaleway.state` now defaults to `storage_class: standard`, and refuses `glacier`. For a state bucket created on v5.0.0, the next plan is an in-place change that removes the lifecycle rule. Nothing is replaced.
- **`workflows/`:** `resolve-workloads.sh` refuses `scaleway.state.storage_class: glacier` before any plan runs.

LIB-0028 gains an amendment recording it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#143](https://github.com/noisypigeon/library/pull/143)

## [4.9.0] - 2026-10-22

### Every workload gets its own project, deployer and state bucket (LIB-0028)

Implements the stub and schema half of [LIB-0028](https://github.com/noisypigeon/library/blob/main/docs/adr/LIB-0028-workload-projects-and-state-buckets.md) (#139). It needs `terragrunt/root-hcl` v5.0.0, which ships next: take this release first and alone, as LIB-0024 §5 asks, and plan no workload until the template follows.

**`resolve-workloads.sh`** now generates three stubs for every `workloads/<workload>/values.yaml`, whatever it declares:
- `scaleway/project/main`;
- `scaleway/terraform-deployer-iam/main`;
- a new `scaleway/bucket/state`, the workload's versioned state bucket.

`scaleway.project`, `scaleway.deployer` and the new `scaleway.state` only override their module's inputs, so a file with just `prefix` and `suffix` is a complete workload.

- **A leaf whose state lives in the workload's bucket** (the IAM application, the API key and every `scaleway.bucket` entry) depends on the state bucket and the deployer. Its stub declares its own `remote_state`: the bucket comes from the state stub's outputs, and it signs in with the deployer's key.
- **`--check` and generation refuse four things:**
  - a `scaleway.bucket.state` entry;
  - a `scaleway.state.prefix` that starts with `/` or doesn't end with one;
  - `scaleway.state.enable_versioning: false`;
  - a `scaleway.deployer.project_permission_sets` without `ObjectStorageFullAccess`.
- **`secrets.yaml`** may now set inputs for the project, deployer and state bucket without a `values.yaml` entry for them.

**`generate-module-redirects.sh`** publishes a `state.schema.json` beside every `scaleway/bucket` version's `inputs.schema.json`: the bucket's inputs plus `prefix`. The workload schema gains `scaleway.state` and rejects the bucket key `state`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#141](https://github.com/noisypigeon/library/pull/141)

## [4.8.0] - 2026-10-22

### Merge a settled automatic re-plan without a last apply (LIB-0027)

When the `replan` job's automatic plan finds nothing left to apply, the PR now closes itself, without one more `terragrunt apply` (LIB-0027's amendment). On runway#48, that last apply did nothing.

- **A plan settles** when the run succeeded and every leaf is unchanged, with nothing deferred, failed or without a result. Such a plan sets `terragrunt/apply` to `success` and merges with `BOT_GITHUB_TOKEN`, as a final apply does. Its summary ends "Nothing left to apply: merging."
- **Only the replan job's plan qualifies,** since its run was started by a person's `terragrunt apply`. A plan from a push or a `terragrunt plan` comment never merges by itself.
- **Output changes now count as changes,** read from the JSON plan's `output_changes`, so an output-only plan, which an apply would still write to state, never settles.

Callers change nothing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#136](https://github.com/noisypigeon/library/pull/136)

## [4.7.1] - 2026-10-22

### Fix the apply's merge-gate step crashing on getOctokit

`workflows/v4.7.0`'s merge-gate step called `getOctokit`, which `actions/github-script@v7` doesn't provide. Every apply therefore failed at that step, after applying, with `ReferenceError: getOctokit is not defined`. The gate status was never set, and a caller's `replan` job, which needs a successful apply, was skipped. noisypigeon/runway#48 hit it.

The step is now two:
- **Set merge-gate status**, with `GITHUB_TOKEN`, as before v4.7.0.
- **Auto-merge**, which runs only after a successful, final apply. It uses `github-script`'s supported `github-token` input, set to `BOT_GITHUB_TOKEN` when the caller has it, else `GITHUB_TOKEN`.

Callers change nothing; take it by moving to this version.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#134](https://github.com/noisypigeon/library/pull/134)

## [4.7.0] - 2026-10-22

### Re-plan staged applies automatically, and merge with the bot token (LIB-0027)

Two changes to `terragrunt-run.yml` (LIB-0027).

- **It reports what a run did.** `workflow_call` gains the outputs `deferred` (`'true'` when an apply left workload leaves deferred) and `exit_code`. A spoke's apply caller can then run a `replan` job, which plans the next stage without a `terragrunt plan` comment. That plan's summary says it was planned automatically. Each stage still needs its own `terragrunt apply`.
- **The final apply merges with `BOT_GITHUB_TOKEN`** when the caller has it (it's an optional secret here; `secrets: inherit` passes it). This fixes the auto-merge that failed on every runway PR with "Resource not accessible by integration". A bot-token merge also starts the workflows that follow a merge, such as the root changelog, which a `GITHUB_TOKEN` merge would not. If the merge fails, the comment names the token and the access it needs.

To take it, a spoke moves to this version and adds a `replan` job to its `terragrunt-apply.yml`. Without that job, a staged apply asks for a `terragrunt plan` comment, as before. Selection is unchanged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#133](https://github.com/noisypigeon/library/pull/133)

## [4.6.0] - 2026-10-22

### Count unchanged leaves instead of listing them in Terragrunt comments

Terragrunt plan and apply comments no longer show leaves with no changes (LIB-0026's 2026-10-22 amendment).

- **The summary opens with a count:** `<sha>: 1 with changes, 26 with no changes, 0 failed to plan` (or `failed to apply`). `, N deferred` is added only when there is one.
- **The table and the detail comments list only leaves that change, fail or are deferred.** The collapsed table of unchanged leaves and their `No changes` sections are gone.
- **A run with nothing to change posts its summary alone,** saying `_Nothing changes._`.
- **Terragrunt's own output (the Run section) appears only when something failed.**

Proved on noisypigeon/runway#46, a plan-only draft pinned to this branch: one changed leaf among 27 showed as one row and one section, and a run with no changes posted only its summary.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#129](https://github.com/noisypigeon/library/pull/129)

## [4.5.0] - 2026-10-22

### Segment Terragrunt plan and apply comments by leaf, never truncated (LIB-0026)

`terragrunt-run.yml` now reports a plan or an apply as a summary comment, then detail comments, and never truncates (LIB-0026).

- **The summary** has one row per leaf: `No changes`, `+a ~c -d`, `destroy (removed from values.yaml)`, `deferred until …`, `applied` or `failed`, with a link to the leaf's section. Changes and failures come first. Unchanged leaves are folded into a collapsed table.
- **Detail comments** hold one collapsible section per leaf: that leaf's Terraform output, without Terragrunt's init narration. Terragrunt's own summary goes in a closing Run section.
- **Nothing is truncated.** Sections are packed into comments of up to 60,000 characters, and a leaf too large for one comment is split across several, with balanced code fences. The old 55,000-character tail cut is gone.
- **Counts come from Terraform's JSON plans,** written with `--json-out-dir`, and fall back to the plan's own summary line.
- **Masked values are replaced with `***`** in comments too, since comments are built from a file GitHub never masks.
- **A new run minimizes every comment of the previous one.**

Rendering lives in a tested library script, `.github/scripts/render-run-comments.js`, with `node --test` tests and fixtures from runway's runs. A new `scripts-test.yml` runs them on this repo's pull requests. Callers change nothing, and unit selection is unchanged, so a spoke takes this in one PR.

Proved on noisypigeon/runway#44, a plan-only draft pinned to this branch.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#127](https://github.com/noisypigeon/library/pull/127)

## [4.4.0] - 2026-10-21

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

## [4.3.0] - 2026-10-20

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

## [4.2.0] - 2026-10-20

### Generate workload stubs in CI and plan removals as destroys (LIB-0023)

A workload now commits only its `workloads/<workload>/values.yaml`. Its stub leaves are generated wherever Terragrunt runs, and are never committed (LIB-0023's second amendment).

- **`terragrunt-run.yml` generates the stubs itself**, so callers change nothing.
  - In a spoke with a `workloads/`, the `[main...HEAD]` git filter excludes `./workloads/**`, so deleting a committed stub, as a spoke does once to adopt this, never plans its destroy.
  - Workload leaves are planned in a Terragrunt invocation of their own: every stub of a workload whose `values.yaml` changed, or of every workload when `root.hcl`, `spoke.hcl` or a secret changed.
- **Removing an instance from `values.yaml` plans its destroy.** CI generates the PR base's stubs in a worktree and plans `-destroy` for each one HEAD no longer has. Those plans are saved with the rest, and apply runs them one at a time, dependents first. The saved plan's `units.txt` names the base and each destroy, so apply can't run against different ones.
- **`resolve-workloads.sh`** gains `--list`, which prints the stub set. `--check` now validates `values.yaml` only, and fails if a stub is tracked by git.

To adopt it, a spoke with committed stubs runs `git rm --cached` on them and gitignores `/workloads/*/*/`, in the same PR that takes this version. Its state keys don't change. A spoke with no `workloads/` behaves exactly as before.

Proved on noisypigeon/runway#33, a plan-only draft pinned to this branch.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#107](https://github.com/noisypigeon/library/pull/107)

## [4.1.0] - 2026-10-20

### Generate workload stubs and publish module inputs schemas (LIB-0023)

This adds the scripts and CI paths LIB-0023's workloads need. A spoke can describe a workload's Scaleway resources in one `workloads/<workload>/values.yaml` at its repo root.

- **`resolve-workloads.sh`** turns each `values.yaml` into one stub leaf per module, at `workloads/<workload>/<provider>/<module>/<instance>/terragrunt.hcl`. A stub carries only the `dependency` blocks its kind implies, with no `mock_outputs`, since apply runs the saved plan. Run it from a spoke's root and commit the result. It removes stubs `values.yaml` no longer implies, but only files carrying its GENERATED header.
- **`resolve-workloads.sh --check`** writes nothing. It fails when a stub is missing, stale or hand-edited, and when an input isn't one of its module's inputs at the version it resolves to. That includes the inputs a workload wires from its dependencies, which an older pinned version may not have. Spokes add it to their `prepare_cmd`. It needs `yq`, which GitHub's Ubuntu runners have.
- **`module-inputs-schema.sh`** prints a JSON Schema of one module directory's inputs, from `terraform-docs`.
- **`generate-module-redirects.sh --static-root <dir>`** also publishes those schemas, one per `scaleway/project`, `bucket`, `iam-application` and `iam-api-key` version, beside each version's redirect page. It also publishes `schemas/workload/v1.json`, which validates a whole `values.yaml` and resolves pins to the right version's schema. Without the flag, nothing changes.
- **`zola-site-pages.yml`** gains a `terraform_docs` input that installs terraform-docs v0.24.0 before `extra_step`.
- **`terragrunt-detect.yml`**'s default `leaf_pattern` now matches `^workloads/`. A caller that overrides it should add the same.
- **`state-backup.yml`** now copies and checks `workloads/**` as well as `terraform/**`, so workload state in R2 is backed up to B2.

Nothing changes for a spoke with no `workloads/`. Workload leaves themselves need `terragrunt/root-hcl` v4.3.0, released separately.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#103](https://github.com/noisypigeon/library/pull/103)

## [4.0.1] - 2026-10-20

### fix(workflows): write changelogs on the newest main, not the merge commit

Every changelog writer now writes on the newest `main` instead of the PR's merge commit, so two PRs merged close together no longer fail each other's changelog commit.

**What went wrong.** #91 and #92 merged seconds apart. Their release runs were serialized, but #92's run still wrote its changelogs on its own merge commit, which predated #91's changelog push. Both had added a root `CHANGELOG.md` line at the same spot, so #92's rebase conflicted, the step stopped, and `workflows/v4.0.0` was never tagged. A re-run would have conflicted the same way.

**The fix, in all four writers:** `template-release.yml`, `root-changelog.yml`, and the reusable `spoke-root-changelog.yml` and `blog-changelog.yml`.
- **They check out `main`,** as `module-docs.yml` already did. The merge commit stays reachable, so detection still diffs it by SHA.
- **`root-changelog.yml` and `spoke-root-changelog.yml` write their line again on each retry,** on a fresh `main`, rather than rebasing the last attempt. Losing a race to another writer can no longer conflict.
- **`template-release.yml` and `blog-changelog.yml` keep a rebase retry.** They write across several steps, so a conflict now needs another workflow's line pushed in the seconds between checkout and push, and it still fails loudly. `blog-changelog.yml` gains the five-attempt retry the others had; it used to try once.

Versions are unaffected. They are still computed from the tags at checkout, and a tag still points at the pushed changelog commit.

Spokes get the `spoke-root-changelog.yml` and `blog-changelog.yml` fixes when they move to this version.

Tested locally with a bare origin and the real `root-changelog.sh`:
- the old flow reproduces #92's conflict;
- the new flow pushes both lines under one date;
- `root-changelog.yml`'s own step text, losing its first push to a rival writer, writes again and pushes on attempt 2.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#93](https://github.com/noisypigeon/library/pull/93)

## [4.0.0] - 2026-10-20

### feat(workflows): apply only the saved plan, and re-plan on comment (LIB-0022)

`terragrunt-run.yml` now applies exactly the plan that was reviewed, and a PR can be re-planned without a push (LIB-0022 §1–3).

**Plans are saved.** Plan runs every selected unit with `--out-dir`, and the new `.github/scripts/plan-archive.sh` packs the plans into one archive. It is encrypted with the spoke's own sops/age recipient (from `.sops.yaml`, through the `terraform/secrets/*.enc` creation rule), because a plan file holds sensitive values in plaintext. It is uploaded as the artifact `terragrunt-plan-<pr>-<head sha>`, kept for 7 days. The plan comment names the commit it planned.

**Apply applies only that plan.** Apply looks up the artifact for the PR's current head and applies it with `-lock-timeout=0s`. It does nothing, and says so on the PR, when:
- there is no plan for the head, because the head moved after planning, the plan failed, or the plan expired;
- the units the PR selects now differ from the ones it planned;
- Terraform refuses the plan as stale (`Saved plan is stale`) because another apply changed that state;
- another apply holds the leaf's state lock (from `terragrunt/root-hcl` v4.2.0).

Each failure has the same fix, a new plan, and the comment says how.

**A `terragrunt plan` comment re-plans.** A comment-triggered plan reacts to the comment as apply does, replaces any earlier plan for the same head (deleting it first, so a failed re-plan leaves nothing to apply), and resets `terragrunt/apply` to `pending`.

**Both commands use the PR's head,** never the merge ref. `checkout_ref` now defaults to the head, so a plan caller no longer needs to pass it.

**State backup skips `.tflock` objects.** It can't delete what it copies, so a lock copied to B2 would stay there forever.

### What a caller must change

- Grant `actions: write` in both `terragrunt-plan.yml` and `terragrunt-apply.yml`. The reusable now asks for it, so a caller without it fails to start.
- `prepare_cmd` must run `fetch-lib.sh`, which puts `plan-archive.sh` where the new `scripts_dir` input expects it (`.lib-src/.github/scripts`). Every current caller already does.
- In `terragrunt-plan.yml`:
  - add an `issue_comment: [created]` trigger;
  - run `plan` on `pull_request` or on a comment that is exactly `terragrunt plan` from an OWNER, MEMBER or COLLABORATOR;
  - run `detect` on `pull_request` only;
  - set the concurrency group to `terragrunt-pr-${{ github.event.pull_request.number || github.event.issue.number }}`.
- The first apply after upgrading needs a plan made by this version. Comment `terragrunt plan` on any PR that was planned before it.

Tested locally against a Terragrunt 1.1.6 / Terraform 1.16.3 fixture, running the workflow's own step scripts: a saved plan round-trips through git-filter worktree units, explicit-filter units and deleted units, and a stale plan is refused with `stale=true`. Not yet exercised on GitHub Actions; LIB-0022's Verification does that in garden after it adopts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#92](https://github.com/noisypigeon/library/pull/92)

## [3.5.0] - 2026-10-20

### Continue a renamed module's version track from its predecessor's last tag

A Terraform module that has no tags under its own path yet used to be released at `0.1.0`, whatever its `release:*` label said. That was right for a brand-new module and wrong for a renamed one, which is the same code with the same history at a new path.

`template-release.yml` now checks first for a `<!-- continues-from: terraform/<provider>/<module>/vX.Y.Z -->` line in the module's own `CHANGELOG.md`. If it finds one, the new track continues from that tag's version, so `release:major` on a module that continues from `v4.2.0` cuts `v5.0.0`. The named tag must exist, or the release fails rather than cut a wrong version. A module with neither tags nor that line still starts at `0.1.0`.

This is what LIB-0020's renames of `scaleway/pigeon-cluster` to `scaleway/compute-cluster` and `scaleway/object-bucket` to `scaleway/bucket` rely on. The record itself lands here too. Spokes don't need to take this release: only this repo's own release runs use the step.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#84](https://github.com/noisypigeon/library/pull/84)

## [3.4.0] - 2026-10-20

### Add a reusable container image release workflow

Adds `container-image-release.yml`, a reusable workflow that publishes a spoke's container image to GHCR for each release ([LIB-0019](docs/adr/LIB-0019-container-image-release.md)). The first caller is pigeon-cli, through its CLI-0163.

- **The spoke owns what the image is.** It keeps its Dockerfile and passes the build context, the image name (by default `ghcr.io/<owner>/<repo>`), build arguments and a platform matrix as inputs.
- **The spoke also writes a smoke test.** It is a shell snippet run inside each platform's image, with the entrypoint overridden, **before anything is pushed**. If it fails, nothing reaches the registry.
- **Native per-platform builds.** By default arm64 builds on `ubuntu-24.04-arm` and amd64 on `ubuntu-24.04`, with no QEMU. Each platform is pushed by digest, with its own GitHub Actions layer cache.
- **One multi-arch tag set.** A final job joins the per-platform digests into one index tagged `X.Y.Z`, `X.Y` and `latest`. `latest` can be turned off with an input. If either platform fails, nothing is published.
- **OCI labels and provenance.** The labels record source, revision, version and licence, and the `source` label links the package to its repository. The index gets a build-provenance attestation, which `gh attestation verify` can check.
- **Caller permissions.** The calling job must grant `contents: read`, `packages: write`, `id-token: write` and `attestations: write`. Images are pushed with the caller's `github.token`, so no new secret is needed.

This is purely additive: no existing caller changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#83](https://github.com/noisypigeon/library/pull/83)

## [3.3.0] - 2026-10-19

### Add pigeon-cli's observability stack and Claude Code plugin

Hoists two more of `pigeon-cli`'s assets into the library, per its [CLI-0161](https://github.com/noisypigeon/pigeon-cli/pull/133). Each gets its own per-set release track.

- **`observability/pigeon-cli/`**, released as `observability/pigeon-cli/vX.Y.Z`. This is pigeon-cli's local Docker Compose stack: Prometheus, Loki, Promtail and Grafana. Grafana no longer keeps its own copy of the dashboard. It mounts `grafana-dashboards/pigeon-cli/` from the same checkout, so there is one dashboard to edit. The compose project name is pinned to `observability`, so an existing stack keeps its Prometheus and Grafana volumes across the move.
- **`claude-plugins/pigeon-cli/`**, released as `claude-plugins/pigeon-cli/vX.Y.Z`. This is a Claude Code plugin holding the `analyze-job-run` skill. The repo root gains `.claude-plugin/marketplace.json`, a marketplace named `library`. A consumer pins the marketplace to the plugin's tag in its `.claude/settings.json` and enables `pigeon-cli@library`.
- **`grafana-dashboards/pigeon-cli`**: the `instance` variable's "All" is now `.*`. Its values come from node-exporter, so on a stack without one, "All" used to match nothing and every pigeon panel came up empty. On Cockpit, "All" still means every instance.
- **`template-release.yml`** treats `observability/<set>/` and `claude-plugins/<set>/` like `grafana-dashboards/<set>/`: one release track per set, and a set's README/CHANGELOG are never a release on their own.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#82](https://github.com/noisypigeon/library/pull/82)

## [3.2.0] - 2026-10-19

### Add a reusable Rust crate release workflow

Adds `rust-crate-release.yml`, a reusable workflow that releases a Rust crate on every push to its `main`, and the scripts it runs. They are hoisted from `pigeon-cli` by its [CLI-0161](https://github.com/noisypigeon/pigeon-cli/pull/133), which is their first consumer.

On each run, the release job checks formatting and lint with the caller's `mise run fmt-check`/`lint`. It then bumps the patch version and cuts `CHANGELOG.md`'s `[Unreleased]`. It commits, tags and pushes **before** publishing to crates.io, so a merge that races the run defers the release instead of burning a version. The publish is skipped if the version is already on the sparse index. Finally it cuts a GitHub Release. A matrix job then builds, smoke-tests and attaches one binary tarball per target.

- **New scripts.** `.github/scripts/crate-release.sh`, `crate-cut-release.sh`, `crate-build-release.sh` and `adr-issue.sh`. Every crate-specific value is an argument: `--crate` (the sparse-index path is derived from it), `--bin` and `--codesign-id`. `crate-release.sh` finds its sibling relative to its own location, so it works wherever `fetch-lib.sh` put the library.
- **`adr-issue.sh`** files an ADR's out-of-scope bullet as an issue and links it back into the ADR. It gains `--repo` and `--label-meta FILE`, so each repo keeps its own `area:*` label taxonomy, and its in-place edit no longer depends on BSD `sed`.
- **Callers.** A caller passes `crate`, `bin`, `codesign_id`, a JSON `targets` matrix and the `CARGO_REGISTRY_TOKEN` secret. It keeps the push trigger, the `chore(release): v` loop guard, `permissions: contents: write` and concurrency, and must have a `fetch-lib.sh`.
- **Tags stay with the caller.** The caller writes its own `vX.Y.Z` tags, an exception to LIB-0001 §4 recorded in its 2026-10-19 amendment.

No existing workflow changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#81](https://github.com/noisypigeon/library/pull/81)

## [3.1.1] - 2026-10-17

### Name the hub noisypigeon/library

This repo is now `noisypigeon/library`, renamed from `noisypigeon/pigeon-lib` (LIB-0015).

- **`generate-module-redirects.sh`** defaults `TAG_REPO` to `noisypigeon/library`. Once a site takes this `workflows` release, every module short URL's `terraform-get` meta resolves to `git::https://github.com/noisypigeon/library.git//…`, and the overview and release links name the new repo too. The old `pigeon-lib.git` sources keep working through GitHub's redirect in the meantime. The short URLs themselves don't change.
- **The theme's `homepage`** points at the new repo.
- **Docs.** The `root.hcl` template header, the READMEs (including the raw dashboard URLs), CLAUDE.md and the release-pr skill now name the library. ADRs and changelogs keep the old name as history.

No inputs, outputs or behaviour change for any consumer.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#70](https://github.com/noisypigeon/library/pull/70)

## [3.1.0] - 2026-10-17

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

## [3.0.0] - 2026-10-17

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

## [2.0.0] - 2026-10-16

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

## [1.6.2] - 2026-10-16

### Dispatch the blog deploy to noisypigeon/blog

The blog repo was renamed from `noisypigeon/noisypigeon.com` to `noisypigeon/blog`, and its Pages caller is now `blog-pages.yml` (noisypigeon/blog#36, [COM-0007](https://github.com/noisypigeon/blog/blob/main/adr/COM-0007-rename-the-repo-to-blog.md)). After a theme release, `template-release.yml` now runs `gh workflow run blog-pages.yml -R noisypigeon/blog`. It no longer relies on GitHub's rename redirect for a workflow-dispatch POST, or on a file name that no longer exists.

Nothing else in the reusable workflows changes. `CLAUDE.md`, `README.md` and the `release-pr` skill name the new repo and workflow.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#56](https://github.com/noisypigeon/pigeon-lib/pull/56)

## [1.6.1] - 2026-10-16

### Drop pigeon.dev from comments and docs

Comments and docs across the hub now describe the current architecture only. `pigeon.dev` is gone from them: the site repo is `noisypigeon/garden`, and module sources are `https://noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z`.

- **`terragrunt/root-hcl`:** the template's header drops how it was generalized from the monorepo's per-domain roots, and its example secret is a real current one. Only comments change, so every leaf renders exactly as it did under v2.2.0, and a spoke can take this version as a no-op.
- **`scaleway/project`:** the header comment drops the module's relocation history. No inputs, outputs or resources change.
- **`generate-module-redirects.sh`:** a comment change only.
- **Docs:** `CLAUDE.md`, `terraform/README.md`, `terragrunt/root-hcl/README.md`, `zola-site/README.md` and the `release-pr` skill name `noisypigeon/garden` and the current host, without the pigeon.dev history.
- **LIB-0009** gets an amendment line. `pigeon.dev` redirects to `https://noisypigeon.com`, not the garden (noisypigeon/noisypigeon.com#33).

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#55](https://github.com/noisypigeon/pigeon-lib/pull/55)

## [1.6.0] - 2026-10-16

### Publish module redirect pages under terraform/ instead of modules/

`generate-module-redirects.sh` now writes each module's per-version redirect page at `terraform/<provider>/<module>/vX.Y.Z` instead of `modules/<provider>/<module>/vX.Y.Z`. Its overview pages and their version links now live in `content/terraform/`. That's [LIB-0009](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0009-terraform-short-urls-move-to-noisypigeon-garden.md) §3, the generator half of moving the short URLs to `https://noisypigeon.garden/terraform/…`.

**A site that takes this version must rename `content/modules/` to `content/terraform/`**, along with its `_index.md` and any `.gitignore` globs for the generated pages. The generator wipes and rewrites `content/terraform/` and no longer touches `content/modules/`.

The `git::` targets, theme-version pages and release posts are unchanged. Nothing renders this until `noisypigeon/garden` bumps its pin at the cutover.

🤖 Generated with [Claude Code](https://claude.com/claude-code)


[#52](https://github.com/noisypigeon/pigeon-lib/pull/52)

## [1.5.4] - 2026-10-16

### Dispatch the site deploy to noisypigeon/garden

The site repo was renamed from `noisypigeon/pigeon.dev` to `noisypigeon/garden`, and its Pages caller is now `garden-pages.yml` (noisypigeon/garden#39). That's [LIB-0009](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0009-terraform-short-urls-move-to-noisypigeon-garden.md) §4. `template-release.yml` now runs `gh workflow run garden-pages.yml -R noisypigeon/garden` after every module or theme release. It no longer relies on GitHub's rename redirect for a workflow-dispatch POST, or on a file name that no longer exists.

Nothing else in the reusable workflows changes. `CLAUDE.md`, `README.md` and the `release-pr` skill name the new repo and workflow.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#51](https://github.com/noisypigeon/pigeon-lib/pull/51)

## [1.5.3] - 2026-10-16

### Fix state-backup.yml: compare state files by checksum

`state-backup.yml` failed once B2 already held the state files. rclone compared modification times, which it read by sending `HEAD` to each B2 object. When the times differed, it tried to rewrite the object's metadata. The backup key has no `readFiles`, so B2 refused both with `403 Forbidden`.

The copy now runs with `--checksum`. R2 and B2's S3 API both list an MD5 ETag for each state file, so rclone decides what to copy from the two listings alone and never needs to read or rewrite an object. That's also an exact content check: a state file is copied when, and only when, its bytes changed.

Checked against noisypigeon.com's buckets: the MD5s listed on both sides match for all nine state files, and a checksum copy transfers nothing and raises no errors.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#45](https://github.com/noisypigeon/pigeon-lib/pull/45)

## [1.5.2] - 2026-10-16

### Fix state-backup.yml: reach B2 through its S3-compatible API

`state-backup.yml` failed on its first real run with `failed to authorize account: This request is not currently supported on API version number 1`. rclone's `b2` backend authenticates with B2's v1 API, which B2 now refuses. The current rclone release, 1.72.1, does the same.

The workflow now reaches B2 through its S3-compatible API:

- **The endpoint is found at run time.** B2's S3 endpoint is per account (for example `https://s3.ca-east-006.backblazeb2.com`), so the job reads it from the backup key's own v4 `b2_authorize_account`. No new secret is needed.
- **It works with a key that can't read.** Without `readFiles`, the key can't answer the `HeadObject` that rclone sends for a sub-path or after an upload. So the copy runs bucket root to bucket root, filtered to `terraform/**`, with `--s3-no-head`. `--s3-no-check-bucket` stops rclone from trying to create either bucket.
- **The key and its capabilities are unchanged:** `listBuckets`, `listFiles` and `writeFiles`, with no read or delete. B2 keeps a new version for every write that arrives over the S3 API, just as it does over its native API.

These are the exact settings that made noisypigeon.com's first backup. That run copied all nine state files from R2 to B2; a second run copied nothing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#44](https://github.com/noisypigeon/pigeon-lib/pull/44)

## [1.5.1] - 2026-10-15

### Stop terragrunt-run.yml running a leaf twice

`terragrunt-run.yml` could run the same leaf twice, at the same time, against the same state key. That's harmless when the leaf has nothing to change. For a new leaf, every resource got created twice and one copy was orphaned. That happened in noisypigeon/noisypigeon.com#19: two B2 buckets and two B2 keys, with only one of each in state.

### Why it happened

The run selects leaves with two kinds of filter, combined:

- **`--filter '[main...HEAD]'`**, Terragrunt's git filter, runs every leaf it considers changed in a git worktree.
- **An explicit `--filter ./<dir>`** for each directory holding a changed file. It's there for Terragrunt's gap with files a module reads through `file()` (gruntwork-io/terragrunt#6952), and it runs the leaf in the checkout.

Terragrunt doesn't deduplicate the two. A leaf both filters matched (any new leaf, and most changed ones) was selected twice, and both copies ran.

### The fix

Before adding explicit filters, the step now asks Terragrunt which leaves the git filter already selects (`terragrunt find --filter '[main...HEAD]' --json`). It adds `--filter ./<dir>` only for directories missing from that list. A change the git filter misses, such as a dashboard JSON file, still gets its explicit filter.

If that lookup fails, the run fails rather than going ahead without it.

Checked against noisypigeon.com#19's branch: the two filters together had selected each new leaf twice; with this change, each of the nine leaves is selected exactly once. `actionlint` is clean.

Spokes pick this up by bumping their `@workflows/…` pins.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#41](https://github.com/noisypigeon/pigeon-lib/pull/41)

## [1.5.0] - 2026-10-15

### Add state-backup.yml: copy R2 Terraform state to a versioned B2 bucket (LIB-0007)

A new reusable workflow, `state-backup.yml`. It copies a spoke's Terraform state objects from its Cloudflare R2 state bucket to a Backblaze B2 bucket that keeps every version. R2 has no object versioning, so this copy is what lets a bad state write be rolled back ([LIB-0007](https://github.com/noisypigeon/pigeon-lib/blob/main/docs/adr/LIB-0007-terraform-state-on-r2-with-offsite-backup.md) §4).

### What it does

1. Decrypts the spoke's `secrets.enc` and masks every value before exporting the few it needs. It never writes a config file.
2. Runs `rclone copy r2:<state bucket>/terraform b2:<backup bucket>/terraform`. It's `copy`, never `sync`, so nothing is deleted.
3. Fails if any state file in R2 is missing from B2 afterwards.

### What it needs in `secrets.enc`

- `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_R2_ACCESS_KEY_ID` and `CLOUDFLARE_R2_SECRET_ACCESS_KEY`, the same keys `root.hcl` v2.1.0 uses for the R2 backend.
- The state bucket's name, under the key passed as `state_bucket_secret` (the spoke's `spoke.hcl` value).
- `TERRAFORM_STATE_BACKUP_B2_BUCKET_NAME`, `TERRAFORM_STATE_BACKUP_B2_KEY_ID` and `TERRAFORM_STATE_BACKUP_B2_KEY`. Each name can be overridden with an input.

Give the B2 key only `listBuckets`, `listFiles` and `writeFiles`, scoped to the backup bucket. Then this job can add versions but never read or delete them. A restore uses an admin key, by hand.

### Calling it

```yaml
jobs:
  backup:
    uses: noisypigeon/pigeon-lib/.github/workflows/state-backup.yml@workflows/v1.5.0
    with:
      state_bucket_secret: NOISYPIGEON_COM_R2_TERRAFORM_STATE_BUCKET_NAME
    secrets: inherit
```

Call it as a job after `apply` in `terragrunt-apply.yml`, and from a daily scheduled caller so that local applies are picked up too.

Checked with `actionlint`. Its first real run will be noisypigeon.com's move to R2.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#40](https://github.com/noisypigeon/pigeon-lib/pull/40)

## [1.4.1] - 2026-10-15

### Regenerate README tables for every module, not a hard-coded list

\`module-docs.yml\` now finds the modules whose README tables it regenerates at run time, using the terraform-docs action's \`find-dir: terraform\` input, instead of reading a hard-coded \`working-dir\` list. That list had drifted from the tree. Five modules added after it was written got no README regeneration when their \`.tf\` changed: \`cloudflare/bucket\`, \`cloudflare/ruleset\`, \`grafana/dashboard\`, \`scaleway/iam-api-key\` and \`scaleway/iam-application\`. A module added from now on is picked up as soon as it has a \`.tf\` file. The \`paths: '**/*.tf'\` trigger already matched every module, so it is unchanged.

This PR also refreshes the five READMEs the old list skipped, so the workflow's first run on them changes nothing:

- \`cloudflare/ruleset\`: the inputs/outputs table was empty, and is now filled in.
- \`scaleway/iam-api-key\`: the \`default_project_id\` input was missing from the table, and is now listed.
- \`cloudflare/bucket\` and \`grafana/dashboard\`: these tables were generated by hand, and now use the action's terraform-docs 0.20 table formatting. The content is the same.

No module's \`.tf\` changes, so no module is released.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#38](https://github.com/noisypigeon/pigeon-lib/pull/38)

## [1.4.0] - 2026-10-15

### Add a grafana-dashboards/<set>/vX.Y.Z release track

A fifth release unit: versioned Grafana dashboard JSON at `grafana-dashboards/<set>/*.json`, tagged `grafana-dashboards/<set>/vX.Y.Z`, one track per set.

A dashboard is something more than one consumer loads. `willowgraysen.com`'s Grafana leaf applies it with Terraform, and `pigeon-cli`'s local observability stack ships its own copy. A tagged file gives both a pinned version to fetch by URL, `raw.githubusercontent.com/noisypigeon/pigeon-lib/refs/tags/<tag>/<path>`, instead of each keeping a duplicate. This PR adds only the release machinery. The first set arrives in the next PR, and linking `pigeon-cli` to it is out of scope for now.

### Release tracking

- **`template-release.yml`** detects changed `grafana-dashboards/<set>/*.json` and cuts one tag per changed set.
  - The first version is `1.0.0`. After that, the PR's `release:*` label sets the bump, as for modules.
  - Each set gets its own `CHANGELOG.md` and a `[grafana-dashboards/<set>]` root line.
  - A README-only change releases nothing.
- **`root-changelog.yml`** gets the matching stand-down arm, so a dashboard release never gets two root lines, and a `grafana-dashboards` tag for non-releasing changes. That makes five duplicated predicates (noisypigeon/noisypigeon#301).

The hub's `CLAUDE.md`, `README.md`, the root `CHANGELOG.md` header and the `release-pr` skill now list the fifth unit.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#28](https://github.com/noisypigeon/pigeon-lib/pull/28)

## [1.3.2] - 2026-10-15

### Generate README tables for cloudflare/dns-record

Adds `terraform/cloudflare/dns-record` to `module-docs.yml`'s `working-dir` list, so its README gets the same generated input/output tables as the other modules.

The list is still hand-maintained, and `grafana-dashboard`, `iam-api-key` and `iam-application` are still missing from it (noisypigeon/noisypigeon#302). This adds only the new module rather than widening the change.

This touches `.github/workflows/`, so it cuts a `workflows/` patch release. No spoke needs to take it: `module-docs.yml` runs only in this repo.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#25](https://github.com/noisypigeon/pigeon-lib/pull/25)

## [1.3.1] - 2026-10-15

### Add a --check mode to resolve-root-hcl.sh

`resolve-root-hcl.sh` gains a `--check` mode. It writes nothing, and exits 1 unless the spoke's `./root.hcl` is byte-identical to the `root.hcl` template at the version `spoke.hcl` pins.

This is needed because spokes now **commit** the generated `root.hcl` instead of gitignoring it. The reusable `terragrunt-run.yml` plans with Terragrunt's `[main...HEAD]` git filter, and Terragrunt 1.1.6 evaluates every unit inside temporary git worktrees, which contain only tracked files.

- **Against the gitignored design,** a dry run of the `pigeon.dev` hoist failed on every leaf with `Could not find a root.hcl`.
- **With the file committed,** the same command planned `No changes.` for all four leaves.
- **Committing also keeps destroy plans working:** a leaf removed from a spoke still plans its destroy, because the base ref's worktree has its own `root.hcl`.

A spoke's CI runs `./fetch-lib.sh && .lib-src/.github/scripts/resolve-root-hcl.sh --check` through `prepare_cmd`, so a hand-edited or stale `root.hcl` fails the plan. Without arguments, the script still (re)writes `./root.hcl`, which is how a spoke takes a template bump. An unknown argument exits 2.

Tested against a scratch library repo:

- a missing `root.hcl` exits 1;
- a matching one exits 0;
- a one-line drift exits 1;
- a bad argument exits 2.

The written file is now mode 644, not the 600 `mktemp` left behind.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#17](https://github.com/noisypigeon/pigeon-lib/pull/17)

## [1.3.0] - 2026-10-15

### Let a spoke run terragrunt CI against a materialized root.hcl

This makes the reusable Terragrunt CI usable from a spoke, not only from `noisypigeon/noisypigeon`. It also adds the release machinery for a fourth track, `terragrunt/root-hcl/vX.Y.Z`, whose first template version follows in a separate PR (LIB-0003).

### `terragrunt-run.yml`: two new optional inputs

- **`secrets_files`** (default `.env.enc`): space-separated sops dotenv files whose decrypted values are masked in the log. A spoke keeps its secrets in `terraform/secrets.enc`; the old step hardcoded `.env.enc`.
- **`prepare_cmd`** (default empty): a command run from the caller's repo root before Terragrunt. A spoke uses it to fetch `pigeon-lib` and materialize `root.hcl`.

Both defaults do exactly what the workflow did before, so existing callers need no change. The final "fail if the run failed" step also reads its exit code through `env` now, which clears a long-standing `actionlint`/shellcheck error (SC2242).

### `.github/scripts/resolve-root-hcl.sh` (new)

Run it from a spoke's repo root. It reads `root_hcl_version` from `spoke.hcl` and writes `./root.hcl` from `terragrunt/root-hcl/root.hcl`:

- A version such as `"1.0.0"` takes the file at tag `terragrunt/root-hcl/v1.0.0`.
- `"main"` takes the working-tree copy.
- An unknown tag, a missing `spoke.hcl`, or running it inside the library itself fails the run with an error.

The script always copies and never symlinks. A leaf's state key is relative to `root.hcl`'s own directory, so `root.hcl` has to be a real file at the spoke's root. Like `resolve-theme.sh`, the script finds the library from its own location. It sits under `.github/scripts/` so the `workflows/` track versions it.

### Release tracking for `terragrunt/root-hcl/`

- **`template-release.yml`** cuts `terragrunt/root-hcl/vX.Y.Z` when `terragrunt/root-hcl/root.hcl` changes. The first version is `1.0.0`. It writes that unit's `CHANGELOG.md` and a `[terragrunt/root-hcl]` root line. There is no site to redeploy.
- **The hub's `root-changelog.yml`** gets the matching stand-down arm in the same change, so a template release never gets two root lines. Its precedence also gains `terragrunt/` → `terragrunt`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#15](https://github.com/noisypigeon/pigeon-lib/pull/15)

## [1.2.0] - 2026-10-15

### Add a reusable spoke-root-changelog.yml

Adds `spoke-root-changelog.yml`, a reusable workflow that writes DEV-0160's single root `CHANGELOG.md` line for a merged PR in a spoke.

Before this, `pigeon.dev` and `noisypigeon.com` each carried that job inline. Both copies fetched `pigeon-lib`, derived a tag from the changed paths, ran `root-changelog.sh` and pushed, and they differed only in their tag precedence. Spokes carrying their own workflow bodies goes against LIB-0001's first invariant. Resolves noisypigeon/noisypigeon#306.

### Inputs

- `precedence` (required): ordered `<ERE>=<tag>` lines matched against the PR's changed paths. The first line with any match wins.
  - Each line is split on its last `=`, so a pattern may contain `=` and a tag may not.
  - Blank lines are ignored. A line with no `=`, or with an empty pattern or tag, fails the run rather than being skipped.
- `fallback_tag` (default `repo`): the tag for a PR that matches no line.
- `fetch_script` (default `fetch-lib.sh`) and `changelog_script` (default `.lib-src/.github/scripts/root-changelog.sh`): where the caller's fetcher is, and where it leaves the script.
- `git_user_name` and `git_user_email`: the same defaults as `blog-changelog.yml`.

The caller keeps the `pull_request: closed` trigger, the merged-only gate, permissions and concurrency.

### Push retry

A rejected push is now retried up to five times with a rebase each time, as the hub's own `root-changelog.yml` already does. The inline copies did one rebase and one push. That was enough while they shared the `main-writer` concurrency group, but it also exposed them to GitHub's one-pending-run-per-group cancellation, the cause of the lost release in pigeon-lib#9. Callers can now use their own concurrency group. A rebase conflict still fails the run outright.

This is deliberately a separate file from the hub's own `root-changelog.yml`. That workflow has to stand down for PRs that `template-release.yml` releases, and it runs the script from its own tree. A spoke releases nothing, so it never stands down.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#14](https://github.com/noisypigeon/pigeon-lib/pull/14)

## [1.1.0] - 2026-10-15

### Let blog-changelog.yml take a site root via src_dir

`blog-changelog.yml` gains an optional `src_dir` input: the path to the Zola site root itself, using the same vocabulary as `zola-site-pages.yml`. With `src_dir` set, the daily digest is written to `<src_dir>/content/changelog/`.

Until now the digest path was hardcoded as `<site_dir>/src/content/changelog/`. That forced every caller to keep its site in a `src/` directory nested one level below some other directory. A spoke whose site root is `web/`, the shape DEV-0162 gave `pigeon.dev`, had no way to express that. `noisypigeon.com` is about to make the same move.

### Compatibility

The change is additive, so it is a minor bump:

- `site_dir` is now optional, but it behaves exactly as before when a caller passes it. Existing callers need no changes.
- Pass `site_dir` or `src_dir`, not both. A new validation step fails the job before checkout if a caller passes both or neither.
- `src_dir` requires `changelog_path`. `site_dir` has an implicit `<site_dir>/CHANGELOG.md` default; a site root has no equivalent, so the job refuses to guess and fails instead.

### Also in this PR

The hub's `CLAUDE.md` and `README.md` now name `noisypigeon.com`'s ADR prefix as `COM-`, its new name. `NPC-` in older prose is an alias for it. The rename itself lands in `noisypigeon.com`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#13](https://github.com/noisypigeon/pigeon-lib/pull/13)

## [1.0.7] - 2026-10-15

### Read release notes from the default branch, not the pinned tree

`terraform/scaleway/project/v2.0.1` published its **redirect page** but not its **release post**. Found by checking the live site after the release, not by reading code.

```
/modules/scaleway/project/v2.0.1/      -> 200   (tag-derived)
/releases/scaleway-project-v2-0-1/     -> 404   (file-derived)
```

### The asymmetry

Two halves of the same generator read from two different points in time:

| Content | Source | Liveness |
| --- | --- | --- |
| Redirect pages, overview pages, version lists | `git tag --list` on `LIB_ROOT` | **Live** — `fetch-lib.sh` fetches tags in full regardless of checkout |
| Release posts | `find "$LIB_ROOT/terraform" -name CHANGELOG.md` | **Pinned** — working tree is at whatever `.lib-version` names |

`.lib-version` pins a ref that *by construction* predates any release cut after it. So the newest entry — the one a fresh release most needs published — is precisely the one the pinned working tree cannot have. The site would only show the post after an unrelated `.lib-version` bump.

### Why `origin/main` and not the version tag

The tag **does** carry its own entry: `template-release.yml` commits the changelog, pushes to `main`, then tags that same commit (`47f4755` is both `v2.0.1` and `main`'s head). So reading `<tag>:…/CHANGELOG.md` was my first fix, and it was wrong.

**A version tag does not carry entries backfilled for *older* tags afterwards.** Four such entries exist — from #14, which backfilled six previously undocumented module tags without cutting new ones. Reading the tag alone silently dropped all four: **87 posts became 83.**

Neither source is a superset of the other. The default branch is a superset of both. And since release notes are append-only published history, and the tag graph is *already* read live, pinning only the notes is what created the mismatch in the first place.

`CHANGELOG_REF` is overridable and verified with `rev-parse` up front, so a missing ref fails loudly instead of yielding an empty site.

### Verification

Ran both generators against the same `LIB_ROOT` into separate content roots and diffed the full output trees:

```
OLD posts: 87
NEW posts: 88
files only in NEW:   ./releases/scaleway-project-v2.0.1.md
files only in OLD:   (none)
content differences: 0
```

Exactly one added file. Nothing removed, nothing changed. The four backfilled posts are all present. `bash -n` and `shellcheck -S warning` clean — the latter caught a genuine `rm -rf` expansion risk in my first draft, now `${var:?}`-guarded.

### Note on scope

The module **description** on overview pages is still read from the pinned `README.md`, so it has the same staleness in principle. Left alone deliberately — it's a different code path with a much weaker failure mode (descriptions rarely change, and a stale one is wrong rather than missing), and I'd rather not widen a verified fix. It goes in the tracked issue.


[#12](https://github.com/noisypigeon/pigeon-lib/pull/12)

## [1.0.6] - 2026-10-15

### Stop the shared concurrency group dropping a release

`template-release`, `root-changelog` and `module-docs` all declared `concurrency.group: main-writer` with `cancel-in-progress: false`.

**GitHub keeps at most one *pending* run per concurrency group, and cancels any previously-pending run when a third arrives.** A `.tf` merge triggers all three of these. So one is always lost — and it was the release.

### It already cost a real release

PR #9 merged, and:

```
template-release  pull_request  completed/cancelled   ← the release
module-docs       push          completed/success
root-changelog    pull_request  completed/success
```

`root-changelog` started and held the group, `template-release` went pending, `module-docs` arrived 1 second later and displaced it.

Outcome: **no tag, no Release, no module `CHANGELOG.md` entry** — and because `root-changelog` had *correctly* stood down for a releasing PR, no root changelog line either. A labelled release PR merged to a completely silent outcome. Nothing failed loudly; the run just said `cancelled`.

### Why four earlier merges didn't hit it

The failure is timing-dependent and shape-dependent. `module-docs` triggers on `**/*.tf`, so a `.github/`-only change triggers two of the three — and two fit, one running and one pending. Every merge in this repo so far has been structural. The first genuine module release found it immediately, which is exactly why that release was worth doing before anything depended on it.

### The fix

Each workflow gets its own group: `main-writer-release`, `main-writer-rollup`, `main-writer-docs`. Nothing can displace anything.

That removes the serialization those groups were providing, so the two writers we control now **retry a rejected push** — up to five times, re-fetching and rebasing each round, with a backoff:

```bash
for attempt in 1 2 3 4 5; do
  git fetch origin main
  if ! git rebase origin/main; then
    git rebase --abort || true
    echo "::error::rebase onto origin/main conflicted; refusing to guess"
    exit 1
  fi
  if git push origin HEAD:main; then echo "Pushed on attempt ${attempt}."; exit 0; fi
  echo "Push rejected (attempt ${attempt}/5); another writer won the race."
  sleep $((attempt * 5))
done
```

**A rebase conflict stays fatal.** A rejected push means someone else moved `main` and rebasing is correct; a conflict means two writers touched the same lines, and that's the `pigeon-lib#2` → `#3` double-write class of bug — guessing there is worse than failing.

For a releasing PR the writers touch disjoint files anyway (`template-release` owns the root changelog, `root-changelog` stands down, `module-docs` writes READMEs), so a conflict should mean a genuine defect.

`module-docs` pushes through `terraform-docs/gh-actions`, so its push isn't retry-protected here. Low stakes — it only regenerates README tables and self-heals on the next `.tf` change.

### After this

Re-running PR #9's cancelled run to recover `terraform/scaleway/project/v2.0.1`. The state is clean for that: the merge commit is on `main` and none of the four release artifacts were written, so the re-run has nothing to collide with.

`actionlint` clean on all three files. (`terragrunt-run.yml` reports a pre-existing SC2242 that also reproduces at `origin/main`; untouched here.)


[#10](https://github.com/noisypigeon/pigeon-lib/pull/10)

## [1.0.5] - 2026-10-15

### The Pages deploy timeout ceiling is hard, not a default

**#7 does not work, and this corrects it.**

`actions/deploy-pages` clamps the `timeout` input to a hard maximum of **600000 ms**. #7 set `1200000`, and the action's own log says what became of it:

```
timeout: 1200000
##[warning]Warning: timeout value is greater than the allowed maximum
           - timeout set to the maximum of 600000 milliseconds.
```

So #7 was inert in the worst way: it set the value back to the exact default it was trying to raise, and added a warning to every deploy from then on. Caught in `pigeon.dev#20`'s deploy log, which is the first deploy that actually ran the change — the step then succeeded in 43 s, so the raised value was never the reason it passed.

I had the input name right and verified it against the action's echoed inputs. What I didn't check was whether the value was *accepted*, and "600000" was sitting there in that same echo as the clue that it was a ceiling rather than a default.

### What this changes

`timeout: 600000` — equal to the default, so behaviour is unchanged and the warning stops. Kept rather than deleted because it documents the ceiling at the exact point someone would try to raise it, which is the mistake #7 made. The comment carries the warning text verbatim so the next reader doesn't have to discover it from a log.

### What this means for the wedge

**The orphaning risk is unmitigated, and cannot be mitigated this way.** Waiting longer is not available at any price:

- 600 s is the ceiling, so the action will always give up while GitHub may still be working.
- When it does, it cancels a deployment the Pages *service* still holds, and later deployments fail with `due to in progress deployment` until a server-side reaper clears it — ~45 minutes in the one incident we have.
- No client-reachable API shortens that. `POST .../cancel` returns 204 and is reflected in the read path without releasing the creation lock; a Deployments-API status write is accepted with no effect; reruns fail identically.

That makes this a tracked issue rather than a fixed bug, and raises its priority — it's the one failure mode in this architecture with no self-service recovery. Filing it against `noisypigeon/noisypigeon` per ADR-0031 with the full log evidence, since "wait for a reaper" is not a conclusion anyone should have to re-derive at 2am.

Cuts `workflows/v1.0.5`; `pigeon.dev` re-pins in the follow-up.


[#8](https://github.com/noisypigeon/pigeon-lib/pull/8)

## [1.0.4] - 2026-10-15

### Raise the Pages deploy timeout to 20 minutes

`actions/deploy-pages` defaults to a **600000 ms** timeout. That default is what orphaned `pigeon.dev`'s Pages deployment yesterday and blocked four consecutive deploys.

### What happened

PR #17's merge created a deployment that reported `Current status: updating_pages` for **110 consecutive polls** — that was the only status it ever reached. At 10 minutes the action's own timeout fired:

```
16:26:13Z  Current status:
16:26:13Z  ##[error]Timeout reached, aborting!
16:26:14Z  Canceled deployment with ID e936dae…
```

It self-cancelled a deployment the Pages **service** still held. Every later deployment then failed with `due to in progress deployment. Please cancel e936dae… first` for ~45 minutes, until a server-side reaper released it.

### Nothing could clear it from the client side

Worth recording, because the recovery is non-obvious:

- `GET /pages/deployments/<sha>` reported `{"status":"deployment_cancelled"}` while `POST /pages/deployments` kept 400ing about that same sha. **The two sides of the Pages API disagreed.**
- `POST /pages/deployments/<sha>/cancel` returned **204** twice and was reflected in the read path — it was not a no-op — but did not release the creation lock.
- `POST /deployments/<id>/statuses -f state=inactive` was accepted, no effect.
- Four `deploy` reruns, including a fresh `workflow_dispatch` on a different build version, all failed identically.

Everything on our side was ruled out: zero in-flight runs, no wait timer or required reviewer on the `github-pages` environment, all deployments terminal, cert approved and domain verified, and `noisypigeon.com` deployed 5/5 successfully in the same window — including two concurrent runs — so it was neither an outage nor a concurrency fault.

### The change

`timeout: 1200000` (20 minutes), with a comment explaining why the default is dangerous rather than just that it was raised.

This **reduces the odds, it does not remove them** — a slow-enough deployment still self-cancels. So the incident is also being filed as a tracked issue, since the recovery path is "wait for a reaper" and that is worth writing down somewhere findable.

Input name verified against the action's own echoed inputs (`timeout: 600000`, `error_count: 10`, `reporting_interval: 5000`) rather than assumed, since an unknown input would warn and change nothing. `actionlint` clean.

### On merge

Touches `.github/workflows/`, so `template-release.yml` cuts **`workflows/v1.0.4`**. `pigeon.dev` re-pins to it in the next PR, which retires its own automation and so touches `.github/` anyway. `noisypigeon.com` stays on `v1.0.2` — its deploys are healthy.


[#7](https://github.com/noisypigeon/pigeon-lib/pull/7)

## [1.0.3] - 2026-10-14

### Follow pigeon.dev's DEV- prefix rename

[DEV-0161](https://github.com/noisypigeon/pigeon.dev/pull/17) flattened `pigeon.dev`'s ADR corpus to `adr/` and re-prefixed it `PD-` → `DEV-`. This repo holds **133** of those citations, so they follow.

### Why rewrite rather than grandfather

PD-0160 grandfathered 1,100+ bare `ADR-NNNN` on volume: rewriting them would churn published changelog entries and another repo's `.hcl`/`.tf`. `PD-` carries none of that weight and was one day old, so DEV-0161 rewrote it instead — leaving **two** live spellings for that corpus rather than three. This PR is this repo's share of that.

Breakdown of the 133:

| Where | Count |
| --- | --- |
| `LIB-0001` + `LIB-0002` | 82 |
| five published module changelogs | 20 |
| `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `terraform/README.md`, the skill | 14 |
| workflows and scripts | 17 |

### The published changelogs are included, deliberately

NPC-0000's precedent is that published changelog copy is **not** retrofitted to a later layout — the reason those files still carry `docs/adr/` paths that stopped existing two moves ago. It doesn't bite here, and I checked rather than assumed:

- Those versions have **no GitHub Release in this repo** to diverge from (`gh release view` → `release not found`). The historical Releases live in `noisypigeon` under the old `templates/terraform/…` tag names.
- The site's release posts are **generated** from these files, so rewriting keeps file and published post consistent rather than splitting them.

DEV-0161's permanent boundary covers bare `ADR-NNNN`, not `PD-`, so this is in scope rather than against it.

One quotation needed care: `LIB-0002` quotes LIB-0001's own phrase *"re-opens every coupling PD-0156 closed"*. Since LIB-0001 is rewritten in the same commit, the quote stays an accurate quotation of its source.

### Verified

- `grep -r 'PD-'` over the repo returns **0**.
- Bare `ADR-NNNN` is **334 before and after** — the grandfathering is not collateral damage.
- `shellcheck` clean on both fetched scripts and `resolve-theme.sh`; `actionlint` clean apart from the pre-existing `terragrunt-run.yml` SC2242 that predates this repo.
- The generator still produces 49 / 13 / 4 / 87 after its comment rewrite — same counts as before.

### On merge

Touches `.github/workflows/` and `.github/scripts/`, so `template-release.yml` cuts **`workflows/v1.0.3`** with this body as its changelog entry and Release notes. No module or theme release: no `.tf` and no theme asset changes.

The five callers stay pinned at `v1.0.2`. A pin exists so it needn't track latest, and the delta here is comment text — but `pigeon.dev` will pin **v1.0.3** when it starts fetching, so it gets the DEV-corrected scripts from the outset.

[#6](https://github.com/noisypigeon/pigeon-lib/pull/6)

## [1.0.2] - 2026-10-13

### Version the generator with the workflows track

Corrects a placement mistake from #4, before Phase C pins anything to a version.

### The gap

I put `generate-module-redirects.sh` at the repo root. The `workflows/` release predicate covers `.github/workflows/*.yml` and `.github/scripts/` — so the generator sat outside it. A spoke pinning `@workflows/vX.Y.Z` would have got a pinned *workflow* and a generator tracked from `main`: invariant 2 half-satisfied, in exactly the branch-tracking direction it exists to forbid. A hub commit touching the generator would have reached every site's next build with no version change to show for it.

Moving it beside `root-changelog.sh` — the other script spokes fetch — means **one pin covers everything a spoke takes from the hub**.

### The path arithmetic, re-verified rather than assumed

`LIB_ROOT` is derived from `${BASH_SOURCE[0]}` precisely so the script finds the clone it was fetched into rather than the consuming site's repo. Moving the file down two directories invalidates that derivation — the same class of breakage the flatten caused in `resolve-theme.sh`, where `../..` silently became one level too high.

So it climbs two levels now, and the proof is empirical: the generator's output from `.github/scripts/` is **byte-identical** to its output from the root — same 49 / 13 / 4 / 87 counts, and `diff -r` across all three content directories is clean.

The comment now also says *why* the arithmetic is what it is, so the next move doesn't get it wrong by inheritance.

### On merge

This touches `.github/scripts/`, so it fires the `workflows/` track and cuts **`workflows/v1.0.2`** — and that is the ref Phase C pins into five caller files across two repos. I'll confirm the cut version before writing it anywhere, since a typo'd ref is how `noisypigeon`'s merge gate gets stuck.

`root-changelog.yml` stands down; `template-release.yml` writes the `[workflows]` line.

[#5](https://github.com/noisypigeon/pigeon-lib/pull/5)

## [1.0.1] - 2026-10-13

### Stand down root-changelog for the workflows release track

Fixes a bug I introduced in #2.

### What broke

#2 added `.github/` as a third releasable unit to `template-release.yml`, but left `root-changelog.yml`'s stand-down predicate checking only the module and theme arms. So on a `.github/`-only PR both workflows concluded they owned the root changelog line:

- `root-changelog.yml` saw "not a release" → wrote `- [ci] …`
- `template-release.yml` saw "release" → wrote `- [workflows] …`

Both insert into the same `## YYYY-MM-DD` section, so the second one to rebase hit `CONFLICT (content): Merge conflict in CHANGELOG.md` and `template-release`'s commit step failed.

DEV-0160 named this risk in the same breath as it created it — the predicates are duplicated across two workflows on purpose, and it wrote that "if one drifts, a PR gets either two root lines or none". This is that drift, one commit after the track was added. The fix is the third arm, and the comment now says what happened so the next person adding a track sees the cost of forgetting.

### Nothing was lost

The collision failed *before* the tag step, so #2 cut no tag and no Release — `git tag -l` was still 53 afterward. `workflows/v1.0.0` has since been seeded by hand at `main`, with the GitHub Release carrying the entry #2 already wrote for it, exactly as #2's changelog entry said would happen.

#2's own root line reads `[ci]` rather than `[workflows]`, which is accurate in retrospect: it released nothing.

### A correction to something #2's body asserted

I said `template-release.yml` wouldn't fire on #2's merge because "a `pull_request: closed` workflow runs from the base branch" — DEV-0154 §9's reasoning, which I took at face value. **It fired**, and the run's step list proves it used the *head* version: it executed "Determine reusable-CI change", a step that only existed on the branch.

So for `pull_request`, GitHub evaluates both the `paths:` filter and the job bodies from the PR's merge commit, not the base. DEV-0154's conclusion — split "retire the automation" from "delete the content" into separate PRs — is still the prudent order, but its stated *reason* doesn't hold, and anything relying on that reason should be re-checked rather than inherited. I'll carry the correction into LIB-0002.

### On merge

This PR touches `.github/`, so with the fix applied from head: `root-changelog.yml` stands down, and `template-release.yml` cuts `workflows/v1.0.1` with this body as its changelog entry and Release notes — the first release this track cuts on its own, and the real test of it.

[#3](https://github.com/noisypigeon/pigeon-lib/pull/3)

## [1.0.0] - 2026-10-13

### Seed the reusable CI's version track

`workflows/v1.0.0` is a seed tag, written by hand rather than by
`template-release.yml`, because the automation that cuts this track is itself
introduced by the PR that this entry documents — and a `pull_request: closed`
workflow runs from the **base** branch, so the version it adds cannot cut its
own first release. The same bootstrapping pattern DEV-0110 used for its five
module seed tags.

It marks the reusable CI as it stood when `pigeon-lib` was stood up by LIB-0002:
the five workflows the spokes call (`terragrunt-detect`, `terragrunt-run`,
`blog-changelog`, `interaction-limits-renew`, `zola-site-pages`), plus
`.github/scripts/root-changelog.sh`, which they fetch.

**No behaviour change from the last `@main` state the spokes consumed**, beyond
what LIB-0002's flatten already required: `zola-site-pages.yml` takes
`fetch_script`/`theme_script` instead of a hardcoded `.templates-src` path, and
`zola-site-deploy.yml` is gone — it had no caller in any repo and its own
`:60` hardcoded a path into a caller's checkout that DEV-0159 had moved away.

From here the track behaves like the other two: one `release:*` label per PR,
the PR body becomes this file's entry and the GitHub Release notes verbatim.

PR: see LIB-0002.
