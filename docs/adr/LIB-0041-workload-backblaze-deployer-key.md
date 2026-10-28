# LIB-0041: A workload's own Backblaze key, and spokes with no spoke-wide key

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-28.
- **Status**: Proposed. Supersedes LIB-0033 §5 for workloads, and retires
  runway's LIB-0033 §2 spoke deployers.

## Context

LIB-0033 §2 gave each spoke two deployer leaves, hand-written under
`terraform/`:

- **`terraform/backblaze/api-key/terraform-deployer`** mints an account-wide
  B2 key, hand-copied into `backblaze.enc`.
- **`terraform/cloudflare/api-token/terraform-deployer`** mints a token,
  hand-copied into `cloudflare.enc`.

Since then everything else has moved into units.

**Cloudflare.** Every zone and workload Cloudflare leaf signs in with its own
unit's token (LIB-0033 §4, LIB-0036), minted with the breakglass token. So in
runway the spoke's token signs in nothing: there is no hand-written
Cloudflare leaf left.

**Backblaze.** LIB-0033 §5 kept workload `backblaze.*` leaves signing in with
the spoke's key, because a key confined to a workload's buckets can't create
them. Since LIB-0040 that's all runway's Backblaze: the cold-storage
workload's five buckets. The spoke key is the last thing under
`terraform/backblaze/`. It's also a key someone has to copy by hand, whenever
it's re-minted, into a file every spoke must keep.

**The library won't let a spoke go without either one:**
- `secrets-schema.json` requires `backblaze.enc` wherever
  `providers.backblaze` is set, and `CLOUDFLARE_PROVIDER_TOKEN` wherever
  `providers.cloudflare` is.
- root.hcl refuses a `breakglass` with no `leaves`. Yet the breakglass key
  has to stay, because it mints every unit's token, and now every unit's key.

## Decision

### 1. A workload with Backblaze kinds gets its own key

A workload that declares any `backblaze.bucket` or `backblaze.apiKey` gets an
implicit leaf, `backblaze/api-key/deployer`, the Backblaze twin of
`cloudflare/api-token/deployer`.

- **It's minted with the spoke's Backblaze breakglass key** where the spoke
  has one: `breakglass_on` holds for it as it does for the Cloudflare token
  leaf. A spoke without one mints it with `backblaze.enc`'s key.
- **It's account-wide,** with the capabilities the spoke key had. LIB-0033
  §5's reason still holds: B2 can't confine a key to buckets that don't exist
  yet. So this decision doesn't narrow what the key can reach. What changes
  is who owns it: it lives, rotates and goes with the workload, and nobody
  copies it anywhere.
- **It rotates** every 30 days, create-before-destroy, and each key expires a
  week after its scheduled rotation. That needs a new input on
  `terraform/backblaze/api-key`, `rotation_days`, copied from
  `cloudflare/api-token`. It defaults to null, so existing callers keep their
  fixed `valid_duration_in_seconds`.
- **Its name is `<prefix>-<suffix><unit_tag>-backblaze-deployer`.**
  `backblaze.deployer` overrides any input. `backblaze.apiKey.deployer` is
  reserved, and refused by name before planning.

### 2. A workload's Backblaze leaves sign in with it

`backblaze/bucket` and `backblaze/api-key` become `credentials = "workload"`
kinds:

- each stub depends on `b2_key`, the key's leaf;
- the stub passes `backblaze_application_key_id` and
  `backblaze_application_key` from that dependency;
- root.hcl's `provider "b2"` reads them as variables.

Nothing in a bucket's own configuration changes, so moving to the key plans
`No changes.` Those leaves are deferred until the key applies (LIB-0027).

### 3. `workloads_only`: a provider with no spoke-wide credentials

A Cloudflare or Backblaze entry in `spoke.hcl`'s `providers` may set
`workloads_only = true`:

```hcl
backblaze  = { workloads_only = true, breakglass = {} }
cloudflare = { workloads_only = true, breakglass = {} }
```

- **No hand-written leaf turns the provider on.** Unit leaves get it from
  their path, as before.
- **The spoke keeps no credentials of its own for it.** A new condition,
  `spoke_credentials.<name>`, holds where `provider.<name>` does unless the
  entry sets `workloads_only`. `backblaze.enc` is required under it, and so
  is `cloudflare.enc`'s `CLOUDFLARE_PROVIDER_TOKEN`, now a `keys_when` entry.
  `cloudflare.enc` itself stays, for `CLOUDFLARE_PROVIDER_ACCOUNT_ID`.
- **It needs `breakglass`, with no `leaves`,** and the entry may set no
  `leaves` either. The breakglass key mints every unit's key, and there is no
  hand-written leaf to scope it to.

root.hcl checks a file's keys against the spoke-wide conditions, as
`check-secrets.sh` does, and not just this leaf's. So a leaf that reads
`cloudflare.enc` for the R2 backend alone doesn't flag the token another leaf
needs.

The change is additive: `leaves` keeps its meaning, and an empty list still
means every leaf. It ships as root-hcl v8.1.0, `workflows/v8.1.0` and
`terraform/backblaze/api-key` v0.2.0.

### 4. runway retires both spoke deployers, in two PRs

1. **PR A takes the release.** cold-storage's key is created (`+1`), and its
   five bucket leaves then plan `No changes.`
2. **PR B retires the spoke deployers and their secrets.**
   - It deletes `terraform/backblaze/` and
     `terraform/cloudflare/api-token/`, whose destroy revokes the spoke key
     and token.
   - It sets both providers `workloads_only`.
   - It deletes `backblaze.enc`.
   - It removes `CLOUDFLARE_PROVIDER_TOKEN` from `cloudflare.enc`, and
     `env.enc`'s two `BACKBLAZE_ORIGINAL_*` keys, which nothing has read
     since noisypigeon/runway#89.

## Consequences

- **runway's secrets lose their two hand-copied values.** Each remaining key
  is either hand-made and only mints (the breakglass files), or is one only
  pigeon-cli's hand-written leaves still use (`scaleway.enc`,
  `terraform.enc`).
- **Each Backblaze workload adds a leaf and a key,** and a monthly rotation
  that defers its Backblaze leaves for one replan.
- **A workload's B2 key still reaches the whole account.** That's B2's model
  (LIB-0033 §5), and so is every key a workload's `apiKey` mints. Those stay
  confined to its buckets.
- **LIB-0033 §5 is superseded** for workloads. Its reason stands; only its
  conclusion, that the spoke key signs them in, changes.

## Out of scope

- **Retiring `scaleway.enc` and `terraform.enc`.** pigeon-cli's hand-written
  leaves still need them, until they become a workload (#98).
- **A `workloads_only` for Scaleway.** Its spoke key also signs in the state
  backend and every unit's project, deployer and state bucket, so there's
  nothing to drop yet.

## Verification

1. **Only cold-storage's stubs change.** Under v8.1.0:
   - a scratch copy of runway generates one new stub, the key;
   - its five bucket stubs gain the `b2_key` dependency and the two
     credential inputs;
   - every other stub and rendered leaf is byte-identical to v8.0.1's.
2. **PR A plans `+1`,** then each bucket leaf plans `No changes.`
3. **PR B plans exactly two destroys,** the spoke key and the spoke token.
   Every other leaf plans `No changes.`
4. **`check-secrets.sh` passes** on runway after PR B, and fails on a leftover
   `CLOUDFLARE_PROVIDER_TOKEN`.
5. **B2 holds cold-storage's key and not the spoke's,** checked by count out
   of band.
