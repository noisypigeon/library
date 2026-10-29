output "id" {
  description = "PAT rule ID"
  value       = scaleway_vpc_public_gateway_pat_rule.this.id
}

output "connect_command" {
  description = "SSH command that reaches the target through the rule, when it forwards to port 22"
  value       = var.private_port == 22 ? "ssh -p ${var.public_port} root@${data.scaleway_vpc_public_gateway_ip.this.address}" : null
}
