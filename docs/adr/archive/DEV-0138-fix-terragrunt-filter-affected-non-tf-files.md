# DEV-0138: fix `terragrunt-plan`/`terragrunt-apply` to catch non-`.tf` asset-file changes

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-07.
- **Status**: Accepted.

## Context

A PR touching only `workloads/willowgraysen.com/terraform/pigeon-cli/shared/
grafana/dashboards/overview.json` (ADR-0135's Grafana dashboard leaf) was suspected
of not actually getting applied by this repo's `terragrunt-plan.yml`/
`terragrunt-apply.yml` CI (ADR-0128/0129/0134).

`terragrunt-plan.yml`'s `detect` job — the thing deciding whether the gated `plan`
job runs at all — is fine. Its check is a path-prefix regex
(`^workloads/[^/]+/terraform/|^\.env\.enc$|^\.sops\.yaml$`), extension-agnostic, so
a JSON-only change under a leaf directory correctly sets `affects-leaves=true` and
the `plan` job runs.

The actual gap is one level deeper, inside the `plan`/`apply` jobs' own
`terragrunt --no-color run --all --filter-affected --filter-allow-destroy ...`
invocation. `--filter-affected` (this repo pins `terragrunt = "1.1.6"` in
`.mise.toml`) is shorthand for `--filter '[main...HEAD]'` — a git-diff-based unit
filter that matches a unit when its own `terragrunt.hcl` (or its HCL-level
`read_terragrunt_config()`/`include` reads) changed. It does not look inside the
unit's actual Terraform module source for `file()`/`fileset()` calls. The grafana
leaf's `grafana.tf` reads `dashboards/*.json` via exactly that pattern
(`fileset("${path.module}/dashboards", "*.json")` feeding `templates/terraform/
scaleway/grafana-dashboard`'s `dashboards` input), so a JSON-only change is
invisible to `--filter-affected`.

This is a confirmed, documented upstream Terragrunt limitation —
[gruntwork-io/terragrunt#6952](https://github.com/gruntwork-io/terragrunt/issues/6952),
closed `NOT_PLANNED` for pre-1.2 ("not a bug, but the documented behavior... It
won't be the behavior of Terragrunt as of 1.2"), with this repo's pinned `1.1.6`
squarely in the affected range. The eventual 1.2 fix is also narrower than this
gap — it's about Terragrunt's own HCL function evaluation (e.g. `file()` called
directly inside `terragrunt.hcl`) gaining automatic read-tracking, not static
analysis of a downstream `.tf` module's `file()`/`fileset()` calls. A separate,
still-open upstream request
([gruntwork-io/terragrunt#6207](https://github.com/gruntwork-io/terragrunt/issues/6207))
confirms affected-unit detection still doesn't reverse-map changes inside a unit's
Terraform module source back to the unit at all.

Net effect today: a JSON-only PR's `plan` job runs, but silently excludes the
grafana leaf from `--filter-affected`'s matched-unit set — reporting a vacuous
"nothing to plan" success. A later `terragrunt apply` comment skips the leaf
identically, auto-merging the PR with a green `terragrunt/apply` status despite the
dashboard content never actually being applied. A silent false-positive in the
merge gate, not a crash — easy to miss in review.

`mark_as_read()` — the obvious-looking Terragrunt escape hatch — turns out not to
fix this. It pairs specifically with the separate `--queue-include-units-reading`
flag (`--filter 'reading=<path>'`), is only callable from a `locals` block in
`terragrunt.hcl`/included config (not from inside a `.tf` file), and even if wired
up from the leaf's `terragrunt.hcl`, it would need an exact absolute path matching
the CI runner's checkout path — fragile, and would only cover this one leaf, not
any future leaf with the same shape.

## Decision

Fix this in the shared workflow files, not in the grafana leaf. Terragrunt's
documented `--filter` flag also supports plain filesystem path expressions
(`'./some/unit/dir'`) alongside the git-diff-range form, and multiple `--filter`
flags explicitly combine with **OR** logic. So both `terragrunt-plan.yml`'s and
`terragrunt-apply.yml`'s `terragrunt plan`/`apply` step now computes, via
`git diff --name-only main...HEAD`, every leaf directory that contains *any*
changed file — found by walking up from each changed file to its nearest ancestor
`terragrunt.hcl`, the same way Terragrunt itself discovers unit boundaries — and
unions an explicit `--filter './<leaf-dir>'` for each onto the existing
`--filter '[main...HEAD]'` (the explicit form of `--filter-affected`, switched to
for uniformity since multiple `--filter` flags combining is the one thing
documented to OR together; mixing the `--filter-affected` boolean shorthand with
explicit `--filter` values isn't documented either way).

This closes the gap generically for any current or future non-`.tf`/`.hcl` asset
(JSON dashboards, policy documents, cloud-init scripts, etc.), not just this one
leaf, and needs no annotation in any leaf's own `terragrunt.hcl`.

The existing git-diff-range matching (`--filter '[main...HEAD]'`) is kept, not
replaced, for one specific reason: it's still the only mechanism that correctly
flags a **deleted** leaf for `--filter-allow-destroy` (ADR-0128) — a deleted
directory has no `terragrunt.hcl` left to walk up to, so the new directory-walk
logic can't see it, but the existing git-diff-range filter still can.

Following this repo's own precedent for these two files (ADR-0134's rationale for
keeping their comment-posting logic duplicated rather than extracted into a shared
composite action), the new ~15-line filter-computation block is duplicated in both
`terragrunt-plan.yml` and `terragrunt-apply.yml` rather than factored out.

## Consequences

- A PR touching only a non-`.tf`/`.hcl` asset file inside a leaf directory (a
  dashboard JSON, a policy document, a cloud-init script, etc.) now gets that leaf
  correctly included in both the `plan` and `apply` runs.
- No change to either workflow's checkout/`fetch-depth`/`git fetch origin main`
  steps — those already provide what `main...HEAD` needs; no change to any leaf's
  own `terragrunt.hcl` or `.tf` files.
- `--filter-allow-destroy`'s deleted-leaf detection (ADR-0128) is unaffected — the
  git-diff-range filter that powers it is kept, not replaced.

## Out of scope

- A PR touching only `.env.enc`/`.sops.yaml` (which `detect` also flags as
  `affects-leaves=true`) still won't map to any specific leaf directory under
  either the old or new filter logic, since secrets aren't scoped to one leaf —
  a pre-existing, separate gap this change neither introduces nor fixes.
- Upgrading `terragrunt` past `1.1.6` to pick up any eventual 1.2-era
  read-tracking improvement — unrelated, and (per the Context above) wouldn't fully
  close this specific gap regardless.
