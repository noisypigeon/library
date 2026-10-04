output "id" {
  description = "IAM policy ID"
  value       = try(scaleway_iam_policy.policy[0].id, null)
}
