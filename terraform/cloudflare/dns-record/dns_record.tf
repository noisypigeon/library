# The zone is looked up by its apex domain rather than passed in by ID, so a
# zone leaf needs no secret: root.hcl derives the apex from the leaf's path
# (LIB-0008, LIB-0011). With a filter, the v5 data source fills in `id`; its
# `zone_id` attribute is the lookup-by-ID input and stays null.
data "cloudflare_zone" "this" {
  filter = {
    name = var.zone
  }
}

# A deliberately thin pass-through: every argument goes to the provider as
# given, and null means "not set", never a default chosen here. It exists so a
# leaf that manages DNS records calls a pigeon-lib module like every other leaf
# (LIB-0004), not to add behaviour. Callers use for_each for several records.
resource "cloudflare_dns_record" "this" {
  zone_id  = data.cloudflare_zone.this.id
  name     = var.name
  type     = var.type
  content  = var.content
  ttl      = var.ttl
  proxied  = var.proxied
  priority = var.priority
  comment  = var.comment
}
