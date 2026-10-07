output "job_ids" {
  description = "Instance ID per job, keyed by job name (null for any job whose instance has already self-deleted)"
  value       = { for k, v in module.job : k => v.id }
}
