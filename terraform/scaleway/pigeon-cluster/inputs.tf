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
  })
  description = "Settings shared by every job instance in this cluster, including a default keyring and permission grant every job inherits unless overridden."

  validation {
    condition     = contains(["VPC-GW-S", "VPC-GW-M", "VPC-GW-L", "VPC-GW-XL"], var.cluster_config.public_gateway_type)
    error_message = "cluster_config.public_gateway_type must be one of VPC-GW-S, VPC-GW-M, VPC-GW-L, VPC-GW-XL."
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
  }))
  description = "Jobs to run right now, each entry naming its own job_name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra_permission_sets plus cluster_config.shared_permission_sets, and its own keyring (merged with cluster_config.shared_keyring, job-specific entries winning on alias collision) -- never shared with another job in this same cluster. Every kind = \"bucket\" keyring entry that omits access_key_id/secret_key defaults to this job's own API key (ADR-0144); job_commands strings may reference an entry by alias, e.g. \"--source '$${keyring.fastmail.alias}:'\" (use $${keyring[\"my-alias\"].alias} bracket syntax for a hyphenated alias). Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality. block_volume_iops defaults to 15000, matching block-volume's and compute-instance's own defaults. No job gets a public IP (ADR-0146) -- every job shares the cluster's Private Network/Public Gateway regardless; use cluster_config.enable_bastion for debug SSH access instead."

  validation {
    condition     = length(var.jobs) == length(distinct([for j in var.jobs : j.job_name]))
    error_message = "jobs[*].job_name must be unique."
  }
}
