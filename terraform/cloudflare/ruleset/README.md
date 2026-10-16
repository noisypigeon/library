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
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_description"></a> [description](#input\_description) | Ruleset description. Null leaves it unset | `string` | `null` | no |
| <a name="input_kind"></a> [kind](#input\_kind) | Ruleset kind, e.g. "zone" | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Ruleset name | `string` | n/a | yes |
| <a name="input_phase"></a> [phase](#input\_phase) | Ruleset phase, e.g. "http\_request\_dynamic\_redirect" | `string` | n/a | yes |
| <a name="input_rules"></a> [rules](#input\_rules) | The ruleset's rules, passed to the provider exactly as given (the cloudflare\_ruleset rules schema) | `any` | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare zone ID the ruleset belongs to | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Ruleset ID |
<!-- END_TF_DOCS -->
