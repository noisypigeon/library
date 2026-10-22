# LIB-0028: Every workload gets its own project and state bucket

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-22.
- **Status**: Proposed. Amends LIB-0023, whose §1 state, §2 kind table and §4
  defaults change, and LIB-0024, whose §1 deployer becomes unconditional and
  whose §3 stages grow from three to four.

## Context

A LIB-0023 workload is one `workloads/<workload>/values.yaml`. Two things about
it are still the spoke's rather than its own.

- **Its state is in the spoke's bucket.** Every workload leaf's key is
  `workloads/<workload>/<provider>/<module>/<instance>/terraform.tfstate` in
  `spoke.hcl`'s `state_backend` (LIB-0023 §1).
  - The spoke's state key reaches every workload's state, so LIB-0024's
    isolation stops at the provider. A workload's resources are reachable only
    by its own key and the spoke's; its state is reachable by the spoke's
    alone.
  - A workload can't be lifted out, handed over or deleted as a unit. Its state
    is a prefix in a bucket it shares.
- **Its project is opt-in.** `scaleway.project` is an entry like any other, and
  LIB-0024's deployer exists only when it does. A workload without one puts
  its buckets in the provider's default project (LIB-0023 §4), signed in with
  the spoke's key. That's the arrangement LIB-0024 was written to end.

The fix is to make the boundary unconditional: a workload is a project, a
deployer that reaches only that project, and a versioned bucket in that project
holding the workload's state. None of the three should need a line in
`values.yaml`, and each should be overridable there.

## Decision

### 1. Project, deployer and state are implicit in every workload

- **`resolve-workloads.sh` generates three stubs for every `values.yaml`**,
  whatever it declares:
  - `workloads/<workload>/scaleway/project/main`;
  - `workloads/<workload>/scaleway/terraform-deployer-iam/main` (LIB-0024 §1,
    no longer conditional on a project entry);
  - `workloads/<workload>/scaleway/bucket/state`, the new kind
    `scaleway.state`.
- **Each key is optional and only overrides.** `scaleway.project`,
  `scaleway.deployer` and `scaleway.state` take their module's inputs by the
  module's own names, as `scaleway.deployer` already does. An empty file with
  a `suffix` is a valid workload.
- **There is no opt-out.** A workload without its own project, deployer or
  state bucket can't be written. Pointing one at an existing project or bucket
  is Out of scope.

### 2. The state bucket is a versioned `scaleway/bucket`

`scaleway.state` maps onto the `scaleway/bucket` module, as a singleton whose
instance is `state`. Its defaults, each overridable:

- **`name_prefix`** = `<prefix>`, and **`name_suffix`** = `terraform-state`.
  The module's random segment sits between them, giving LIB-0016's
  `<name>-<code>-terraform-state` shape.
- **`enable_versioning`** = `true`. The module's own default is `false`. A
  guard refuses `enable_versioning: false` for this kind: versioning is the
  state's only protection. There is no B2 copy, as there is none for any
  Scaleway state bucket (LIB-0007).
- **`force_destroy`** = `false` (§7).
- **`project_id`** is wired from the workload's project.

### 3. Keys sit under a prefix, `workloads/<workload>/` by default

- **`scaleway.state.prefix`** is the one input in this record that isn't a
  module's. It defaults to `workloads/<workload>/`. It must not start with
  `/`, and it must end with one.
- **A workload leaf's key is
  `<prefix><provider>/<module>/<instance>/terraform.tfstate`.** With the
  default, that's exactly `path_relative_to_include()`'s key, so LIB-0001
  invariant 4 holds unchanged. An override is a deliberate move, and moves
  every key in the workload's bucket at once.
- **The schema follows.** `scaleway.state` validates against the bucket's
  per-version `inputs.schema.json` plus `prefix` (LIB-0023 §6).

### 4. Each kind says where its state lives

LIB-0023 §2's kind table gains a `state` column beside LIB-0024's
`credentials`, in all three copies (root.hcl, `resolve-workloads.sh` and
`generate-module-redirects.sh`).

| Kind | Credentials | State | Why |
| --- | --- | --- | --- |
| `scaleway.project` | spoke | spoke bucket | it creates the project the workload bucket lives in |
| `scaleway.deployer` | spoke | spoke bucket | its key is what signs in to the workload bucket |
| `scaleway.state` | workload | spoke bucket | it *is* the workload bucket; the spoke key has no grants in the workload's project (LIB-0024 Context) |
| `scaleway.iam.application`, `scaleway.iam.apiKey` | spoke | workload bucket | |
| `scaleway.bucket` | workload | workload bucket | |

- **The bootstrap three stay in the spoke's bucket.** They make the workload
  bucket, so they can't keep state in it. Their keys don't change.
- **Credentials and state are separate columns.** The IAM kinds still sign
  their provider in with the spoke's key (LIB-0024 §2 Out of scope), while
  their state is the workload's.

### 5. The workload bucket's backend signs in with the workload's key

- **Every workload-bucket stub depends on `deployer` and `state`**, beyond the
  wiring §4 of LIB-0023 implies.
- **That stub declares its own `remote_state`**, which replaces root.hcl's
  through the include merge:
  - `bucket` is `dependency.state.outputs.module.name`;
  - `key` is §3's;
  - `access_key` and `secret_key` come from
    `dependency.deployer.outputs.module`, as a workload-credentials provider's
    already do;
  - everything else, including `use_lockfile` (LIB-0022), is root.hcl's
    `scaleway_state_config`, exposed to the stub.
- **The deployer's default `ObjectStorageFullAccess` covers it.** A guard
  fails a `scaleway.deployer.project_permission_sets` override that drops it,
  since the workload could then no longer read its own state.
- **If Terragrunt won't resolve dependency outputs inside a child's
  `remote_state`,** the stub passes the bucket and credentials to
  `terraform init` as `-backend-config` through `extra_arguments` instead.
  Verification 2 decides which.

### 6. A new workload lands in four stages

LIB-0024 §3's deferral is unchanged. Its stage list becomes:

1. the project;
2. the deployer;
3. the state bucket;
4. everything else, in the workload's bucket.

The IAM application, which was stage 1, now waits for stage 3, since its
state lives in the bucket stage 3 makes. LIB-0027 re-plans between stages by
itself.

### 7. Removing a workload takes two PRs

Destroys already run dependents first (LIB-0023's second amendment), so the
state bucket goes last. It still fails while the bucket holds noncurrent
versions and lock files, since `force_destroy` is off.

1. **Set `scaleway.state.force_destroy: true`**, and apply.
2. **Remove `values.yaml`**, and apply the destroys.

The bootstrap keys left in the spoke's bucket go with their leaves' destroys.

### 8. runway's `poc` is destroyed and recreated

`poc`'s application, API key and `scratch` bucket have state in runway's
bucket today. It's disposable (LIB-0023 §7), so it isn't migrated.

1. **On the current template**, remove `bucket.scratch`, `iam.application`
   and `iam.apiKey` from `workloads/poc/values.yaml`, and apply their
   destroys. Only the project and deployer remain.
2. **The workflows alone** (LIB-0024 §5).
3. **The template, and the three entries back.** Stage 3 creates `poc`'s state
   bucket, and stage 4 recreates the three in it.

A key a destroy leaves behind in runway's bucket under
`workloads/poc/scaleway/{bucket,iam-application,iam-api-key}/` is deleted by
hand.

### 9. Release impact

- **`terragrunt/root-hcl` takes a major version.** Every existing workload's
  plan changes: it gains a project, deployer and state bucket if it had none,
  and its non-bootstrap leaves read state from a new backend. A spoke with no
  `workloads/` plans `No changes.`
- **`workflows/` takes a minor version**, for `resolve-workloads.sh`'s new
  stubs, dependencies and `remote_state`, and the schema in
  `generate-module-redirects.sh`. A spoke takes it alone first (LIB-0024 §5).
- **`state-backup.yml` is unchanged.** Its `+ workloads/**` filter still
  backs up the bootstrap keys of an R2 spoke.

## Consequences

- **A workload's state is its own.** Its non-bootstrap state is reachable by
  its own key, and by the spoke's only through the spoke's organization IAM
  rights, which already create the deployer.
- **A workload is a unit.** One project, one key, one bucket, removable in two
  PRs.
- **Every workload costs a project and a bucket**, even one that only declares
  IAM objects. Versioning keeps every state write, so the bucket grows with
  each apply.
- **A new workload takes four applies, not three.** LIB-0027 re-plans between
  them, so it costs time, not comments.
- **The kind table grows another column**, still in three copies that must
  agree.
- **A deployer override can now break a workload's backend.** §5's guard
  catches the one known way.
- **A spoke with workloads has `1 + n` state buckets.** Finding a leaf's state
  means reading its workload's `scaleway.state`, or the stub's backend.

## Out of scope

- **Migrating an existing workload's state into its bucket.** `poc` is
  recreated. A key-for-key copy, under LIB-0016 §4's no-apply gate, comes when
  a workload that can't be recreated needs it. Deferred ([#137](https://github.com/noisypigeon/library/issues/137)).
- **Pointing a workload at an existing project, deployer or bucket.** Each is
  always the workload's own. Deferred ([#138](https://github.com/noisypigeon/library/issues/138)).
- **Workloads for providers other than Scaleway.** As LIB-0023 and LIB-0024;
  extends [#109](https://github.com/noisypigeon/library/issues/109).
- **Building §§1–9.** The template, scripts, schema and runway's adoption ship
  in later PRs that cite this record ([#139](https://github.com/noisypigeon/library/issues/139)).

## Verification

1. **A workload needs no keys.** A `values.yaml` with only `prefix` and
   `suffix` generates the project, deployer and state stubs, and lands in
   stages 1 to 3.
2. **State lands in the workload's bucket.** After stage 4, the workload's
   leaves' keys are under `workloads/<workload>/` in its own bucket, and no
   new key under that path appears in the spoke's bucket. This also decides
   §5's mechanism.
3. **The bucket is versioned.** Its versioning reads `Enabled`, and a second
   apply leaves a noncurrent version of a state object.
4. **A prefix override moves keys.** Setting `scaleway.state.prefix` plans
   from the new keys.
5. **The guards hold.** `enable_versioning: false` on `scaleway.state`, and a
   deployer override without `ObjectStorageFullAccess`, each fail before any
   plan runs.
6. **`poc` converges.** After §8, a re-plan of every `poc` leaf shows
   `No changes.`, and every hand-written leaf in runway does too.
