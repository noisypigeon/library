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

variable "image" {
  type        = string
  description = "Instance image label (e.g. ubuntu_jammy, ubuntu_noble, ubuntu_resolute)"
  default     = "ubuntu_jammy"
}

variable "type" {
  type        = string
  description = "Instance commercial type"
  default     = "STARDUST1-S"
}

variable "ssh_key" {
  type        = string
  description = "Public SSH key to authorize on the instance, passed through as an AUTHORIZED_KEY tag. Exactly one key, not a list (ADR-0118)."
  default     = null
}

# ADR-0153: this module no longer renders cloud-init -- it takes an
# already-rendered document, which compute-instance-config produces. Changing
# the document replaces the server, via terraform_data.cloud_init below. Note
# that this means rotating any secret the document embeds (notably the
# self-delete API key) also replaces the server.
variable "cloud_init" {
  type        = string
  description = "Rendered cloud-init document for user_data[\"cloud-init\"], normally compute-instance-config's cloud_init output. null attaches no user_data at all. Changing it replaces the instance."
  default     = null
  sensitive   = true
}

variable "ip_ids" {
  type        = list(string)
  description = "IDs of scaleway_instance_ip resources to attach. Created by the caller (ADR-0153) -- an IP must exist before the server that references it, so this module cannot create one and attach it in the same step."
  default     = []
}

variable "additional_volume_ids" {
  type        = list(string)
  description = "IDs of block volumes to attach. Created by the caller (ADR-0153, reversing ADR-0120's internal block-volume composition). Note the instance only mounts /dev/sdb if its cloud-init was rendered with has_attached_volume = true."
  default     = []
}

# ADR-0126, narrowed by ADR-0153: false destroys the server, and only the
# server. It used to also tear down this module's IP addresses, block volume
# and IAM policy/key, but those are now the caller's resources and are
# unaffected -- a caller wanting a full teardown has to gate them too.
# random_string.suffix stays unconditional, so the instance's name is stable
# across a disable/re-enable cycle.
variable "enabled" {
  type        = bool
  description = "Whether to create the instance. false destroys the server only; any IP, volume or IAM the caller created for it is untouched."
  default     = true
}
