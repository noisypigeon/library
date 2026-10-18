# DEV-0122: Compose scaleway/iam-policy and iam-api-key inside compute-instance

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Superseded by [ADR-0153](DEV-0153-decompose-compute-instance.md).

## Context

`workloads/pigeon-cli/terraform/job/iam.tf` composes `scaleway/iam-policy` and `scaleway/iam-api-key` externally, passing the same `application_id` to both and exposing their `access_key`/`secret_key` outputs at the leaf's own top level. A census of every `compute-instance` consumer finds exactly one real pairing, ever — `pigeon-cli/job` — and it always pairs the same project-scoped IAM policy + API key 1:1 with the same instance, exactly the shape ADR-0120 found for `block-volume`. External composition here buys no real flexibility, just a second pair of module blocks and manual output plumbing every caller has to repeat.

This ADR extends ADR-0120's narrow, named exception to ADR-0081/ADR-0085's "no local module composes another internally" principle to this second pairing. The principle still holds for every other module in this provider root — `object-bucket` (12 consumers) keeps composing externally.

Scoped deliberately to **project-level grants only** (`project_ids`/`project_permission_sets`), matching what the one real consumer actually uses. Organization-scoped grants (`iam-policy` also supports `organization_id`/`organization_permission_sets`) are left out of this interface; a future caller needing them composes `iam-policy`/`iam-api-key` externally instead, same as any caller needing a standalone volume still can with `block-volume`.

Unlike ADR-0120's first attempt, which used a relative `source` that ADR-0121 then had to fix, this composition pins released tags from the start — `iam-policy/v4.0.0` and `iam-api-key/v0.1.0`, the same versions `pigeon-cli/job/iam.tf` already used.

## Decision

`compute-instance` gains a new optional `iam_config` input:

```hcl
variable "iam_config" {
  type = object({
    application_id          = string
    project_ids              = optional(list(string))
    project_permission_sets  = optional(list(string))
    description              = optional(string)
    api_key_expires_at       = optional(string)
  })
  default = null
}
```

- `iam_config` left unset (`null`, the default): no policy or API key created — unchanged from before this ADR.
- `iam_config` set: `compute-instance` composes `iam-policy` and `iam-api-key` internally (new `iam.tf`), naming the policy `${name_prefix}-${name_suffix}-iam-policy` and defaulting the API key's description to `${name_prefix}-${name_suffix} API key` when `iam_config.description` isn't given — matching what the one real past consumer always did by hand.

Two new outputs expose the API key, both `null` when `iam_config` is unset:

```hcl
output "access_key_id" { value = try(module.iam_api_key[0].access_key, null); sensitive = true }
output "secret_key"    { value = try(module.iam_api_key[0].secret_key, null); sensitive = true }
```

`iam-policy`'s own `name`-non-empty-plus-grant validation already guards misconfiguration; this ADR doesn't duplicate it, the same way `block-volume`'s own constraints are relied on rather than re-validated in `compute-instance`.

This is purely additive — a new optional input defaulting to `null`, two new outputs — no existing consumer's behavior changes. `release:minor`, `v5.0.1` → `v5.1.0`.

## Consequences

- `workloads/pigeon-cli/terraform/job` migrates onto `iam_config`, deleting its own `iam.tf` and reading `access_key_id`/`secret_key` through `module.compute` instead. Both IAM resources already have live state under the old `module.iam_policy`/`module.iam_api_key` addresses, so the migration uses `moved` blocks to avoid destroy/recreate.
- `access_key_id`/`secret_key` are named to match `compute-instance`'s own `keyring` entries' `access_key_id` field, not `iam-api-key`'s own `access_key` output name.
- `iam-policy` and `iam-api-key` are not removed or deprecated; they remain independently callable for any hypothetical future caller needing organization-scoped grants or a policy/key not paired with an instance.
- `README.md` for `compute-instance` regenerates automatically via `module-docs.yml` on merge.

## Out of scope

- Organization-scoped grants (`organization_id`/`organization_permission_sets`) — available only via external composition.
- Multiple IAM policies or API keys per instance.
