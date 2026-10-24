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
