# DEV-0121: Pin block-volume's source in compute-instance instead of a relative path

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Superseded by [ADR-0153](DEV-0153-decompose-compute-instance.md).

## Context

ADR-0120 folded `block-volume` creation into `compute-instance`'s `instance_config.block_volume`, composing the two modules internally:

```hcl
module "block_volume" {
  count  = ...
  source = "../block-volume"
  ...
}
```

The first real `tofu init` against a released consumer — `workloads/pigeon-cli/terraform/job`, sourcing `compute-instance` from its short URL (ADR-0109) — failed outright:

```
Error: Local module path escapes module package

The given source directory for module.compute.module.block_volume would be
outside of its containing package
"https://noisypigeon.com/modules/scaleway/compute-instance/v5.0.0". Local
source addresses starting with "../" must stay within the same package that
the calling module belongs to.
```

A relative source only resolves within the boundary of whatever package the referencing module itself was fetched as. A local clone or a `git::...` source fetches the whole repository tree, so `../block-volume` happens to resolve — but go-getter's HTTP installer (what the `noisypigeon.com` short URLs resolve to, per ADR-0109) fetches only `compute-instance`'s own module directory as its package, with no sibling `block-volume` directory present at all. ADR-0120's relative-path composition was never actually exercised against this path before being tagged and released as `v5.0.0`.

## Decision

Pin the internal `block_volume` module's source to `block-volume`'s current released tag instead of a relative path:

```hcl
source = "https://noisypigeon.com/modules/scaleway/block-volume/v4.0.0"
```

matching the short-URL pin convention every other cross-module reference in this repo already uses (e.g. `compute-instance`'s own consumers, `object-bucket`'s consumers). This resolves correctly regardless of how `compute-instance` itself was fetched.

This reintroduces a small manual-bump coupling ADR-0120's relative-path approach would have avoided: a future `block-volume` release doesn't automatically reach `compute-instance` until this pin is bumped by hand. That cost is accepted as the necessary price of the composition actually working for real (HTTP-sourced) consumers at all — a relative path that only works for some source protocols isn't a usable internal-composition mechanism.

`release:patch` on `compute-instance` — no input/output signature change, `v5.0.0` → `v5.0.1`.

ADR-0120 is amended in place: the sentence describing relative-path composition in its Decision section is struck through, pointing at this ADR, matching the existing strikethrough-amendment style already used on ADR-0081/ADR-0085.

## Consequences

- No consumer-facing change — `compute-instance`'s interface (inputs/outputs) is untouched by this fix.
- `workloads/pigeon-cli/terraform/job` (the leaf that surfaced this) needs its `compute-instance` source bumped from `v5.0.0` to `v5.0.1` to pick up the fix; its `tofu init`/`terragrunt plan` is expected to run clean afterward.
- Any future module that considers composing a sibling module internally (an exception to ADR-0081/ADR-0085's general principle, as ADR-0120 carved out for this one pairing) should pin a released tag from the start, not a relative path — this failure mode applies to any such composition, not just this one.
- `README.md` for `compute-instance` regenerates automatically via `module-docs.yml` on merge, picking up the new pinned source in its rendered example.

## Out of scope

- Any mechanism to automatically bump this internal pin when `block-volume` cuts a new release — this is a manual, deliberate step for now, consistent with every other version pin in this repo.
