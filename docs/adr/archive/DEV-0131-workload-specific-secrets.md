# DEV-0131: Workload-specific secrets via `workloads/<name>/secrets.enc`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-05.
- **Status**: Accepted.

## Context

Every leaf under `workloads/` has, until now, decrypted the same single repo-root `.env.enc` (ADR-0123) via the shared `workloads/root.hcl`, regardless of which workload it belongs to. That's the right default for infrastructure genuinely shared across the whole repo (the Scaleway organization ID, the repo-wide deployer credentials, etc.), but it means every workload's secrets live in one undifferentiated file, and every workload implicitly trusts the same credentials.

ADR-0130 gives `workloads/pigeon.dev` its own dedicated Terraform state bucket and deployer identity, decoupled from the shared repo-wide bootstrap. That identity's own credentials — and the handful of other values only `pigeon.dev`'s leaves need (its Scaleway project ID, its dedicated state bucket name, its copy of the Cloudflare token) — need somewhere to live that isn't the shared `.env.enc`, or the whole point of the decoupling is undermined.

## Decision

A workload MAY place a `secrets.enc` file directly under its own `workloads/<name>/` directory (sibling to a `workloads/<name>/root.hcl`, not the shared `workloads/root.hcl`). It's sops/age-encrypted exactly like the repo-root `.env.enc` — same dotenv input/output format, same `sops --decrypt` invocation pattern — but decrypted and consumed entirely independently: a workload's own `root.hcl` reads only its own `secrets.enc`, never merged with or falling back to the shared `.env.enc`.

No leading dot, unlike the repo-root `.env.enc` — just `secrets.enc`.

`.sops.yaml` gained a second creation rule, `workloads/[^/]+/secrets\.enc$`, reusing the same single age recipient as the existing `\.env\.enc$` rule (no new key material — this is about secrets *locality*, not a different trust boundary).

`workloads/pigeon.dev/secrets.enc` is the first and, as of this ADR, only consumer — holding its own `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY` (the `pigeon-dev` deployer from ADR-0130), `SCALEWAY_ORGANIZATION_ID`, `SCALEWAY_PROJECT_ID` (moved out of the shared `.env.enc`'s `ENV_SW_SCALEWAY_PROJECT_ID_PIGEON_DEV`), `PIGEON_DEV_TERRAFORM_STATE_BUCKET_NAME`, and copies of `CLOUDFLARE_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`/`ENV_CF_ZONE_ID_PIGEON_DEV`. The `ENV_SW_`/`ENV_CF_`-prefix-stripping generated-local convention (ADR-0006) carries over unchanged within a workload's own `secrets.enc` — it's the same mechanism, just reading from a different, narrower file.

## Consequences

- A workload adopting this pattern takes on its own secret-management overhead (its own `sops`-encrypted file to edit, its own entries to keep in sync when credentials rotate) in exchange for not sharing fate with every other workload's credentials.
- The shared `.env.enc` keeps the secrets actually needed repo-wide (the shared deployer, the shared state bucket name, the Cloudflare token used by workloads that haven't opted into their own `secrets.enc`). Nothing about this ADR changes `.env.enc`'s existing role for workloads that don't adopt the new pattern.
- `workloads/pigeon.dev`'s copy of `ENV_SW_SCALEWAY_PROJECT_ID_PIGEON_DEV` is now redundant in the shared `.env.enc` (superseded by `secrets.enc`'s own `SCALEWAY_PROJECT_ID`) — left in place rather than cleaned up as part of this change; a harmless, unused leftover, not a correctness issue.

## Out of scope

- Retrofitting any other existing workload with its own `secrets.enc` — this ADR establishes the pattern via `pigeon.dev` only. Every other workload keeps reading the shared `.env.enc` exactly as before.
- Removing the now-unused `ENV_SW_SCALEWAY_PROJECT_ID_PIGEON_DEV` key from the shared `.env.enc` — a cleanup opportunity, not addressed here.
