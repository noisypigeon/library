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
    post_provision_commands = optional(list(string), [])
    enable_transcoding      = optional(bool, false)
  })
  description = "Instance-level configuration: image, commercial type, Cockpit/Alloy wiring (ADR-0102), block volume attachment (ADR-0120), and post-provision commands (ADR-0125). null cockpit disables Alloy entirely. null block_volume attaches nothing; block_volume.size unset skips creating a managed volume but still attaches block_volume.additional_volume_ids. post_provision_commands defaults to [] (nothing extra runs); when set, the commands run once, in order, as a systemd oneshot unit ordered after cloud-init's own completion (cloud-final.service) rather than blocking it -- inspect output with `journalctl -u pigeon-post-provision.service`. enable_transcoding (ADR-0150, renamed by ADR-0151; default false) installs ffmpeg from ppa:savoury1/ffmpeg4, for job commands that run `pigeon-cli transform`. That PPA is used rather than Ubuntu's own archive build specifically because it ships libheif-based HEIC decode support, which the archive build lacks -- without it, transform --input-file-type=heic fails fast on the first .heic file with ffmpeg's own \"decoder not found\" error -- but the build is a general-purpose one and the flag is not HEIC-specific."
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

variable "enabled" {
  type        = bool
  description = "Kill switch. false destroys every resource this module manages for this instance -- the server, its IP address(es), its block volume (and the volume's data -- this is a real data-loss event, not a pause), and its IAM policy/API key (ADR-0126) -- while the module block itself stays in the caller's configuration. true (default) runs normally. The instance's name (random suffix) stays stable across a disable/re-enable cycle."
  default     = true
}

variable "self_delete_on_exit" {
  type        = bool
  description = "When true, the instance deletes itself (server, IP(s), block volume) once post_provision_commands finishes, success or failure, using its own composed IAM API key (ADR-0138). Requires iam_config to be set -- the module folds the permission needed to delete itself into the composed IAM policy automatically, on top of whatever project_permission_sets the caller already requested."
  default     = false

  validation {
    condition     = !var.self_delete_on_exit || var.iam_config != null
    error_message = "self_delete_on_exit requires iam_config to be set -- the instance needs its own IAM credential to delete itself."
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

variable "private_network_id" {
  type        = string
  description = "ID of an existing Scaleway Private Network to attach this instance to via a dedicated private NIC (scaleway_instance_private_nic), alongside its normal public IP(s). null (default): no private NIC, unchanged behavior. Bring-your-own ID -- this module does not create the Private Network itself (see pigeon-cluster, which creates one shared PN per cluster and passes its ID here to every job instance). Whether the NIC is actually created is controlled by enable_private_network, not by this value's nullness -- see that variable's description."
  default     = null
}

variable "enable_private_network" {
  type        = bool
  description = "Whether to attach a scaleway_instance_private_nic using private_network_id. Kept separate from private_network_id (rather than gating on private_network_id != null) because that ID's value is frequently only known after apply -- e.g. a Private Network created in the same apply, as pigeon-cluster does -- and count/for_each can never depend on such a value without OpenTofu failing to plan with \"Invalid count argument\". default false."
  default     = false

  validation {
    condition     = !var.enable_private_network || var.private_network_id != null
    error_message = "private_network_id must be set when enable_private_network is true."
  }
}
