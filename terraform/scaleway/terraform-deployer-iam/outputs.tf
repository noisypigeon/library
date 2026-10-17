output "application_id" {
  description = "IAM application ID"
  value       = scaleway_iam_application.application.id
}

output "policy_id" {
  description = "IAM policy ID"
  value       = try(scaleway_iam_policy.policy[0].id, null)
}

output "access_key" {
  description = "IAM API key access key"
  value       = scaleway_iam_api_key.api_key.access_key
  sensitive   = true
}

output "secret_key" {
  description = "IAM API key secret key"
  value       = scaleway_iam_api_key.api_key.secret_key
  sensitive   = true
}
