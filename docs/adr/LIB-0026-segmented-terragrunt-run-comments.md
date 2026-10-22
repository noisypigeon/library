# LIB-0026: Plan and apply comments, one section per leaf, never truncated

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-22.
- **Status**: Proposed. Amends LIB-0022's PR comment.

## Context

`terragrunt-run.yml` reports a plan or an apply as one PR comment. It reads
everything Terragrunt printed, from `output.txt`, and posts it in one code
block. Over 55,000 characters, it keeps only the last 55,000.

That comment has three problems, all of them hit while building LIB-0023 to
LIB-0025 against runway.

- **It's one stream.** Every unit's lines are interleaved, in the order the
  units happened to run. Finding what one leaf will do means searching for its
  path.
- **Most of it is noise.** Each unit's `terraform init` contributes a dozen
  lines, such as provider signing notes and "Terraform has been successfully
  initialized!", before the few lines that say what will change.
- **The front is dropped.** A plan of runway's 22 hand-written leaves plus a
  workload passes 55,000 characters. Since only the tail is kept, whichever
  units ran first lose their output, and those can be the ones that change.
  The comment gives no hint which units are missing.

The cap itself is real: GitHub refuses a comment body over 65,536 characters.
What it doesn't require is cutting the output to fit one comment.

## Decision

### 1. A summary comment, then detail comments

Each run posts one **summary comment** first. It carries:

- the result and the head SHA it planned or applied, as today;
- **a table with one row per leaf**: its path, its result, and a link to the
  comment holding its detail. The results are:
  - `No changes`;
  - `+a ~c -d`, the counts to add, change and destroy;
  - `destroy`, for an instance removed from `values.yaml` (LIB-0023);
  - `deferred until <dependency>` (LIB-0024);
  - `applied`, `failed` and `error`.
- **Ordering:** leaves with changes and failures come first, in path order.
  Unchanged leaves follow in one collapsed list, so that twenty `No changes`
  rows don't bury the one that matters.
- today's footer: how to apply exactly this plan, or how to plan the next
  stage.

**Detail comments** follow, holding each leaf's own output.

### 2. Each leaf is its own section

- **A leaf's section is a `<details>` block.** It opens by default when the
  leaf changes or fails.
- **It holds that leaf's Terraform output only:** the `STDOUT` and `STDERR`
  lines Terragrunt attributes to the unit, with the `[<unit>]` prefix
  stripped.
- **Terragrunt's own `INFO` lines are dropped,** which is where init's noise
  lives. Its `WARN` and `ERROR` lines are kept.
- **Lines that belong to no unit,** such as Terragrunt's run summary or an
  error raised before any unit ran, go in a closing "Run" section.

### 3. Results come from structure

- **A plan's counts come from Terraform's JSON plan.** Terragrunt's
  `--json-out-dir` writes one per unit. Each counts `resource_changes[].change.actions`.
- **An apply's result comes from the leaf's own output:** its
  `Apply complete! Resources: …` line, or its error.
- **Deferred and destroy rows come from the files CI already writes:**
  `deferred-units.txt` and `destroy-units.txt`.

### 4. Nothing is truncated

- **Leaves are packed into detail comments in order,** within a budget of
  60,000 characters each. That leaves room under GitHub's 65,536 for the
  markup around them.
- **A leaf too large for one comment is split** at line boundaries, across
  consecutive comments, as `<leaf> (part 2 of 3)`. Its code fence is closed
  and reopened at each split, so each comment renders on its own.
- **There is no cap on the number of comments.** They're posted about one a
  second, under GitHub's secondary rate limits.
- **The summary is posted first,** then edited once the detail comments exist,
  to link each row to its comment.

### 5. A run's comments are outdated together

Every comment a run posts carries the run's marker,
`<!-- terragrunt-<command> -->`, as the single comment does today. A new run
minimizes all of the previous run's comments, summary and details alike.

### 6. The renderer is a tested library script

- **Rendering lives in `.github/scripts/render-run-comments.js`,** a Node
  module with no dependencies, which `actions/github-script` `require`s from
  `scripts_dir`. It takes the run's output, the JSON plans, the deferred and
  destroy lists and the masked values, and returns the comment bodies. It does
  no I/O.
- **The workflow step only posts, edits and minimizes.**
- **It's tested offline** with `node --test`, against fixtures captured from
  real runway runs. A new workflow, `scripts-test.yml`, runs those tests on
  this repo's pull requests. It's this repo's own CI, not a reusable workflow,
  and releases nothing.

### 7. A comment never carries a masked value

Comments carry Terraform's own output, so a sensitive variable still shows as
`(sensitive value)` (LIB-0025). But comments are built from `output.txt`, a
file GitHub never masks. So the renderer replaces every value the run masked
in its log with `***`, as the log does. A secret that reaches Terraform's
output, such as a provider error that echoes it, appears in neither.

### 8. Release impact

- **`workflows/` takes a minor version.** Callers change nothing.
- **Selection doesn't change,** so a spoke takes it in one PR, with no
  "workflows alone first" step (LIB-0024 §5).

## Consequences

- **A reviewer reads one table** to see what a PR changes, and opens only the
  leaves that matter.
- **No output is lost,** however large the run.
- **A large run posts several comments.** They collapse together when the PR
  re-plans.
- **The comment format becomes code with tests,** in place of an inline
  script nobody could run outside Actions.
- **Parsing depends on Terragrunt's `[<unit>]` prefix.** A Terragrunt release
  that changes its log format breaks segmentation. Output it can't attribute
  still lands in the "Run" section, so nothing is lost, and the tests catch
  the change.

## Out of scope

- **One comment, edited in place,** in place of a new comment per run.
  Deferred ([#123](https://github.com/noisypigeon/library/issues/123)).
- **A GitHub Checks summary,** as a second place to read the run.
  Deferred ([#124](https://github.com/noisypigeon/library/issues/124)).
- **The full raw log as a downloadable artifact.** Deferred ([#125](https://github.com/noisypigeon/library/issues/125)).
- **Building §§1–8,** and the spokes adopting it, in later PRs that cite this
  record ([#122](https://github.com/noisypigeon/library/issues/122)).

## Verification

To be completed when §§1–8 ship.

1. **The renderer's tests pass,** covering:
   - segmentation and stripped prefixes;
   - `INFO` noise dropped;
   - counts read from JSON plans;
   - deferred and destroy rows;
   - packing within the budget;
   - a leaf split across three comments, with balanced fences;
   - masked lines dropped.
2. **A large plan is complete.** On runway, a plan of every leaf posts a
   summary row per leaf and several detail comments. No output is truncated,
   and every row's link resolves.
3. **A re-plan outdates the whole run.** A `terragrunt plan` comment minimizes
   every comment of the previous run.
4. **An apply reads the same way,** one row and one section per leaf.
