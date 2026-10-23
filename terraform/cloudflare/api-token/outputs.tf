output "id" {
  description = "Token ID"
  value       = cloudflare_account_token.this.id
}

output "token" {
  description = "The token's secret value"
  value       = cloudflare_account_token.this.value
  sensitive   = true
}
