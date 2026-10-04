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
  })
  description = "Instance-level configuration: image, commercial type, and Cockpit/Alloy wiring (ADR-0102). null cockpit disables Alloy entirely."
  default     = {}
  sensitive   = true
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

variable "additional_volume_ids" {
  type        = list(string)
  description = "IDs of pre-created block volumes (e.g. scaleway/block-volume's id output) to attach to the instance"
  default     = []
}
