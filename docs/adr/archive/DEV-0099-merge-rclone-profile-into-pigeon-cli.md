# DEV-0099: merge the `rclone` cloud-init profile into `pigeon-cli`, remove `rclone`

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-02.
- **Status**: Accepted.

## Context

`modules/scaleway/compute-instance`'s `profile` input had three values: `"rclone"` (default — installs `rclone`+`neovim`, writes `/root/.config/rclone/rclone.conf` from `var.buckets`, ADR-0081/0087), `"docker"` (Docker CE, ADR-0087), and `"pigeon-cli"` (runs the `pigeon-cli` bootstrap script via `runcmd`, no packages or bucket config of its own, ADR-0088/0089). `buckets` was only accepted when `profile == "rclone"`.

The user asked for `"pigeon-cli"` to absorb everything `"rclone"` did, and for `"rclone"` to be removed as a distinct profile entirely.

This isn't a hypothetical cleanup — it was actively blocking real, in-progress work. `workloads/pigeon-cli/terraform/sort/macbook-scratch/compute.tf` (the user's own in-progress leaf, a new `sort` job alongside the existing `import`/`deduplication` ones) already calls the module with `profile = "pigeon-cli"` **and** a non-empty `buckets` list (source/destination rclone remotes) — under the prior module version this fails `buckets`' own validation outright. The sibling `deduplication/macbook-scratch/compute.tf` (also mid-edit, currently commented out) shows the same shape with `profile = "rclone"` plus `buckets` — i.e. the user was actively working out how to get both bucket-sync and the pigeon-cli bootstrap running on one instance. Merging the profiles is exactly the fix, confirmed directly against both files before making any change.

**Research confirmed, verbatim, before planning anything:**

- A repo-wide grep for `profile\s*=` across every `.tf` file found exactly one live (uncommented) module call anywhere: `sort/macbook-scratch/compute.tf`, already on `profile = "pigeon-cli"`. No caller anywhere relies on the `"rclone"` default or passes `profile = "rclone"` live — the commented-out `deduplication/macbook-scratch` and `custodian-buckets/.../duck-jellyfish-import` blocks are both dormant. Removing `"rclone"` breaks zero live configuration.
- In the cloud-init template, `packages:` was wrapped in `%{~if var.profile != "pigeon-cli"~}` specifically because ADR-0088 found an empty `packages:` key is invalid/null in cloud-init YAML, and `"pigeon-cli"` installed zero packages at the time. Once `"pigeon-cli"` absorbs `rclone`+`neovim`, every remaining profile (`"docker"`, `"pigeon-cli"`) always has at least one package — the whole empty-packages special case became moot, so it was removed rather than extended with a third branch.
- The `write_files` block (the `rclone.conf` templating over `var.buckets`) needed no content change, only its gate: `var.profile == "rclone"` → `var.profile == "pigeon-cli"`.
- `runcmd` needed no changes at all — there was never a `profile == "rclone"`-gated `runcmd` entry; rclone's only footprint was `packages:` + `write_files:`. The existing `pigeon-cli` bootstrap `runcmd` line is untouched, and cloud-init always runs `write_files` before `runcmd`, so the bootstrap script still sees a populated `rclone.conf` on first boot — same ordering as before, now just always true for this profile instead of true only when both profiles happened to apply.

## Decision

### `instance.tf`

`packages:` is now unconditional (it can never be empty anymore); `write_files:` is gated on `profile == "pigeon-cli"` instead of `profile == "rclone"`:

```hcl
packages:
%{~if var.profile == "docker"~}
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
%{~endif~}
%{~if var.profile == "pigeon-cli"~}
  - rclone
  - neovim
%{~endif~}
%{~if var.profile == "pigeon-cli"~}

write_files:
  ... (unchanged, loops over var.buckets)
%{~endif~}
```

### `inputs.tf`

- `profile`: validation list `["docker", "pigeon-cli"]`; default `"rclone"` → `"pigeon-cli"` (the closest equivalent to preserving "omit `profile`, get rclone+neovim+bucket config" — `"pigeon-cli"` is now a strict superset of the old default's behavior). Description updated to describe the merged profile.
- `buckets`: validation condition `var.profile == "rclone"` → `var.profile == "pigeon-cli"`; description updated the same way.

No output changes.

### Version bump: major

An accepted enum value disappearing and a validation gate moving are both breaking interface changes — per this repo's semver discipline (`modules/README.md`, and the major bumps ADR-0093/0096 made for similar interface changes), `compute-instance` goes v1.0.0 → **v2.0.0**.

### Verified before release, not assumed

- `terraform fmt -check` and `terraform init -backend=false && terraform validate` clean on the module itself.
- A standalone scratch config exercising just the cloud-init `locals` block (no provider needed) confirmed: `profile = "docker"` renders byte-identical output to before; `profile = "pigeon-cli"` with a sample `buckets` entry now renders the `rclone`/`neovim` packages, the populated `write_files` block, and the unchanged pigeon-cli bootstrap `runcmd` line, in that order.
- A second scratch config calling the real module (triggering its own `validation` blocks) confirmed: `profile = "rclone"` is now rejected outright (invalid enum value); `profile = "docker"` with a non-empty `buckets` is rejected with the updated error message; `profile = "pigeon-cli"` with a non-empty `buckets` plans cleanly. (Note: `terraform validate` alone doesn't evaluate a module's cross-variable validation rules without a full `plan` — confirmed the rejection only surfaces under `terraform plan`, which is what matters for real usage.)

### Consumer update

`workloads/pigeon-cli/terraform/sort/macbook-scratch/compute.tf`'s module source bumped from `?ref=modules/scaleway/compute-instance/v1.0.0` to `v2.0.0` once tagged — this is what actually unblocks that leaf, since its `profile = "pigeon-cli"` + `buckets` combination only validates successfully against the new version. `deduplication/macbook-scratch/compute.tf` was left untouched — it's fully commented out, the user's own active work-in-progress, not something to edit on their behalf.

## Consequences

- A caller wanting "just the pigeon-cli bootstrap, no rclone/neovim" no longer has that option — `"pigeon-cli"` is now always rclone+neovim+bootstrap. No such caller exists today; stated here as a deliberate tradeoff rather than an oversight, should one ever come up.
- Any existing instance using this module gets replaced on its next apply, same as every prior cloud-init content change to this module (ADR-0084's force-replace-on-cloud-init-change lifecycle) — not a new consequence, just the usual one.

## Out of scope

- The `"docker"` profile — untouched by this change.
