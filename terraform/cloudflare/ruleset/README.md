# ruleset

> **End-of-life.** This module gets no further releases. Its existing tags stay
> resolvable, so a leaf pinned to one keeps working, but its only use was
> redirects, and those now use
> [`cloudflare/apex-redirect`](../apex-redirect/README.md), one leaf that owns
> the placeholder records and the ruleset together (LIB-0011). A future
> non-redirect use of `cloudflare_ruleset` gets its own module rather than a
> revived `ruleset`.

A thin wrapper around a single `cloudflare_ruleset`. It adds no behaviour: the
`rules` list goes to the provider exactly as given, and `description` left
`null` stays unset. It exists so that a leaf managing a ruleset calls a
library module (LIB-0004).

It's **zone-scoped**: a spoke declares it as `cloudflare.ruleset.<instance>` in
`zones/<zone>/zone.yaml`, and `resolve-workloads.sh` generates its leaf at
`zones/<zone>/cloudflare/ruleset/<instance>/` (LIB-0036). Only a zone takes it,
since a phase has one entrypoint per zone. The hand-written
`terraform/cloudflare/<zone>/ruleset/<instance>/` leaves LIB-0008 described are
refused since `terragrunt/root-hcl` v6.0.0.

## Usage

```hcl
module "ruleset" {
  source = "https://noisypigeon.garden/terraform/cloudflare/ruleset/v0.1.0"

  zone_id = local.cloudflare_zone_id
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
| <a name="input_zone"></a> [zone](#input\_zone) | Apex domain of the zone the ruleset belongs to, looked up by name (LIB-0011, LIB-0030). Set this or zone\_id, not both | `string` | `null` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare zone ID the ruleset belongs to. Set this or zone, not both | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Ruleset ID |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | ID of the zone the ruleset belongs to |
<!-- END_TF_DOCS -->
