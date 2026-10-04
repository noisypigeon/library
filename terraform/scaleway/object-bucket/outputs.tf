output "id" {
  description = "Bucket ID"
  value       = scaleway_object_bucket.bucket.id
}

output "name" {
  description = "Computed bucket name"
  value       = scaleway_object_bucket.bucket.name
}

output "endpoint" {
  description = "Bucket endpoint URL"
  value       = "https://s3.${scaleway_object_bucket.bucket.region}.scw.cloud"
}
