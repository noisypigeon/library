# LIB-0038: Compose deployers and redirects from single-resource modules

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-26.
- **Status**: Proposed. Amends:
  - LIB-0023 §2 and LIB-0028 §4, whose kind table loses
    `scaleway/terraform-deployer-iam` and `cloudflare/apex-redirect` and gains
    three `deployer` kinds;
  - LIB-0024 §§1, 4 and LIB-0028 §§1, 5, whose implicit deployer becomes three
    leaves, and whose `ObjectStorageFullAccess` guard moves with the policy;
  - LIB-0030 §§1, 4, 6 and LIB-0036 §§1–3, whose `apexRedirect` becomes a
    shorthand for `dnsRecord` and `ruleset` entries;
  - LIB-0033 §§2, 4, whose rotation moves into `scaleway/iam-api-key`, and
    whose spoke deployers gain a Scaleway one under the same name.

  Its majors also carry LIB-0037 §6's refusal of the old layout.

## Context

Two hub modules bundle resources that other hub modules already wrap one at a
time.

- **`scaleway/terraform-deployer-iam`** holds a `scaleway_iam_application`, a
  `scaleway_iam_policy` and a `scaleway_iam_api_key`, plus the key's rotation:
  `time_static`, `time_rotating` and a `terraform_data` that carries it
  (LIB-0024 §4). `scaleway/iam-application`, `scaleway/iam-policy` and
  `scaleway/iam-api-key` wrap the first three. The split is old: the three
  came out of `iam-policy` in October 2026, and the deployer module bundled
  them back for LIB-0014.
- **`cloudflare/apex-redirect`** holds a `cloudflare_zone` lookup, a proxied
  placeholder `A` at `@`, an optional `CNAME` at `www` and a
  `cloudflare_ruleset`. `cloudflare/dns-record` and `cloudflare/ruleset` wrap
  the last three, and each looks its zone up by apex (LIB-0011).

Every unit gets an implicit deployer (LIB-0028 §1), and every zone may declare
an `apexRedirect` (LIB-0036 §3). So both bundles sit in the kind table, in
three copies, beside the modules they duplicate. That costs three things.

- **Two copies of one resource drift apart.** A fix to `iam-api-key` doesn't
  reach the deployer's key, and a fix to `dns-record` doesn't reach a
  redirect's records. apex-redirect's own header says it uses raw resources
  only because a module can't source another by short URL (LIB-0009).
- **A bundle's parts can't be told apart.** A deployer's policy and its key
  are one leaf, one state and one plan line. A change to the policy's
  permission sets plans in the same leaf as the key every other leaf in the
  unit signs in with.
- **The checks see a bundle as one thing.** LIB-0030 §6 needs special cases
  for an `apexRedirect`'s placeholder records and its entrypoint, because they
  aren't `dnsRecord` and `ruleset` entries.

Single-resource modules are what LIB-0004 asks a leaf to call, and the kind
table can compose them as well as a module can.

## Decision

### 1. A unit's deployer is three leaves

Every unit, a zone or a workload, gets three implicit leaves in place of
`scaleway/terraform-deployer-iam/main`:

```
<unit>/scaleway/iam-application/deployer
<unit>/scaleway/iam-policy/deployer
<unit>/scaleway/iam-api-key/deployer
```

`<unit>` is `zones/<zone>`, `workloads/<zone>/<w>` or `workloads/private/<w>`.
Their instance is `deployer`, as the unit's Cloudflare token's is (LIB-0033
§4), so a workload's own `scaleway.iam.application` and `scaleway.iam.apiKey`
keep `main`.

- **`scaleway.deployer` overrides them,** one key per module, each taking that
  module's inputs by their own names:

  ```yaml
  scaleway:
    deployer:
      application: {}   # scaleway/iam-application
      policy: {}        # scaleway/iam-policy
      apiKey: {}        # scaleway/iam-api-key
  ```

  A module input directly under `scaleway.deployer`, as LIB-0024 §1 wrote it,
  is refused with a message naming this record. So is `scaleway.deployer` in
  `secrets.workload.yaml`, except under the same three keys.
- **Their defaults** keep every name the bundle gave, for blog in
  noisypigeon.com (LIB-0037 §2):

  | Leaf | Defaults | blog |
  | --- | --- | --- |
  | `iam-application/deployer` | `name`: `<prefix>-<suffix><tag>-deployer` | `npc-noisypigeon-blog-deployer` |
  | `iam-policy/deployer` | `name`: the same, which the module suffixes with `-policy`; `project_permission_sets`: `["ObjectStorageFullAccess"]` | `npc-noisypigeon-blog-deployer-policy` |
  | `iam-api-key/deployer` | `rotation_days`: 30 (§2) | |

  `<tag>` is `-zone` for a zone and `-<name>` for a workload, as LIB-0037 §2
  has it.
- **Their wiring:**
  - the policy takes `application_id` from the application, and
    `project_ids = [project.id]` from the unit's project;
  - the key takes `application_id` from the application, and
    `default_project_id` from the project;
  - the application takes nothing.

  The project is the unit's own, or its zone's for a workload in its zone's
  project (LIB-0037 §2).
- **All three sign in with the spoke's key and keep their state in the
  spoke's bucket,** as the bundle did (LIB-0028 §4). The key is what signs in
  to the unit's bucket, so it can't keep its state there, and the other two
  are what make it.
- **Every leaf that signed in with the deployer's key now signs in with
  `iam-api-key/deployer`'s.** That covers a `workload`-credentials provider
  (LIB-0024 §2) and a `workload`-state leaf's `remote_state` (LIB-0028 §5).
  Both read `access_key` and `secret_key`, which `iam-api-key` outputs under
  the same names, so a stub's `dependency "deployer"` changes only its path.
- **LIB-0028 §5's guard moves with the permission sets.** A
  `scaleway.deployer.policy.project_permission_sets` without
  `ObjectStorageFullAccess` is refused.
- **A new unit's stages** become project, application, policy and key, state
  bucket, and the rest. The policy and the key both depend on the
  application, so they plan and apply in the same stage, and the state bucket
  waits for the key (LIB-0024 §3).

#### The spoke deployer

A spoke's own Scaleway deployer is a hand-written leaf, not a kind, so the
spoke changes it in its own PR. runway's
`terraform/scaleway/terraform-deployer-iam/runway` becomes:

```
terraform/scaleway/iam-application/terraform-deployer
terraform/scaleway/iam-policy/terraform-deployer
terraform/scaleway/iam-api-key/terraform-deployer
```

These are the names LIB-0033 §2 gives the spoke's Cloudflare and Backblaze
deployers. The policy and the key take the application's ID through a
`dependency` block. The key keeps the bundle's inputs, with no rotation: its
output is hand-copied into sops (LIB-0014 §4).

### 2. `scaleway/iam-api-key` rotates

`iam-api-key` takes the bundle's rotation unchanged, as a `release:minor`:

- **`rotation_days`,** optional: a `time_rotating` replaces the key every
  `rotation_days`, with `create_before_destroy`, and the key expires a week
  after each scheduled rotation. Unset, the key keeps today's expiry, 30 days
  after it was first created. An explicit `expires_at` still wins.
- **The same resource addresses:** `time_static.created`,
  `time_rotating.key[0]`, `terraform_data.rotation` and
  `scaleway_iam_api_key.api_key`. A deployer's key then moves from the bundle
  with its rotation timestamp, so nothing rotates early.
- **`terraform_data.rotation` always exists,** as it does in the bundle,
  because `replace_triggered_by` can't name a resource that may have no
  instances. A key that takes the minor without `rotation_days` plans one
  `terraform_data` create, and no change to the key.

LIB-0024 §4's rotation, and §3's deferral that makes it safe, are otherwise
unchanged.

### 3. `apexRedirect` is a shorthand

`cloudflare.apexRedirect.<key>` stays in `zone.yaml`, with the bundle's
inputs: `target_url`, `status_code`, `include_www` and
`preserve_query_string`. It's no longer a kind. It expands, before anything
else reads the file, into three entries. Below, `<host>` is `target_url`'s
host, as the bundle derived it:

| Entry | What it is |
| --- | --- |
| `cloudflare.dnsRecord.<key>-apex` | `@`, `A`, `192.0.2.1`, proxied, `ttl` 1, comment `placeholder so Cloudflare intercepts apex traffic for the <host> redirect` |
| `cloudflare.dnsRecord.<key>-www` | only with `include_www`, as by default: `www`, `CNAME` to the zone, proxied, `ttl` 1, comment `placeholder so Cloudflare intercepts www traffic for the <host> redirect` |
| `cloudflare.ruleset.<key>` | `<zone> to <host> redirect`, kind `zone`, phase `http_request_dynamic_redirect`, one redirect rule from the four inputs |

- **Every generated string is the bundle's,** so a moved resource plans
  `No changes.`, and a ruleset's name, which Cloudflare replaces it on, never
  changes.
- **An explicit entry of the same key is merged over its default, field by
  field,** as LIB-0034 §2's Pages records are. That's also how an expanded
  entry is pinned to a `version`.
- **Any other input under an `apexRedirect` entry is refused,** `version`
  included, since the shorthand calls no module of its own. So is an
  `apexRedirect` in a workload, as LIB-0036 §3 already refuses.
- **LIB-0030 §6's checks run on the expanded entries.** One entrypoint per
  zone and phase then covers two redirects in one zone, and one record per
  name and type covers a second `A` at `@`. A `CNAME` or `AAAA` at `@`, or
  anything at `www`, beside a redirect is still refused by name. LIB-0037
  §3's refusal of `hosts.@` beside an `apexRedirect` is unchanged.
- **A zone's token keeps the redirect group,** as LIB-0036's first amendment
  gave it.

### 4. The kind table's three copies

The table changes in all three places at once (LIB-0023 §2):

- root.hcl's `workload_kinds`;
- `resolve-workloads.sh`'s KINDS;
- `generate-module-redirects.sh`'s schema list.

| Kind | Module | Shape | Credentials | State | Units |
| --- | --- | --- | --- | --- | --- |
| `scaleway.deployer.application` | `scaleway/iam-application` | `deployer` | spoke | spoke | both |
| `scaleway.deployer.policy` | `scaleway/iam-policy` | `deployer` | spoke | spoke | both |
| `scaleway.deployer.apiKey` | `scaleway/iam-api-key` | `deployer` | spoke | spoke | both |

- **`scaleway.deployer` and `cloudflare.apexRedirect` leave the table.** A stub
  under `scaleway/terraform-deployer-iam/` or `cloudflare/apex-redirect/` is
  refused by root.hcl, naming this record.
- **The schemas take a new version:** `/schemas/workload/v3.json` and
  `/schemas/zone/v2.json`. Older versions stay published, unchanged, for files
  still pinned to them.

### 5. State moves; nothing is recreated and no key rotates

Each old leaf's state goes to its new leaves by `terragrunt state pull` and
`state push`, with `state rm` and `state mv` inside a leaf for what changes.
Nothing is imported: each resource keeps its provider ID. runway is frozen, as
`docs/runbooks/import-a-leaf-into-a-workload.md` says, from the first push
until the PR that commits the move merges.

For each old leaf:

1. **Pull a backup** of its state into a private directory outside every
   checkout. A deployer's state holds its secret key, so the backup is deleted
   once the move is merged.
2. **For each new leaf:**
   1. check its backend is empty, as `state list`'s `No state file was
      found!` says;
   2. `state push` the backup;
   3. `state rm` every address that belongs to another new leaf, and
      `state mv` what keeps a different address;
   4. plan with `-detailed-exitcode`, which must exit 0.
3. **Empty the old leaf** with `state rm`, only once every new leaf has planned
   `No changes.` The PR that removes its stub plans its destroy from the base,
   as LIB-0037 found, and an empty state destroys nothing.

A push into an empty backend gives the state a new lineage, which is harmless.

| Old address | New leaf | New address |
| --- | --- | --- |
| `module.this.scaleway_iam_application.application` | `iam-application/deployer` | the same |
| `module.this.scaleway_iam_policy.policy[0]` | `iam-policy/deployer` | the same |
| `module.this.time_static.created`, `time_rotating.key[0]`, `terraform_data.rotation`, `scaleway_iam_api_key.api_key` | `iam-api-key/deployer` | the same |
| `module.this.cloudflare_dns_record.apex` | `dns-record/<key>-apex` | `module.this.cloudflare_dns_record.this` |
| `module.this.cloudflare_dns_record.www[0]` | `dns-record/<key>-www` | `module.this.cloudflare_dns_record.this` |
| `module.this.cloudflare_ruleset.this` | `ruleset/<key>` | the same |
| `module.this.data.cloudflare_zone.this` | none | removed; each leaf reads its own |

A hand-written leaf's addresses follow its own module block names, such as
`module.terraform_deployer_iam` in runway's.

### 6. Release impact

- **`terraform/scaleway/iam-api-key` takes a minor** for §2, and ships first.
- **`terragrunt/root-hcl` v7.0.0 and `workflows/v7.0.0`** take the rest: the
  new kinds, the shorthand, and the refusals of the old kinds and keys.
- **The same majors carry LIB-0037 §6's refusal of the old layout.** Each of
  these is refused before planning, with a message naming LIB-0037:
  - a `workloads/<w>/values.yaml`, and a leaf at the old depth;
  - a `secrets.yaml` in a workload;
  - `zone.yaml`'s `workload`, which `hosts` replaced;
  - `features`, which `deployments` replaced;
  - `cloudflare.zone` in a workload, which its directory names.

  The old layout's branches leave root.hcl, `resolve-workloads.sh`,
  `terragrunt-run.yml`, `terragrunt-detect.yml`, `site-dispatch.yml` and
  `site-pages.yml`.
- **The two old modules are deprecated.** Their READMEs say so and point
  here. They get no new release, and their tags and short URLs stay, since a
  short URL is a public interface (LIB-0009). A hand-written leaf may still
  call them.
- **A spoke takes the workflows alone first** (LIB-0024 §5): `.lib-version`
  and every `@workflows/` ref, with no unit change. An apply runs `main`'s
  workflow, so a PR that also adds v7-only units fails apply's
  saved-plan comparison.

### 7. runway moves

runway uses both bundles: each of its four zones' and two workloads'
implicit deployers, the redirects in pigeon.dev and willowgraysen.com, and
its hand-written spoke deployer. LIB-0037's old workloads go first, in
runway's teardown PR.

1. **Pins:** `.lib-version` and the callers to `workflows/v7.0.0`, alone.
2. **Move, with runway frozen:** §5, locally, for the six unit deployers, the
   two redirects and the spoke deployer.
3. **Commit:** `root_hcl_version` 7.0.0, the regenerated `root.hcl`, and the
   spoke deployer's three leaves in place of its old one. Its plan must show
   `No changes.` for every moved leaf, and nothing to destroy in any old one.
4. **Check:** a re-plan of every leaf shows `No changes.`, and DNS and every
   redirect answer as before step 2.

## Consequences

- **One resource, one module.** A fix to `iam-api-key` or `dns-record` reaches
  every deployer and redirect at their next plan.
- **A deployer's policy plans apart from its key.** A permission change no
  longer touches the leaf every other leaf signs in with.
- **The clash checks lose their special cases** for a redirect's entrypoint
  and its `A` record. They keep one, for what may sit beside a redirect at
  `@` and `www`.
- **Every unit has two more leaves.** runway grows from six deployer leaves to
  eighteen, and from two redirect leaves to six. A new unit takes one more
  stage, since its application lands before its policy and key.
- **A zone file's redirect looks as it did,** but a plan names three leaves
  where it named one.
- **Every spoke moves its deployers' state once,** to new keys in the same
  bucket. Nothing is recreated and no key rotates.

## Out of scope

- **Deleting the two modules' sources from `main`.** Their tags keep them
  fetchable, and a hand-written leaf may still call them. Deferred until no
  spoke does
  ([#190](https://github.com/noisypigeon/library/issues/190)).
- **A `scaleway.iam.policy` kind for a workload's own application.** A
  workload's application and key have kinds, but its policy doesn't, so the
  application can't be granted anything from YAML. Deferred
  ([#191](https://github.com/noisypigeon/library/issues/191)).
- **Shorthands other than `apexRedirect`.** The expansion is the one LIB-0034
  §2 introduced, for one more key. A general macro language over the kind
  table is a design boundary.
- **Building §§1–7.** The module, template, scripts, schemas and runway's move
  ship in later PRs that cite this record. Deferred
  ([#192](https://github.com/noisypigeon/library/issues/192)).

## Verification

1. **Names don't change.** Each new leaf's rendered inputs give the
   application, policy, key, records and ruleset the names, comments and
   rules the bundle gave them.
2. **Wiring holds.** A `workload`-state leaf's rendered `remote_state` signs
   in with `iam-api-key/deployer`'s outputs, and its `workload`-credentials
   provider does too.
3. **Each is refused by name, before planning:**
   - a module input directly under `scaleway.deployer`;
   - `ObjectStorageFullAccess` dropped from
     `scaleway.deployer.policy.project_permission_sets`;
   - an input other than the four under an `apexRedirect` entry;
   - a stub under `scaleway/terraform-deployer-iam/` or
     `cloudflare/apex-redirect/`;
   - each of LIB-0037 §6's, in §6's list.
4. **State moved, not recreated.** Every new leaf planned `No changes.` before
   its old leaf was emptied, and no key's ID or expiry changed.
5. **It converges.** A re-plan of every leaf in runway shows `No changes.`,
   and DNS and both redirects answer as before.
