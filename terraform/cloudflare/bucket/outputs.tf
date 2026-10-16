output "id" {
  description = "Bucket ID"
  value       = cloudflare_r2_bucket.this.id
}

output "name" {
  description = "Computed bucket name"
  value       = cloudflare_r2_bucket.this.name
}

output "endpoint" {
  description = "Bucket S3 API endpoint URL (EU jurisdiction)"
  value       = "https://${var.account_id}.eu.r2.cloudflarestorage.com"
}
