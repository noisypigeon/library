# Terraform modules

Versioned, reusable Terraform modules, consumed by
[`noisypigeon/noisypigeon`](https://github.com/noisypigeon/noisypigeon)'s
`workloads/` and any future infra repo. Originally the standalone `pigeon-tf`
repo, merged into `noisypigeon` by
[ADR-0037](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0037-merge-pigeon-tf-terraform-modules.md);
see [ADR-0054](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0054-pigeon-tf-scaffold.md)
(originally `pigeon-do` ADR-0002) for the design decisions behind consuming the
original repo. Moved from `terraform/modules/` to top-level `modules/` by
[ADR-0093](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0093-move-scaleway-modules-to-top-level-modules.md),
then to `templates/terraform/` by
[ADR-0110](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0110-move-modules-to-templates-terraform.md),
and then into this repo — paths unchanged — by
[ADR-0154](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0154-hoist-templates-to-pigeon-dev-repo.md).

This directory holds only module source — it has no root provider/backend configuration and is never `terraform`/`terragrunt` run standalone.

## Modules

| Path | Description |
| --- | --- |
| `scaleway/project` | A thin wrapper around `scaleway_account_project`. |
| `scaleway/object-bucket` | A Scaleway Object Storage bucket (`scaleway_object_bucket`) with a randomized name suffix, versioning, and a standard/glacier storage-class toggle implemented via an immediate lifecycle transition. |
| `scaleway/compute-instance` | A Scaleway compute Instance (`scaleway_instance_server`) with a randomized name suffix. A thin wrapper since ADR-0153: image, type (defaults to `STARDUST1-S`), an already-rendered `cloud_init` document, and pass-through `ip_ids`/`additional_volume_ids` the caller creates. |
| `scaleway/compute-instance-config` | Renders a `pigeon-cli` cloud-init document (keyring, rclone remotes, Cockpit/Alloy, post-provision systemd unit, optional self-delete trap and static ffmpeg) for `compute-instance`'s `cloud_init` input. Creates no resources — its only output is the rendered string. |
| `scaleway/iam-application` | A thin wrapper around `scaleway_iam_application`. |
| `scaleway/iam-policy` | A Scaleway `scaleway_iam_policy` wrapper granting organization/project permission-set rules to an existing IAM application. |
| `scaleway/iam-api-key` | A thin wrapper around `scaleway_iam_api_key`, defaulting `expires_at` to 30 days after first creation. |
| `scaleway/block-volume` | A Scaleway Block Storage volume (`scaleway_block_volume`) with a randomized name suffix; minimal interface — `size` (renamed from `size_in_gb`), `iops` (defaults to `15000`). |
| `scaleway/cockpit-observability` | A Scaleway Cockpit (`scaleway_cockpit_source`/`scaleway_cockpit_token`) wrapper that creates a metrics and/or logs source plus a shared push token, each individually toggleable via `enable_metrics`/`enable_logs`. |
| `scaleway/grafana-dashboard` | A `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder and provisions a set of dashboards into it from JSON dashboard models. |
| `scaleway/pigeon-cluster` | A cluster of `pigeon-cli` job instances: one shared Private Network and Public Gateway, an optional debug bastion, and per job an instance, IAM application/policy/API keys, optional block volume, IP and private NIC. The composing layer for every `compute-instance` concern (ADR-0153). |
| `backblaze/bucket` | A private Backblaze B2 bucket (`b2_bucket`) with a randomized name suffix; always `bucket_type = "allPrivate"`. |
| `backblaze/api-key` | A thin wrapper around `b2_application_key`, defaulting `valid_duration_in_seconds` to 30 days. |

## Versioning

Releases are tagged with per-module, path-scoped semantic versions matching wherever this directory lived at release time. Four tag-prefix eras exist: an original, even shorter pre-ADR-0037 form; `terraform/modules/<provider>/<module>/vX.Y.Z` (ADR-0037 era); `modules/<provider>/<module>/vX.Y.Z` (ADR-0093 era); and `templates/terraform/<provider>/<module>/vX.Y.Z` (ADR-0110 era, and still current — ADR-0154 moved the directory into this repo without changing its path, so the prefix did not change either). Old tags are never renamed or deleted: each is an immutable snapshot of a whole repo at one commit, so a tag from an earlier era still resolves correctly even after this directory later moved.

**The first three eras' tags live in `noisypigeon/noisypigeon`, not here** — their commits predate `templates/` existing, so ADR-0154's `git filter-repo --path templates/` could not carry them across, and 20 of them (the `modules/*` era) are still reachable through the short-URL layer, which maps each tag prefix to the repo that holds it. One of those, `scaleway/project/v1.0.0`, is still live-pinned by a consumer. Only `templates/*` tags exist in this repo.

**The public `pigeon.dev/modules/<provider>/<module>/vX.Y.Z` short-URL namespace (see "Consuming" below, [ADR-0109](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0109-short-module-source-urls-via-blog-redirect.md)) stays `modules/...` forever, regardless of which era a given version's tag actually lives under or where this directory itself moves in the future.** It is a stable public interface, deliberately decoupled from the repo's internal layout.

## Consuming

The recommended way to consume a tagged module — from
[`noisypigeon/noisypigeon`](https://github.com/noisypigeon/noisypigeon)'s
`workloads/` or any external infra repo — is the short `pigeon.dev` URL for
that module and version:

```hcl
module "state_bucket" {
  source = "https://pigeon.dev/modules/scaleway/object-bucket/v4.2.0"
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
  source = "git::https://github.com/noisypigeon/pigeon.dev.git//templates/terraform/scaleway/object-bucket?ref=templates/terraform/scaleway/object-bucket/v4.2.0"
  ...
}
```

Both forms are equivalent, but note the `git::` form has to name the right
repo *and* the right tag prefix for the era that version was released in —
which is exactly what the short URL exists to hide. The redirect page behind it
is generated for every module version tag by
`workloads/pigeon.dev/generate-module-redirects.sh`, which lives in
`noisypigeon/noisypigeon` alongside the Zola site that serves it (ADR-0109,
ADR-0136, ADR-0154).

For local iteration against an unreleased module change (no network fetch, no
tag required), clone this repo as a sibling directory and reference it by path:

```
git clone git@github.com:noisypigeon/pigeon.dev.git ../pigeon.dev
```

then reference modules under `templates/terraform/`, e.g.
`../pigeon.dev/templates/terraform/scaleway/object-bucket`.
