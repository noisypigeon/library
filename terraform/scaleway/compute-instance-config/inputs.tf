# ADR-0153: the cloud-init half of what used to be compute-instance's input
# surface. This module creates nothing -- it renders a cloud-init document from
# these inputs and returns it as a string, so that a provisioning change cuts a
# release here instead of in the module that owns the live server.

variable "keyring" {
  # LIB-0018: mirrors pigeon-cli's keyring.toml schema field for field.
  type = list(object({
    kind  = string # "email" | "bucket"
    alias = string

    # kind = "email" -- pigeon-cli's Identity
    email                = optional(string)
    provider             = optional(string) # gmail | fastmail | icloud | proton | custom
    host                 = optional(string)
    port                 = optional(number)
    secret               = optional(string)
    max_imap_connections = optional(number)

    # kind = "bucket" -- pigeon-cli's BucketConfig
    endpoint      = optional(string)
    bucket        = optional(string)
    access_key_id = optional(string)
    secret_key    = optional(string)
  }))
  description = "pigeon-cli keyring.toml entries, written to /root/.config/pigeon/keyring.toml (0600) with each secret in it: secret on an email identity, secret_key on a bucket (LIB-0018). Email entries require email, provider, host, port and secret; bucket entries require endpoint, bucket, access_key_id and secret_key. No rclone.conf is rendered and no PIGEON_SECRET_<ALIAS> is exported: pigeon-cli generates its own rclone.conf beside the keyring from the bucket entries."
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.keyring : contains(["email", "bucket"], e.kind)])
    error_message = "keyring.kind must be one of \"email\", \"bucket\"."
  }

  validation {
    condition     = alltrue([for e in var.keyring : can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", e.alias))])
    error_message = "keyring aliases must be lowercase alphanumeric with hyphens."
  }

  validation {
    condition     = length(var.keyring) == length(distinct([for e in var.keyring : e.alias]))
    error_message = "keyring aliases must be unique."
  }


  validation {
    condition     = alltrue([for e in var.keyring : e.kind != "email" || contains(["gmail", "fastmail", "icloud", "proton", "custom"], coalesce(e.provider, "custom"))])
    error_message = "keyring email provider must be one of \"gmail\", \"fastmail\", \"icloud\", \"proton\", \"custom\"."
  }

}

variable "cockpit" {
  type = object({
    metrics_push_url = string
    logs_push_url    = string
    token_secret     = string
    scrape_port      = optional(number, 9091)
  })
  description = "Cockpit/Alloy wiring (ADR-0102). null disables Alloy entirely -- no apt repo, no config.alloy, no PIGEON_LOG_DIR."
  default     = null
  sensitive   = true
}

variable "post_provision_commands" {
  type        = list(string)
  description = "Commands to run once, in order, as a self-disabling systemd oneshot unit ordered after cloud-init's own completion (cloud-final.service) rather than blocking it (ADR-0125). Inspect output with `journalctl -u pigeon-post-provision.service`. Defaults to [] -- nothing extra runs."
  default     = []
  sensitive   = true
}

variable "enable_transcoding" {
  type        = bool
  description = "Install a pinned, checksum-verified static ffmpeg 9.0.2 build into /usr/local/bin, for job commands that run `pigeon-cli transform` (ADR-0150, renamed by ADR-0151, reworked by ADR-0152). A static build is used rather than any apt package because grid-tiled HEIF images are only reconstructed by the ffmpeg CLI from 8.1 onwards, and no Ubuntu archive reaches that floor while every savoury1 PPA above ffmpeg4 needs a donation-gated private PPA. The pinned artifact is an x86_64 (linux64) binary: do not enable this for an arm64 instance type such as COPARM1-*."
  default     = false
}

variable "self_delete_on_exit" {
  type        = bool
  description = "Prepend a trap to the post-provision script that deletes this instance (with its IP and volumes) when the script exits, whether it succeeded or failed (ADR-0138). The instance discovers its own ID and zone at runtime from the Scaleway metadata service, so no Terraform-side instance reference is needed. Requires self_delete_credentials."
  default     = false
}

variable "self_delete_credentials" {
  type = object({
    access_key = string
    secret_key = string
    project_id = string
  })
  description = "IAM credentials the self-delete trap authenticates as. ADR-0153 moved minting these to the caller (pigeon-cluster composes an iam-policy/iam-api-key pair per job, kept separate from the job's own work credential so the keyring key never carries InstancesFullAccess). Ignored unless self_delete_on_exit is true. Note that rotating this key changes the rendered cloud-init, which replaces the server."
  default     = null
  sensitive   = true

  validation {
    condition     = !var.self_delete_on_exit || var.self_delete_credentials != null
    error_message = "self_delete_on_exit requires self_delete_credentials -- the instance needs its own IAM credential to delete itself."
  }
}

variable "has_attached_volume" {
  type        = bool
  description = "Whether a block volume is attached to this instance, which adds the mkfs/mount//etc/fstab steps for /dev/sdb at /mnt/data. A plain bool rather than the volume's ID, deliberately: the volume is created by the caller (ADR-0153), and a bool keeps the rendered document independent of apply-time-unknown values."
  default     = false
}

variable "keyring_wiring" {
  type = map(object({
    bucket        = optional(string)
    access_key_id = optional(string)
    secret_key    = optional(string)
  }))
  description = "Per-alias keyring fields another module's outputs fill, merged over the keyring entry of the same alias (LIB-0043 §4): a bucket's name, and an API key's access_key_id and secret_key. A null field leaves the entry's own value. Every key must be an alias in keyring."
  default     = {}
  sensitive   = true
  nullable    = false
}

variable "keyring_secrets" {
  type        = map(map(string))
  description = "Per-alias keyring fields that are secrets, merged over keyring and keyring_wiring by alias (LIB-0043 §4): a workload's secretRefs, resolved. Each inner key is a string field of the entry: email, host, secret, endpoint, bucket, access_key_id or secret_key. Every key must be an alias in keyring."
  default     = {}
  sensitive   = true
  nullable    = false

  validation {
    condition = alltrue(flatten([for alias, fields in var.keyring_secrets : [
      for k in keys(fields) : contains(["email", "host", "secret", "endpoint", "bucket", "access_key_id", "secret_key"], k)
    ]]))
    error_message = "keyring_secrets fields must be among email, host, secret, endpoint, bucket, access_key_id, secret_key."
  }
}
