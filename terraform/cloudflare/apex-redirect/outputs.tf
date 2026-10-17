output "zone_id" {
  description = "ID of the zone looked up from `zone`"
  value       = data.cloudflare_zone.this.id
}

output "ruleset_id" {
  description = "ID of the redirect ruleset"
  value       = cloudflare_ruleset.this.id
}

output "apex_record_id" {
  description = "ID of the apex placeholder A record"
  value       = cloudflare_dns_record.apex.id
}

output "www_record_id" {
  description = "ID of the www placeholder CNAME record, or null when include_www is false"
  value       = one(cloudflare_dns_record.www[*].id)
}
