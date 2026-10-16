# LIB-0006: Cloudflare R2 buckets are EU-jurisdiction only

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-15.
- **Status**: Accepted.

## Context

`terraform/cloudflare/bucket` v0.1.0 (#34) was written as a deliberately thin
pass-through. Apart from the family's bucket naming scheme, it handed three
arguments to `cloudflare_r2_bucket` as given, each validated against the
provider's full list of values and `null` by default:

- **`location`**: a hint (`apac`, `eeur`, `enam`, `weur`, `wnam`, `oc`).
- **`jurisdiction`**: `default`, `eu`, `fedramp` or `us`.
- **`storage_class`**: `Standard` or `InfrequentAccess`.

For this family, that neutrality protects the wrong things:

- **Where the data lives is a requirement, not a preference.** R2 enforces a
  jurisdiction: an `eu` bucket's data stays in the EU. A location hint is
  best effort, and Cloudflare doesn't always respect it. Only the jurisdiction
  delivers the guarantee that matters.
- **The other choices aren't wanted.** No hint covers Canada. The remaining
  non-EU hints, and the `us` and `fedramp` jurisdictions, are places this
  family's data shouldn't go. `default` places data anywhere.
- **A pass-through leaves the guarantee to every leaf.** Each leaf has to
  remember to set `jurisdiction = "eu"`, and forgetting it produces a working
  bucket in the wrong place. R2 can't change a bucket's jurisdiction after
  creation, so fixing that means a new bucket and a copy.
- **A null `storage_class` leaves the class to the provider's default,** which is
  implicit. The default should be written down where it's used.

Checked against every checkout that pins pigeon-lib modules (`pigeon.dev`,
`noisypigeon.com`, `willowgraysen.com`, `noisypigeon` and `pigeon-cli`), no
leaf calls `cloudflare/bucket` yet. Changing its interface migrates nothing.

## Decision

### 1. Every bucket is in the `eu` jurisdiction

`cloudflare_r2_bucket.this` sets `jurisdiction = "eu"`, and the module has no
`jurisdiction` input. A bucket outside the EU can't be expressed through this
module, so passing `jurisdiction` is a Terraform error ("Unsupported argument").

### 2. `location` is removed

The hint isn't always respected, and under the `eu` jurisdiction it adds
nothing the jurisdiction doesn't already enforce. Passing `location` is an
error too. The provider still reports the bucket's actual location as a
computed attribute.

### 3. `storage_class` defaults to `Standard`

`storage_class` is non-nullable with a default of `"Standard"`, and it accepts
`Standard` or `InfrequentAccess`. Passing `null` gets the default rather than
leaving the class unset.

### 4. `endpoint` is always the EU endpoint

`endpoint` is `https://<account_id>.eu.r2.cloudflarestorage.com`. An EU bucket
isn't reachable through the default endpoint.

### 5. Released as `terraform/cloudflare/bucket/v1.0.0`

This is a breaking change to the module's inputs, so it ships with
`release:major`, even before 1.0. That's how this repo treats breaking changes
(`scaleway/pigeon-cluster` went from 0.3.2 to 1.0.0 when it dropped an input).
There are no consumers to bump.

## Consequences

- **A leaf can't choose a jurisdiction or a location.** Every R2 bucket made
  through pigeon-lib keeps its data in the EU.
- **The module is no longer a neutral wrapper.** It encodes a family policy, so
  changing that policy means a new ADR, not a new input.
- **EU-jurisdiction constraints apply to every bucket.** S3 clients such as
  rclone must use the `.eu.` endpoint, which the `endpoint` output gives them.
- **The storage class is visible in every plan** as `Standard` unless a leaf
  asks for `InfrequentAccess`.

## Out of scope

All of these are permanent design boundaries, not deferred work:

- **Non-EU jurisdictions** (`default`, `us`, `fedramp`), and an input to choose
  between jurisdictions.
- **Location hints,** with or without the `eu` jurisdiction.
- **Per-leaf overrides** of either.
- **Other providers' bucket modules.** `scaleway/object-bucket` already runs in
  `fr-par`, and `backblaze/bucket` is unchanged by this record.

## Verification

1. **Formatting and validation.** `mise run fmt-check-terraform` passed, and
   `terraform validate` passed on the module with `terraform init -backend=false`.
2. **Plans.** A scratch root used `cloudflare/cloudflare` 5.28.0, with a dummy
   account ID and token. It called the local module three times:
   - `name_prefix`/`name_suffix` with no `storage_class`;
   - `exact_name` with `storage_class = "InfrequentAccess"`;
   - `exact_name` with `storage_class = null`.

   All three planned `jurisdiction = "eu"`. Their storage classes were
   `Standard`, `InfrequentAccess` and `Standard`. `location` was left unset, so
   the provider showed it as known after apply. Every `endpoint` output was
   `https://<account_id>.eu.r2.cloudflarestorage.com`.
3. **The guards.** Against the same root, each of these failed the plan:
   - `storage_class = "Foo"`, with the module's validation message;
   - `location = "weur"`, as an unsupported argument;
   - `jurisdiction = "us"`, as an unsupported argument.
4. **The release.** This record's PR changes `.tf` files under
   `terraform/cloudflare/bucket/` and carries `release:major`, so its merge
   should cut `terraform/cloudflare/bucket/v1.0.0` and make
   `pigeon.dev/modules/cloudflare/bucket/v1.0.0/` resolve to it.
