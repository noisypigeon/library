# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-04

### Split iam-policy's application/API-key into iam-application and iam-api-key modules

`iam-policy` bundled three independent concerns into one module: `scaleway_iam_application`, `scaleway_iam_policy`, and `scaleway_iam_api_key`. A repo-wide census found exactly two real consumers, and confirmed zero consumers use `bucket_names`/`bucket_actions`/`admin_project_id` -- that bucket-scoped policy feature (ADR-0066/ADR-0069) never had a second real caller.

This PR splits the bundle into three modules:

- **New `iam-application`**: wraps `scaleway_iam_application` only. Inputs `name` (required), `description` (optional). Outputs `id`, `name`.
- **New `iam-api-key`**: wraps `scaleway_iam_api_key` only. Inputs `application_id` (required), `description` (optional), `expires_at` (optional -- defaults to 30 days after the key is first created, anchored via a `time_static` resource so the default doesn't drift on every `plan`). Outputs `access_key`/`secret_key` (both sensitive).
- **`iam-policy`, slimmed to policy-only**: no longer creates an application or API key -- takes a new required `application_id` input instead. Drops `bucket_names`, `bucket_actions`, `admin_project_id`, and `expires_at` entirely (none were used by any real consumer), along with the `access_key`/`secret_key` outputs. Gains a new `id` output for the policy itself.

This lets one `iam-application` be shared across several `iam-policy` calls instead of each policy call minting its own throwaway application -- the motivating use case is a shared `pigeon-cli` identity with multiple job policies attached to it.

Breaking for every `iam-policy` consumer: existing callers need to add an `iam-application` module call and pass its `id` as `application_id`, add a separate `iam-api-key` call to get a credential, and drop any `bucket_names`/`bucket_actions`/`admin_project_id`/`expires_at` arguments (moving `expires_at` to the new `iam-api-key` call if still needed).

See docs/adr/0119-decouple-scaleway-iam-application-api-key-rename-object-bucket.md for the full decision record (this PR covers the IAM-module half of that ADR).

[#162](https://github.com/noisypigeon/noisypigeon/pull/162)
