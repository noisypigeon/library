output "id" {
  description = "Bucket ID"
  value       = cloudflare_r2_bucket.this.id
}

output "name" {
  description = "Computed bucket name"
  value       = cloudflare_r2_bucket.this.name
}

output "endpoint" {
  description = "Bucket S3 API endpoint URL (the eu and fedramp jurisdictions have their own)"
  value       = contains(["eu", "fedramp"], coalesce(var.jurisdiction, "default")) ? "https://${var.account_id}.${var.jurisdiction}.r2.cloudflarestorage.com" : "https://${var.account_id}.r2.cloudflarestorage.com"
}
