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
  })
  description = "Settings shared by every job instance in this cluster."
}

variable "jobs" {
  type = map(object({
    job_commands      = list(string)
    instance_type     = optional(string, "STARDUST1-S")
    block_volume_size = optional(number)
    keyring = optional(list(object({
      kind  = string
      alias = string

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
    })), [])
    extra_permission_sets = optional(list(string), [])
  }))
  description = "Jobs to run right now, keyed by job name. Each entry becomes one self-deleting compute-instance (ADR-0138), with its own IAM application/policy/key scoped to exactly extra_permission_sets plus whatever self-deletion needs, and its own keyring -- never shared with another job in this same cluster. Remove an entry and re-apply once its instance has self-terminated, to reconcile Terraform state with reality."
}
