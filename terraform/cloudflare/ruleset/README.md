# ruleset

A thin wrapper around a single `cloudflare_ruleset`. It adds no behaviour: the
`rules` list goes to the provider exactly as given, and `description` left
`null` stays unset. It exists so that a leaf managing a ruleset calls a
pigeon-lib module and can live at `terraform/cloudflare/ruleset/<instance>/`
(LIB-0004).

## Usage

```hcl
module "ruleset" {
  source = "https://pigeon.dev/modules/cloudflare/ruleset/v0.1.0"

  zone_id = local.zone_id
  name    = "example.com to example.org redirect"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    expression  = "(http.host eq \"example.com\")"
    description = "redirect example.com to example.org"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code           = 301
        target_url            = { value = "https://example.org" }
        preserve_query_string = false
      }
    }
  }]
}
```

Moving an existing raw `cloudflare_ruleset` under this module is an address
change only:

```hcl
moved {
  from = cloudflare_ruleset.example
  to   = module.ruleset.cloudflare_ruleset.this
}
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
