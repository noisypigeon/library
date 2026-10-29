variable "gateway_id" {
  type        = string
  description = "ID of the Public Gateway whose IP the rule listens on"
}

variable "private_ip" {
  type        = string
  description = "The target's IPv4 address on the gateway's Private Network"
}

variable "public_port" {
  type        = number
  description = "Port on the gateway's public IP"
}

variable "private_port" {
  type        = number
  description = "Port on the target"
  default     = 22
}

variable "protocol" {
  type        = string
  description = "tcp, udp or both"
  default     = "tcp"

  validation {
    condition     = contains(["tcp", "udp", "both"], var.protocol)
    error_message = "protocol must be one of tcp, udp, both."
  }
}
