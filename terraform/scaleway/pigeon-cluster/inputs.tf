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
  })
  description = "Settings shared by every job instance in this cluster, including a default keyring and permission grant every job inherits unless overridden."
}

variable "jobs" {
  type = list(object({
    job_name          = string
    job_commands      = list(string)
    instance_type     = optional(string, "STARDUST1-S")
    block_volume_size = optional(number)
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
    # ADR-0145: default false -- every job instance attaches to the cluster's
    # shared Private Network regardless, so losing the public IP by default
    # doesn't cost internet access (the cluster's Public Gateway NATs it).
    # Flip to true on one job's entry to get a public IP back temporarily,
    # e.g. to SSH directly into a specific failing instance.
    enable_ipv4 = optional(bool, false)
  }))
  description = "Jobs to run right now, each entry naming its own job_name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra_permission_sets plus cluster_config.shared_permission_sets, and its own keyring (merged with cluster_config.shared_keyring, job-specific entries winning on alias collision) -- never shared with another job in this same cluster. Every kind = \"bucket\" keyring entry that omits access_key_id/secret_key defaults to this job's own API key (ADR-0144); job_commands strings may reference an entry by alias, e.g. \"--source '$${keyring.fastmail.alias}:'\" (use $${keyring[\"my-alias\"].alias} bracket syntax for a hyphenated alias). Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality. enable_ipv4 defaults to false (ADR-0145) -- every job shares the cluster's Private Network/Public Gateway regardless, so set enable_ipv4 = true on a job to additionally attach a public IP, e.g. for debugging."

  validation {
    condition     = length(var.jobs) == length(distinct([for j in var.jobs : j.job_name]))
    error_message = "jobs[*].job_name must be unique."
  }
}
