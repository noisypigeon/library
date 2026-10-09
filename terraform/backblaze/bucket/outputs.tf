output "bucket_id" {
  description = "B2 bucket ID"
  value       = b2_bucket.bucket.bucket_id
}

output "bucket_name" {
  description = "Computed bucket name"
  value       = b2_bucket.bucket.bucket_name
}
