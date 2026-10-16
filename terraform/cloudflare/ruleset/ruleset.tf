# A deliberately thin pass-through over one cloudflare_ruleset, so a leaf that
# manages a ruleset calls a pigeon-lib module like every other leaf (LIB-0004).
# The rules are passed verbatim; null means "not set", never a default here.
resource "cloudflare_ruleset" "this" {
  zone_id     = var.zone_id
  name        = var.name
  kind        = var.kind
  phase       = var.phase
  description = var.description
  rules       = var.rules
}
