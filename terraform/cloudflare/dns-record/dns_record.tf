# A deliberately thin pass-through: every argument goes to the provider as
# given, and null means "not set", never a default chosen here. It exists so a
# leaf that manages DNS records calls a pigeon-lib module like every other leaf
# (LIB-0004), not to add behaviour. Callers use for_each for several records.
resource "cloudflare_dns_record" "this" {
  zone_id  = var.zone_id
  name     = var.name
  type     = var.type
  content  = var.content
  ttl      = var.ttl
  proxied  = var.proxied
  priority = var.priority
  comment  = var.comment
}
