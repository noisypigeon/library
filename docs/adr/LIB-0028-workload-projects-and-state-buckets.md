# LIB-0028: Every workload gets its own project and state bucket

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-22.
- **Status**: Accepted; amended twice on 2026-10-22 (see `## Amendments`). Amends LIB-0023, whose §1 state, §2 kind table and §4
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

Recorded 2026-10-22, against runway's `workloads/poc` and a scratch spoke.
Items 3 and 4 remain open, and so does part of item 2.

1. **A workload needs no keys.** A `values.yaml` with only `prefix` and
   `suffix` generates the project, deployer and state stubs, and lands in
   stages 1 to 3.
   - **Passed locally:** on a scratch spoke, such a file generated exactly
     those three stubs. `terragrunt find --dag` ordered them project, deployer,
     state bucket, without fetching any outputs.
   - **Landed in runway from an existing project:**
     [runway#54](https://github.com/noisypigeon/runway/pull/54) created the
     state bucket as its own stage, with everything that depends on it
     deferred. A workload with no project yet is the same path, plus two
     earlier stages.
2. **State lands in the workload's bucket.** After stage 4, the workload's
   leaves' keys are under `workloads/<workload>/` in its own bucket, and no
   new key under that path appears in the spoke's bucket. This also decides
   §5's mechanism.
   - **§5 is decided: dependency outputs in the stub's `remote_state` work.**
     On runway#54, the stage after the state bucket's apply initialised the
     bucket, the IAM application and the API key against the workload's
     bucket, signed in with the deployer's key, and applied them. The
     `-backend-config` fallback isn't needed.
   - **Open:** the keys haven't been listed, in either bucket. runway's bucket
     also still holds those three leaves' keys from before
     [runway#52](https://github.com/noisypigeon/runway/pull/52) destroyed
     them, which §8 says to delete by hand.
3. **The bucket is versioned.** Its versioning reads `Enabled`, and a second
   apply leaves a noncurrent version of a state object.
   - **Half passed:** runway#54's plan created the bucket with versioning
     `enabled = true`.
   - **Open:** no workload-bucket leaf has been applied twice yet, so no
     noncurrent version exists to check.
4. **A prefix override moves keys.** Setting `scaleway.state.prefix` plans
   from the new keys.
   - **Passed locally, not in runway:** on a scratch spoke, an override of
     `custom/<workload>/` gave `custom/<workload>/scaleway/<module>/<instance>/terraform.tfstate`.
     No runway workload overrides it.
5. **The guards hold.** `enable_versioning: false` on `scaleway.state`, and a
   deployer override without `ObjectStorageFullAccess`, each fail before any
   plan runs.
   - **Passed locally:** `resolve-workloads.sh` and root.hcl each refused all
     of these, by name, before anything planned:
     - versioning off;
     - `glacier` (the second amendment);
     - a deployer without `ObjectStorageFullAccess`;
     - a prefix starting with `/`;
     - a `scaleway.bucket.state` entry (only `resolve-workloads.sh` was
       tested on this one);
     - a stub without `remote_state` (root.hcl only).

     A hand-written leaf rendered identically under v4.5.0 and v5.0.0.
6. **`poc` converges.** After §8, a re-plan of every `poc` leaf shows
   `No changes.`, and every hand-written leaf in runway does too.
   - **Passed:** §8 ran as runway#52, #53 and #54, and the storage-class fix
     as [runway#55](https://github.com/noisypigeon/runway/pull/55). The
     automatic re-plan after #55's apply showed `No changes.` on all 28
     leaves, and the PR merged itself.

## Amendments

### 2026-10-22: what building it changed

Building §§1–5 ([#141](https://github.com/noisypigeon/library/pull/141) for the
scripts, and the `terragrunt/root-hcl` v5.0.0 PR for the template) found three
things the record didn't say.

1. **`state` is a reserved `scaleway.bucket` key.** The state bucket's stub is
   `workloads/<workload>/scaleway/bucket/state`, the path a bucket entry named
   `state` would also take. `resolve-workloads.sh`, the template and the
   schema all refuse one.
2. **`scaleway.state` has a schema file of its own.** Each module's
   `inputs.schema.json` sets `additionalProperties: false`, and a `$ref` can't
   relax that to admit `prefix`. So every `scaleway/bucket` version also
   publishes `state.schema.json`: its inputs plus `prefix`.
3. **The template refuses an old stub.** A workload-state leaf whose stub
   declares no `remote_state`, as a `resolve-workloads.sh` older than
   `workflows/v4.9.0` generates, would keep its state in the spoke's bucket
   without a word. root.hcl fails it instead.

The stub's `remote_state` reads dependency outputs, as §5 hoped. `terragrunt
find --dag` orders a workload's stubs project, deployer, state bucket, then
the rest, without fetching any outputs, so `terragrunt-run.yml`'s staged
planning needs no change.

### 2026-10-22: the state bucket's storage class is `standard`

§2's defaults left `storage_class` to the module. The module's default is
`glacier`, which adds a lifecycle rule moving every object to `GLACIER` after
90 days. runway's `poc` state bucket was created that way
([runway#54](https://github.com/noisypigeon/runway/pull/54)). A leaf whose
state went unwritten for 90 days would then fail at `init`, since state in
`GLACIER` can't be read without a restore.

- **§2 gains a default:** `storage_class` = `standard`.
- **`glacier` is refused** for `scaleway.state`, by `resolve-workloads.sh` and
  root.hcl, as `enable_versioning: false` already is.
- **It ships as patches**, `terragrunt/root-hcl` v5.0.1 and `workflows/`
  v4.9.1. For an existing state bucket the change is in place: the lifecycle
  rule goes, and nothing is replaced.
