# dns-record

A thin wrapper around a single `cloudflare_dns_record`. It adds no behaviour:
every argument is passed through as given, and an optional argument left `null`
stays unset rather than picking up a default here. It exists so that a leaf
managing DNS records calls a pigeon-lib module and can live at
`terraform/cloudflare/dns-record/<instance>/`, like every other leaf (LIB-0004).

## Usage

One module call per record, with `for_each` over a map whose keys name the
records:

```hcl
locals {
  records = {
    mx_primary = {
      name     = "@"
      type     = "MX"
      content  = "in1-smtp.example.com"
      priority = 10
      comment  = "primary mx"
    }
    www_cname = {
      name    = "www"
      type    = "CNAME"
      content = "example.github.io"
      proxied = false
    }
  }
}

module "dns_record" {
  source   = "https://pigeon.dev/modules/cloudflare/dns-record/v0.1.0"
  for_each = local.records

  zone_id  = local.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = try(each.value.ttl, 1)
  proxied  = try(each.value.proxied, null)
  priority = try(each.value.priority, null)
  comment  = try(each.value.comment, null)
}
```

Moving an existing raw `cloudflare_dns_record` under this module is an address
change only. Add a `moved` block per record, and the plan shows moves and no
changes:

```hcl
moved {
  from = cloudflare_dns_record.mx_primary
  to   = module.dns_record["mx_primary"].cloudflare_dns_record.this
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_comment"></a> [comment](#input\_comment) | Free-text comment stored on the record | `string` | `null` | no |
| <a name="input_content"></a> [content](#input\_content) | Record content (a TXT value includes its own surrounding quotes) | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Record name, relative to the zone ("@" for the apex) | `string` | n/a | yes |
| <a name="input_priority"></a> [priority](#input\_priority) | Record priority (MX, SRV, URI). Null for types that have none | `number` | `null` | no |
| <a name="input_proxied"></a> [proxied](#input\_proxied) | Whether Cloudflare proxies the record. Null leaves it unset, which is not the same as false in plan output | `bool` | `null` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | TTL in seconds; 1 means automatic | `number` | `1` | no |
| <a name="input_type"></a> [type](#input\_type) | Record type, e.g. A, AAAA, CNAME, MX, TXT | `string` | n/a | yes |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare zone ID the record belongs to | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | DNS record ID |
<!-- END_TF_DOCS -->
