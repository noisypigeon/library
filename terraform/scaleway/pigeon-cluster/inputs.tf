variable "cluster_config" {
  type = object({
    name_prefix = string
    project_id  = string
    cockpit = optional(object({
      metrics_push_url = string
      logs_push_url    = string
      token_secret     = string
      scrape_port      = optional(number, 9091)
    }))
    shared_keyring = optional(map(object({
      kind = string

      # kind = "email"
      email                = optional(string)
      provider             = optional(string)
      host                 = optional(string)
      port                 = optional(number)
      max_imap_connections = optional(number)

      # kind = "bucket" -- also generates an rclone.conf remote; access_key_id/secret_key
      # default to the consuming job's own API key when omitted (see `jobs`)
      endpoint             = optional(string)
      bucket               = optional(string)
      access_key_id        = optional(string)
      secret_key           = optional(string)
      encryption_key_alias = optional(string)

      # kind = "encryption-key"
      created_at = optional(string)
    })), {})
    shared_permission_sets = optional(list(string), [])
    # ADR-0146: default false -- no bastion is created. true provisions one
    # debug-SSH instance on the cluster's shared Private Network, reachable
    # only through the shared Public Gateway's PAT rule (see outputs.bastion_connect_command),
    # not via its own public IP -- a direct public IP on an instance attached
    # to this PN doesn't actually work, see cluster.tf's module.bastion comment.
    enable_bastion = optional(bool, false)
    # Scaleway offer type for the cluster's shared Public Gateway (default
    # matches today's hardcoded behavior). Changing this upgrades the
    # existing gateway in place via Scaleway's UpgradeGateway API -- same
    # gateway ID/IP, no job or bastion instance needs to restart or
    # reconnect to benefit. Upgrade-only: Scaleway doesn't support
    # downgrading a gateway back to a smaller tier afterward.
    public_gateway_type = optional(string, "VPC-GW-S")
    # ADR-0149: independent kill switches for the cluster's two shared
    # networking resources. Both default true (today's unconditional
    # behavior). Set enable_private_network = false once no remaining job
    # needs the shared Private Network (e.g. every job has completed or
    # opted out via jobs[*].enable_private_network) to tear it down -- the
    # Public Gateway can keep running untouched (e.g. still fronting the
    # bastion's PAT rule) since the two are independent. Set
    # enable_public_gateway = false to tear down the metered gateway once
    # nothing needs internet/private-Object-Storage egress, leaving the
    # (free) Private Network provisioned for later. enable_bastion requires
    # both to be true (see validation below) -- the bastion is reachable
    # only via the gateway's PAT rule onto the shared PN.
    enable_private_network = optional(bool, true)
    enable_public_gateway  = optional(bool, true)
  })
  description = "Settings shared by every job instance in this cluster, including a default keyring and permission grant every job inherits unless overridden."

  validation {
    condition     = contains(["VPC-GW-S", "VPC-GW-M", "VPC-GW-L", "VPC-GW-XL"], var.cluster_config.public_gateway_type)
    error_message = "cluster_config.public_gateway_type must be one of VPC-GW-S, VPC-GW-M, VPC-GW-L, VPC-GW-XL."
  }

  validation {
    condition     = !var.cluster_config.enable_bastion || (var.cluster_config.enable_private_network && var.cluster_config.enable_public_gateway)
    error_message = "cluster_config.enable_bastion requires enable_private_network and enable_public_gateway to both be true."
  }
}

variable "jobs" {
  type = list(object({
    job_name          = string
    job_commands      = list(string)
    instance_type     = optional(string, "STARDUST1-S")
    block_volume_size = optional(number)
    block_volume_iops = optional(number, 15000)
    keyring = optional(map(object({
      kind = string

      # kind = "email"
      email                = optional(string)
      provider             = optional(string)
      host                 = optional(string)
      port                 = optional(number)
      max_imap_connections = optional(number)

      # kind = "bucket" -- also generates an rclone.conf remote
      endpoint             = optional(string)
      bucket               = optional(string)
      access_key_id        = optional(string)
      secret_key           = optional(string)
      encryption_key_alias = optional(string)

      # kind = "encryption-key"
      created_at = optional(string)
    })), {})
    extra_permission_sets = optional(list(string), [])
    # ADR-0149: default true preserves today's behavior -- this job attaches
    # to the cluster's shared Private Network. false makes this job a plain,
    # undecorated compute-instance call: no private NIC, no dependency on
    # the cluster's shared PN/Gateway at all. Requires cluster_config's own
    # enable_private_network/enable_public_gateway to still be true for this
    # job -- if the cluster has disabled its shared PN while this stays
    # true, compute-instance's own validation will fail the plan
    # ("private_network_id must be set when enable_private_network is
    # true"), since pigeon-cluster doesn't duplicate that check itself.
    enable_private_network = optional(bool, true)
    # ADR-0149: reinstates the per-job public-IP override ADR-0146 removed.
    # When enable_private_network is true, this job gets enable_ipv4's exact
    # value (default false, matching prior behavior) -- note ADR-0146 found
    # a direct public IP on a PN-attached instance can't be reached by
    # inbound SSH while the cluster's gateway is still pushing a default
    # route (Scaleway's own documented behavior); this remains true here,
    # so set this only once cluster_config.enable_public_gateway is false,
    # or when only outbound use of the IP is needed. When
    # enable_private_network is false, this job always gets a public IP
    # regardless of this field's value -- it has no other network path.
    enable_ipv4 = optional(bool, false)
    # ADR-0150, renamed by ADR-0151: passed straight through to this job's
    # own compute-instance call. false (default) preserves today's behavior
    # -- no ffmpeg installed. true installs a general-purpose ffmpeg build,
    # for jobs whose job_commands run `pigeon-cli transform` (of any input
    # file type, not just heic).
    enable_transcoding = optional(bool, false)
  }))
  description = "Jobs to run right now, each entry naming its own job_name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra_permission_sets plus cluster_config.shared_permission_sets, and its own keyring (merged with cluster_config.shared_keyring, job-specific entries winning on alias collision) -- never shared with another job in this same cluster. Every kind = \"bucket\" keyring entry that omits access_key_id/secret_key defaults to this job's own API key (ADR-0144); job_commands strings may reference an entry by alias, e.g. \"--source '$${keyring.fastmail.alias}:'\" (use $${keyring[\"my-alias\"].alias} bracket syntax for a hyphenated alias). Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality. block_volume_iops defaults to 15000, matching block-volume's and compute-instance's own defaults. By default every job shares the cluster's Private Network/Public Gateway and gets no public IP (ADR-0146) -- use cluster_config.enable_bastion for debug SSH access, or set enable_private_network = false to opt this job out of the shared networking entirely (ADR-0149), or enable_ipv4 = true for a job that keeps its Private Network attachment but also wants its own public IP. enable_transcoding = true (ADR-0150, renamed by ADR-0151) installs a general-purpose ffmpeg build on this job's instance, for job_commands that run pigeon-cli transform -- any input file type, not just heic."

  validation {
    condition     = length(var.jobs) == length(distinct([for j in var.jobs : j.job_name]))
    error_message = "jobs[*].job_name must be unique."
  }

  # ADR-0153: compute-instance used to catch this one level down, with its own
  # "private_network_id must be set when enable_private_network is true"
  # validation -- ADR-0149 deliberately leaned on that instead of duplicating
  # the check here. That validation is gone now that the NIC is this module's
  # resource, so the check lands here, where it can name both variables.
  validation {
    condition     = var.cluster_config.enable_private_network || alltrue([for j in var.jobs : !j.enable_private_network])
    error_message = "a job with enable_private_network = true requires cluster_config.enable_private_network = true."
  }
}
