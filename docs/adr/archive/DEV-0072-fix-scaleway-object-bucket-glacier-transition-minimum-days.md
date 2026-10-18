# DEV-0072: fix scaleway/object-bucket's GLACIER transition minimum-days rejection

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-27.
- **Status**: Accepted.

## Context

ADR-0044 designed `terraform/modules/scaleway/object-bucket`'s `storage_class = "glacier"` behavior as an immediate (`days = 0`) `lifecycle_rule` transition to `GLACIER`. Applying it against the one live consumer (`noisypigeon/vault/email`) fails outright:

```
Error: error applying lifecycle configuration to bucket vault-5t39z4-email:
operation error S3: PutBucketLifecycleConfiguration, ... api error InvalidArgument:
Transition rule for storage-class "GLACIER" must be at least 90 days
```

Scaleway rejects a `days = 0` transition to `GLACIER` outright — the API enforces a 90-day minimum. So `storage_class = "glacier"` never actually worked; ADR-0044's design was never field-tested against the real API before being documented.

## Decision

Set `transition.days = 90` in `bucket.tf` — the minimum Scaleway's API will accept. No input/output signature change (`storage_class` itself is unaffected); this is a pure bugfix to a previously-nonfunctional default, matching how ADR-0070 treated an analogous field-test failure in a sibling module.

## Consequences

- `release:patch` — no interface change.
- `noisypigeon/vault/email`, the one live `storage_class = "glacier"` consumer, can now actually `apply` successfully; previously every attempt failed at this step.
- Supersedes ADR-0044's "immediate (`days = 0`) transition" design detail — `days = 0` is not a valid Scaleway API value for a `GLACIER` transition.
