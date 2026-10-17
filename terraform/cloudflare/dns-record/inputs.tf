variable "zone" {
  type        = string
  description = "Apex domain of the Cloudflare zone the record belongs to, e.g. \"example.com\". The zone ID is looked up from it"
}

variable "name" {
  type        = string
  description = "Record name, relative to the zone (\"@\" for the apex)"
}

variable "type" {
  type        = string
  description = "Record type, e.g. A, AAAA, CNAME, MX, TXT"
}

variable "content" {
  type        = string
  description = "Record content (a TXT value includes its own surrounding quotes)"
}

variable "ttl" {
  type        = number
  description = "TTL in seconds; 1 means automatic"
  default     = 1
}

variable "proxied" {
  type        = bool
  description = "Whether Cloudflare proxies the record. Null leaves it unset, which is not the same as false in plan output"
  default     = null
}

variable "priority" {
  type        = number
  description = "Record priority (MX, SRV, URI). Null for types that have none"
  default     = null
}

variable "comment" {
  type        = string
  description = "Free-text comment stored on the record"
  default     = null
}
