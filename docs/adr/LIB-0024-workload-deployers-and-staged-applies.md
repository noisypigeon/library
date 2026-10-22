# LIB-0024: Workload deployers, and staged applies

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-20.
- **Status**: Accepted. Amends LIB-0023, which gains a kind and a credentials
  column, and LIB-0022, whose merge gate now waits for every stage.

## Context

LIB-0023's proof of concept failed at its first project-scoped resource. In
noisypigeon/runway#35, the POC bucket's apply stopped at `CreateBucket` with
`403 AccessDenied`, while the IAM API key in the same run was created.

The cause is runway's deployer, `terraform/scaleway/terraform-deployer-iam/runway`
(LIB-0014). Every leaf in the spoke signs in with its key.

- **Organization grants:** `ProjectManager`, `IAMManager` and
  `IAMApplicationManager`. So it can create a workload's project and its IAM
  objects.
- **Project grants:** `ObjectStorageFullAccess` and nine more, but only for
  `project_ids = [runway's project]`. So it can create nothing inside a project
  it made for a workload.

Widening that list per workload would work, but every new `values.yaml` would
then need a hand edit to a hand-written leaf. It would also leave one key able
to reach every workload's project. A workload should be able to bootstrap
itself, with credentials that reach only its own project.

Two constraints from the records it builds on make that harder than it sounds.

- **Dependents can't be planned before their dependencies exist.** LIB-0022
  applies only the saved plan, so a stub's `dependency` blocks carry no
  `mock_outputs` (LIB-0023's first 2026-10-20 amendment). A credential a leaf
  depends on has to be applied before that leaf can plan.
- **A rotated key must not outlive a saved plan.** If a key a plan was made
  with is replaced before that plan is applied, the apply fails.

runway#32 and #34 also surfaced an ordering rule. GitHub runs an
`issue_comment` workflow from the default branch, so a PR's `terragrunt apply`
always runs `main`'s callers, whatever the PR changes. #32's apply was refused
because its plan had run newer selection logic than its apply. That would have
been worse had the units happened to match.

## Decision

### 1. Every workload with a project gets its own deployer

- **It's implicit.** Whenever a `values.yaml` declares `scaleway.project`,
  `resolve-workloads.sh` also generates
  `workloads/<workload>/scaleway/terraform-deployer-iam/main`. It needs no
  entry. An optional `scaleway.deployer` mapping overrides its inputs, by the
  module's own names.
- **Its defaults:**
  - `name`: `<prefix>-<suffix>-deployer`.
  - `project_permission_sets`: `["ObjectStorageFullAccess"]`, the union of
    what today's project-scoped kinds need. It grows when a kind needs more.
  - `rotation_days`: 30 (§4).
  - No organization grants at all.
- **It's wired from the workload's project:** `project_ids` is
  `[project.id]`, and `default_project_id` is `project.id`.
- **It runs with the spoke's key,** whose organization IAM rights are what
  create it. The spoke's deployer stays the root of every workload's project
  and IAM objects.

### 2. Each kind says whose credentials it runs with

LIB-0023 §2's kind table gains a `credentials` column, in all three of its
copies (root.hcl, `resolve-workloads.sh` and `generate-module-redirects.sh`).

| Kind | Credentials | Why |
| --- | --- | --- |
| `scaleway.project` | spoke | creating a project needs organization `ProjectManager` |
| `scaleway.deployer` | spoke | it is the workload's credential, so it can't sign itself in |
| `scaleway.iam.application`, `scaleway.iam.apiKey` | spoke | IAM objects are organization-scoped. A workload key with organization IAM rights could reach every workload |
| `scaleway.bucket` | workload | project-scoped |

- **A workload-credentials stub depends on the deployer,** and passes
  `scaleway_access_key` and `scaleway_secret_key` from
  `dependency.deployer.outputs.module`.
- **root.hcl** declares those two as `sensitive` variables in
  `workload_generated.tf`. For such a leaf, `provider "scaleway"` reads them
  in place of the spoke's key.
  - The state backend still uses the spoke's state key (LIB-0010).
  - No credential is written into a generated file. The values arrive as
    `TF_VAR_`s, and the saved plan that holds them is encrypted
    (LIB-0022 §2).
- **Wiring is typed.** The table's `wiring` becomes a map of input name to
  Terraform type, since the deployer's `project_ids` is a `list(string)`.

### 3. A dependent plans only against settled dependencies

`terragrunt-run.yml` plans a spoke's workload leaves one at a time, in
`terragrunt find --dag` order.

- **A unit is deferred** if any of its workload dependencies is deferred, or
  has a plan with changes, which includes being created.
- **Otherwise it plans on its own,** with `-detailed-exitcode`. 0 means
  settled. 2 means changed, which defers its dependents. Anything else is an
  error.
- **A deferred unit has no saved plan.** It's written into `units.txt` as
  `deferred: <unit>`, so apply's comparison covers it too. The PR comment
  lists it under "Deferred until its dependencies are applied".
- **Apply applies the planned units,** in DAG order, as before.
- **The merge gate waits for every stage.** It amends LIB-0022, which turned
  `terragrunt/apply` green on any successful apply. Now, after an apply whose
  plan deferred units, it stays `pending`, described as "deferred units
  remain; comment terragrunt plan". The re-plan picks up the next stage.
- **A new workload therefore lands in one PR,** in stages:
  1. its project and IAM application;
  2. its deployer, and its API keys;
  3. everything that runs with the workload's own key.

  Each stage is an apply followed by a `terragrunt plan` comment.

Hand-written leaves, and the destroys of removed instances (LIB-0023's second
amendment), are unchanged.

### 4. The workload deployer's key rotates

- **`scaleway/terraform-deployer-iam` gains `rotation_days`.** When it's set,
  a `time_rotating` resource triggers the key's replacement, with
  `create_before_destroy`, every `rotation_days`. The key expires a week
  after each scheduled rotation. When it's unset, the module keeps today's
  30-day expiry from `time_static`. An explicit `expires_at` still wins.
- **§3 is what makes rotation safe.** When a rotation is due, the deployer's
  plan shows a replace. Its dependents defer, the apply rotates the key, and
  the re-plan signs them in with the new one. A saved plan never holds a key
  that is about to be destroyed.
- **The week's grace** covers a month in which nothing plans the workload. A
  workload untouched for longer still recovers on its own: its first plan
  replaces the key with the spoke's credentials, and its dependents follow on
  the re-plan.

### 5. A spoke takes a selection change in its workflows alone

Because an apply runs the default branch's callers (Context), a `workflows/`
release that changes which units are selected is taken in two PRs.

1. **The workflows alone:** `.lib-version` and the callers. Its plan selects
   nothing, so it merges without an apply.
2. **Everything else:** the template bump and any workload change. Its plan
   and apply then run the same selection.

This applies to LIB-0023's `workflows/v4.2.0` and to this record's release
alike.

## Consequences

- **A `values.yaml` is self-sufficient.** No hand-written leaf changes to
  add a workload, and each workload's project-scoped resources are reachable
  only by its own key and the spoke's.
- **A new workload takes three applies, not one.** Each needs a re-plan
  comment in between. The PR comment says which stage it's at.
- **A rotation costs two applies** every 30 days, on the next plan to touch
  the workload.
- **Planning a workload is slower.** Its leaves plan one at a time. Today
  that's a handful of leaves, about 10 to 20 seconds each.
- **The kind table grows a column**, still in three copies that must agree.

## Out of scope

- **Organization-scoped kinds under the workload key.** IAM objects stay with
  the spoke's key. A permanent boundary, since a workload key with
  organization IAM rights would reach every workload.
- **Workload deployers for other providers.** Scaleway only, as LIB-0023 is.
  Deferred ([#109](https://github.com/noisypigeon/library/issues/109)).
- **Deriving a deployer's permission sets from its workload's kinds.** Today
  it's one fixed set, overridable in `values.yaml`. Deferred ([#110](https://github.com/noisypigeon/library/issues/110)).
- **Rotating the keys of workloads nobody plans.** Covered for a week by §4's
  grace, and for longer by its recovery. A scheduled re-plan would close the
  gap. That's LIB-0023's #100, which this extends ([#111](https://github.com/noisypigeon/library/issues/111)).
- **Building §§1–5.** The module, template and workflow changes, and runway's
  adoption, ship in later PRs that cite this record ([#108](https://github.com/noisypigeon/library/issues/108)).

## Verification

Recorded 2026-10-21 and 2026-10-22, against runway's `workloads/poc`. Every
item passed.

1. **A new workload bootstraps in one PR.** A fresh `values.yaml` with a
   project, an application, an API key and a bucket plans in three stages,
   and each stage's apply succeeds. The gate goes green only after the third.
   - **Passed, from an existing workload:** [runway#38](https://github.com/noisypigeon/runway/pull/38)
     planned the new deployer and deferred the bucket. It applied that stage,
     with the gate left pending and no auto-merge. It then re-planned the
     bucket, and applied it. A fresh workload from nothing is the same path
     with one more stage.
2. **The bucket signs in with the workload's key.** Its apply succeeds in a
   project the spoke's deployer has no project grants on, which is where
   runway#35 failed.
   - **Passed:** #38's second apply created `poc-scratch-8nx0we-lib-0023` in
     the POC project, signed in with the POC deployer's key.
3. **Rotation defers.** With rotation forced, the deployer's plan replaces
   the key, and the bucket is deferred. After the apply, the re-plan shows the
   bucket `No changes.`, signed in with the new key.
   - **Passed:** on [runway#42](https://github.com/noisypigeon/runway/pull/42), forcing rotation
     (`scaleway.deployer.rotation_days: 1`) planned the API key "must be
     replaced", and deferred the bucket. On [runway#48](https://github.com/noisypigeon/runway/pull/48), the
     rotation was applied, and the re-plan after it showed the bucket
     `No changes`, signed in with the new key.
4. **Adoption selects nothing first.** runway's workflows-only PR plans no
   units.
   - **Passed:** [runway#37](https://github.com/noisypigeon/runway/pull/37) and [#40](https://github.com/noisypigeon/runway/pull/40)
     changed only `.lib-version` and the callers, and selected nothing.
