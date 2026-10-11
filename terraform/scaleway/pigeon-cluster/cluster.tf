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

# ADR-0153: a job's per-job derived maps, computed once. Each keys off a
# jobs[*] field only -- never a resource ID -- because every for_each below
# consumes them, and ADR-0145 Section 4 established that count/for_each can
# never depend on an apply-time-unknown value.
locals {
  jobs_with_volume = { for k, v in local.jobs_by_name : k => v if v.block_volume_size != null }

  # ADR-0149: a job that opts out of the Private Network is forced onto its own
  # public IP, since it would otherwise have no route at all.
  job_wants_ipv4 = { for k, v in local.jobs_by_name : k => v.enable_private_network ? v.enable_ipv4 : true }

  jobs_on_private_network = { for k, v in local.jobs_by_name : k => v if v.enable_private_network }
}

# ADR-0138: one IAM application + one self-deleting compute-instance per job,
# so each job's blast radius is its own grants/keyring, never shared with a
# sibling job in the same cluster. Pinned to released tags per ADR-0121.
module "job_application" {
  for_each = local.jobs_by_name
  source   = "https://pigeon.dev/modules/scaleway/iam-application/v0.1.0"
  name     = "${var.cluster_config.name_prefix}-${each.key}"
}

# ADR-0144: pigeon-cluster composes its own policy/key per job so the
# resulting key can be read back here and used as the job's keyring default
# before the job's instance is even built. iam-policy requires at least one
# non-empty permission grant, so job_policy is skipped for a job with no
# extra_permission_sets and no shared_permission_sets.
locals {
  job_permission_sets = {
    for k, v in local.jobs_by_name : k => distinct(concat(var.cluster_config.shared_permission_sets, v.extra_permission_sets))
  }
}

module "job_policy" {
  for_each = { for k, v in local.job_permission_sets : k => v if length(v) > 0 }
  source   = "https://pigeon.dev/modules/scaleway/iam-policy/v4.0.0"
  # ADR-0153: this used to need a distinct "-work-" segment, because
  # compute-instance's own internal self-delete policy named itself
  # "${name_prefix}-${name_suffix}-iam-policy" and Scaleway rejects duplicate
  # policy names with a 409. Both policies are now named here, so the
  # collision is visible and avoided by the self-delete one's own name below.
  name = "${var.cluster_config.name_prefix}-${each.key}-iam-policy"

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

# ADR-0153: lifted out of compute-instance, which used to compose these two
# itself (ADR-0122). Kept as a second, separate policy/key pair rather than
# folded into job_policy/job_api_key above: ADR-0144 deliberately narrowed the
# self-delete grant to InstancesFullAccess and nothing else, and merging would
# hand the job's own keyring credential the right to delete instances.
module "job_self_delete_policy" {
  for_each = local.jobs_by_name
  source   = "https://pigeon.dev/modules/scaleway/iam-policy/v4.0.0"
  name     = "${var.cluster_config.name_prefix}-${each.key}-self-delete-iam-policy"

  application_id          = module.job_application[each.key].id
  project_ids             = [var.cluster_config.project_id]
  project_permission_sets = ["InstancesFullAccess"]
}

module "job_self_delete_key" {
  for_each = local.jobs_by_name
  source   = "https://pigeon.dev/modules/scaleway/iam-api-key/v0.2.0"

  application_id     = module.job_application[each.key].id
  description        = "${var.cluster_config.name_prefix}-${each.key} self-delete key"
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

# ADR-0153: lifted out of compute-instance, which used to compose block-volume
# itself (ADR-0120). ADR-0120's justification was that the pairing was always
# 1:1 with exactly one consumer; here each job decides independently whether
# it wants a volume, so it isn't.
module "job_block_volume" {
  for_each = local.jobs_with_volume
  source   = "https://pigeon.dev/modules/scaleway/block-volume/v4.0.0"

  name_prefix = var.cluster_config.name_prefix
  name_suffix = each.key
  size        = each.value.block_volume_size
  iops        = each.value.block_volume_iops
  project_id  = var.cluster_config.project_id
}

# ADR-0153: cloud-init is rendered here, one document per job, so a
# provisioning change cuts a compute-instance-config release and a re-pin
# rather than a new version of the module that owns the live server.
module "job_config" {
  for_each = local.jobs_by_name
  source   = "https://pigeon.dev/modules/scaleway/compute-instance-config/v0.1.0"

  keyring            = values(local.effective_keyring[each.key])
  cockpit            = var.cluster_config.cockpit
  enable_transcoding = each.value.enable_transcoding

  # ADR-0144: job_commands are rendered through templatestring so a caller can
  # reference a keyring entry by alias (e.g. "${keyring.fastmail.alias}")
  # instead of hand-typing a literal that only matches by convention.
  post_provision_commands = [
    for cmd in each.value.job_commands : templatestring(cmd, { keyring = local.effective_keyring[each.key] })
  ]

  self_delete_on_exit = true
  self_delete_credentials = {
    access_key = module.job_self_delete_key[each.key].access_key
    secret_key = module.job_self_delete_key[each.key].secret_key
    project_id = var.cluster_config.project_id
  }

  # Drives cloud-init's mkfs/mount//etc/fstab block for /dev/sdb. Derived from
  # the job's own config rather than from the volume's ID, so the rendered
  # document never depends on an apply-time-unknown value.
  has_attached_volume = contains(keys(local.jobs_with_volume), each.key)
}

# ADR-0153: lifted out of compute-instance. An IP has to exist before the
# server that references it via ip_ids, so it cannot be created by the same
# module that creates the server and attached in one step.
resource "scaleway_instance_ip" "job_ipv4" {
  for_each = { for k, v in local.job_wants_ipv4 : k => v if v }
  type     = "routed_ipv4"
}

module "job" {
  for_each    = local.jobs_by_name
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v7.0.0"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = each.key

  type       = each.value.instance_type
  cloud_init = module.job_config[each.key].cloud_init

  ip_ids                = local.job_wants_ipv4[each.key] ? [scaleway_instance_ip.job_ipv4[each.key].id] : []
  additional_volume_ids = contains(keys(local.jobs_with_volume), each.key) ? [module.job_block_volume[each.key].id] : []
}

# ADR-0153: lifted out of compute-instance. Still a standalone resource rather
# than an inline private_network block on the server, for ADR-0145's original
# reason: attaching or detaching must never force server replacement. This now
# sits next to the Private Network it attaches to, which pigeon-cluster
# already owned.
resource "scaleway_instance_private_nic" "job" {
  for_each = local.jobs_on_private_network

  server_id          = module.job[each.key].id
  private_network_id = scaleway_vpc_private_network.jobs[0].id
}

# ADR-0146: the cluster's shared Public Gateway advertises a default route
# (ipam_config.push_default_route, above) that takes priority over any attached
# instance's own public interface --
# https://www.scaleway.com/en/docs/public-gateways/troubleshooting/cant-connect-to-instance-with-pn-gateway/
# -- so a direct public IP on this bastion would not actually be reachable by
# SSH; it gets none. The only working path is PAT through the gateway's own
# public IP, below.
#
# ADR-0153: the bastion's cloud-init is the module's defaults -- no keyring, no
# Cockpit, no post-provision commands, no self-deletion -- which is exactly
# what it got before, when it passed no instance_config at all.
module "bastion_config" {
  count  = var.cluster_config.enable_bastion ? 1 : 0
  source = "https://pigeon.dev/modules/scaleway/compute-instance-config/v0.1.0"
}

module "bastion" {
  count       = var.cluster_config.enable_bastion ? 1 : 0
  source      = "https://pigeon.dev/modules/scaleway/compute-instance/v7.0.0"
  name_prefix = var.cluster_config.name_prefix
  name_suffix = "bastion"

  cloud_init = module.bastion_config[0].cloud_init
}

resource "scaleway_instance_private_nic" "bastion" {
  count = var.cluster_config.enable_bastion ? 1 : 0

  server_id          = module.bastion[0].id
  private_network_id = scaleway_vpc_private_network.jobs[0].id
}

resource "scaleway_vpc_public_gateway_pat_rule" "bastion_ssh" {
  count = var.cluster_config.enable_bastion ? 1 : 0

  gateway_id = try(scaleway_vpc_public_gateway.jobs[0].id, null)
  # private_ips is dual-stack (IPv4 + IPv6) -- the gateway only tracks IPv4
  # addresses for PAT, so blindly indexing [0] can grab the IPv6 one instead.
  #
  # ADR-0153: read from the NIC resource directly. This used to go through
  # compute-instance's private_ips output, which existed only to work around
  # scaleway_instance_server's own private_ips attribute not reflecting a
  # separately-attached NIC. With the NIC in this module there is one
  # authoritative source and no fallback needed.
  private_ip   = [for ip in scaleway_instance_private_nic.bastion[0].private_ips : ip.address if !strcontains(ip.address, ":")][0]
  private_port = 22
  public_port  = 2222
  protocol     = "tcp"
}
