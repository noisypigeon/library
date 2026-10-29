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

variable "project_id" {
  type        = string
  description = "Project the instance, and the IP public_ipv4 creates, live in (LIB-0043). Required since v8.0.0: the provider's own default project is rarely the one a caller means."
}

variable "public_ipv4" {
  type        = bool
  description = "Create a routed public IPv4 for the instance and attach it, beside any ip_ids (LIB-0043). The IP isn't gated by enabled, so it keeps its address across an enabled = false cycle. While a Public Gateway pushes its default route on the instance's Private Network, the IP works outbound only (ADR-0146)."
  default     = false
}

variable "enable_private_network" {
  type        = bool
  description = "Attach the instance to private_network_id with a standalone scaleway_instance_private_nic, so attaching or detaching never replaces the server (ADR-0145). An explicit bool rather than private_network_id != null, since count can't depend on an apply-time-unknown ID (compute-instance v5.6.0)."
  default     = false
}

variable "private_network_id" {
  type        = string
  description = "ID of the Private Network to attach to when enable_private_network is true (LIB-0043)."
  default     = null

  validation {
    condition     = !var.enable_private_network || var.private_network_id != null
    error_message = "private_network_id must be set when enable_private_network is true."
  }
}
