#
# Instances follow a consistent naming scheme.
# Format: {name_prefix}-{random_code}-{name_suffix}
# I.e. example-com-q82q17-sample
#
variable "name_prefix" {
  type        = string
  description = "Instance name prefix"
}

variable "name_suffix" {
  type        = string
  description = "Instance name suffix"
}

variable "user_config" {
  type = object({
    ssh_key = optional(string)
  })
  description = "Per-instance user/access configuration"
  default     = {}
}

variable "instance_config" {
  type = object({
    image = optional(string, "ubuntu_jammy")
    type  = optional(string, "STARDUST1-S")
    cockpit = optional(object({
      metrics_push_url = string
      logs_push_url    = string
      token_secret     = string
      scrape_port      = optional(number, 9091)
    }))
    block_volume = optional(object({
      size                  = optional(number)
      iops                  = optional(number, 15000)
      project_id            = optional(string)
      additional_volume_ids = optional(list(string), [])
    }))
  })
  description = "Instance-level configuration: image, commercial type, Cockpit/Alloy wiring (ADR-0102), and block volume attachment (ADR-0120). null cockpit disables Alloy entirely. null block_volume attaches nothing; block_volume.size unset skips creating a managed volume but still attaches block_volume.additional_volume_ids."
  default     = {}
  sensitive   = true

  validation {
    condition     = var.instance_config.block_volume == null || var.instance_config.block_volume.size == null || var.instance_config.block_volume.project_id != null
    error_message = "instance_config.block_volume.project_id is required when instance_config.block_volume.size is set."
  }
}

variable "keyring" {
  type = list(object({
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
  }))
  description = "pigeon-cli keyring.toml entries. kind = \"bucket\" entries also generate an rclone.conf remote; any entry with secret_key set also exports PIGEON_SECRET_<ALIAS> on the instance. secret_key is never written into keyring.toml itself."
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.keyring : contains(["email", "bucket", "encryption-key"], e.kind)])
    error_message = "keyring.kind must be one of \"email\", \"bucket\", \"encryption-key\"."
  }

  validation {
    condition     = alltrue([for e in var.keyring : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", e.alias))])
    error_message = "keyring aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.keyring) == length(distinct([for e in var.keyring : e.alias]))
    error_message = "keyring aliases must be unique."
  }
}

variable "iam_config" {
  type = object({
    application_id          = string
    project_ids             = optional(list(string))
    project_permission_sets = optional(list(string))
    description             = optional(string)
    api_key_expires_at      = optional(string)
  })
  description = "Composes an IAM policy + API key for this instance's application (ADR-0122). null (default): no policy/API key created. project_ids/project_permission_sets grant project-scoped permissions on the policy."
  default     = null
}

variable "enable_ipv4" {
  type        = bool
  description = "Create and attach a routed IPv4 address (true/false)"
  default     = true
}

variable "enable_ipv6" {
  type        = bool
  description = "Create and attach a routed IPv6 address (true/false)"
  default     = false
}
