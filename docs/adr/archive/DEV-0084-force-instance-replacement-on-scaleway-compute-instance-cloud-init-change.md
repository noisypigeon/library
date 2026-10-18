# DEV-0084: force instance replacement when scaleway/compute-instance's cloud-init content changes

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-30.
- **Status**: Accepted.

## Context

A real instance created via `terraform/modules/scaleway/compute-instance` was
missing `rclone`/`neovim` and `/root/.config/rclone/rclone.conf`, even though
the module's cloud-init wiring (ADR-0081, `v0.2.0`) is designed to install
and write exactly those. Root-causing this (three parallel investigations
plus a follow-up check) ruled out the obvious suspects before landing on the
actual cause:

**The module's cloud-init code itself is correct.** `instance.tf` sets
`user_data = { cloud-init = <<-EOF ... EOF }`, matching Scaleway's documented
contract exactly — cloud-init's Scaleway datasource only picks up user data
stored under the literal, reserved `cloud-init` key inside the `user_data`
map (confirmed against the Terraform provider docs and Scaleway's Instance
API docs). The rendered YAML, the `%{~ for ~}` bucket loop, and
`write_files`/`defer: true` all check out against ADR-0081's design.

**`scaleway_instance_server.user_data` has no `ForceNew` in the Terraform
provider schema.** Confirmed directly from `terraform-provider-scaleway`
source: changing `user_data` (including the `cloud-init` key) calls
Scaleway's `SetAllServerUserData` API against the already-running instance —
an in-place metadata PATCH, not a destroy/recreate. The instance keeps its
existing instance-id.

**cloud-init only runs its package-install and `write_files` modules once
per instance-id, on that instance's first boot.** Scaleway's own cloud-init
how-to guide says this explicitly: *"updating the user-data of an Instance
may not have the expected outcome when the system reboots... many of
[cloud-init's] modules are intended to only activate during the Instance's
first boot, and not subsequent ones."* Neither an in-place user-data update
nor a plain reboot clears the per-instance semaphores that track this —
only `cloud-init clean --logs --reboot` on the box, or a genuinely new
instance-id, does.

**This is exactly the gap ADR-0081 didn't anticipate when porting the
pattern from `digitalocean/droplet`.** `digitalocean_droplet.user_data` *is*
`ForceNew: true` in the DigitalOcean provider (confirmed from provider
source) — any `user_data` change there always recreates the droplet, so
droplet's cloud-init always gets a genuine first boot. Scaleway has no
equivalent safety net. So any instance that already existed when cloud-init
content was first added, or later changed (a `buckets` edit, a module
version bump that touches the rendered cloud-config), silently keeps running
with stale — or entirely absent — provisioning, with no error from
Terraform at all.

Sources: [`scaleway_instance_server` resource docs](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs/resources/instance_server),
[Scaleway Instance API — User Data](https://www.scaleway.com/en/developers/api/instance/user-data),
[Scaleway — How to use cloud-init with Instances](https://www.scaleway.com/en/docs/instances/how-to/use-cloud-init/),
[cloud-init — How to re-run cloud-init](https://docs.cloud-init.io/en/24.1/howto/rerun_cloud_init.html),
`terraform-provider-scaleway`'s `scaleway_instance_server` resource schema/update logic,
`terraform-provider-digitalocean`'s `digitalocean_droplet` resource schema (`user_data` `ForceNew: true`).

## Decision

Force `scaleway_instance_server.server` to be replaced whenever its rendered
cloud-init content changes, using `terraform_data` + `lifecycle.replace_triggered_by`
— the standard Terraform/OpenTofu ≥1.2 mechanism for triggering replacement
from a derived value, requiring no extra provider (`terraform_data` is a
core builtin):

```hcl
locals {
  cloud_init = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - rclone
      - neovim

    write_files:
      - path: /root/.config/rclone/rclone.conf
        permissions: '0600'
        defer: true
        content: |
          %{~ for bucket in var.buckets ~}
          [${bucket.bucket_alias}]
          type = alias
          remote = ${bucket.bucket_name}:${bucket.bucket_name}
          [${bucket.bucket_name}]
          type = s3
          provider = ${bucket.bucket_provider}
          access_key_id = ${bucket.bucket_access_key}
          secret_access_key = ${bucket.bucket_secret_key}
          endpoint = ${bucket.bucket_endpoint}
          acl = private
          no_check_bucket = true
          %{~ endfor ~}
  EOF
}

resource "terraform_data" "cloud_init" {
  input = md5(local.cloud_init)
}

resource "scaleway_instance_server" "server" {
  name  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image = var.image
  type  = var.type
  ip_id = var.enable_ipv6 ? scaleway_instance_ip.ipv6[0].id : null
  tags  = [for key in var.ssh_keys : "AUTHORIZED_KEY=${replace(key, " ", "_")}"]

  user_data = {
    cloud-init = local.cloud_init
  }

  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init.output]
  }
}
```

The cloud-config content itself is unchanged — only moved into `local.cloud_init`
so it can be hashed and reused. `terraform_data.cloud_init.output` changes
whenever `local.cloud_init` changes (any edit to `packages`, `buckets`, or the
`write_files` template), and `replace_triggered_by` propagates that into a
forced replacement of the instance — giving it a fresh instance-id and,
therefore, a genuine cloud-init first boot. This mirrors what DigitalOcean's
provider does automatically via `ForceNew`, without requiring Scaleway's
provider to support it natively.

## Consequences

- `release:patch` for `scaleway/compute-instance` — this fixes existing,
  documented behavior; no input or output changes.
- Every future change to `buckets`, the installed `packages` list, or any
  other part of the rendered cloud-init content will now replace the
  instance, not just patch its metadata. This is a behavior change for
  *future* applies — previously-silent no-op cloud-init edits now show up as
  a `-/+` replace in `tofu plan`, which is the point.
- Does **not** retroactively fix any instance that is already running with
  skipped cloud-init modules — an instance that predates this fix needs a
  one-time manual rebuild (or `cloud-init clean --logs --reboot` run by hand
  on the box) to pick up rclone/neovim and the rclone config. Confirming
  that a *new* apply now behaves correctly requires actually applying
  against a live Scaleway project, which is out of scope for this repo/ADR
  to verify directly.
- `terraform/modules/scaleway/compute-instance/README.md` is unaffected —
  no input/output table changes, so `module-docs.yml` produces no diff on
  merge.

## Out of scope

- Retroactively repairing any already-running instance — an operational
  follow-up for whoever owns that instance, not a module concern.
- The commented-out `terraform/infrastructure/.../custodian/dhj/compute.tf`
  itself — that's the user's own in-progress infrastructure config, not
  governed by this ADR.
- Making non-cloud-init changes (e.g. `type`, `enable_ipv6`, `ssh_keys`)
  also force replacement — they already do or don't per the provider's own
  schema, and that's unrelated to the cloud-init staleness bug this ADR
  fixes.
