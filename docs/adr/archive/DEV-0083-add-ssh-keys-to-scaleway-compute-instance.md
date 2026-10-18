# DEV-0083: add instance-specific SSH keys to scaleway/compute-instance

- **Author**: Willow Finch ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-09-30.
- **Status**: Accepted.

## Context

The user asked how to attach an SSH key to a `compute-instance`, linking
Scaleway's docs on adding Instance-specific SSH keys via tags
([add-instance-specific-ssh-keys-using-tags](https://www.scaleway.com/en/docs/instances/reference-content/add-instance-specific-ssh-keys-using-tags/)).
That page is client-rendered, so its actual content was pulled from the raw
HTML directly rather than trusting a possibly-truncated fetch.

Every Scaleway Instance image ships a `scw-fetch-ssh-keys` script that
populates `/root/.ssh/authorized_keys` on boot from two sources: account-
wide SSH keys (already auto-applied to every instance — confirmed in
ADR-0081's Context, no Terraform config needed) and any instance **tag**
matching:

```
AUTHORIZED_KEY=ssh-ed25519_AAAAC3NzaC1lZDI1NTE5AAAA...
```

— the public key with every space replaced by an underscore. Each key is
its own separate tag; these apply only to that one instance and don't
propagate to others, unlike account-wide keys.

This maps directly onto `scaleway_instance_server`'s existing `tags`
argument (`list(string)`, confirmed via the provider's own example usage —
`tags = ["hello", "public"]`) — the exact field ADR-0079 named in its
`compute-instance` Out-of-scope list. No cloud-init/`user_data` involvement
is needed; the key-fetching script is already baked into Scaleway's images,
the same automatic-injection behavior ADR-0081 already relied on for
account-wide keys.

## Decision

### New variable: `ssh_keys`

`inputs.tf` gains, optional/default `[]` (matching `buckets`'s precedent
from ADR-0081 — most instances need no extra keys beyond the account-wide
set that's already automatic):

```hcl
variable "ssh_keys" {
  type        = list(string)
  description = "SSH public keys granted instance-specific access via Scaleway's AUTHORIZED_KEY tag convention, in addition to account-wide keys"
  default     = []
}
```

A raw public key is passed in as-is (e.g. `"ssh-ed25519 AAAAC3Nz..."`) —
the module handles the space-to-underscore encoding Scaleway's tag format
requires, rather than making every caller remember to do it by hand.

### `instance.tf`: encode into `tags`

```hcl
resource "scaleway_instance_server" "server" {
  name  = "${var.namespace}-${random_string.suffix.result}-${var.name}"
  image = var.image
  type  = var.type
  tags  = [for key in var.ssh_keys : "AUTHORIZED_KEY=${replace(key, " ", "_")}"]

  user_data = { ... } # unchanged, from ADR-0081
}
```

`tags` is fully derived from `ssh_keys` — this module has no other use for
tags today, so there's no merge-with-existing-tags concern. `ssh_keys = []`
produces `tags = []`, identical to today's untagged behavior.

**Documented caveat, not a guarded feature**: Terraform fully replaces
`tags` on every apply. If someone also adds `AUTHORIZED_KEY` tags by hand
in the Scaleway console — exactly how the linked doc's own walkthrough
describes doing it manually — the next `terraform apply` will overwrite
those with whatever `ssh_keys` currently says. This is stated as a caveat
below rather than solved with drift-detection/merge logic.

### No output changes

`ssh_keys` is caller-supplied; there's nothing new to surface — the same
"no invented output" posture ADR-0079/ADR-0082 already established.

## Consequences

- `release:minor` for `scaleway/compute-instance` — new, backwards-
  compatible, default-`[]` input; no behavior change for existing callers.
- `terraform/modules/scaleway/compute-instance/README.md` regenerates
  automatically via `module-docs.yml` on merge.
- Managing this instance's tags by hand in the Scaleway console (instead of
  via `ssh_keys`) will be overwritten on the next `apply` — it becomes the
  caller's responsibility to manage keys through Terraform once `ssh_keys`
  is in use.

## Out of scope

- A generic `tags` passthrough variable for arbitrary (non-SSH-key)
  tagging — rejected in favor of the dedicated `ssh_keys` convenience
  variable; can be added later via a follow-up ADR if a real non-SSH
  tagging need arises.
- Validating SSH key format/algorithm (e.g. requiring an `ssh-ed25519`/
  `ssh-rsa` prefix) — no validation block, matching how `buckets`'
  `bucket_provider` also goes unvalidated.
- Managing the account's own SSH key inventory (e.g. a
  `scaleway_iam_ssh_key`-style resource) — this ADR is only about
  instance-specific keys via tags.
- Everything else ADR-0079 already deferred and still untouched: root
  volume sizing, additional volumes, security/placement groups, `private_network`,
  `state`, Windows admin password support, `type` enum validation,
  attaching to an existing root volume.
