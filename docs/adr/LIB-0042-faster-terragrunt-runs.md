# LIB-0042: Faster spoke Terragrunt runs

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed. Amends LIB-0024 §3 (how workload leaves plan) and
  LIB-0027 §1 (what the automatic re-plan selects).

## Context

On runway a plan often takes 10–20 minutes, even when one leaf changes. A
staged apply then adds the same again for its automatic re-plan. Before
proposing anything, we measured where the time goes.

**The data.** We took all 73 successful `Terragrunt plan` and
`Terragrunt apply` runs on runway from 2026-10-24 to 2026-10-28. For each, we
took the step timings from the Actions jobs API and counted units from the
"Selected units" list in its log. Nothing was re-run.

| Job      | Runs | `terragrunt` step, total | Mean  |
|----------|-----:|-------------------------:|------:|
| plan     |   34 |                  13,493s |  397s |
| replan   |   16 |                   8,083s |  505s |
| apply    |   30 |                   2,914s |   97s |

**Everything else is small.** The other steps of a job take about 40–50s
together: checkout 2–8s, mise 3–9s, masking under 1s, `prepare_cmd` 7–13s,
"Select units" 6–15s and the comments 2–11s. The `terragrunt` step is
85–95% of every slow job.

**The per-leaf cost.** A least-squares fit of the step's time against unit
counts:

- **Plan** (41 runs with 10 or more units): about **11.9s per workload or
  zone leaf** plus 2.7s per hand-written leaf, with a fixed cost near zero.
  Across the 24 plans that selected only unit leaves, the cost per leaf
  ranges from 7.4s to 15.7s (median 11.4s).
- **Apply** (25 runs): about 63s fixed plus **1.1s per workload leaf**.

Plan and apply touch the same leaves: both parse them, initialise them and
fetch their dependencies' outputs. The tenfold gap is how they run.
`terragrunt-run.yml` plans workload leaves one `terragrunt run --all --filter
./<unit>` at a time, in `find --dag` order, because LIB-0024 §3 decides
whether to defer a unit from its dependencies' plans. Apply hands every
planned unit to one `run --all`, which runs them in parallel.

**runway#90 is the typical slow case.** It is a library bump, so `root.hcl`
and `spoke.hcl` changed and every unit was selected:

- **Plan**: 92 units (72 workload or zone, 20 hand-written) in 979s. One
  leaf had changes, 86 had none, and 5 were deferred.
- **Apply**: the same 92 units in 144s.
- **Automatic re-plan**: all 92 units again, in 1,233s. It found nothing to
  change, and only the 5 deferred units had anything left to plan.

That is about 40 minutes of planning for one changed leaf and five deferred
ones. runway#89 selected 16 units: 143s to plan and 59s to apply.

**What one serial invocation costs.** We measured locally, with no
credentials:

- **Parsing.** A filtered `run --all` parses the unit and its whole
  transitive dependency chain. A `run_cmd` probe logged one parse for a leaf
  with no dependencies, and six for the end of a five-link chain. Each
  dependency's outputs are fetched too.
- **Initialisation.** A cold `terraform init` of a workload root module from
  its `noisypigeon.garden` URL took 5.3s with Scaleway's provider (58 MB) and
  4.2s with Cloudflare's (192 MB). It took 3.5–3.9s with a warm plugin cache,
  and 1.7s with a lock file as well.
- **Module versions.** Each parse of a workload leaf runs `git ls-remote`
  against this repo to resolve its module's version (LIB-0023 §3). That takes
  0.45–0.50s.
- **Decryption.** sops decrypts a secrets file in about 14ms, which is
  negligible.

That accounts for roughly half of the 11.9s. The rest is dependency output
fetches against remote state, the refresh, and terragrunt's own startup, all
paid once per leaf in series.

**Nothing is cached.** No `TG_PROVIDER_CACHE` or plugin cache is set, and
`.terraform.lock.hcl` is gitignored, so every init downloads its providers.
`.terragrunt-cache` is cleared on purpose, and it must stay that way:
root.hcl's generated files hold decrypted values (`env_secrets_generated.tf`
and the provider credentials).

**The DAG is shallow.** From the KINDS table in `resolve-workloads.sh`, the
longest chain of workload dependencies is about six levels:

1. project, and the deployer's application;
2. the deployer's policy and key;
3. the state bucket;
4. the workload's leaves, and its Cloudflare and Backblaze deployers;
5. a DNS record or a Backblaze bucket;
6. a key confined to Backblaze buckets.

**Parallel runs are safe.** Every leaf has its own state key and its own lock
(LIB-0022 §4). A plan writes no state, and a dependency's outputs are read
without a lock.

## Decision

These are ranked by expected savings. Each saving is projected from the
measurements above.

### 1. Workload leaves plan in DAG waves, not one at a time

`terragrunt-run.yml` plans a spoke's workload leaves one wave at a time. A
wave is every selected unit that is neither planned nor deferred yet, and
whose workload dependencies all have settled plans. Each wave is a single
`terragrunt run --all` with one `--filter` per unit. Terragrunt runs the
units in parallel.

**Deferral keeps LIB-0024 §3's rules,** decided after each wave rather than
after each unit:

- A unit is **changed** if its JSON plan (`--json-out-dir`) has any resource
  or output change other than a no-op. That is the same test
  `render-run-comments.js`'s `countPlan` uses for the comment.
- A unit is **deferred** if any of its workload dependencies is changed or
  deferred. Its saved plan, if the wave made one, is deleted before the
  archive is packed.
- **A failed unit fails the run,** as it does today.

**So the outcome is unchanged:** the same units are planned, deferred and
applied as with the serial loop. Only the number of invocations changes,
from one per workload leaf (72 on runway#90) to one per level (about 6).

**Expected saving: about 12 minutes on every full plan.** Each wave's cost
should be close to apply's parallel run. That puts runway#90's plan at about
150–250s, against 979s. Across the dataset's 34 plans, about 8,000s of
13,493s would be saved.

### 2. A re-plan plans only the stage that is left

The re-plan that a staged apply starts (LIB-0027 §1) plans only that apply's
deferred units. It no longer plans the PR's whole selection.

**How:** the plan archive (`plan-archive.sh`) records its deferred units. The
re-plan reads them from the archive it just applied.

**Every leaf the previous stage planned is settled.** Its saved plan has just
been applied, so planning it again finds nothing, as runway#90's re-plan
showed.

**The manifest is unchanged in what apply checks.** It still records the
PR's full selection, its base and its destroys. It also names the stage's
units. Apply still refuses a plan whose selection differs from its own, and
applies only units that have a saved plan, as now.

**A `terragrunt plan` comment from a person still plans everything.** That
remains the way to catch drift, or to recover from a failed stage.

**Expected saving: about 18 minutes on runway#90's re-plan,** from 1,233s to
about 2 minutes for its five units, even before decision 1. Across the
dataset's 16 re-plans, we expect about 6,000s of 8,083s saved.

### 3. One provider cache per run, kept between runs

The `terragrunt` step sets `TG_PROVIDER_CACHE=1`, with its cache directory
under `$RUNNER_TEMP`. `actions/cache` restores the directory before the step
and saves it after, keyed on the runner's OS and the provider constraints in
`root.hcl`.

**Expected saving: about 1–1.5s per init** (measured), so about 90s on a
serial full plan. Decision 1 needs it more than the clock does:

- **Concurrency.** Terragrunt's provider cache is safe to use from parallel
  inits, and `TF_PLUGIN_CACHE_DIR` is not.
- **Disk.** A wave would otherwise download the Cloudflare provider (192 MB)
  once per Cloudflare leaf at the same moment.

**Providers only.** Nothing that holds a generated file is cached, and
"Clear terragrunt cache" stays.

### 4. Module versions are resolved once per run

Today each parse of a workload leaf runs `git ls-remote` against this repo.

**"Select units" lists every `refs/tags/terraform/*` tag once** and writes
them to a file whose path it exports as `LIB_TAG_LIST`. When that is set,
root.hcl reads the list with `file()` and picks the version with the same
`--sort=-v:refname` order. Without it, root.hcl falls back to `run_cmd` and
`git ls-remote`, as now, so a local `mise run plan` is unchanged.

**Expected saving: about 0.5s per parse.** In today's serial loop that is
over 100s on a full plan, because each invocation also parses the unit's
dependency chain. After decision 1 it is less, by however much terragrunt
already reuses identical `run_cmd` calls within one process. The
implementation measures that first.

### 5. What we don't do

- **We don't cache `.terragrunt-cache`.** It holds decrypted secrets, and
  runway is public.
- **We don't cache sops output.** Decrypting a file takes about 14ms.
- **We don't split the work into a job per leaf or per wave.** Each job pays
  about 45s of setup. The plan archive would also have to be merged from
  many artifacts. Terragrunt's own parallelism does the same work inside one
  job.
- **We don't trim setup.** All of it together is about 45s a job.

### 6. Release impact

- **Decisions 1–3** are a `workflows` minor. A spoke takes them by bumping
  its callers alone, which selects no units (LIB-0024 §5).
- **Decision 4** also needs a `terragrunt/root-hcl` minor. root.hcl falls
  back when `LIB_TAG_LIST` is unset, so either release can land first.
- **An archive made before the change** records no deferred units. A re-plan
  that applies such an archive plans the whole selection, as today.

## Consequences

- **A full plan of runway should take about 3–4 minutes,** against 13–17
  today. A staged PR's re-plan should take about 2 minutes, against up to 20.
- **The apply side is unchanged.** It already runs in parallel, and these
  decisions don't touch it.
- **A wave's log interleaves its units' output,** as the hand-written leaves'
  `run --all` already does. The comment still renders each leaf on its own,
  because it reads the JSON plans and terragrunt's unit prefixes (LIB-0026).
- **A failing unit can fail its wave alongside units that succeeded.** That
  doesn't change the outcome: the run fails, and nothing is archived.
- **A re-plan no longer notices drift** in units it doesn't plan. A
  `terragrunt plan` comment still does.

## Out of scope

- **Selecting leaves by what root.hcl renders for them.** A `root.hcl` or
  `spoke.hcl` change selects every unit, but on runway#90 it changed one leaf
  in 92. Rendering every leaf at the PR's base and head, and planning only
  those whose generated files or inputs differ, would be the next big saving.
  But a rendered file holds secrets, so the comparison has to hash in memory,
  and dependency outputs complicate it. That needs its own record.
- **Narrowing a secrets-only change** to the leaves that read the changed
  file. Today any change under `terraform/secrets/` selects every unit (#211).
- **Committing provider lock files.** A lock file saved about 1.9s per init
  in our measurements. But unit leaves are generated, so a lock file needs a
  home that survives regeneration (#212).
- **Bigger or self-hosted runners.**

## Verification

After the releases, on runway:

1. **A library bump plans in under 300s.** A PR that bumps `root.hcl` (and
   so selects every unit) finishes its `terragrunt plan` step in under 300s.
   Its comment lists the same changed, unchanged and deferred leaves that a
   serial plan of the same head would.
2. **A staged re-plan plans only its deferred units.** Its "Selected units"
   and its comment cover only those units, and the step takes under 180s.
3. **Deferral holds.** A change shaped like runway#90's, which creates a
   workload's own key, defers the same five units, and the next stage plans
   them.
4. **Apply still refuses a mismatch.** An apply against a plan whose
   selection no longer matches the PR is still refused, with nothing
   applied.
5. **The cache never holds a secret.** The restored cache directory contains
   only provider packages.
