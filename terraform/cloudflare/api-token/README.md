# api-token

One account-owned Cloudflare API token, `cloudflare_account_token`, with its
policies written by name (LIB-0033 §3).

- **Permission groups by name,** such as `"DNS Write"`, resolved through the
  account's permission-groups list at the scope each policy needs. An unknown
  name fails the plan, and so does one the signing-in token may not grant.
- **Resources by name:** `zones` by apex domain, looked up as `dns-record`
  does (LIB-0011); `all_zones` for every zone in the account; or `account`.
  Each policy sets exactly one.
- **Expiry or rotation.** `rotation_days` replaces the token on a schedule,
  create-before-destroy, and it expires a week after each scheduled rotation
  (LIB-0024 §4). Without it, `expires_on`, or 365 days after creation.

A spoke's breakglass token, which can only mint, signs in to mint both the
spoke's Cloudflare deployer token (LIB-0033 §2) and each workload's own token
(LIB-0033 §4). A token minted here can never mint in turn: Cloudflare won't
grant *Account API Tokens Write* from a token, so the plan refuses it.

## Usage

```hcl
module "token" {
  source = "https://noisypigeon.garden/terraform/cloudflare/api-token/v0.1.0"

  account_id = local.cloudflare_account_id
  name       = "runway-cloudflare-deployer"
  policies = [
    { permission_groups = ["Zone Read"], all_zones = true },
  ]
}
```

The `token` output is sensitive. A spoke deployer's token is copied by hand
into `cloudflare.enc` (LIB-0014 §4).

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | Cloudflare account the token belongs to, and the account its account policies grant | `string` | n/a | yes |
| <a name="input_expires_on"></a> [expires\_on](#input\_expires\_on) | RFC 3339 expiry. Null means a week past the next rotation with rotation\_days, or 365 days after creation without | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Token name | `string` | n/a | yes |
| <a name="input_policies"></a> [policies](#input\_policies) | The token's policies. Each names its permission groups (e.g. "DNS Write") and exactly one resource: zones by apex domain, all\_zones for every zone in the account, or account for the account itself | <pre>list(object({<br/>    permission_groups = list(string)<br/>    zones             = optional(list(string), [])<br/>    all_zones         = optional(bool, false)<br/>    account           = optional(bool, false)<br/>    effect            = optional(string, "allow")<br/>  }))</pre> | n/a | yes |
| <a name="input_rotation_days"></a> [rotation\_days](#input\_rotation\_days) | Replace the token every this many days, create-before-destroy (LIB-0024 §4, LIB-0033 §3). Null never rotates | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Token ID |
| <a name="output_token"></a> [token](#output\_token) | The token's secret value |
<!-- END_TF_DOCS -->