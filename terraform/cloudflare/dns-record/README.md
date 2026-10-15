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
<!-- END_TF_DOCS -->
