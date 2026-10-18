# DEV-0081: add cloud-init rclone/neovim and bucket access to scaleway/compute-instance

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-30.
- **Status**: Accepted.

## Context

`terraform/modules/scaleway/compute-instance` (ADR-0079) is a deliberately
minimal wrapper around `scaleway_instance_server` — no `user_data`/cloud-init
support at all, by design, pending real usage. `digitalocean/droplet` is the
DigitalOcean analog and already has this machinery: its cloud-init installs
`rclone` and `neovim` (alongside `lvm2`, for its LVM auto-combine feature)
via a `packages:` list, and writes `/home/${var.user_name}/.config/rclone/
rclone.conf` from a `buckets` variable — `list(object({bucket_name,
bucket_alias, bucket_endpoint, bucket_access_key, bucket_secret_key,
bucket_provider}))` — looping with `%{~ for ~}` to emit one `alias` remote
plus one `s3` remote per bucket. Notably, droplet does **not** create the
bucket access key itself: the caller resolves `bucket_access_key`/
`bucket_secret_key` externally and passes them in already-populated.

Real usage now needs the Scaleway equivalent: instances that pre-install
`rclone` and `neovim`, and can be configured with rclone access to specific
Scaleway Object Storage buckets. Unlike droplet's "port everything" scope
(LVM, sudo-user creation, SSH-key data source), this only ports the parts
that are actually needed: package installation and bucket-scoped rclone
config.

**`scaleway_instance_server` does not have a `cloud_init` argument.** Per
the provider's resource docs, cloud-init is supplied via `user_data`, a
`map(string)` argument, using the `"cloud-init"` key — e.g. `user_data = {
cloud-init = file(...) }`. This is a different shape from
`digitalocean_droplet.user_data`, which is a plain heredoc string.

**Scaleway needs no SSH-key/user-creation machinery to get this working.**
Droplet's `users:` cloud-init block and `ssh_key_name` data source exist
because DigitalOcean droplets don't automatically grant account SSH keys to
new instances. Scaleway instances do — the organization's account-level SSH
keys are injected automatically outside Terraform, and marketplace images
provision `root` as the default login identity. So this ADR writes
`rclone.conf` to `/root/.config/rclone/rclone.conf` directly rather than
porting droplet's sudo-user creation.

**Bucket access key creation stays a caller responsibility, not a module
one.** `scaleway/iam-policy` (hardened by ADR-0066/0069/0070) already
supports exactly the "bucket-scoped key" need: `bucket_names` (map),
`bucket_actions` (a subset of `s3:ListBucket`/`s3:GetObject`/`s3:PutObject`/
`s3:DeleteObject`), `admin_project_id` (avoids the ADR-0069 self-lockout),
and outputs `access_key`/`secret_key` (sensitive). No changes are needed
there. `compute-instance` and `iam-policy` stay independent sibling
modules with independent release cycles — mirroring how droplet itself
never created its own bucket credentials, and consistent with every other
module pairing in this repo (~~no module in `terraform/modules/` invokes
another local module internally~~ superseded by ADR-0120, narrowly for the
`block-volume`/`compute-instance` pairing — the principle otherwise still
holds, including for `iam-policy`/`compute-instance` here).

## Decision

### `scaleway/compute-instance`: cloud-init via `user_data`

`instance.tf` gains a `user_data` block on `scaleway_instance_server`:

```hcl
resource "scaleway_instance_server" "server" {
  name  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image = var.image
  type  = var.type

  user_data = {
    cloud-init = <<-EOF
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
}
```

`packages:` always installs `rclone` + `neovim`, unconditionally — no
`lvm2`, no LVM auto-combine script, no sudo-user creation, no welcome
message. `write_files` for `rclone.conf` stays `%{~ for ~}`-looped even
when `buckets` is empty: an empty list renders an empty `content:` block,
which is harmless (rclone with no configured remotes is a no-op), so no
separate conditional is needed to skip the file entirely.

### `scaleway/compute-instance`: new `buckets` variable

`inputs.tf` gains, reusing droplet's schema and alias validations:

```hcl
variable "buckets" {
  type = list(object({
    bucket_name       = string
    bucket_alias      = string
    bucket_endpoint   = string
    bucket_access_key = string
    bucket_secret_key = string
    bucket_provider   = string
  }))
  description = "Buckets to configure in rclone (rclone/neovim always install regardless)"
  default     = []

  validation {
    condition     = alltrue([for b in var.buckets : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", b.bucket_alias))])
    error_message = "Bucket aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.buckets) == length(distinct([for b in var.buckets : b.bucket_alias]))
    error_message = "Bucket aliases must be unique."
  }
}
```

**`buckets` is optional, default `[]` — unlike droplet's required,
non-empty `buckets`.** `compute-instance` is a general-purpose module, not
an rclone-specific one; forcing every caller to supply bucket config even
when they have no rclone use case would contradict that. Droplet's "at
least one bucket" validation is dropped accordingly — only the alias-format
and alias-uniqueness validations carry over.

`bucket_provider` is expected to be `"Scaleway"` (rclone's built-in
S3-provider name for Scaleway Object Storage) and `bucket_endpoint`
something like `s3.fr-par.scw.cloud` / `s3.nl-ams.scw.cloud` (per ADR-0080's
two live regions) — documented as guidance, not validated, matching how
droplet never validates `bucket_provider` either.

### Bucket access key: compose `scaleway/iam-policy` externally

No changes to `scaleway/iam-policy`. The intended composition pattern, at
the infrastructure/Terragrunt layer:

```hcl
module "iam" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/iam-policy?ref=terraform/modules/scaleway/iam-policy/v1.1.1"
  name   = "${module.bucket.name}-iam"

  bucket_names = {
    data = module.bucket.name
  }
  bucket_actions = [
    "s3:ListBucket",
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
  ]
  admin_project_id = local.scaleway_project_id
}

module "instance" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/compute-instance?ref=..."
  # ...
  buckets = [{
    bucket_name       = module.bucket.name
    bucket_alias      = "data"
    bucket_endpoint   = "s3.fr-par.scw.cloud"
    bucket_access_key = module.iam.access_key
    bucket_secret_key = module.iam.secret_key
    bucket_provider   = "Scaleway"
  }]
}
```

All four `bucket_actions` are recommended for full rclone sync capability
(list, read, write, delete). `admin_project_id` should always be set to the
applying identity's own project, per ADR-0069, to avoid a bucket-policy
self-lockout.

## Consequences

- `release:minor` for `scaleway/compute-instance` — `user_data` and
  `buckets` are both new, backwards-compatible, optional-by-default inputs.
- `terraform/modules/scaleway/compute-instance/README.md` regenerates
  automatically via `module-docs.yml` on merge.
- `scaleway/iam-policy` is untouched — no release triggered there.
- Consumers wanting rclone bucket access must compose two module calls
  (`iam-policy` + `compute-instance`) themselves at the infrastructure
  layer; this ADR adds no shortcut/wrapper for that composition.

## Out of scope

- Everything ADR-0079 already deferred and this ADR doesn't touch: root
  volume sizing, additional volumes, security/placement groups, `ip_id`/
  `enable_dynamic_ip`, `tags`, `private_network`, zone/project overrides,
  `state`, Windows admin password support, `type` enum validation, attaching
  to an existing root volume.
- SSH-key management / non-root user creation (droplet's `users:` block +
  `ssh_key_name` data source) — Scaleway's automatic account-level SSH key
  injection makes this unnecessary for now.
- LVM auto-combine / attached-volume machinery from droplet.
- Cloudflare DNS wiring — already removed from droplet itself (`2.0.0`),
  never existed in `compute-instance`, not being added here.
- A wrapper or nested-module composition that creates the `iam-policy`
  application/key automatically from inside `compute-instance` —
  deliberately rejected in favor of external composition (see Context/
  Decision above). Unaffected by ADR-0120, which composes `block-volume`
  (not `iam-policy`) inside `compute-instance` as a one-off named
  exception.
