# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-10-20

### Rotate the deployer API key every rotation_days

`terraform-deployer-iam` gains an optional `rotation_days` input (LIB-0024 §4).

- **With it set,** a `time_rotating` resource replaces the API key every `rotation_days`. The new key is created before the old one is destroyed, and each key expires a week after its scheduled rotation, so a month in which nothing plans doesn't strand its users. It's meant for a key Terraform hands to other leaves, such as a LIB-0024 workload deployer, which pick up the new key on the next plan.
- **Without it,** nothing changes in behaviour: the key expires 30 days after it was first created, and an explicit `expires_at` still wins. A caller upgrading from v0.1.0 does see one new resource in its plan, `terraform_data.rotation`, which carries the rotation trigger and does nothing while `rotation_days` is unset.

`rotation_days` must be positive.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#113](https://github.com/noisypigeon/library/pull/113)

## [0.1.0] - 2026-10-17

### Add terraform-deployer-iam: a spoke's deployer application, policy and API key in one module

A new module, `scaleway/terraform-deployer-iam`, builds a spoke's Terraform deployer identity in one call: an IAM application, its policy, and an API key for it (LIB-0014). It replaces calling `iam-application`, `iam-policy` and `iam-api-key` side by side and takes the same inputs: `name`, `description`, the organization and project permission sets, `default_project_id` and `expires_at`, with `api_key_description` for the key.

Two details matter when adopting existing objects:

- **`policy_name` is used exactly as given.** `iam-policy` appends `-policy`, so a policy it created is named `<name>-policy`. Pass that full name here and the adoption is a zero diff. It defaults to `"<name>-policy"`.
- **The resources are inlined,** at fixed addresses (`scaleway_iam_application.application`, `scaleway_iam_policy.policy[0]`, `time_static.created`, `scaleway_iam_api_key.api_key`). A leaf moving off the three separate modules writes one `moved` block for each.

The leaf that calls this manages the key every other leaf deploys with. Allowlist it for the spoke's Scaleway breakglass credential, so it never authenticates with the key it rotates.

Outputs: `application_id`, `policy_id`, and the sensitive `access_key` and `secret_key`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#66](https://github.com/noisypigeon/pigeon-lib/pull/66)
