# LIB-0023: A workload `values.yaml` for Scaleway modules

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Proposed. Amends LIB-0004 §1 with a second leaf layout, and makes
  a bounded exception to LIB-0001 invariant 2 for that layout only.

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

### 1. A workload is `terraform/workloads/<workload>/values.yaml`

- **The file sits under `terraform/`**, not at the repo root. That keeps
  LIB-0001 invariant 4: leaves under `terraform/`, state keyed by their path.
  It also keeps root.hcl's `is_valid_leaf`, which excludes any leaf whose
  first segment is not `terraform`.
- **Its leaves sit beside it**, at
  `terraform/workloads/<workload>/<provider>/<module>/<instance>/`. This is a
  second exception to LIB-0004 §1's "exactly three segments", after LIB-0008's
  zone leaves. Below `workloads/<workload>/`, the path is LIB-0004's
  `<provider>/<module>/<instance>`.
- **The state key follows from the path, as always:**
  `terraform/workloads/<workload>/scaleway/bucket/<key>/terraform.tfstate`.
  The template needs no change for that.
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
- **root.hcl takes a minor release** that recognizes a leaf under
  `terraform/workloads/`. For such a leaf it:
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
  leaf. spoke.hcl's `providers` map turns Scaleway on for it the same way
  (LIB-0005).

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

- **runway adds one workload, `terraform/workloads/poc/values.yaml`.** It
  declares:
  - a new `project`;
  - one bucket, `scratch`, with `storage_class: standard`, `expiration_days: 1`
    and `force_destroy: true`;
  - an `iam.application`;
  - an `iam.apiKey`.

  Everything else stays at its default, and nothing is pinned.
- **No existing leaf, state key or resource changes.** pigeon-cli's leaves stay
  hand-written until Verification passes and a later record decides whether to
  move them.
- **`poc` stays the only workload** until then.

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
- **Two leaf layouts coexist.** `ls terraform/scaleway/bucket/` no longer lists
  every bucket in a spoke. Finding every consumer of a module now means also
  grepping each `values.yaml`.

## Out of scope

- **Providers other than Scaleway.** Cloudflare, Backblaze and Grafana keep
  hand-written leaves. Deferred ([#96](https://github.com/noisypigeon/library/issues/96)).
- **More Scaleway kinds**, `iam-policy` first. An API key without a policy
  grants nothing, so the POC proves only the mechanism. Deferred
  ([#97](https://github.com/noisypigeon/library/issues/97)).
- **Moving existing leaves into a workload.** That is a state move per leaf,
  under LIB-0004 §3. Deferred ([#98](https://github.com/noisypigeon/library/issues/98)).
- **References between workloads.** §4 wires within one file only.
  Deferred ([#99](https://github.com/noisypigeon/library/issues/99)).
- **A scheduled re-plan to surface floating-version drift.** Deferred
  ([#100](https://github.com/noisypigeon/library/issues/100)).
- **Building §§3–7.** This record decides the design. The template, scripts,
  schema generation and runway's POC ship in later PRs that cite it
  ([#95](https://github.com/noisypigeon/library/issues/95)).

## Verification

To be completed when §§3–7 ship.

1. **The stubs match the file.** `resolve-workloads.sh --check` passes in
   runway, and fails after a bucket key is added to `values.yaml` without
   regenerating.
2. **The POC touches only itself.** The first plan of
   `terraform/workloads/poc/` creates four modules' resources, all under that
   path, and every other leaf plans `No changes.`
3. **It converges.** After apply, a second plan of every `poc` leaf shows
   `No changes.`
4. **Latest is latest.** A `scaleway/bucket` release, with no runway commit,
   appears as a new source version on a `terragrunt plan` comment.
5. **A pin holds.** Setting `version` to the previous `X.Y.Z` plans that
   version.
6. **The schema rejects a typo.** A misspelt bucket input fails
   `resolve-workloads.sh --check` before any plan runs.
7. **It tears down.** Removing `bucket.scratch` from `values.yaml` and
   regenerating plans the destroy of that leaf only.
