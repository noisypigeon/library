# apex-redirect

Redirects a Cloudflare zone's apex, and `www` with it, to a single URL. It
manages the three things a redirect needs, which used to be two leaves calling
`cloudflare/dns-record` and `cloudflare/ruleset` (LIB-0011):

- a proxied placeholder `A @ 192.0.2.1` record, so Cloudflare sees apex traffic
  (192.0.2.1 is documentation space that routes nowhere; the ruleset answers
  first);
- a proxied placeholder `CNAME www → <zone>` record, unless `include_www` is
  false;
- one `http_request_dynamic_redirect` ruleset whose rule sends both hosts to
  `target_url` with `status_code`.

Every request goes to `target_url` itself; the path isn't preserved. The query
string is appended only when `preserve_query_string` is true.

It's **zone-scoped**: a leaf calling it lives at
`terraform/cloudflare/<zone>/apex-redirect/<instance>/`, where `<zone>` is the
zone's apex domain (LIB-0008). The module looks the zone ID up from `zone`
with `data "cloudflare_zone"`, so the leaf passes
`zone = local.cloudflare_zone` and no zone ID is kept in a secret. The token
needs **Zone:Read** on the zone, as well as DNS and ruleset edit.

The module owns its resources directly rather than calling other library
modules: a module that sources another by short URL breaks when that URL's
host moves (LIB-0009).

## Usage

```hcl
module "apex_redirect" {
  source = "https://noisypigeon.garden/terraform/cloudflare/apex-redirect/v0.1.0"

  zone       = local.cloudflare_zone
  target_url = "https://example.org"
}
```

## Generated names

Names and comments are built from `zone` and the target's host, which is
`target_url` without its scheme or trailing slash. For `zone = "example.com"`
and `target_url = "https://example.org"`:

| Resource | Field | Value |
| --- | --- | --- |
| ruleset | `name` | `example.com to example.org redirect` |
| rule | `expression` | `(http.host eq "example.com") or (http.host eq "www.example.com")` |
| rule | `description` | `redirect example.com and www to the example.org homepage` |
| apex record | `comment` | `placeholder so Cloudflare intercepts apex traffic for the example.org redirect` |
| www record | `comment` | `placeholder so Cloudflare intercepts www traffic for the example.org redirect` |

With `include_www = false` the expression and description name the apex only.
Changing `zone` or `target_url`'s host renames the ruleset, which Cloudflare
does by replacing it.

## Adopting an existing redirect

The names above match what the hand-written two-leaf redirects used, so
existing resources import into a new leaf with no diff. Import the three, then
check that the leaf plans `No changes.`:

```hcl
import {
  to = module.apex_redirect.cloudflare_dns_record.apex
  id = "<zone_id>/<apex_record_id>"
}

import {
  to = module.apex_redirect.cloudflare_dns_record.www[0]
  id = "<zone_id>/<www_record_id>"
}

import {
  to = module.apex_redirect.cloudflare_ruleset.this
  id = "zones/<zone_id>/<ruleset_id>"
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_include_www"></a> [include\_www](#input\_include\_www) | Whether the www subdomain is redirected too, with its own placeholder CNAME | `bool` | `true` | no |
| <a name="input_preserve_query_string"></a> [preserve\_query\_string](#input\_preserve\_query\_string) | Whether the request's query string is appended to target\_url | `bool` | `false` | no |
| <a name="input_status_code"></a> [status\_code](#input\_status\_code) | HTTP status code of the redirect | `number` | `301` | no |
| <a name="input_target_url"></a> [target\_url](#input\_target\_url) | URL every redirected request goes to, e.g. "https://example.org". The path is not preserved | `string` | n/a | yes |
| <a name="input_zone"></a> [zone](#input\_zone) | Apex domain of the Cloudflare zone to redirect, e.g. "example.com". The zone ID is looked up from it | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apex_record_id"></a> [apex\_record\_id](#output\_apex\_record\_id) | ID of the apex placeholder A record |
| <a name="output_ruleset_id"></a> [ruleset\_id](#output\_ruleset\_id) | ID of the redirect ruleset |
| <a name="output_www_record_id"></a> [www\_record\_id](#output\_www\_record\_id) | ID of the www placeholder CNAME record, or null when include\_www is false |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | ID of the zone looked up from `zone` |
<!-- END_TF_DOCS -->
