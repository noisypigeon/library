output "job_ids" {
  description = "Instance ID per job, keyed by job name (null for any job whose instance has already self-deleted)"
  value       = { for k, v in module.job : k => v.id }
}

output "bastion_connect_command" {
  description = "SSH command to reach the cluster's bastion through the shared Public Gateway's PAT rule (null when cluster_config.enable_bastion is false)"
  value       = var.cluster_config.enable_bastion ? "ssh -p 2222 root@${try(scaleway_vpc_public_gateway_ip.jobs[0].address, null)}" : null
}
