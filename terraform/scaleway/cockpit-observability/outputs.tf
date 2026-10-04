output "metrics_push_url" {
  description = "Mimir ingest endpoint (null if enable_metrics is false)"
  value       = try(scaleway_cockpit_source.metrics[0].push_url, null)
}

output "logs_push_url" {
  description = "Loki ingest endpoint (null if enable_logs is false)"
  value       = try(scaleway_cockpit_source.logs[0].push_url, null)
}

output "token_secret" {
  description = "Push token secret"
  value       = scaleway_cockpit_token.push.secret_key
  sensitive   = true
}
