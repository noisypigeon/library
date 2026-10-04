#
# Instances follow a consistent naming scheme.
# Format: {namespace}-{random_code}-{name}
# I.e. example-com-q82q17-sample
#
variable "namespace" {
  type        = string
  description = "Instance name prefix"
}

variable "name" {
  type        = string
  description = "Instance name suffix"
}

variable "image" {
  type        = string
  description = "Instance image (UUID or marketplace label)"
}

variable "type" {
  type        = string
  description = "Instance commercial type"
  default     = "STARDUST1-S"
}

variable "profile" {
  type        = string
  description = "Cloud-init provisioning profile: \"docker\" (Docker CE), or \"pigeon-cli\" (rclone/neovim + rclone.conf from buckets, plus runs the pigeon-cli bootstrap script directly on first boot)"
  default     = "pigeon-cli"

  validation {
    condition     = contains(["docker", "pigeon-cli"], var.profile)
    error_message = "profile must be \"docker\" or \"pigeon-cli\"."
  }
}

variable "buckets" {
  type = list(object({
    bucket_name       = string
    bucket_alias      = string
    bucket_endpoint   = string
    bucket_access_key = string
    bucket_secret_key = string
    bucket_provider   = string
  }))
  description = "Buckets to configure in rclone; only used when profile = \"pigeon-cli\""
  default     = []

  validation {
    condition     = alltrue([for b in var.buckets : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", b.bucket_alias))])
    error_message = "Bucket aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.buckets) == length(distinct([for b in var.buckets : b.bucket_alias]))
    error_message = "Bucket aliases must be unique."
  }

  validation {
    condition     = var.profile == "pigeon-cli" || length(var.buckets) == 0
    error_message = "buckets is only used when profile = \"pigeon-cli\"."
  }
}

variable "keyring_entries" {
  type = list(object({
    kind  = string
    alias = string

    # kind = "email"
    email                = optional(string)
    provider             = optional(string)
    host                 = optional(string)
    port                 = optional(number)
    max_imap_connections = optional(number)

    # kind = "bucket"
    endpoint             = optional(string)
    bucket               = optional(string)
    access_key_id        = optional(string)
    encryption_key_alias = optional(string)

    # kind = "encryption-key"
    created_at = optional(string)
  }))
  description = "pigeon-cli keyring.toml entries; only used when profile = \"pigeon-cli\""
  default     = []

  validation {
    condition     = alltrue([for e in var.keyring_entries : contains(["email", "bucket", "encryption-key"], e.kind)])
    error_message = "keyring_entries.kind must be one of \"email\", \"bucket\", \"encryption-key\"."
  }

  validation {
    condition     = alltrue([for e in var.keyring_entries : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", e.alias))])
    error_message = "keyring_entries aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.keyring_entries) == length(distinct([for e in var.keyring_entries : e.alias]))
    error_message = "keyring_entries aliases must be unique."
  }

  validation {
    condition     = var.profile == "pigeon-cli" || length(var.keyring_entries) == 0
    error_message = "keyring_entries is only used when profile = \"pigeon-cli\"."
  }
}

variable "environment_variables" {
  type        = map(string)
  description = "Key/value environment variables exported on the instance for any profile (e.g. pigeon-cli secrets, by convention named PIGEON_SECRET_<ALIAS> but not enforced by this module)"
  default     = {}
  sensitive   = true

  validation {
    condition     = alltrue([for k in keys(var.environment_variables) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k))])
    error_message = "environment_variables keys must be valid shell variable names."
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

variable "ssh_keys" {
  type        = list(string)
  description = "SSH public keys granted instance-specific access via Scaleway's AUTHORIZED_KEY tag convention, in addition to account-wide keys"
  default     = []
}

variable "additional_volume_ids" {
  type        = list(string)
  description = "IDs of pre-created block volumes (e.g. scaleway/block-volume's id output) to attach to the instance"
  default     = []
}

variable "cockpit" {
  type = object({
    metrics_push_url = string
    logs_push_url    = string
    token_secret     = string
    scrape_port      = optional(number, 9091)
  })
  description = "Scaleway Cockpit wiring for an on-host Grafana Alloy agent that tails pigeon-cli's JSONL log and scrapes its Prometheus metrics endpoint (ADR-0102); only used when profile = \"pigeon-cli\". null disables Alloy entirely."
  default     = null
  sensitive   = true

  validation {
    condition     = var.profile == "pigeon-cli" || var.cockpit == null
    error_message = "cockpit is only used when profile = \"pigeon-cli\"."
  }
}
