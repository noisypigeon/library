# Terraform modules

Versioned, reusable Terraform modules, consumed by this repo's own
[`workloads/`](../workloads/) and any future infra repos. Originally the
standalone `pigeon-tf` repo, merged into this
repo by [ADR-0037](../docs/adr/0037-merge-pigeon-tf-terraform-modules.md);
see [ADR-0054](../docs/adr/0054-pigeon-tf-scaffold.md) (originally
`pigeon-do` ADR-0002) for the design decisions behind consuming the
original repo. Moved from `terraform/modules/` to top-level `modules/` by
[ADR-0093](../docs/adr/0093-move-scaleway-modules-to-top-level-modules.md),
then here, to `templates/terraform/`, by
[ADR-0110](../docs/adr/0110-move-modules-to-templates-terraform.md).

This directory holds only module source — it has no root provider/backend configuration and is never `terraform`/`terragrunt` run standalone.

## Modules

| Path | Description |
| --- | --- |
| `scaleway/project` | A thin wrapper around `scaleway_account_project`. |
| `scaleway/object-bucket` | A Scaleway Object Storage bucket (`scaleway_object_bucket`) with a randomized name suffix, versioning, and a standard/glacier storage-class toggle implemented via an immediate lifecycle transition. |
| `scaleway/compute-instance` | A Scaleway compute Instance (`scaleway_instance_server`) with a randomized name suffix; minimal interface — image, type (defaults to `STARDUST1-S`), optional block volume attachment via `additional_volume_ids`. |
| `scaleway/iam-application` | A thin wrapper around `scaleway_iam_application`. |
| `scaleway/iam-policy` | A Scaleway `scaleway_iam_policy` wrapper granting organization/project permission-set rules to an existing IAM application. |
| `scaleway/iam-api-key` | A thin wrapper around `scaleway_iam_api_key`, defaulting `expires_at` to 30 days after first creation. |
| `scaleway/block-volume` | A Scaleway Block Storage volume (`scaleway_block_volume`) with a randomized name suffix; minimal interface — `size` (renamed from `size_in_gb`), `iops` (defaults to `15000`). |
| `scaleway/cockpit-observability` | A Scaleway Cockpit (`scaleway_cockpit_source`/`scaleway_cockpit_token`) wrapper that creates a metrics and/or logs source plus a shared push token, each individually toggleable via `enable_metrics`/`enable_logs`. |
| `scaleway/grafana-dashboard` | A `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder and provisions a set of dashboards into it from JSON dashboard models. |

## Versioning

Releases are tagged on `noisypigeon`'s `main` with per-module, path-scoped semantic versions matching wherever this directory lived at release time. Three tag-prefix eras exist: an original, even shorter pre-ADR-0037 form; `terraform/modules/<provider>/<module>/vX.Y.Z` (ADR-0037 era); `modules/<provider>/<module>/vX.Y.Z` (ADR-0093 era); and now `templates/terraform/<provider>/<module>/vX.Y.Z` (this directory, ADR-0110 era). Consuming repos pin to a tag by checking out that tag in their local clone of this repo. Old tags are never renamed or deleted — each is an immutable snapshot of the whole repo at that commit, so a tag from an earlier era still resolves correctly even after this directory later moved, see ADR-0037/ADR-0093/ADR-0110 for why.

**The public `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` short-URL namespace (see "Consuming" below, [ADR-0109](../docs/adr/0109-short-module-source-urls-via-blog-redirect.md)) stays `modules/...` forever, regardless of which era a given version's tag actually lives under or where this directory itself moves in the future.** It is a stable public interface, deliberately decoupled from the repo's internal layout.

## Consuming

The recommended way to consume a tagged module — from this repo's own
[`workloads/`](../workloads/) or any external infra repo — is the short
`noisypigeon.com` URL for that module and version:

```hcl
module "state_bucket" {
  source = "https://pigeon.dev/modules/scaleway/object-bucket/v1.0.0"
  ...
}
```

This works via Terraform/go-getter's HTTP module-source discovery protocol:
`terraform init` requests that URL with `?terraform-get=1` and follows the
`terraform-get` `<meta>` tag it finds in the response, which resolves to a
tagged `git::` source pointing back at this repo — the same form you could
write by hand:

```hcl
module "state_bucket" {
  source = "git::https://github.com/noisypigeon/noisypigeon.git//modules/scaleway/object-bucket?ref=modules/scaleway/object-bucket/v1.0.0"
  ...
}
```

Both forms are equivalent; the short URL is a redirect page generated for
every module version tag (see `workloads/pigeon.dev/generate-module-redirects.sh`
and [ADR-0109](../docs/adr/0109-short-module-source-urls-via-blog-redirect.md)).
For local iteration against an unreleased module change (no network fetch),
clone this repo as a sibling directory instead and reference it by path:

```
git clone git@github.com:noisypigeon/noisypigeon.git ../noisypigeon
```

then reference modules under `templates/terraform/`, e.g.
`../noisypigeon/templates/terraform/scaleway/object-bucket`.
