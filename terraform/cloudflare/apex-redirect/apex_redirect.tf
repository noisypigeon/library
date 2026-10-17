# Redirects a zone's apex, and optionally www, to one URL. Raw resources rather
# than calls to cloudflare/dns-record and cloudflare/ruleset: a module that
# sources another by short URL breaks when that host moves (LIB-0009, LIB-0011).
#
# Every generated string below keeps the wording the hand-written redirect
# leaves used, so those resources import with no diff. The ruleset's name
# matters most: Cloudflare replaces a ruleset whose name changes.
locals {
  # "https://example.org/" -> "example.org", for names and comments only.
  host = trimsuffix(regex("^[a-zA-Z][a-zA-Z0-9+.-]*://(.*)$", var.target_url)[0], "/")

  hosts = var.include_www ? [var.zone, "www.${var.zone}"] : [var.zone]
  froms = var.include_www ? "${var.zone} and www" : var.zone
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.zone
  }
}

# Proxied placeholders: Cloudflare only sees traffic for a name that resolves
# through it, and the ruleset below answers before the origin is ever reached.
# 192.0.2.1 is TEST-NET-1, documentation space that routes nowhere.
resource "cloudflare_dns_record" "apex" {
  zone_id = data.cloudflare_zone.this.id
  name    = "@"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
  ttl     = 1
  comment = "placeholder so Cloudflare intercepts apex traffic for the ${local.host} redirect"
}

resource "cloudflare_dns_record" "www" {
  count = var.include_www ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = "www"
  type    = "CNAME"
  content = var.zone
  proxied = true
  ttl     = 1
  comment = "placeholder so Cloudflare intercepts www traffic for the ${local.host} redirect"
}

resource "cloudflare_ruleset" "this" {
  zone_id = data.cloudflare_zone.this.id
  name    = "${var.zone} to ${local.host} redirect"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    expression  = join(" or ", [for h in local.hosts : "(http.host eq \"${h}\")"])
    description = "redirect ${local.froms} to the ${local.host} homepage"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code = var.status_code
        target_url = {
          value = var.target_url
        }
        preserve_query_string = var.preserve_query_string
      }
    }
  }]
}
