variable "name" {
  type        = string
  description = "Public Gateway name"
}

variable "project_id" {
  type        = string
  description = "Project ID"
}

variable "private_network_id" {
  type        = string
  description = "ID of the Private Network the gateway attaches to, and routes out of"
}

variable "type" {
  type        = string
  description = "Gateway offer type. Changing it upgrades the gateway in place, keeping its ID and IP; Scaleway can't downgrade one."
  default     = "VPC-GW-S"

  validation {
    condition     = contains(["VPC-GW-S", "VPC-GW-M", "VPC-GW-L", "VPC-GW-XL"], var.type)
    error_message = "type must be one of VPC-GW-S, VPC-GW-M, VPC-GW-L, VPC-GW-XL."
  }
}

variable "enable_masquerade" {
  type        = bool
  description = "NAT the Private Network's outbound traffic through the gateway's IP"
  default     = true
}

variable "push_default_route" {
  type        = bool
  description = "Advertise the gateway as the Private Network's default route. While it does, an attached instance's own public IP is reachable outbound only (ADR-0146)."
  default     = true
}
