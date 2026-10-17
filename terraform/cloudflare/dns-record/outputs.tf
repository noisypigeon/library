output "id" {
  description = "DNS record ID"
  value       = cloudflare_dns_record.this.id
}

output "zone_id" {
  description = "ID of the zone looked up from `zone`"
  value       = data.cloudflare_zone.this.id
}
