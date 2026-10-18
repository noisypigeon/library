# DEV-0126: Add an `enabled` kill switch to compute-instance

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted; superseded in part by [ADR-0153](DEV-0153-decompose-compute-instance.md) (the kill switch now tears down only the server).

## Context

The only way today to stop paying for a `compute-instance` between uses (e.g. a job-runner instance that only needs to exist while a job is running) is to delete the module block from the caller's configuration entirely — which also throws away every argument on it, so bringing the instance back means retyping or restoring the block from git history. A boolean kill switch is a better fit: flip it to `false` to tear the instance down, flip it back to `true` to recreate it from the same, still-present configuration.

**Scope, decided deliberately with the user: full teardown, not a pause.** Setting `enabled = false` destroys everything this module instance manages — the server, its IP address(es), its block volume, and its IAM policy/API key — not just the compute server. This is the cheaper option while disabled, at the cost of two things worth stating plainly rather than discovering later:

- **Destroying the block volume destroys its data.** This is not a stop/suspend; any data on the managed volume is gone when `enabled` goes to `false`, exactly as if the volume were deleted directly. A caller that needs the volume's data to survive a disable cycle should not use this switch for that volume — there is no partial-teardown mode in this ADR (see Out of scope).
- Re-enabling re-provisions a fresh IP address and a fresh IAM API key — neither is preserved across a disable cycle, so anything hardcoded against the old IP or key (DNS records, other systems' stored credentials) needs updating again on re-enable.

## Decision

New top-level variable, a sibling to `enable_ipv4`/`enable_ipv6` (this controls the module's own lifecycle, not the instance's runtime provisioning, so it doesn't belong inside `instance_config`):

```hcl
variable "enabled" {
  type        = bool
  description = "Kill switch. false destroys every resource this module manages for this instance -- the server, its IP address(es), its block volume (and the volume's data -- this is a real data-loss event, not a pause), and its IAM policy/API key -- while the module block itself stays in the caller's configuration. true (default) runs normally. The instance's name (random suffix) stays stable across a disable/re-enable cycle."
  default     = true
}
```

`var.enabled` is cascaded into every existing conditional in the module — `scaleway_instance_ip.ipv4`/`.ipv6`, `module.block_volume`, `module.iam_policy`, `module.iam_api_key` all gain a `var.enabled &&` on their existing `count` condition. `scaleway_instance_server.server` itself gains `count = var.enabled ? 1 : 0`, moving it from a singleton resource to a conditional one for the first time.

`random_string.suffix` and `terraform_data.cloud_init` stay unconditional. Keeping the random suffix unconditional is what makes the instance's computed name identical before a disable and after a re-enable — re-running `apply` with `enabled = true` again reconstructs the same name rather than drawing a new random suffix.

Because `scaleway_instance_server.server`'s address changes from `scaleway_instance_server.server` to `scaleway_instance_server.server[0]`, a `moved` block ships inside the module itself:

```hcl
moved {
  from = scaleway_instance_server.server
  to   = scaleway_instance_server.server[0]
}
```

Living inside the module (rather than something each caller has to write) means it protects any caller's existing state automatically, the same way ADR-0122 protected `pigeon-cli/job`'s state through its own internal-composition change.

Outputs that referenced the singleton directly (`id`, `name`, `public_ips`, `private_ips`) now go through `try(scaleway_instance_server.server[0].<attr>, null)`, resolving to `null` when `enabled = false`. `ipv4_address`'s existing `var.enable_ipv4 ? ... : null` guard gains a `var.enabled &&`, since the IP resource's own `count` now depends on both. `access_key_id`/`secret_key` needed no change — they already went through `try(module.iam_api_key[0]..., null)`, and that module's `count` now folds in `var.enabled` too.

No new `validation` block — `enabled` has no cross-field constraint with anything else.

This is purely additive: a new optional input defaulting to `true`, with a `moved` block keeping the one addressing change state-safe. `release:minor`, `v5.2.0` → `v5.3.0`.

## Consequences

- Flipping `enabled` to `false` and back to `true` is a destroy-and-recreate cycle for the server, its IP(s), its block volume, and its IAM policy/API key — **the block volume's data does not survive this**, by deliberate design (see Context). Any caller relying on this switch should budget for that, not treat it as a pause button.
- The server's public/private IPs and IAM API key both change on re-enable (freshly reprovisioned), even though the instance's name does not.
- `README.md` for `compute-instance` regenerates automatically via `module-docs.yml` on merge.
- No consumer migration needed: `workloads/pigeon-cli/terraform/job` is still fully commented out, so there is no active caller whose state the `moved` block needs to protect today — it protects any future real caller going forward.

## Out of scope

- A partial-teardown mode (e.g. destroy only the server, keep the block volume/IP/IAM key allocated) is not provided. A caller wanting that would need a different mechanism — this ADR's `enabled` always tears down everything.
- Any notion of "stopped" vs. "destroyed" power state on the underlying Scaleway instance (e.g. `scaleway_instance_server`'s own `state` attribute) — this switch operates purely at the Terraform resource-existence level.
