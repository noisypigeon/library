variable "key_name" {
  type        = string
  description = "Application key name"
}

variable "capabilities" {
  type        = set(string)
  description = "Capability strings the key grants (e.g. [\"listBuckets\", \"readFiles\", \"writeFiles\"]) -- see Backblaze's own capability catalog, not validated locally since it's provider-defined and subject to change"
}

variable "bucket_ids" {
  type        = set(string)
  description = "Bucket IDs this key is restricted to (unset = account-wide access)"
  default     = null
}

variable "valid_duration_in_seconds" {
  type        = number
  description = "Key validity duration in seconds, counted from creation. Defaults to 30 days (2592000 seconds); pass null for a key that never expires."
  default     = 2592000
}
