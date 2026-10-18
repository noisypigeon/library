# DEV-0123: SOPS-encrypted root `.env`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-04.
- **Status**: Accepted.

## Context

The repo's only secrets file, root `.env`, is plaintext and gitignored (`*.env` in `.gitignore`) — never committed, hand-copied between machines. `workloads/root.hcl` locates it via `find_in_parent_folders(".env", "")`, reads it with `file()`, and parses `KEY=VALUE` lines into `local.secrets` with a hand-rolled regex comprehension; every leaf then reads a value via `get_env("KEY", lookup(local.secrets, "KEY", ""))`. Nothing else in the repo reads `.env` — not `.mise.toml` (no dotenv auto-load), not any `.github/workflows/*.yml` (none of the three workflows invoke `terragrunt`/`terraform` or touch cloud credentials at all; CI is fully decoupled from this secrets system). There is no SOPS, age, or gpg tooling anywhere in the repo prior to this ADR.

Hand-copying a plaintext secrets file between machines, with no backup beyond whatever the operator does manually, is the actual gap this ADR closes: committing the secrets in encrypted form means they survive in repo history and sync via a normal `git pull`, with Terragrunt transparently decrypting them at run time.

## Decision

Encrypt with [SOPS](https://github.com/getsops/sops) using an **age** keypair as the only recipient — a single-operator repo doesn't need GPG's keyring/trust-model ceremony. The committed file is `.env.enc` (repo root), replacing the hand-copied plaintext `.env` entirely; `.env` no longer exists on disk at all, decrypted or otherwise.

### `.sops.yaml` (new, committed)

```yaml
creation_rules:
  - path_regex: \.env\.enc$
    age: age1cx0hla738df54dk9kjnecv987uwvlh6f8wjy08ps5rxh68w9zgas90l5jh
```

Only the age *public* key is committed here — not a secret. `input_type`/`output_type: dotenv` keys were tried in this same creation rule but turned out not to be honored by `sops --encrypt`/`--decrypt`/edit invocations in practice (confirmed live: omitting them produced sops' generic JSON-wrapped binary format instead of per-key dotenv encryption, and bare `sops --decrypt .env.enc` without explicit flags failed to parse the file at all) — format must be passed explicitly as `--input-type dotenv --output-type dotenv` on every invocation instead, which is what both `root.hcl` and the new mise task below do.

### `workloads/root.hcl` — decrypt in-memory via `run_cmd`

Replaces the old `find_in_parent_folders(".env", "")` + `fileexists()`/`file()` read with a `sops` decrypt, called straight from the `locals` block on every Terragrunt invocation. No plaintext copy is ever written to disk:

```hcl
locals {
  root_env_enc_path = find_in_parent_folders(".env.enc", "")

  root_env_decrypted = local.root_env_enc_path != "" ? run_cmd(
    "--terragrunt-quiet", "sops", "--decrypt",
    "--input-type", "dotenv", "--output-type", "dotenv",
    local.root_env_enc_path
  ) : ""

  root_secrets = { for pair in [
    for line in split("\n", local.root_env_decrypted) :
    regex("^([^=]+)=(.*)$", trimspace(line))
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
    && !startswith(trimspace(line), "sops_")
    && can(regex("^([^=]+)=(.*)$", trimspace(line)))
  ] : trimspace(pair[0]) => trimspace(pair[1]) }

  secrets = local.root_secrets
}
```

The `local.root_env_enc_path != "" ? ... : ""` guard is a direct replacement for the old `fileexists()` check — if `.env.enc` is ever missing, every leaf resolves an empty secrets map instead of erroring, same as before. The new `!startswith(trimspace(line), "sops_")` filter drops the `sops_*` metadata keys sops' dotenv output format appends (MAC, lastmodified, age recipient) so they never land in `local.secrets`. Every other local in the file — `cloudflare_api_token`, `scaleway_access_key`, the `ENV_SW_`-prefixed `bucket_name_secrets` generator, the `remote_state` bucket lookup — is unchanged; all of them go through `local.secrets`, which keeps the exact same shape as before.

### Editing secrets

`mise run secrets-edit` (`sops --input-type dotenv --output-type dotenv .env.enc`) opens a decrypted buffer in `$EDITOR` and re-encrypts transparently on save — the only sanctioned way to change a value going forward. There is deliberately no task that writes a plaintext `.env` to disk.

### Tooling

- `.mise.toml`'s `[tools]` gains `sops = "3.13.3"`, pinned the same way as `terraform`/`terragrunt`/`zola`. `sops` runs on every `terragrunt`/`mise run plan`/`apply` invocation via `root.hcl`'s `run_cmd`, so it's a real repo dependency.
- `age`/`age-keygen` are **not** added to `[tools]` — generating the keypair is a one-time, out-of-band local action (`brew install age; age-keygen`), not something every invocation needs. The private key lives outside the repo (`~/.config/sops/age/noisypigeon.txt` on the author's machine, permissioned `0600`), pointed at via the `SOPS_AGE_KEY_FILE` environment variable; sops itself has native Go age support and never shells out to the `age` binary for encrypt/decrypt.
- `.env.example` keeps documenting expected key *names* only (no real values, safe to commit, unaffected by this ADR) — its header comment is corrected to describe the new `.env.enc`/`secrets-edit` flow instead of a stale, since-renumbered ADR reference.

### Migration of the real secret

The existing plaintext `.env` was encrypted to `.env.enc` (`sops --encrypt --input-type dotenv --output-type dotenv --filename-override .env.enc .env > .env.enc`), verified to round-trip with an identical key set, committed, and the plaintext `.env` deleted from disk. `.env.enc` is **not** covered by `.gitignore`'s `*.env` pattern — it ends in `.enc`, not `.env` — so no `.gitignore` change was needed; worth stating explicitly here so a future reader doesn't assume it's excluded.

## Consequences

- Every `terragrunt`/`mise run plan`/`mise run apply` invocation now shells out to `sops` once per leaf (`root.hcl`'s `run_cmd` runs inside every leaf's own locals evaluation) — a small, sub-second startup cost per leaf. `sops` plus a readable `SOPS_AGE_KEY_FILE` are now a hard requirement for any Terragrunt command to resolve secrets, same as a missing `.env` already made every leaf resolve an empty secrets map before.
- Verified live: `terragrunt init` and `terragrunt plan` against `workloads/scaleway/terraform/management` both succeeded through the new decrypt path — the S3 state backend configured correctly and `plan` reported "No changes," confirming every secret (Scaleway keys, state bucket name, Cloudflare token/account/zone IDs) resolved identically to the old plaintext-`.env` path.
- Secrets now live in git history permanently, in ciphertext — rotating a real leaked credential still requires manually rotating it at the provider (Scaleway/Cloudflare) regardless of this change; old ciphertext blobs for rotated secrets simply become undecryptable-but-harmless history.
- Single age recipient today (personal, single-operator repo) — adding a second operator later is additive: append their public key to `.sops.yaml`'s `age:` list and run `sops updatekeys .env.enc`.
- No CI changes needed — none of the three `.github/workflows/*.yml` workflows invoke Terragrunt or need decrypted secrets today.

## Out of scope

- CI ever running `terragrunt plan`/`apply` — would need an age key injected via a GitHub Actions secret; none of today's workflows need this.
- Multi-recipient/team key sharing.
- Age key rotation automation.
- GPG as an alternative backend.
