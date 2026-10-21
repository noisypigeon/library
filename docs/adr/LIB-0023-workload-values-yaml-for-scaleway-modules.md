# LIB-0023: A workload `values.yaml` for Scaleway modules

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Proposed; amended 2026-10-20 (see `## Amendments`). Adds a second home for leaves, `workloads/`, beside
  `terraform/`. Makes bounded exceptions to LIB-0001 invariants 2 and 4 for
  those leaves only. LIB-0004's layout does not govern them.

## Context

LIB-0004 gives every leaf one module and one path. That made a module's blast
radius easy to find, and it made a workload hard to read. A workload is
the set of resources one thing needs. pigeon-cli's in runway is spread over
at least six leaves:

- `terraform/scaleway/bucket/pigeon-cli-email`
- `terraform/scaleway/bucket/pigeon-cli-email-reports`
- `terraform/scaleway/iam-application/pigeon-cli`
- `terraform/scaleway/iam-application/pigeon-cli-grafana`
- `terraform/scaleway/iam-api-key/pigeon-cli-grafana`
- `terraform/scaleway/iam-policy/pigeon-cli-grafana`

Each leaf repeats the same three kinds of boilerplate.

- **Names, by hand.** `bucket/pigeon-cli-email` has a `bucket_definition.tf`
  whose only job is `name_prefix = "pigeon-cli"` and `name_suffix = "email"`.
  The sibling leaves carry the same two words again.
- **Versions, by hand.** Every leaf pins its own
  `noisypigeon.garden/terraform/scaleway/<module>/vX.Y.Z`. A module release
  reaches a workload only after one edit per leaf, so in practice versions
  drift apart within one workload.
- **Wiring, by hand.** `iam-api-key/pigeon-cli-grafana` declares
  `variable "application_id"` and gets it from a hand-written `dependency`
  block. LIB-0004 §2 named this cost when it split multi-module leaves:
  "dependency edges that were implicit inside one state file become explicit
  between two".

None of that boilerplate decides anything. Given a workload's name and the
modules it uses, all of it follows. Crossplane's answer to the same problem is
one declarative document per workload, with the controller filling in names
and references. This record adopts that shape on top of Terragrunt, for the
Scaleway modules only. It leaves LIB-0004's guarantees alone: one module per
leaf, and a state key that follows from the path.

## Decision

### 1. A workload is `workloads/<workload>/values.yaml`, at the repo root

- **The file sits at the spoke's repo root**, beside `terraform/`, not inside
  it. A workload is a different kind of thing from a hand-written leaf, and the
  path says so.
- **Its leaves sit beside it**, at
  `workloads/<workload>/<provider>/<module>/<instance>/`. Below
  `workloads/<workload>/`, that is LIB-0004's `<provider>/<module>/<instance>`
  shape, but LIB-0004's rules for `terraform/` do not govern it.
- **State belongs to the template, not to the file.** `values.yaml` names no
  backend, bucket or key. Each leaf's key is `path_relative_to_include()`, the
  same arithmetic as LIB-0001 invariant 4, in the spoke's existing state bucket
  (`spoke.hcl`'s `state_backend`):
  `workloads/<workload>/scaleway/bucket/<key>/terraform.tfstate`.
  - A workload key can never collide with a `terraform/` key, because the
    first segment differs.
  - A workload key never moves unless its path does.
- **`<workload>` is kebab-case** and unique in the spoke. It usually equals
  the file's `prefix`, but nothing requires that.

The file:

```yaml
# yaml-language-server: $schema=https://noisypigeon.garden/schemas/workload/v1.json
prefix: pigeon-cli
suffix: email

scaleway:
  project:
    version: "2"            # optional; see §3
    description: pigeon-cli email ingestion
  bucket:
    example:
      storage_class: standard
      expiration_days: 30
  iam:
    application: {}
    apiKey:
      expires_at: "2027-10-20T00:00:00Z"
```

### 2. Kinds map one-to-one onto hub modules

A fixed table in the template maps each YAML key to one hub module. Below the
key, everything except `version` is that module's own input, by its own
snake_case name, passed through unchanged.

| YAML key | Module | Shape | `<instance>` |
| --- | --- | --- | --- |
| `scaleway.project` | `scaleway/project` | singleton | `main` |
| `scaleway.bucket.<key>` | `scaleway/bucket` | map | `<key>` |
| `scaleway.iam.application` | `scaleway/iam-application` | singleton | `main` |
| `scaleway.iam.apiKey` | `scaleway/iam-api-key` | singleton | `main` |

- **Kind keys are camelCase; inputs are snake_case.** A kind is this
  interface's own name. An input belongs to the module, and renaming it here
  would create a second name for each input.
- **An unknown kind fails the run.** A new kind arrives as an amendment to
  this record and a template release, never by convention.
- **A singleton is still a leaf.** Its instance is `main`, so every workload
  leaf has the same depth.

### 3. Unpinned means the newest release, resolved at every plan

- **`version` is optional.**
  - `X.Y.Z` pins exactly.
  - `X.Y` takes the newest `X.Y.*`.
  - `X` takes the newest `X.*.*`.
  - No `version` takes the newest `terraform/scaleway/<module>/v*` tag.
- **Resolution runs at every plan, not at commit time.** The template calls
  `.github/scripts/resolve-module-version.sh <provider>/<module> [<version>]`
  through `run_cmd`. The script runs `git ls-remote --tags` against this repo
  and prints one `X.Y.Z`. The leaf's `terraform.source` becomes
  `https://noisypigeon.garden/terraform/<provider>/<module>/v<X.Y.Z>`, the
  same short URL a hand-written leaf uses (LIB-0009).
- **This is an exception to LIB-0001 invariant 2**, and it is bounded.
  - It applies only to workload leaves.
  - It is still a tag, never a branch.
  - Every other pin stays exact: `/.lib-version`, `root_hcl_version`, and
    every hand-written leaf.
- **LIB-0022 is what makes it safe.** Apply runs the saved plan for the PR's
  head SHA and nothing else. A release that lands between plan and apply
  cannot reach state unreviewed. The plan comment shows the resolved version,
  because it is part of the source Terraform prints at `init`.

### 4. Names and wiring default from the workload

Each default applies only when the input is absent. Any input written in the
file wins.

- **Names.**
  - `project.name` = `<prefix>-<suffix>`.
  - `bucket.<key>.name_prefix` = `<prefix>-<key>`, and
    `name_suffix` = `<suffix>`. The module's random segment sits between them,
    as it does today.
  - `iam.application.name` = `<prefix>-<suffix>`.
- **Wiring, within one workload only.**
  - `bucket.<key>.project_id` comes from the workload's `project`.
  - `iam.apiKey.default_project_id` comes from the workload's `project`.
  - `iam.apiKey.application_id` comes from the workload's
    `iam.application`.
- **A default that needs a kind the file doesn't declare is not applied.** A
  bucket in a workload with no `project` takes the provider's default project,
  as the module already does.

### 5. Generated stubs hold the structure; the template does the rest at plan time

- **`.github/scripts/resolve-workloads.sh` turns each `values.yaml` into stub
  leaves.** A stub is a `terragrunt.hcl` that:
  - includes `root.hcl`;
  - declares the `dependency` blocks its kind implies under §4, each with
    `mock_outputs` so a first plan works before anything is applied.
- **The stubs are committed**, for the same reason resolve-root-hcl.sh's copies
  are (LIB-0003): Terragrunt's git filter plans inside worktrees, where only
  tracked files exist. CI runs the script with `--check` and fails on drift.
- **A stub holds no values and no versions.** Only adding or removing an
  instance or a kind changes the stubs. Editing an input or a `version` changes
  only `values.yaml`.
- **root.hcl accepts a second leaf root.** Today `is_valid_leaf` requires a
  first path segment of `terraform`, and the `exclude` block skips anything
  else. It now accepts `terraform` or `workloads`. A leaf whose first segment is
  `workloads` is a workload leaf, and for it the template:
  1. reads the workload's `values.yaml`, found with `find_in_parent_folders`,
     through `yamldecode(file(...))`, and marks
     it read with `mark_as_read`. Terragrunt's filter then re-plans every leaf
     that reads a changed `values.yaml`;
  2. picks the leaf's slice of the file from the path's
     `<provider>/<module>/<instance>`, through §2's table;
  3. applies §4's defaults, taking IDs from the stub's `dependency` outputs;
  4. resolves the version per §3 and sets `terraform.source`;
  5. passes the result as `inputs`.
- **Providers, secrets and the backend are unchanged.** A workload leaf is a
  leaf.
  - spoke.hcl's `providers` map turns Scaleway on for it the same way
    (LIB-0005). A `leaves` prefix such as `workloads/` works as written.
  - Secrets stay in `terraform/secrets/` (LIB-0012). They are the spoke's, not
    a workload's.
  - The backend is the spoke's one state bucket, per §1.

### 6. A JSON Schema, generated from each module version

- **Each Scaleway module release publishes its inputs as a JSON Schema**, at
  `noisypigeon.garden/terraform/scaleway/<module>/v<X.Y.Z>/inputs.schema.json`.
  It is generated from that version's `inputs.tf`.
- **One workload schema ties them together**, at
  `noisypigeon.garden/schemas/workload/v1.json`.
  - A kind with no `version` validates against its newest version's schema.
  - A kind with a `version` validates against that version's schema, through
    an `if`/`then` on `version`.
- **`generate-module-redirects.sh` writes both**, since it already turns this
  repo's tags into garden pages.
- **Editors validate as you type**, from the `yaml-language-server` comment in
  §1. CI validates with `resolve-workloads.sh --check`. A misspelt input then
  fails in the PR, not at `terraform plan`.

### 7. A proof of concept on new, disposable resources

- **runway adds one workload, `workloads/poc/values.yaml`.** It
  declares:
  - a new `project`;
  - one bucket, `scratch`, with `storage_class: standard`, `expiration_days: 1`
    and `force_destroy: true`;
  - an `iam.application`;
  - an `iam.apiKey`.

  Everything else stays at its default, and nothing is pinned.
- **No existing leaf, state key or resource changes.** pigeon-cli's leaves stay
  hand-written until Verification passes. Importing their state into workload
  leaves comes after that (Out of scope).
- **`poc` stays the only workload** until then.

### 8. Release impact

The spoke CI also assumes that every leaf is under `terraform/`.

- **`terragrunt/root-hcl` takes a minor version:** §5's second leaf root and
  the workload handling. A spoke with no `workloads/` plans `No changes.`
- **`workflows/` takes a minor version**, for two path assumptions and the
  scripts:
  - **`terragrunt-detect.yml`**'s default `paths` regex gains `^workloads/`.
    A spoke caller that overrides it adds the same. Without it, a PR that
    touches only a workload never plans.
  - **`state-backup.yml`**'s rclone filters, on the copy and on both sides of
    its post-copy check, gain `+ workloads/**`. Without it, workload state is
    never backed up to B2 (LIB-0007).
  - `resolve-module-version.sh` and `resolve-workloads.sh` live in
    `.github/scripts/`, so they ride this track too.
- **runway adopts in its own PR**, template and workflows first, then
  `workloads/poc/`.

## Consequences

- **A workload reads as one file.** Names, versions and wiring follow from
  `prefix`, `suffix` and the kinds declared. The six-leaf boilerplate in the
  Context comes down to a few lines of YAML.
- **A module release can change a spoke's plan with no spoke commit.** Nothing
  plans until something triggers it. The drift shows up on the workload's next
  plan, or on a `terragrunt plan` comment (LIB-0022 §1).
- **A major release can break an unpinned workload's plan.** Pinning a major,
  `version: "5"`, keeps a workload on its current major. Pinning is a one-line
  change to `values.yaml`.
- **The template gets more complex.** It parses YAML, applies defaults, and
  makes a network call per workload leaf per plan. A tag lookup that fails
  fails the plan. It never falls back to an older version.
- **A spoke has two homes for Terraform**, `terraform/` and `workloads/`.
  `ls terraform/scaleway/bucket/` no longer lists every bucket in a spoke.
  Finding every consumer of a module now also means grepping each
  `values.yaml`.
- **Both homes share one state bucket and one backup.** A workload costs no new
  bucket, key or secret.

## Out of scope

- **Providers other than Scaleway.** Cloudflare, Backblaze and Grafana keep
  hand-written leaves. Deferred ([#96](https://github.com/noisypigeon/library/issues/96)).
- **More Scaleway kinds**, `iam-policy` first. An API key without a policy
  grants nothing, so the POC proves only the mechanism. Deferred
  ([#97](https://github.com/noisypigeon/library/issues/97)).
- **Importing state from hand-written leaves into workload leaves**, once the
  POC passes Verification. It is a `state pull`/`push` per leaf, within the one
  bucket, under LIB-0004 §3's gates, with no resource changes. Deferred ([#98](https://github.com/noisypigeon/library/issues/98)).
- **References between workloads.** §4 wires within one file only.
  Deferred ([#99](https://github.com/noisypigeon/library/issues/99)).
- **A scheduled re-plan to surface floating-version drift.** Deferred
  ([#100](https://github.com/noisypigeon/library/issues/100)).
- **Building §§3–8.** This record decides the design. The template, scripts,
  schema generation and runway's POC ship in later PRs that cite it
  ([#95](https://github.com/noisypigeon/library/issues/95)).

## Verification

To be completed when §§3–8 ship.

1. **The stubs match the file.** `resolve-workloads.sh --check` passes in
   runway, and fails after a bucket key is added to `values.yaml` without
   regenerating.
2. **The POC touches only itself.** The first plan of
   `workloads/poc/` creates four modules' resources, all under that
   path, and every other leaf plans `No changes.`
3. **It converges, in the same bucket.** The apply writes keys under
   `workloads/poc/` in runway's existing state bucket, and nothing else. A
   second plan of every `poc` leaf shows `No changes.`
4. **Latest is latest.** A `scaleway/bucket` release, with no runway commit,
   appears as a new source version on a `terragrunt plan` comment.
5. **A pin holds.** Setting `version` to the previous `X.Y.Z` plans that
   version.
6. **The schema rejects a typo.** A misspelt bucket input fails
   `resolve-workloads.sh --check` before any plan runs.
7. **It tears down.** Removing `bucket.scratch` from `values.yaml` and
   regenerating plans the destroy of that leaf only.
8. **It is backed up.** The next `state-backup.yml` run copies the
   `workloads/poc/` keys to B2, and its post-copy check passes.

## Amendments

### 2026-10-20: what planning the build changed

Planning #95 against the code found four places where §§3–7 can't work as
written. The design is otherwise unchanged.

1. **§3: the version is resolved inside root.hcl, not by a script.**
   Terragrunt's `[main...HEAD]` filter plans inside git worktrees, which hold
   only tracked files. `.lib-src/` is gitignored, so `run_cmd` would find no
   `resolve-module-version.sh` there. The only files beside a spoke's
   `root.hcl` are the template's own committed copies.
   - root.hcl calls `run_cmd` on
     `git ls-remote --sort=-v:refname --tags <library> refs/tags/terraform/scaleway/<module>/v<pin>*`
     and takes the first line. git's version sort needs no shell and no new
     file.
   - There is no `resolve-module-version.sh`.
2. **§5: root.hcl writes a wrapper module; it does not set
   `terraform.source`.** Pointing `terraform.source` at the module would put
   root.hcl's generated `required_providers` block beside the module's own,
   and Terraform allows only one per module.
   - A workload leaf keeps `source = get_terragrunt_dir()`, as a hand-written
     leaf does.
   - root.hcl generates `workload_generated.tf`: a `module "this"` block at
     the resolved short URL, and `output "module" { value = module.this }`.
     A hand-written leaf writes the same thing by hand.
   - The entry's inputs are written into that block as literals. A
     `type = any` variable set through `TF_VAR_` arrives as a string, so a list
     or object input passed as a variable would break. Only the wiring inputs
     are variables, set by the stub from its dependencies' outputs.
3. **§5 and §7: no `mock_outputs`.** Under LIB-0022, apply runs the saved plan.
   A bucket planned with a mock project ID, before its project exists, would
   apply that mock.
   - A stub's `dependency` blocks have no mocks. A leaf plans only once its
     dependencies are applied, as runway's hand-written leaves already do.
   - The POC therefore lands in two runway PRs: `project` and
     `iam.application` first, then `bucket.scratch` and `iam.apiKey`.
4. **§6: the per-version schema has no `required`, and it allows `version`.**
   §4's defaults fill inputs a module requires, such as `name` and
   `application_id`, so the module's own `required` list would reject a valid
   file. Terraform still rejects a missing input at plan time. Each schema
   sets `additionalProperties: false`, which is what catches a misspelt
   input, and so it has to list `version` itself.

**Verification 8 runs elsewhere.** `state-backup.yml` copies R2 to B2, and only
spokes whose state is on R2 call it. runway's state is on Scaleway. So the new
`+ workloads/**` filter is proved against garden's R2 bucket, by comparing
`rclone lsf` with and without it.
