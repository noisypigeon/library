# ADR-0145: one shared Private Network for the whole cluster -- every job
# instance that wants one attaches to this same PN (never one per job), so
# bucket traffic routed to Scaleway's private Object Storage endpoint
# (s3-vpc.<region>.scw.eu) avoids public-internet egress billing. Enabling
# Object Storage private access itself (authorizing this PN to reach
# buckets privately) is a manual, one-time step against the Scaleway VPC
# API -- not automated here, see ADR-0145.
# ADR-0149: count-gated (previously unconditional) -- cluster_config.
# enable_private_network can be flipped off independently of
# enable_public_gateway once no remaining job needs it; see the moved
# block below protecting existing callers' state through this change.
resource "scaleway_vpc_private_network" "jobs" {
  count      = var.cluster_config.enable_private_network ? 1 : 0
  name       = "${var.cluster_config.name_prefix}-jobs"
  project_id = var.cluster_config.project_id
}

# ADR-0145/ADR-0146: by default no job instance gets a public IP, so this
# shared Public Gateway is their only path to the public internet --
# cloud-init's apt-get/mise-install/curl/scw-CLI-install steps all need it.
# enable_masquerade/push_default_route must be set explicitly; neither
# defaults on. This same gateway IP also fronts the optional bastion's PAT
# rule below when cluster_config.enable_bastion is true.
# ADR-0149: count-gated (previously unconditional) -- independent of
# enable_private_network, so the gateway (and its stable IP) can keep
# running even once the PN is torn down, or vice versa.
resource "scaleway_vpc_public_gateway_ip" "jobs" {
  count      = var.cluster_config.enable_public_gateway ? 1 : 0
  project_id = var.cluster_config.project_id
}

resource "scaleway_vpc_public_gateway" "jobs" {
  # ADR-0145: move_to_ipam deliberately omitted -- confirmed deprecated
  # against the installed provider (v2.86.0): "All gateways now use IPAM.
  # This field is no longer needed."
  count      = var.cluster_config.enable_public_gateway ? 1 : 0
  name       = "${var.cluster_config.name_prefix}-jobs-gw"
  type       = var.cluster_config.public_gateway_type
  ip_id      = scaleway_vpc_public_gateway_ip.jobs[0].id
  project_id = var.cluster_config.project_id
}

# ADR-0149: requires both the PN and the gateway to exist -- gated on the
# conjunction of both toggles, rather than inheriting either resource's own
# count, since this is the one resource that genuinely needs both IDs.
resource "scaleway_vpc_gateway_network" "jobs" {
  count              = var.cluster_config.enable_private_network && var.cluster_config.enable_public_gateway ? 1 : 0
  gateway_id         = scaleway_vpc_public_gateway.jobs[0].id
  private_network_id = scaleway_vpc_private_network.jobs[0].id
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }
}

# ADR-0149: these four resources moved from unconditional singletons to
# count = ... ? 1 : 0 above -- same precedent as ADR-0126's compute-instance
# kill switch. Protects any existing caller's state through the address
# change.
moved {
  from = scaleway_vpc_private_network.jobs
  to   = scaleway_vpc_private_network.jobs[0]
}

moved {
  from = scaleway_vpc_public_gateway_ip.jobs
  to   = scaleway_vpc_public_gateway_ip.jobs[0]
}

moved {
  from = scaleway_vpc_public_gateway.jobs
  to   = scaleway_vpc_public_gateway.jobs[0]
}

moved {
  from = scaleway_vpc_gateway_network.jobs
  to   = scaleway_vpc_gateway_network.jobs[0]
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
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v5.6.1"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = each.key

  self_delete_on_exit = true
  keyring             = values(local.effective_keyring[each.key])

  # ADR-0145/ADR-0146: by default every job attaches to the cluster's one
  # shared Private Network and gets no public IP of its own (NAT'd through
  # the cluster's Public Gateway instead) -- use cluster_config.enable_bastion
  # for debug SSH access. ADR-0149: a job may opt out entirely
  # (enable_private_network = false, a plain public-IP compute-instance with
  # no dependency on the cluster's shared networking) or keep its PN
  # attachment while also requesting its own public IP (enable_ipv4 = true).
  # try(...) guards the PN lookup since that resource is now conditional
  # (cluster_config.enable_private_network) -- if a job still requests
  # enable_private_network = true against a cluster with it disabled, the
  # resulting null private_network_id trips compute-instance's own
  # validation rather than this module duplicating the check.
  private_network_id     = each.value.enable_private_network ? try(scaleway_vpc_private_network.jobs[0].id, null) : null
  enable_private_network = each.value.enable_private_network
  enable_ipv4            = each.value.enable_private_network ? each.value.enable_ipv4 : true

  instance_config = {
    type    = each.value.instance_type
    cockpit = var.cluster_config.cockpit
    block_volume = each.value.block_volume_size == null ? null : {
      size       = each.value.block_volume_size
      iops       = each.value.block_volume_iops
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

# ADR-0146: folded in from what was a one-off, fully commented-out leaf file
# (workloads/willowgraysen.com/terraform/pigeon-cli/cluster/bastion.tf) that
# confirmed the fix below. The cluster's shared Public Gateway advertises a
# default route (ipam_config.push_default_route, above) that takes priority
# over any attached instance's own public interface --
# https://www.scaleway.com/en/docs/public-gateways/troubleshooting/cant-connect-to-instance-with-pn-gateway/
# -- so a direct public IP on this bastion would not actually be reachable by
# SSH; it gets none (enable_ipv4 omitted, compute-instance's default of true
# deliberately overridden to false). The only working path is PAT through
# the gateway's own public IP, below.
module "bastion" {
  count       = var.cluster_config.enable_bastion ? 1 : 0
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v5.6.1"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = "bastion"

  enable_ipv4            = false
  private_network_id     = try(scaleway_vpc_private_network.jobs[0].id, null)
  enable_private_network = true
}

# Scaleway's own documented workaround for the routing conflict above: SSH to
# the gateway's public IP on an alternate port, PAT'd through to the
# bastion's private IP:22.
resource "scaleway_vpc_public_gateway_pat_rule" "bastion_ssh" {
  count = var.cluster_config.enable_bastion ? 1 : 0

  gateway_id = try(scaleway_vpc_public_gateway.jobs[0].id, null)
  # private_ips is dual-stack (IPv4 + IPv6) -- the gateway only tracks IPv4
  # addresses for PAT, so blindly indexing [0] can grab the IPv6 one instead.
  private_ip   = [for ip in module.bastion[0].private_ips : ip.address if !strcontains(ip.address, ":")][0]
  private_port = 22
  public_port  = 2222
  protocol     = "tcp"
}
