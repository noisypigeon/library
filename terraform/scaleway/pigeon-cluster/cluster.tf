# ADR-0145: one shared Private Network for the whole cluster -- every job
# instance attaches to this same PN (never one per job), so bucket traffic
# routed to Scaleway's private Object Storage endpoint (s3-vpc.<region>.scw.eu)
# avoids public-internet egress billing. Enabling Object Storage private
# access itself (authorizing this PN to reach buckets privately) is a manual,
# one-time step against the Scaleway VPC API -- not automated here, see
# ADR-0145.
resource "scaleway_vpc_private_network" "jobs" {
  name       = "${var.cluster_config.name_prefix}-jobs"
  project_id = var.cluster_config.project_id
}

# ADR-0145: job instances default to no public IP (jobs[*].enable_ipv4 =
# false) so this shared Public Gateway is their only path to the public
# internet -- cloud-init's apt-get/mise-install/curl/scw-CLI-install steps
# all need it. enable_masquerade/push_default_route must be set explicitly;
# neither defaults on.
resource "scaleway_vpc_public_gateway_ip" "jobs" {
  project_id = var.cluster_config.project_id
}

resource "scaleway_vpc_public_gateway" "jobs" {
  # ADR-0145: move_to_ipam deliberately omitted -- confirmed deprecated
  # against the installed provider (v2.86.0): "All gateways now use IPAM.
  # This field is no longer needed."
  name       = "${var.cluster_config.name_prefix}-jobs-gw"
  type       = "VPC-GW-S"
  ip_id      = scaleway_vpc_public_gateway_ip.jobs.id
  project_id = var.cluster_config.project_id
}

resource "scaleway_vpc_gateway_network" "jobs" {
  gateway_id         = scaleway_vpc_public_gateway.jobs.id
  private_network_id = scaleway_vpc_private_network.jobs.id
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }
}

# ADR-0145: jobs is caller-facing as a list (each entry names its own
# job_name), but for_each still needs a map for stable per-job resource
# addressing -- converted once here, keyed by job_name, and used everywhere
# var.jobs would otherwise be used directly. jobs's own validation block
# (inputs.tf) guarantees job_name is unique, so this conversion never
# silently drops an entry.
locals {
  jobs_by_name = { for j in var.jobs : j.job_name => j }
}

# ADR-0138: one IAM application + one self-deleting compute-instance per job,
# so each job's blast radius is its own grants/keyring, never shared with a
# sibling job in the same cluster. Pinned to released tags per ADR-0121.
module "job_application" {
  for_each = local.jobs_by_name
  source   = "https://pigeon.dev/modules/scaleway/iam-application/v0.1.0"
  name     = "${var.cluster_config.name_prefix}-${each.key}"
}

# ADR-0144: pigeon-cluster composes its own policy/key per job -- directly,
# not via compute-instance's internal self-delete-only composition -- so the
# resulting key can be read back here and used as the job's keyring default
# before module.job (compute-instance) is even built. iam-policy requires at
# least one non-empty permission grant, so job_policy is skipped for a job
# with no extra_permission_sets and no shared_permission_sets.
locals {
  job_permission_sets = {
    for k, v in local.jobs_by_name : k => distinct(concat(var.cluster_config.shared_permission_sets, v.extra_permission_sets))
  }
}

module "job_policy" {
  for_each = { for k, v in local.job_permission_sets : k => v if length(v) > 0 }
  source   = "https://pigeon.dev/modules/scaleway/iam-policy/v4.0.0"
  # ADR-0144 fix: compute-instance's own internal self-delete policy (iam.tf)
  # names itself "${name_prefix}-${name_suffix}-iam-policy" -- an identical
  # name here collided with it (Scaleway rejects duplicate policy names with
  # a 409), so this one gets a distinct "-work-" segment.
  name = "${var.cluster_config.name_prefix}-${each.key}-work-iam-policy"

  application_id          = module.job_application[each.key].id
  project_ids             = [var.cluster_config.project_id]
  project_permission_sets = each.value
}

module "job_api_key" {
  for_each = local.jobs_by_name
  source   = "https://pigeon.dev/modules/scaleway/iam-api-key/v0.2.0"

  application_id     = module.job_application[each.key].id
  description        = "${var.cluster_config.name_prefix}-${each.key} API key"
  default_project_id = var.cluster_config.project_id
}

# ADR-0144: merge cluster_config.shared_keyring under each job's own keyring
# (job-specific alias wins on collision), then default any kind = "bucket"
# entry's access_key_id/secret_key to this job's own API key above when the
# entry doesn't specify its own.
locals {
  effective_keyring = {
    for job_key, job in local.jobs_by_name : job_key => {
      for alias, entry in merge(var.cluster_config.shared_keyring, job.keyring) : alias => merge(entry, {
        alias         = alias
        access_key_id = entry.kind != "bucket" ? entry.access_key_id : coalesce(entry.access_key_id, module.job_api_key[job_key].access_key)
        secret_key    = entry.kind != "bucket" ? entry.secret_key : coalesce(entry.secret_key, module.job_api_key[job_key].secret_key)
      })
    }
  }
}

module "job" {
  for_each    = local.jobs_by_name
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v5.6.0"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = each.key

  self_delete_on_exit = true
  keyring             = values(local.effective_keyring[each.key])

  # ADR-0145: every job attaches to the cluster's one shared Private Network;
  # enable_ipv4 defaults false (NAT'd through the cluster's Public Gateway
  # instead), overridable per job for debugging. enable_private_network is
  # set unconditionally true (not gated on private_network_id != null) --
  # that ID is only known after apply on a fresh cluster (the PN above is
  # created in this same apply), and compute-instance's count can never
  # depend on such a value.
  private_network_id     = scaleway_vpc_private_network.jobs.id
  enable_private_network = true
  enable_ipv4            = each.value.enable_ipv4

  instance_config = {
    type    = each.value.instance_type
    cockpit = var.cluster_config.cockpit
    block_volume = each.value.block_volume_size == null ? null : {
      size       = each.value.block_volume_size
      project_id = var.cluster_config.project_id
    }
    # ADR-0144: job_commands are rendered through templatestring so a caller
    # can reference a keyring entry by alias (e.g. "${keyring.fastmail.alias}")
    # instead of hand-typing a literal that only matches by convention.
    post_provision_commands = [
      for cmd in each.value.job_commands : templatestring(cmd, { keyring = local.effective_keyring[each.key] })
    ]
  }

  iam_config = {
    application_id = module.job_application[each.key].id
    project_ids    = [var.cluster_config.project_id]
    # ADR-0144: narrowed to self-delete only (InstancesFullAccess, auto-folded
    # in by compute-instance) -- the job's real permissions now live entirely
    # on module.job_policy above, which is also what the keyring defaults to.
    project_permission_sets = []
  }
}
