# dns-record

A thin wrapper around a single `cloudflare_dns_record`. It adds no behaviour:
every argument is passed through as given, and an optional argument left `null`
stays unset rather than picking up a default here. It exists so that a leaf
managing DNS records calls a pigeon-lib module, like every other leaf (LIB-0004).

It's **zone-scoped**: a leaf calling it lives at
`terraform/cloudflare/<zone>/dns-record/<instance>/`, where `<zone>` is the
zone's apex domain (LIB-0008). The module takes that apex as `zone` and looks
the zone ID up itself with `data "cloudflare_zone"`, so the leaf passes
`zone = local.cloudflare_zone`, which `terragrunt/root-hcl` derives from the
path, and no zone ID is kept in a secret (LIB-0011). The lookup needs a token
with **Zone:Read** on the zone as well as DNS edit. The ID it found is the
`zone_id` output.

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
  source   = "https://noisypigeon.garden/terraform/cloudflare/dns-record/v1.0.0"
  for_each = local.records

  zone     = local.cloudflare_zone
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

### Upgrading from v0.x

v1.0.0 replaces the `zone_id` input with `zone`. Swap
`zone_id = local.cloudflare_zone_id` for `zone = local.cloudflare_zone` and
change nothing else: the looked-up ID is the one that was configured, so the
plan shows `No changes.`

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
| <a name="input_zone"></a> [zone](#input\_zone) | Apex domain of the Cloudflare zone the record belongs to, e.g. "example.com". The zone ID is looked up from it | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | DNS record ID |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | ID of the zone looked up from `zone` |
<!-- END_TF_DOCS -->
