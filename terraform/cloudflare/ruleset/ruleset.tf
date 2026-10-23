# A deliberately thin pass-through over one cloudflare_ruleset, so a leaf that
# manages a ruleset calls a pigeon-lib module like every other leaf (LIB-0004).
# The rules are passed verbatim; null means "not set", never a default here.
#
# Since v0.2.0 the zone may be named by its apex, as dns-record v1 and
# apex-redirect do (LIB-0011), which is how a workload names it (LIB-0030).
data "cloudflare_zone" "this" {
  count = var.zone != null ? 1 : 0

  filter = {
    name = var.zone
  }
}

locals {
  zone_id = var.zone != null ? data.cloudflare_zone.this[0].id : var.zone_id
}

resource "cloudflare_ruleset" "this" {
  zone_id     = local.zone_id
  name        = var.name
  kind        = var.kind
  phase       = var.phase
  description = var.description
  rules       = var.rules
}
