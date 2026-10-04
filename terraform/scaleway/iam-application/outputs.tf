output "id" {
  description = "IAM application ID"
  value       = scaleway_iam_application.application.id
}

output "name" {
  description = "IAM application name"
  value       = scaleway_iam_application.application.name
}
