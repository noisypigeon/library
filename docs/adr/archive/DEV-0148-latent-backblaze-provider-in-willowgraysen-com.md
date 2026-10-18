# DEV-0148: latent Backblaze B2 provider in willowgraysen.com's root.hcl

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-09.
- **Status**: Accepted.

## Context

`workloads/willowgraysen.com/root.hcl` (this self-sufficient workload's own Terragrunt root, [ADR-0133](DEV-0133-willowgraysen-com-terraform-self-sufficiency.md)) has an unconditional `generate "provider"` block that always emits `required_providers`/`provider` blocks for `cloudflare` and `scaleway` (plus a `grafana` `required_providers` entry) for every leaf under `workloads/willowgraysen.com/terraform/`, regardless of whether that particular leaf actually uses those resources. Terraform tolerates a configured-but-unused provider fine, so this has never been a problem for the two providers already there.

A third provider, Backblaze B2 (`Backblaze/b2`, the provider [ADR-0147](DEV-0147-add-backblaze-bucket-and-api-key-modules.md)'s `templates/terraform/backblaze/{bucket,api-key}` modules target), needs wiring into this same root.hcl — but *latent*: inert for every leaf by default, only switched on for a leaf that opts in via a small sibling file, `backblaze_config.hcl`.

This repo already has exactly one precedent for a leaf-local, optionally-present `.hcl` file that a root.hcl reads to change its own generated behavior: **`scaleway_config.hcl`** ([ADR-0098](DEV-0098-decommission-terraform-infrastructure.md)'s per-leaf Scaleway region/zone override — the file is actually named `scaleway_config.hcl` on disk and in every root.hcl's live code; ADR-0098's own prose and `CLAUDE.md` call it `workload_definition.hcl`, an undocumented rename drift, not a second mechanism). Its shape, reused directly for `backblaze_config.hcl`:

```hcl
workload_dir             = dirname(find_in_parent_folders("root.hcl"))
workload_definition_path = "${local.workload_dir}/${path_relative_to_include()}/scaleway_config.hcl"
workload_definition      = read_terragrunt_config(local.workload_definition_path, { locals = {} })
scaleway_region          = lookup(local.workload_definition.locals, "scaleway_region", "fr-par")
```

`read_terragrunt_config` returns the given `{ locals = {} }` default — no error — when the file doesn't exist, so every leaf that never creates a `backblaze_config.hcl` is completely unaffected. The one existing real consumer of this mechanism is `workloads/willowgraysen.com/terraform/custodial-storage/duck-jellyfish/scaleway_config.hcl` (a bare `locals { scaleway_region = "nl-ams" ... }` file sitting beside that leaf's otherwise-minimal `terragrunt.hcl`).

**Provider auth**: confirmed against the live `Backblaze/b2` provider docs — `provider "b2" { application_key_id = ...; application_key = ...; endpoint = ... }`, all three optional (falls back to `B2_APPLICATION_KEY_ID`/`B2_APPLICATION_KEY`/`B2_ENDPOINT` env vars if omitted). Following this repo's existing convention of always writing an explicit block (same as `provider "scaleway"`, never left empty to rely on bare env vars), the generated block sets `application_key_id`/`application_key` from two new secrets.

**Secrets**: `workloads/willowgraysen.com/secrets.enc` (sops/age, [ADR-0131](DEV-0131-workload-specific-secrets.md)) already decrypts into `local.secrets` unconditionally for every leaf today — adding two more `lookup()`s costs nothing extra; only the provider-block *emission* needs gating. The file already has `ENV_SW_DIGITALOCEAN_BACKBLAZE_ACCESS_KEY_ID`/`ENV_SW_DIGITALOCEAN_BACKBLAZE_SECRET_KEY` — but those are a narrower-scoped, job-specific S3-compatible credential (an existing rclone/import remote), not the broader account-level credential the Terraform provider needs to create/manage buckets and keys. New, dedicated top-level keys are added instead, named like the existing `CLOUDFLARE_TOKEN`/`SCALEWAY_ACCESS_KEY` (not the generic `ENV_SW_*` sweep, since this is a provider-level credential, not an ad hoc leaf-injected value): `BACKBLAZE_APPLICATION_KEY_ID`, `BACKBLAZE_APPLICATION_KEY`.

Scope is `willowgraysen.com` only — the shared `workloads/root.hcl` and `pigeon.dev`'s/`noisypigeon.com`'s own `root.hcl` files are untouched.

## Decision

### New locals in `workloads/willowgraysen.com/root.hcl`

Alongside the existing `cloudflare_api_token`/`scaleway_access_key`-style credential locals:

```hcl
backblaze_application_key_id = get_env("BACKBLAZE_APPLICATION_KEY_ID", lookup(local.secrets, "BACKBLAZE_APPLICATION_KEY_ID", ""))
backblaze_application_key    = get_env("BACKBLAZE_APPLICATION_KEY", lookup(local.secrets, "BACKBLAZE_APPLICATION_KEY", ""))
```

Alongside the existing `scaleway_config.hcl` region/zone override locals:

```hcl
backblaze_config_path = "${local.workload_dir}/${path_relative_to_include()}/backblaze_config.hcl"
backblaze_config      = read_terragrunt_config(local.backblaze_config_path, { locals = {} })
backblaze_enabled     = lookup(local.backblaze_config.locals, "enabled", false)
```

### New `generate "provider_backblaze"` block

A separate generate block (not folded into the existing `generate "provider"` block, to keep that block's diff untouched) whose entire contents are gated on `local.backblaze_enabled`:

```hcl
generate "provider_backblaze" {
  path      = "provider_backblaze_generated.tf"
  if_exists = "overwrite"
  contents  = local.backblaze_enabled ? <<EOF
terraform {
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.14"
    }
  }
}

provider "b2" {
  application_key_id = "${local.backblaze_application_key_id}"
  application_key    = "${local.backblaze_application_key}"
}
EOF
  : "# Backblaze not enabled for this leaf -- see backblaze_config.hcl.\n"
}
```

A leaf with no `backblaze_config.hcl` gets the one-line comment file — functionally a no-op. A leaf that drops:

```hcl
# backblaze_config.hcl
locals {
  enabled = true
}
```

beside its own `terragrunt.hcl` (exact placement/shape mirroring `scaleway_config.hcl`) gets the real `required_providers`/`provider "b2"` block, and can then compose `templates/terraform/backblaze/{bucket,api-key}` ([ADR-0147](DEV-0147-add-backblaze-bucket-and-api-key-modules.md)) directly.

No consumer leaf is added in this change — it lands purely latent.

## Consequences

- Every existing leaf under `workloads/willowgraysen.com/terraform/` is unaffected — same behavior as today, just one new inert generated file.
- A leaf opting in gets a real, credentialed `provider "b2"` block with no further root.hcl changes needed.
- `secrets.enc` needs two new keys before any leaf's opt-in actually works end-to-end: `BACKBLAZE_APPLICATION_KEY_ID`/`BACKBLAZE_APPLICATION_KEY`. No dedicated `mise` task exists for editing a per-workload `secrets.enc` (only the shared `.env.enc` has `mise run secrets-edit`) — adding these is a manual step: `sops --input-type dotenv --output-type dotenv workloads/willowgraysen.com/secrets.enc`.

## Out of scope

- Creating any real `backblaze_config.hcl` consumer leaf — left for a future, separate change once an actual B2-backed leaf is needed.
- Populating `BACKBLAZE_APPLICATION_KEY_ID`/`BACKBLAZE_APPLICATION_KEY` with real values in `secrets.enc` — manual step for the user, not performed by this change.
- A dedicated `mise run secrets-edit`-style task for workload-specific `secrets.enc` files — none exists today for any workload; not added here.
- Extending this same latent-opt-in mechanism to the shared `workloads/root.hcl` or to `pigeon.dev`'s/`noisypigeon.com`'s own `root.hcl` — not requested; `willowgraysen.com` only.
- A per-leaf Backblaze region/`location` override mirroring `scaleway_config.hcl`'s region/zone fields — `b2_bucket`'s `location` hint was already left out of scope by ADR-0147; not revisited here.
- Fixing the long-standing `scaleway_config.hcl`/`workload_definition.hcl` naming drift in ADR-0098/`CLAUDE.md` — noted in Context, not this change's job to fix.
