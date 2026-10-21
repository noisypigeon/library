# LIB-0025: A workload's `secrets.yaml`

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-21.
- **Status**: Accepted. Amends LIB-0023, adding `secrets.yaml` beside
  `values.yaml`, and `secretRef` in `values.yaml`.

## Context

A LIB-0023 workload is one plaintext file, `workloads/<workload>/values.yaml`,
reviewed in every PR that changes it. It has nowhere to put a secret.

- **A spoke's secrets are spoke-wide.** They live in the dotenv sops files under
  `terraform/secrets/` (LIB-0012). `env.enc`'s keys become locals in every
  leaf, but a workload leaf has no hand-written code to read a local, and a
  secret one workload needs shouldn't reach every leaf in the spoke.
- **Writing a secret into `values.yaml` is the failure to prevent.** root.hcl
  writes `values.yaml`'s inputs into `workload_generated.tf` as literals
  (LIB-0023's first amendment). That's fine for plaintext, and wrong for a
  secret.

Every secret in this family is encrypted with sops and one age key per spoke.
The private key sits in the spoke's GitHub secret `SOPS_AGE_KEY`, and in a
file on each laptop that edits it. That key is the weakest link, whatever file
format it encrypts.

## Decision

### 1. A workload may have a `secrets.yaml`, encrypted with sops

```yaml
# workloads/pigeon-cli/secrets.yaml
env:
  API_TOKEN: ENC[AES256_GCM,data:…,type:str]
scaleway:
  bucket:
    example:
      some_secret_input: ENC[AES256_GCM,data:…,type:str]
sops:
  age: [...]
```

- **It's SOPS YAML,** which encrypts values and leaves keys readable. A PR's
  diff shows which secrets changed, and CI checks the file's shape without
  decrypting it, as `check-secrets.sh` already does for dotenv (LIB-0012 §4).
- **The spoke's `.sops.yaml` gains a rule** for
  `^workloads/[^/]+/secrets\.yaml$`, with the spoke's existing age recipient.
  `sops edit workloads/<workload>/secrets.yaml` then creates and edits it.
- **It holds two things:**
  - **secret module inputs,** under the same kind paths as `values.yaml`;
  - **`env`,** a flat map of named secrets for the whole workload.
- **Every value is a string.** A number or a boolean is passed as its string.
  A list or a map is refused.

### 2. What it may hold, checked without decrypting

`resolve-workloads.sh --check` reads the keys, which sops leaves in clear.

- **Only `env` and kind paths at the top.** `env`'s values are scalars. The
  kind paths are the ones `values.yaml` allows, including the implicit
  `scaleway.deployer` (LIB-0024).
- **A secret can't declare an instance.** Every kind path under `secrets.yaml`
  must exist in `values.yaml` too.
- **A secret input is a real input.** Its name must be a property of the
  module's `inputs.schema.json` at the version the entry resolves to, as for
  `values.yaml` (LIB-0023 §6).
- **Each input has one source.** An input set in both files fails, naming both.
- **Plaintext is refused.** A `secrets.yaml` with no `sops` metadata, or with
  any value not of the form `ENC[…]`, fails. That's the guard against a secret
  committed in clear.

A `secrets.yaml` adds no stubs, so `--list` and stub generation don't read it.

### 3. Secrets reach the module as sensitive variables, never as literals

`terragrunt/root-hcl` takes a minor version.

- **root.hcl decrypts the file** with `run_cmd` on `sops --decrypt --output-type
  json`, the way it decrypts `terraform/secrets/` today. It does so inside a
  `for` whose filter is "a workload leaf, and the file exists", since HCL
  evaluates both arms of a conditional. It marks the file read, so a change
  to `secrets.yaml` alone re-plans the workload.
- **A secret input** becomes `variable "<input>" { type = string, sensitive =
  true }` in `workload_generated.tf`, passed into the module call. Its value
  arrives through the template's own `inputs`, which Terragrunt merges with the
  stub's wiring. It's never written into a generated file, and the plan shows
  it as `(sensitive value)`.
- **`env` is reached by reference.** Any input in `values.yaml` may be written
  as `{ secretRef: NAME }`, as in Crossplane's `secretKeyRef`. root.hcl swaps
  it for a sensitive variable fed from `env.NAME`. The whole map is also passed
  to every leaf of the workload as `var.workload_env` (`map(string)`,
  sensitive), for kinds that take an environment map.
- **Guards fail the run** when `secrets.yaml` doesn't decrypt, when an input
  is set in both files, when a `secretRef` names something `env` doesn't
  have, and when a value isn't a scalar.

### 4. CI selects, masks and checks it

`workflows/` takes a minor version.

- **Selection:** a changed `workloads/<w>/secrets.yaml` selects workload `<w>`,
  as `values.yaml` does (LIB-0023's second amendment).
- **Masking:** "Mask decrypted secret values" also decrypts every
  `workloads/*/secrets.yaml`, and masks each value. A sensitive variable is
  already hidden in plan output. This covers an error message that echoes one.
- **Schema:** the workload schema accepts `{ secretRef: <name> }` as the value
  of any input. `secrets.yaml` has no schema, since its `sops` block and
  `ENC[…]` strings would defeat one. `--check` covers it.
- **A spoke takes the workflows release alone first,** since it changes
  selection (LIB-0024 §5).

### 5. This iteration keeps the spoke's age key; hardening it comes next

The options considered, for the key and for where secrets live:

| Option | Cost | Gains | Leaves |
| --- | --- | --- | --- |
| The spoke's age key, in `SOPS_AGE_KEY` and on laptops (today) | free | — | a long-lived key, copied to every machine that edits secrets, decrypting all of the spoke's secrets |
| The age key in **1Password**, loaded in CI by `1password/load-secrets-action` and on laptops by `op` | already paid | no key file on disk; rotation and revocation in one place; an access log; with GitHub OIDC ("Workload Identity"), no long-lived CI credential at all | one key for all of a spoke's secrets |
| Workload secrets in **Scaleway Secret Manager**, in the workload's own project, read at plan time by the workload's own deployer (LIB-0024) through `scaleway_secret_version` | €0.04 per version per month, and €0.03 per 10,000 calls | isolation by IAM, per workload; secrets out of git | the values reach state and saved plans, which are encrypted (LIB-0022 §2); changes leave git review |
| sops with a cloud KMS (AWS, GCP, Azure, or Vault) | a free tier, on a new account | a KMS-held key, reached by OIDC | a new cloud provider. Scaleway Key Manager has no sops backend |
| An age recipient per workload | free | a laptop holds only the keys for its workloads | CI still holds every key |

**The direction:**

1. **First, move the age key into 1Password.** It's the largest gain for the
   least change: no plaintext key on any disk, one place to rotate and revoke
   it, and a record of every read. Use GitHub OIDC if the plan offers it.
   Otherwise use a service account limited to one vault, whose token
   replaces `SOPS_AGE_KEY` in GitHub. Its availability needs checking first.
2. **Then, for secrets a workload's resources use at run time, Scaleway
   Secret Manager in the workload's project.** LIB-0024 already gives each
   workload a deployer scoped to its project, so it's the only option here
   that isolates one workload's secrets from another's.

Per-workload age recipients and a cloud KMS are not pursued.

Sources:
- [1Password's load-secrets-action](https://github.com/1Password/load-secrets-action)
- [1Password in GitHub Actions](https://developer.1password.com/docs/ci-cd/github-actions)
- [1Password service accounts](https://1password.com/blog/1password-service-accounts)
- [Scaleway Secret Manager](https://www.scaleway.com/secret-manager)
- [`scaleway_secret_version`](https://www.pulumi.com/registry/packages/scaleway/api-docs/secrets/getversion), as mirrored from the Terraform provider
- [Scaleway Key Manager's API](https://www.scaleway.com/en/developers/api/key-manager)

## Consequences

- **A workload carries its own secrets,** reviewed by name in the same PRs as
  its `values.yaml`, and readable only by whoever holds the spoke's age key.
- **A secret can't leak through a generated file.** Only plaintext values are
  ever written as literals.
- **The age key's reach grows.** It now decrypts workload secrets too, which
  makes §5's first step more urgent.
- **Two files per workload, where secrets are needed.** A workload without
  secrets has no `secrets.yaml`.

## Out of scope

- **The age key in 1Password.** Deferred ([#116](https://github.com/noisypigeon/library/issues/116)).
- **Workload secrets in Scaleway Secret Manager.** Deferred ([#117](https://github.com/noisypigeon/library/issues/117)).
- **An age recipient per workload, and sops with a cloud KMS.** Considered in §5
  and not pursued. A permanent boundary until §5's steps change the picture.
- **Building §§1–4.** The workflows and template changes, and runway's
  adoption, ship in later PRs that cite this record ([#115](https://github.com/noisypigeon/library/issues/115)).

## Verification

Recorded 2026-10-21. Every item passed.

1. **Plaintext is refused.** `--check` fails on a `secrets.yaml` without
   `sops` metadata, and on one with a plaintext value.
   - **Passed** on a scratch spoke, for both, and for unknown keys, an input
     in both files, a secret for an undeclared instance, and an unknown
     input.
2. **Secrets never reach a generated file.** With a dummy secret in a workload
   leaf, `workload_generated.tf` holds only a sensitive variable, and the
   secret appears nowhere in the leaf's `.terragrunt-cache` except the plan.
   - **Passed** on a scratch spoke. The rendered leaf's generate blocks
     contain no secret text. The values travel only in its inputs.
3. **The plan hides it.** The PR's plan comment shows `(sensitive value)`, and
   the job log shows no secret.
   - **Passed:** on the plan-only draft [runway#39](https://github.com/noisypigeon/runway/pull/39), a
     secret `expiration_days` planned as `days = (sensitive value)`. Neither
     dummy value appeared in the comment or the job log.
4. **A secrets-only change re-plans.** Editing only `secrets.yaml` selects its
   workload.
   - **Passed:** [runway#43](https://github.com/noisypigeon/runway/pull/43)
     changed only `workloads/poc/secrets.yaml`, re-encrypting it with
     `sops --rotate`. It selected exactly the five `workloads/poc` leaves,
     all `No changes.`, and no hand-written leaf. (#39 couldn't isolate this,
     since its diff also changed `root.hcl`.)
5. **`secretRef` resolves,** and a `secretRef` to a name `env` lacks fails the
   plan.
   - **Passed:** `website_index_document: { secretRef: … }` resolved on #39
     and on [runway#41](https://github.com/noisypigeon/runway/pull/41). A `secretRef` to a missing name
     failed on a scratch spoke, both in root.hcl's guard and in `--check`.
