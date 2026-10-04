output "id" {
  description = "Project ID"
  value       = scaleway_account_project.project.id
}

output "name" {
  description = "Project name"
  value       = scaleway_account_project.project.name
}

output "ssh_key_id" {
  description = "ID of the created SSH key, if ssh_key was provided"
  value       = try(scaleway_iam_ssh_key.key[0].id, null)
}
