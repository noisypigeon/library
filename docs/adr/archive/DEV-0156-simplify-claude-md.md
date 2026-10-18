# DEV-0156: Simplify CLAUDE.md to current-state-only documentation

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-12.
- **Status**: Accepted; superseded in part by [ADR-0157](DEV-0157-hoist-adrs-to-pigeon-dev.md) (the in-repo longform role passes to `docs/ARCHITECTURE.md`).

## Context

CLAUDE.md exists to onboard an agent or a human quickly into this repo's current structure and conventions. In practice, nearly every structurally-relevant ADR over its life (73 commits touching the file since ADR-0002) has appended to it rather than edited it: a clause describing what moved from where to where, folded into one continuously-growing run-on paragraph, plus a full summary bullet under "ADRs govern this project" for the ADR itself. The result: 75 lines, ~64KB, with a single paragraph running roughly 5,500 words of migration history and a 54-entry bullet list that largely restates each ADR's own Context/Decision/Consequences instead of pointing at it. None of it is wrong — every claim was accurate as of the ADR that added it — but the ratio of "what the repo looks like today" to "how it got that way" has inverted, and the file is now expensive to read for its actual job. (It has also gone stale in the process: the current "Commands" section still describes `blog-build`/`blog-serve` as building `workloads/blog/src`, though `.mise.toml` has built `workloads/noisypigeon.com/src` since ADR-0132, and omits `pigeon-dev-build`/`pigeon-dev-serve`/`secrets-edit` entirely.)

## Decision

Rewrite CLAUDE.md to document only the current state of the repo, plus a short, curated set of gotchas — things true today that are non-obvious enough (usually because of where they used to be) to cause real confusion if left undocumented.

- Replace the single lineage paragraph with a short "Project layout" section stating what's true now: the `workloads/<name>/{src,terraform}` convention, which domains are Terraform-self-sufficient, where the Terraform modules and `zola-site` theme actually live now (`noisypigeon/pigeon.dev`, ADR-0154), and the GitHub-workflow thin-caller pattern (ADR-0155). No blow-by-blow move history.
- Replace the 54-bullet per-ADR digest under "ADRs govern this project" with a pointer to `docs/adr/` itself (numbered chronologically, one file per decision, the actual source of truth) plus a curated "Gotchas" list of roughly 6-7 one-sentence items, each citing the ADR that explains it — covering the trip-hazards a new session would actually hit: legacy `modules/*` tags still resolving from this repo while everything else resolves from `pigeon.dev`; Terraform module/theme development itself happening in `pigeon.dev`, not here; the pre-ADR-0133 shared bootstrap bucket/IAM still alive and intentionally unmanaged; `pigeon-cli`'s Rust source living in a third repo; CI job bodies living in `pigeon.dev`; `workloads/` being the only live Terragrunt tree.
- Fix the stale "Commands" section while rewriting it (correct paths, add the missing tasks) — a direct instance of the problem this ADR addresses.
- Keep "Dev cycle" conceptually unchanged (it already documents current PR process, not history), folded into the rewrite.
- Going forward: a new ADR updates CLAUDE.md's "Project layout" / "Gotchas" only when it changes something CLAUDE.md currently asserts — editing the existing line in place, not appending a clause. An ADR that doesn't change a current-state fact (most bugfixes, internal refactors, one-off incidents) doesn't touch CLAUDE.md at all. Full narrative history stays exclusively in `docs/adr/*.md`.

## Consequences

- CLAUDE.md drops from ~64KB/75 lines to roughly a tenth of that, readable start to finish in less time than the current opening paragraph alone takes to parse.
- `docs/adr/` becomes the sole record of *how* the repo got here; CLAUDE.md stops duplicating it. Anyone wanting history reads the ADRs directly rather than a compressed paragraph describing them.
- Loses the one-line-per-ADR "at a glance" index. Mitigated by ADR filenames already being descriptive and the directory being small enough to `ls`/`grep` directly; this repo has no `docs/adr/README.md` or template today, and this ADR doesn't add one.
- Future ADRs get slightly more review-time judgment (does this change anything CLAUDE.md currently asserts?) in exchange for CLAUDE.md never re-ballooning the way it just did.
- If a future reader needs "why is it this way" for something CLAUDE.md now states tersely, they follow the cited ADR — an intentional trade of self-containedness for brevity.

## Out of scope

- `docs/USAGE.md` and `workloads/README.md` likely have similar sprawl (both are mentioned as needing fixes alongside CLAUDE.md in ADR-0116/ADR-0117) but aren't touched by this ADR.
- No renumbering, splitting, or archiving of `docs/adr/*.md` — ADR-0154 already considered and declined this.
- No `docs/adr/` template or README is added.
