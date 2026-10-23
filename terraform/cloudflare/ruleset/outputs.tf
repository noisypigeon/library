output "id" {
  description = "Ruleset ID"
  value       = cloudflare_ruleset.this.id
}

output "zone_id" {
  description = "ID of the zone the ruleset belongs to"
  value       = local.zone_id
}
