# LIB-0033: Self-bootstrapped Cloudflare and Backblaze keys

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-23.
- **Status**: Proposed; amended 2026-10-23 (see `## Amendments`). Amends:
  - LIB-0014, which gains two breakglass providers;
  - LIB-0024, whose deployers reach Cloudflare;
  - LIB-0030, whose Cloudflare kinds move to workload credentials, behind a
    new implicit kind;
  - LIB-0032, whose first prerequisite changes.

## Context

Scaleway credentials in this family are already split by power.

- **A spoke deployer is Terraform-managed** (LIB-0014). Its key is a module's
  output, scoped by IAM policy, and copied by hand into `scaleway.enc`. A
  hand-made breakglass key can stand in for a leaf that must not sign in with
  the key it manages (LIB-0014 §2).
- **Each workload has its own deployer** (LIB-0024), scoped to its own
  project and rotated every 30 days. A workload's project-scoped leaves sign
  in with it.

Cloudflare and Backblaze have neither.

- **Cloudflare** signs in with one hand-made token in `cloudflare.enc`
  (LIB-0010, LIB-0012). LIB-0032 asks the owner for another, with DNS and
  ruleset powers over three zones, before the blog can move. LIB-0030 then
  lets every Cloudflare workload leaf use it, so `zones.yaml`'s ownership is
  checked but not enforced: every workload can still reach every zone the
  token can.
- **Backblaze** signs in with one hand-made, account-wide key in
  `backblaze.enc`.

Both providers can mint narrower credentials themselves.

- **A Cloudflare account token** with *Account API Tokens Write* can create
  account-owned tokens. Their policies are scoped by permission group, and by
  zone or account.
- **A B2 key** with `writeKeys` can create application keys. Their
  capabilities are scoped by name, and optionally to buckets.

So the hand-made credential can shrink to one that only mints keys, and
Terraform can mint the ones that do the work.

One Backblaze limit decides how far that goes. A B2 key restricted to buckets
can't create a bucket, or reconfigure one: that needs `writeBuckets` without a
bucket restriction. A per-workload B2 key couldn't run its own workload's
bucket leaves, so it would buy nothing.

## Decision

### 1. The bootstrap keys are breakglass keys

`secrets-schema.json` gains two breakglass files (LIB-0014 §2):

| File | Key | Replaces |
| --- | --- | --- |
| `cloudflare_breakglass.enc` | `CLOUDFLARE_BREAKGLASS_TOKEN` | `CLOUDFLARE_PROVIDER_TOKEN` |
| `backblaze_breakglass.enc` | `BACKBLAZE_BREAKGLASS_ACCESS_KEY_ID` | `BACKBLAZE_PROVIDER_ACCESS_KEY_ID` |
| | `BACKBLAZE_BREAKGLASS_ACCESS_KEY` | `BACKBLAZE_PROVIDER_ACCESS_KEY` |

- **Each is required under `breakglass.<provider>`,** and only the leaves
  `spoke.hcl` allowlists ever decrypt it. Cloudflare's account ID stays in
  `cloudflare.enc`: it isn't a credential.
- **The owner makes them by hand, with key-minting power only:**
  - for Cloudflare, a token with *Account API Tokens Write*;
  - for B2, a key with `writeKeys`, `listKeys` and `deleteKeys`.
- **Terraform never manages them** (LIB-0014 §3). They're the spoke's root of
  trust for these two providers, rotated by editing one file.

### 2. The spoke deployers are Terraform leaves, signed in with breakglass

Unlike runway's Scaleway deployer (LIB-0014's amendment), these leaves mint
the very credential the spoke then signs in with, so they use breakglass.

- **`terraform/cloudflare/api-token/terraform-deployer`** mints the spoke's
  Cloudflare token. It may:
  - create account tokens, for §4's workload tokens;
  - read zones, and write DNS records and rulesets, in the zones `zones.yaml`
    registers to `terraform`, for the spoke's hand-written zone leaves;
  - write R2, only where the leaf says so, for hand-written R2 buckets.
- **`terraform/backblaze/api-key/terraform-deployer`** mints the spoke's B2
  key with the existing `backblaze/api-key` module. It gets bucket
  administration and `writeKeys`, `listKeys` and `deleteKeys`, account-wide.
  The last three are what LIB-0029's `apiKey` kind needs.
- **The owner copies each output into `cloudflare.enc` and `backblaze.enc`,**
  as LIB-0014 §4 does for Scaleway. So the spoke deployers' expiry is long, a
  year by default: each rotation is a hand-copy.
- **`spoke.hcl` allowlists the two leaves:**

  ```hcl
  providers = {
    cloudflare = {
      leaves     = ["terraform/cloudflare/"]
      breakglass = { leaves = ["terraform/cloudflare/api-token/terraform-deployer/"] }
    }
    backblaze = {
      leaves     = ["terraform/backblaze/"]
      breakglass = { leaves = ["terraform/backblaze/api-key/terraform-deployer/"] }
    }
  }
  ```

### 3. A `cloudflare/api-token` module

A new hub module wraps one `cloudflare_account_token`.

- **Policies are written by permission-group name,** such as `"DNS Write"`.
  The module resolves the names to IDs through the provider's account
  permission-groups data source, so a leaf never holds an opaque ID.
- **Resources are named, too:** zones by apex domain, looked up as LIB-0011
  does, or the whole account.
- **Expiry is `expires_on`, or rotation.** `rotation_days` replaces the token
  through `time_rotating`, with `create_before_destroy`, as LIB-0024 §4 does
  for Scaleway. Its expiry is a week past each scheduled rotation.
- **It outputs `id` and a sensitive `token`.**

### 4. Every workload with Cloudflare kinds gets its own token

- **It's implicit.** Whenever a `values.yaml` declares any `cloudflare`
  kind, `resolve-workloads.sh` also generates
  `workloads/<w>/cloudflare/api-token/deployer`. An optional
  `cloudflare.deployer` overrides its inputs, by the module's own names.
- **It signs in with the spoke's token,** whose *Account API Tokens Write*
  creates it. Its state lives in the workload bucket.
- **Its defaults:**
  - *Zone Read*, *DNS Write*, and the ruleset permission groups the
    `ruleset` and `apexRedirect` kinds need, on exactly the zones
    `zones.yaml` registers to this workload;
  - *Workers R2 Storage Write* on the account, only if the workload declares
    a `cloudflare.bucket`. Creating an R2 bucket needs that account-wide, as
    B2's does;
  - `rotation_days`: 30.
- **LIB-0030's four kinds move from spoke to workload credentials.** Their
  stubs depend on the token, and pass it as `cloudflare_api_token`. root.hcl's
  `provider "cloudflare"` reads it for those leaves, as `provider "scaleway"`
  reads `scaleway_access_key` (LIB-0024 §2). The account ID is still the
  spoke's.
- **A Cloudflare workload has one more stage:**
  1. project;
  2. deployer;
  3. state bucket;
  4. Cloudflare token;
  5. Cloudflare entries.
- **A `zones.yaml` change updates the token's resources in place,** so
  ownership and reach move together.

### 5. Backblaze has no per-workload deployer

Workload `backblaze.bucket` entries keep signing in with the spoke deployer's
key. A key restricted to a workload's buckets couldn't create or reconfigure
them (Context). What a workload hands out is still scoped: LIB-0029's
`apiKey` kind mints keys that reach only its own buckets.

This is a permanent boundary of B2's key model, not a deferral.

### 6. runway adopts first, as part of LIB-0032

1. **The owner makes the two bootstrap keys** (§1) and encrypts them into the
   two breakglass files, on a runway branch.
2. **A PR adds them and the two deployer leaves,** allowlisted in
   `spoke.hcl`, and applies.
3. **The owner copies the deployer outputs** into `cloudflare.enc` and
   `backblaze.enc`, in a PR whose plan shows `No changes.`
4. **The old hand-made B2 key is revoked,** by the owner.
5. **LIB-0032 continues** from its bootstrap step, with no broad hand-made
   Cloudflare token.

### 7. Release impact

- **`terraform/cloudflare/api-token` v0.1.0**, a new module.
- **`terragrunt/root-hcl` takes a minor version:**
  - the two schema entries;
  - workload Cloudflare credentials;
  - the implicit kind.
  
  A spoke without the new kinds or files renders the same.
- **`workflows/` takes a minor version:**
  - `KINDS` and the implicit stub;
  - the schema;
  - `check-secrets.sh` for the two breakglass files.
- **A spoke takes both in one PR.** Selection doesn't change.

## Consequences

- **No hand-made credential does day-to-day work.** The owner keeps two
  minting keys and copies two outputs. Everything else is minted, scoped and
  rotated by Terraform.
- **`zones.yaml` is enforced by Cloudflare,** not only checked. A workload's
  token can't reach a zone it doesn't own.
- **A Cloudflare workload takes five stages**, one more than LIB-0028's four.
  LIB-0027 plans each one by itself.
- **The spoke deployers still need a hand-copy,** once a year by default.
- **B2 stays account-wide** for workload buckets, by necessity (§5).

## Out of scope

- **Writing a deployer's output into sops in CI,** which would end the
  hand-copy for every provider. Deferred ([#156](https://github.com/noisypigeon/library/issues/156)).
- **garden's adoption.** It has Cloudflare and Backblaze, but no workloads.
  Deferred ([#157](https://github.com/noisypigeon/library/issues/157)).
- **Per-workload B2 deployers.** A permanent boundary (§5).
- **Building §§1–7.** The module, template and scripts ship in later PRs that
  cite this record ([#155](https://github.com/noisypigeon/library/issues/155)).

## Verification

Run in runway, during LIB-0032.

1. **The bootstrap keys only mint.**
   - The Cloudflare breakglass token creates the spoke token, and is refused
     a DNS read.
   - The B2 breakglass key creates the spoke key, and is refused a bucket
     listing.
2. **A workload token is confined.** `blog`'s token edits records in its own
   zones, and is refused on a zone it doesn't own.
3. **Rotation defers.** Forcing rotation replaces `blog`'s token, defers its
   Cloudflare entries, and their re-plan signs in with the new token,
   as LIB-0024's Verification 3 does.
4. **The B2 spoke key works.** It runs `poc`'s Backblaze bucket, and mints
   its `apiKey`.
5. **Nothing else changes.** Every other leaf in runway plans `No changes.`
6. **The providers' minting rules are recorded.** Two things are untested
   until the first real apply:
   - whether a minted Cloudflare token may carry permissions its minter
     lacks;
   - whether B2 requires a minted key's capabilities to be a subset of its
     creator's.

   If either refuses, the bootstrap key's grants widen to the smallest set
   that works. That's an amendment, not a silent change.

## Amendments

### 2026-10-23: what building it changed

§§1–4 and §7 shipped in `terraform/cloudflare/api-token` v0.1.0,
`terragrunt/root-hcl` v5.3.0 and `workflows/v4.13.0`. Building them settled
four things.

1. **A workload's token is keyed on what it owns, not on its entries.** §4
   created it when the workload declared a Cloudflare kind. But LIB-0032's
   import runs before any Cloudflare entry is committed, signed in with that
   token. So the token exists whenever `zones.yaml` registers a zone to the
   workload, or the workload declares a `cloudflare.bucket`.
2. **The first `cloudflare.enc` holds the bootstrap token.** `cloudflare.enc`
   is required wherever Cloudflare is on, and the deployer leaf is such a
   place, but its token is that leaf's output. So at bootstrap the owner
   writes the account ID and, as a placeholder, the bootstrap token. The
   hand-copy (§2) replaces it. No template change is needed.
3. **The module checks what the minter may grant.** The provider's
   permission-groups list marks each group `is_selectable` for the caller.
   `cloudflare/api-token` fails a plan that asks for a group that isn't, by
   name. That's §Verification 6's first question, answered at plan time.
4. **Two names are confirmed only by the first real plan.**
   - The token's secret is the provider's `value`, exposed as `token`.
   - Cloudflare's docs list the API-token permission groups at user scope,
     while the provider's docs name *Account API Tokens Read/Write*. The
     module resolves account policies at account scope. If the first plan
     finds no such group there, the spoke deployer's policy names change in
     another amendment.

