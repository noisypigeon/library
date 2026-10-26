# Terraform modules

Versioned, reusable Terraform modules, consumed by every repo in this family
that runs Terraform — today `noisypigeon/noisypigeon`'s per-domain
`<name>/terraform/` trees. Originally the standalone `pigeon-tf`
repo, merged into `noisypigeon` by
[ADR-0037](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0037-merge-pigeon-tf-terraform-modules.md);
see [ADR-0054](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0054-pigeon-tf-scaffold.md)
(originally `pigeon-do` ADR-0002) for the design decisions behind consuming the
original repo. Moved from `terraform/modules/` to top-level `modules/` by
[ADR-0093](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0093-move-scaleway-modules-to-top-level-modules.md),
then to `templates/terraform/` by
[ADR-0110](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0110-move-modules-to-templates-terraform.md),
then into `noisypigeon/garden` — paths unchanged — by
[ADR-0154](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0154-hoist-templates-to-pigeon-dev-repo.md),
and finally into this repo as top-level `terraform/` by LIB-0002, which
dropped the `templates/` segment ADR-0154 had kept only to limit its own
blast radius.

This directory holds only module source — it has no root provider/backend configuration and is never `terraform`/`terragrunt` run standalone.

## Modules

| Path | Description |
| --- | --- |
| `scaleway/project` | A thin wrapper around `scaleway_account_project`. |
| `scaleway/bucket` | A Scaleway Object Storage bucket (`scaleway_object_bucket`) with a randomized name suffix, versioning, and a standard/glacier storage-class toggle implemented via an immediate lifecycle transition. |
| `scaleway/compute-instance` | A Scaleway compute Instance (`scaleway_instance_server`) with a randomized name suffix. A thin wrapper since ADR-0153: image, type (defaults to `STARDUST1-S`), an already-rendered `cloud_init` document, and pass-through `ip_ids`/`additional_volume_ids` the caller creates. |
| `scaleway/compute-instance-config` | Renders a `pigeon-cli` cloud-init document (keyring, rclone remotes, Cockpit/Alloy, post-provision systemd unit, optional self-delete trap and static ffmpeg) for `compute-instance`'s `cloud_init` input. Creates no resources — its only output is the rendered string. |
| `scaleway/iam-application` | A thin wrapper around `scaleway_iam_application`. |
| `scaleway/iam-policy` | A Scaleway `scaleway_iam_policy` wrapper granting organization/project permission-set rules to an existing IAM application. |
| `scaleway/iam-api-key` | A thin wrapper around `scaleway_iam_api_key`, defaulting `expires_at` to 30 days after first creation, with optional `rotation_days` (LIB-0038). |
| `scaleway/terraform-deployer-iam` | **Deprecated** (LIB-0038): no further releases, tags still resolve. Compose `iam-application`, `iam-policy` and `iam-api-key` instead. |
| `scaleway/block-volume` | A Scaleway Block Storage volume (`scaleway_block_volume`) with a randomized name suffix; minimal interface — `size` (renamed from `size_in_gb`), `iops` (defaults to `15000`). |
| `scaleway/cockpit-observability` | A Scaleway Cockpit (`scaleway_cockpit_source`/`scaleway_cockpit_token`) wrapper that creates a metrics and/or logs source plus a shared push token, each individually toggleable via `enable_metrics`/`enable_logs`. |
| `scaleway/compute-cluster` | A cluster of `pigeon-cli` job instances: one shared Private Network and Public Gateway, an optional debug bastion, and per job an instance, IAM application/policy/API keys, optional block volume, IP and private NIC. The composing layer for every `compute-instance` concern (ADR-0153). |
| `backblaze/bucket` | A private Backblaze B2 bucket (`b2_bucket`) with a randomized name suffix, or `exact_name`; always `bucket_type = "allPrivate"`. |
| `backblaze/api-key` | A thin wrapper around `b2_application_key`, defaulting `valid_duration_in_seconds` to 30 days. |
| `cloudflare/bucket` | A thin wrapper around a single Cloudflare R2 bucket (`cloudflare_r2_bucket`), named like `backblaze/bucket` and `scaleway/bucket`: a randomized name suffix, or `exact_name`. |
| `cloudflare/dns-record` | A thin wrapper around a single `cloudflare_dns_record`. Zone-scoped: takes the zone's apex domain as `zone` and looks its ID up (LIB-0011). |
| `cloudflare/ruleset` | A thin wrapper around a single `cloudflare_ruleset`, its zone named by apex (LIB-0030). A zone's `apexRedirect` expands into one, beside two `dns-record` placeholders (LIB-0038). |
| `cloudflare/apex-redirect` | **Deprecated** (LIB-0038): no further releases, tags still resolve. Compose `cloudflare/dns-record` and `cloudflare/ruleset` instead. |
| `scaleway/object-bucket` | **Renamed** to `scaleway/bucket` (LIB-0020): no further releases, tags still resolve. |
| `scaleway/pigeon-cluster` | **Renamed** to `scaleway/compute-cluster` (LIB-0020): no further releases, tags still resolve. |
| `grafana/dashboard` | A `grafana_folder`/`grafana_dashboard` wrapper that creates a Grafana folder and provisions a set of dashboards into it from JSON dashboard models or tag URLs. Formerly `scaleway/grafana-dashboard`. |

## Versioning

Releases are tagged with per-module, path-scoped semantic versions matching wherever this directory lived at release time. Four tag-prefix eras exist: an original, even shorter pre-ADR-0037 form; `terraform/modules/<provider>/<module>/vX.Y.Z` (ADR-0037 era); `modules/<provider>/<module>/vX.Y.Z` (ADR-0093 era); `templates/terraform/<provider>/<module>/vX.Y.Z` (ADR-0110 era, carried into `noisypigeon/garden` unchanged by ADR-0154); and `terraform/<provider>/<module>/vX.Y.Z` (LIB-0002 era, and current — the flatten re-cut all 53 tags under this shape in this repo). Old tags are never renamed or deleted: each is an immutable snapshot of a whole repo at one commit, so a tag from an earlier era still resolves correctly even after this directory later moved.

**Only the current era's tags live here, and only they resolve.** The first three eras' tags remain in `noisypigeon/noisypigeon` and the fourth in `noisypigeon/garden`; none are deleted — ADR-0154 made that a permanent boundary — but none are served either. DEV-0160 step 0 retired the last mapping arm once `scaleway/project/v1.0.0`, its only remaining consumer, was repinned. Every version a consumer can resolve today is a `terraform/*` tag in this repo, because LIB-0002 re-cut all 53 of them here.

**The public `noisypigeon.garden/terraform/<provider>/<module>/vX.Y.Z` short-URL namespace (see "Consuming" below, [LIB-0009](../docs/adr/LIB-0009-terraform-short-urls-move-to-noisypigeon-garden.md)) is published for every current-era tag, whatever version, and doesn't move when this directory does.** It is a stable public interface, deliberately decoupled from the repo's internal layout.

## Consuming

The recommended way to consume a tagged module — from any repo in this
family that runs Terraform, or an external one — is the short `noisypigeon.garden`
URL for that module and version:

```hcl
module "state_bucket" {
  source = "https://noisypigeon.garden/terraform/scaleway/bucket/v5.0.0"
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
  source = "git::https://github.com/noisypigeon/library.git//terraform/scaleway/bucket?ref=terraform/scaleway/bucket/v5.0.0"
  ...
}
```

Both forms are equivalent, but note the `git::` form has to name the right
repo *and* the right tag prefix for the era that version was released in —
which is exactly what the short URL exists to hide. The redirect page behind
it is generated for every module version tag by
`generate-module-redirects.sh` in this repo, run by the `noisypigeon.garden` site at
build time against the library version that site pins (ADR-0109, ADR-0136,
LIB-0002, LIB-0009).

For local iteration against an unreleased module change (no network fetch, no
tag required), clone this repo as a sibling directory and reference it by path:

```
git clone git@github.com:noisypigeon/library.git ../library
```

then reference modules under `terraform/`, e.g.
`../library/terraform/scaleway/bucket`.
