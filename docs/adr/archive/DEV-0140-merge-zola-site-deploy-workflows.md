# DEV-0140: merge the noisypigeon.com and pigeon.dev deploy workflows into one matrix job

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-06.
- **Status**: Accepted.

## Context

`.github/workflows/noisypigeon-com-deploy.yml` (ADR-0132) and
`.github/workflows/pigeon-dev-pages.yml` (ADR-0130) are near-duplicates: both
checkout → resolve the zola-site theme → install Zola → `zola build` → `aws
s3 sync` to the site's own Scaleway Object Storage bucket. The only real
differences between them are the bucket name, the two `AWS_*` secret names,
one pigeon.dev-only pre-build step (`generate-module-redirects.sh`,
ADR-0109/0136), and one noisypigeon.com-only env var on the build step
(`SITE_COMMIT_SHA`).

## Decision

Replace both workflows with one, `.github/workflows/zola-sites-deploy.yml`,
running a single `strategy.matrix` `deploy` job parameterized per site —
this repo's first use of a matrix plus `secrets[matrix.<field>]` dynamic
secret lookup to pull each leg's own `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
by name:

```yaml
strategy:
  matrix:
    include:
      - site: noisypigeon.com
        changed_key: noisypigeon
        src_dir: workloads/noisypigeon.com/src
        bucket: noisypigeon.com
        access_key_secret: NOISYPIGEON_COM_SCW_ACCESS_KEY
        secret_key_secret: NOISYPIGEON_COM_SCW_SECRET_KEY
        build_cmd: "SITE_COMMIT_SHA=$(git rev-parse --short HEAD) zola build"
        extra_step: ""
      - site: pigeon.dev
        changed_key: pigeondev
        src_dir: workloads/pigeon.dev/src
        bucket: pigeon.dev
        access_key_secret: PIGEON_DEV_SCW_ACCESS_KEY
        secret_key_secret: PIGEON_DEV_SCW_SECRET_KEY
        build_cmd: "zola build"
        extra_step: "workloads/pigeon.dev/generate-module-redirects.sh"
```

Every step in the job body (checkout, resolve theme, the conditional
`extra_step`, install Zola, `${{ matrix.build_cmd }}`, and the `aws s3 sync`
using `secrets[matrix.access_key_secret]`/`secrets[matrix.secret_key_secret]`)
is otherwise identical to what each original workflow already did — this is
a parameterization, not a behavior change, for the push-triggered path.

### Preserving per-site gating: a `detect` job

Today, each site's own workflow only runs when *that site's* `src/` paths
(or the shared `templates/zola-site/**`) change — a pigeon.dev-only commit
never triggers noisypigeon.com's workflow. A bare matrix loses this, since
`on.push.paths` gates the whole workflow trigger, not individual matrix
legs. `zola-sites-deploy.yml` adds a `detect` job — mirroring the `detect`
job `terragrunt-plan.yml` already uses for the same kind of problem
(ADR-0129) — that `git diff --name-only ${{ github.event.before }}
${{ github.sha }}` on `push` and sets one boolean output per site
(`noisypigeon`, `pigeondev`); a shared-theme change sets both. Each matrix
entry carries a `changed_key` field naming which output is its own.

The `matrix` context is only available to steps, not to a job-level `if:`
(confirmed via `actionlint`, which flags exactly this: "context `matrix` is
not allowed here" on a job condition) — so gating happens one level down
instead. The `deploy` job's first real step reads
`needs.detect.outputs[matrix.changed_key]` into a step output
(`steps.gate.outputs.run`), and every subsequent step carries
`if: steps.gate.outputs.run == 'true'`. Both matrix legs' jobs still show up
in the Actions UI either way; the ungated leg's steps just report
"skipped" past checkout, rather than the job never running.

### `workflow_dispatch` gains a `site` input

A bare `workflow_dispatch` with no way to say which site has nothing to
diff against. Rather than accept "a manual dispatch always redeploys both
sites" as a silent side effect, `zola-sites-deploy.yml` adds an explicit
input:

```yaml
workflow_dispatch:
  inputs:
    site:
      description: "Which site to deploy"
      type: choice
      options: ["all", "noisypigeon.com", "pigeon.dev"]
      default: "all"
```

`detect` honors it on `workflow_dispatch`: an explicit `noisypigeon.com` or
`pigeon.dev` targets just that site; the default `"all"` (a genuinely manual
dispatch, with no site chosen) redeploys both, same as a `templates/zola-site`
content change would.

This matters beyond convenience: both old workflows were already dispatched
*automatically* by other workflows after a merge, by filename —
`blog-changelog.yml`'s "Trigger blog Pages deploy" step ran
`gh workflow run noisypigeon-com-deploy.yml`, and `template-release.yml`'s
"Trigger pigeon.dev deploy" step (after a module/zola-site tag) ran
`gh workflow run pigeon-dev-pages.yml`. Without a `site` input, merging the
two workflows would have turned every single blog-content edit into a
redeploy of *both* sites (and every module/zola-site release into the same),
not just an occasional manual-dispatch edge case. Both call sites are
updated to the merged workflow with an explicit input instead:

- `blog-changelog.yml`: `gh workflow run zola-sites-deploy.yml --ref main -f site=noisypigeon.com`
- `template-release.yml`: `gh workflow run zola-sites-deploy.yml --ref main -f site=pigeon.dev`

### Concurrency

Each site's own deploys must still serialize independently of the other
site's — today's two separate `concurrency.group`s. The job-level
`concurrency.group` is scoped per matrix leg: `"zola-deploy-${{ matrix.site }}"`,
`cancel-in-progress: false`, so the two sites' deploys still never block
each other, while each site's own deploys still serialize exactly as
before.

## Consequences

- One workflow file instead of two; a future third `workloads/<name>/src`
  Zola site is a new `matrix.include` entry plus two new repo secrets,
  not a third near-duplicate workflow file.
- `ZOLA_VERSION` is now declared once instead of being duplicated (and
  potentially drifting) across two files.
- This repo's first use of `secrets[matrix.<field>]` dynamic secret lookup
  and of a job-level `if:` keyed on a matrix field — both now available as
  precedent for any future per-site/per-target CI workflow.
- `blog-changelog.yml` and `template-release.yml`'s automated deploy
  triggers are unaffected in practice: each still redeploys exactly the one
  site it always meant to, via an explicit `-f site=...` instead of a
  filename.
- A genuinely manual `workflow_dispatch` (no `site` input given) now
  redeploys both sites instead of the one whose old workflow file you'd
  have picked — an accepted, deliberate tradeoff for the rare manual case,
  not something either automated caller relies on.

## Out of scope

- Any change to `resolve-theme.sh`'s internal behavior — see ADR-0139,
  landed independently; this workflow's "Resolve zola-site theme" step
  invocation is unchanged either way.
- Any change to how `terragrunt-plan.yml`/`terragrunt-apply.yml`'s own
  `detect` job or merge-gate status work — this ADR only reuses the same
  pattern, not the same job.
