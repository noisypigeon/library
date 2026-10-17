# LIB-0014: The deployer IAM moves to runway, and breakglass keys become possible

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-17.
- **Status**: Accepted.
- **Amended 2026-10-17**: runway doesn't enable breakglass. Its own Scaleway
  key is not the one the deployer leaf mints, so the leaf doesn't sign in with
  a key it manages, and it uses `scaleway.enc` like every other leaf. §2's
  breakglass ships in the template as the precedent for a leaf that does.
  The state copy was a server-side S3 copy with runway's own key, which can
  reach the old bucket, not the LIB-0008 §3 pull/push runbook. §4, §5,
  Consequences and Verification are corrected to match.

## Context

`noisypigeon/noisypigeon` runs one last Terraform leaf,
`willowgraysen.com/terraform/state/iam`. LIB-0001 §8 left three `state/iam`
leaves behind, and Amendment 7 chose option 1 for each: stay in `noisypigeon`
on the monorepo's shared `root.hcl`, `.env.enc` and shared state bucket. The
other two have since gone, and this one remains. It composes three hub modules:

- `scaleway/iam-application` v0.1.0, named
  `willowgraysen-com-terraform-deploy`;
- `scaleway/iam-policy` v4.0.0, named `willowgraysen-com-terraform-deploy-policy`.
  The module appends `-policy`, so the policy that exists is
  `willowgraysen-com-terraform-deploy-policy-policy`. It grants ten project
  permission sets and `ProjectManager`, `IAMManager` and
  `IAMApplicationManager` on the organization;
- `scaleway/iam-api-key` v0.2.0.

The key's two halves are hand-copied into runway's
`terraform/secrets/scaleway.enc`. Because runway's state is in Scaleway, the
same value is also its `TERRAFORM_STATE_ACCESS_KEY(_ID)` in `terraform.enc`
(LIB-0010 §1, "willowgraysen's case"). Its state is
`workloads/willowgraysen.com/terraform/state/iam/terraform.tfstate` in the
shared bucket. That bucket, and the IAM that reaches it, are the
pre-DEV-0133 infrastructure DEV-0133 calls "permanently load-bearing".

They stayed load-bearing for one reason, which DEV-0130, DEV-0132 and DEV-0133
all give: an IAM-rotation leaf must not depend on the credential it manages
itself. If the leaf lived in runway, it would plan and apply with the very key
it creates. Once that key expired, or a bad apply destroyed it, the leaf could
read neither its provider nor its own state, and nothing could repair it.

That's the dependency to break. The leaf needs a credential that Terraform
doesn't manage, that only this leaf uses, and that lives in the spoke that
owns the leaf.

## Decision

### 1. A `scaleway/terraform-deployer-iam` module

A new hub module, `terraform/scaleway/terraform-deployer-iam/`, rolls up the
application, the policy and the API key into one module call. It exposes the
same inputs as the three modules it replaces:

| Input | From | Note |
| --- | --- | --- |
| `name` | iam-application | the application's name |
| `policy_name` | iam-policy | default `"${name}-policy"`, used **exactly**, with no suffix appended |
| `description` | iam-application, iam-policy | |
| `organization_id`, `organization_permission_sets` | iam-policy | same validation |
| `project_ids`, `project_permission_sets` | iam-policy | same validation |
| `default_project_id`, `expires_at`, `api_key_description` | iam-api-key | same 30-day default, anchored by `time_static` |

It outputs `application_id`, `policy_id`, and the sensitive `access_key` and
`secret_key`.

The resources are inlined, not nested module calls. A module that sources
another by short URL breaks when that URL does, as LIB-0009 §2 found with
`pigeon-cluster` and `compute-instance`. Inlining also fixes the addresses a
caller moves state into: `scaleway_iam_application.application`,
`scaleway_iam_policy.policy[0]`, `time_static.created` and
`scaleway_iam_api_key.api_key`.

`policy_name` is exact so that an existing policy can be adopted as it is
named. runway passes `willowgraysen-com-terraform-deploy-policy-policy`, and
the move is a zero diff. A rename is its own PR.

### 2. Breakglass credentials, per provider and per leaf

A spoke may hold a second credential for a provider, in
`terraform/secrets/<provider>_breakglass.enc`. Only the leaves it allowlists
use it.

- **The schema declares it.** `secrets-schema.json` gains a
  `<provider>_breakglass` file entry. It is required when
  `breakglass.<provider>`, and holds its own distinctly named keys, so every
  value still has one name (LIB-0010 §1). Two maps say which credentials it
  stands in for: `replaces` for the provider's own keys, and `replaces_state`
  for the state backend's keys. The second applies only when `state_backend`
  is that provider.
  Scaleway's entry:

  | Key | Replaces | And, when `state_backend = "scaleway"` |
  | --- | --- | --- |
  | `SCALEWAY_BREAKGLASS_ACCESS_KEY_ID` | `SCALEWAY_PROVIDER_ACCESS_KEY_ID` | `TERRAFORM_STATE_ACCESS_KEY_ID` |
  | `SCALEWAY_BREAKGLASS_ACCESS_KEY` | `SCALEWAY_PROVIDER_ACCESS_KEY` | `TERRAFORM_STATE_ACCESS_KEY` |

  The organization and project IDs aren't credentials, and still come from
  `scaleway.enc`.

- **spoke.hcl enables it, and lists the leaves.** It goes inside the
  provider's entry in the `providers` map (LIB-0005):

  ```hcl
  providers = {
    scaleway = {
      breakglass = { leaves = ["terraform/scaleway/terraform-deployer-iam/"] }
    }
  }
  ```

  `leaves` is required and must be non-empty. Unlike a provider's own
  `leaves`, it has no "every leaf" default, because a breakglass key that
  every leaf reads is just a second provider key. Each prefix ends in `/`.

- **root.hcl applies it per leaf.** A leaf under one of those prefixes, with
  the provider on, gets the condition `breakglass.<provider>`. The existing
  LIB-0012 machinery then decrypts and checks the breakglass file for that leaf
  only. No other leaf ever decrypts it. Each replaced credential then reads
  the breakglass key in place of its regular one. An environment variable
  under the regular name still wins over both, as everywhere else.

- **Guards fail the run.** They fire on `breakglass` without `leaves`, on a
  prefix without a trailing `/`, and on `breakglass` for a provider the schema
  has no breakglass file for. `check-secrets.sh` also requires the file
  spoke-wide whenever spoke.hcl enables it.

- **It's generic, with Scaleway the only provider wired up.** The credential
  lookups for all four providers go through the same replacement map. A
  `backblaze_breakglass` would be a schema entry and nothing more.

This ships as `terragrunt/root-hcl/v4.1.0` and `workflows/v3.1.0`, both minor:
a spoke that doesn't set `breakglass` renders the same.

### 3. The breakglass key is made by hand, and Terraform never manages it

The Scaleway organization owner creates the key in the console and encrypts it
into `scaleway_breakglass.enc` with sops. It is the spoke's root of trust for
its own IAM, which is why Terraform never manages it. It needs the deployer
leaf's permissions: `IAMManager` and `IAMApplicationManager` on the
organization, and object-storage access to the state bucket. It is rotated by
hand, by editing that one file.

### 4. runway takes the leaf: `terraform/scaleway/terraform-deployer-iam/runway`

- **The leaf** calls the module (§1) with the existing names, permission sets
  and project. It signs in with runway's own Scaleway key, which it doesn't
  manage, so it needs no breakglass key. If runway ever hands it the key it
  signs in with, allowlist it (§2) first. Its outputs keep
  the existing hand-copy step: the deployer key goes into `scaleway.enc` and
  `terraform.enc`.
- **The state is copied, not imported.** Runway's own key can reach the
  shared bucket, so a server-side S3 copy moves the old state object into
  runway's bucket, at the leaf's key, and it is checked by SHA-256, serial and
  lineage. An import couldn't recover the API
  key's `secret_key`, so the outputs would be empty until the next rotation.
- **`moved` blocks map the addresses.** `module.iam_application`,
  `module.iam_policy` and `module.iam_api_key` become
  `module.terraform_deployer_iam`. CI must plan four moves and no adds,
  changes or destroys.
- **Then the old key is emptied.** DEV-0130 says a migration "is not complete
  until the old location's state is also emptied, not merely orphaned". So
  after runway's apply, `workloads/willowgraysen.com/terraform/state/iam/terraform.tfstate`
  is rewritten as the same lineage at the next serial, with no resources and
  no outputs. That is `state rm` of every instance, and it also drops the API
  key's secret from the old output. The bucket is versioned, so the previous
  version is kept.
- **The old leaf's files stay where they are.** This record moves state, not
  files (see Out of scope).

### 5. LIB-0001 §8 is resolved

After §4, nothing in runway reads anything from `noisypigeon`: no root, no
secrets, no state, and no IAM that `noisypigeon` manages. That was the last
`state/iam` leaf. This record amends LIB-0001 Amendment 7: a spoke runs its
own deployer IAM. When that leaf would depend on a key it manages, a per-leaf
breakglass key breaks the loop (§2). That is the "local bootstrap root"
candidate in §8, done with one root and a per-leaf credential rather than a
second root. runway doesn't need it today (Amended).

## Consequences

- **`noisypigeon` is no longer load-bearing for Terraform.** Its shared bucket
  and the pre-DEV-0133 IAM still exist, unused. Retiring them is another
  record's job.
- **noisypigeon's `state/iam` leaf must never be applied again.** Its state is
  empty, so an apply would create a second application, policy and key with the
  same names. The leaf's files stay until a separate cleanup, so this hazard
  lasts until then.
- **A breakglass-allowlisted leaf survives its own key.** If the key it
  manages expires or is destroyed, it still plans and applies with the
  breakglass key and can mint a new one. runway's deployer leaf already
  survives the deployer key, because it signs in with runway's own key.
- **A breakglass file is one more secret to guard,** in a spoke that enables
  one. It holds an organization-level IAM credential. Only the allowlisted
  leaf decrypts it, but the age key that decrypts every other file decrypts it
  too. A separate recipient is possible later and isn't needed for this.
- **The template grows a concept.** spoke.hcl's `providers` entries gain an
  optional `breakglass` key, and the schema gains `replaces` and
  `replaces_state`. Both are additive.

## Out of scope

- **Cleaning up or deleting `noisypigeon/noisypigeon`**, including removing the
  legacy `willowgraysen.com/terraform/state/iam` files, its `.env.enc` and
  shared bucket, and the pre-DEV-0133 IAM. A permanent boundary for this
  record: the owner does this separately.
- **Renaming the hoisted IAM objects** away from `willowgraysen-com-*`.
  Genuinely deferred: it's a plain in-place update, and its own PR in runway (noisypigeon/noisypigeon#324).
- **Breakglass for Cloudflare and Backblaze.** Genuinely deferred: the template
  supports it (§2), but no spoke needs it yet (noisypigeon/noisypigeon#325).
- **A separate sops recipient for breakglass files.** Genuinely deferred
  (Consequences) (noisypigeon/noisypigeon#326).
- **Automating the deployer key's hand-copy** into `scaleway.enc` and
  `terraform.enc`. Genuinely deferred: rotation stays a manual step (noisypigeon/noisypigeon#327).

## Verification

1. `terraform/scaleway/terraform-deployer-iam/v0.1.0` was tagged (pigeon-lib#66).
   Its `noisypigeon.garden` short URL serves the `terraform-get` meta for that
   tag.
2. `terragrunt/root-hcl/v4.1.0` and `workflows/v3.1.0` were tagged
   (pigeon-lib#67). Against a sops/age fixture spoke:
   - an allowlisted leaf took its provider and backend credentials from
     `scaleway_breakglass.enc`;
   - a non-allowlisted leaf rendered with that file corrupted, so it never
     decrypted it;
   - each guard fired;
   - `check-secrets.sh` failed without the file and passed with it.
   A spoke without `breakglass` rendered byte-for-byte the same as under
   v4.0.0.
3. runway took v4.1.0 and `workflows/v3.1.0` without enabling breakglass
   (noisypigeon/runway#18). Its CI planned `No changes.` on all 17 existing
   leaves.
4. The server-side copy matched the source by SHA-256, serial (6), lineage and
   resource count (4 resources, 4 instances), and the policy kept its `[0]`
   index. CI planned four moves and `0 to add, 0 to change, 0 to destroy` on
   `terraform/scaleway/terraform-deployer-iam/runway`, and the apply was a
   no-op. The new state is at serial 7 with all four resources under
   `module.terraform_deployer_iam`.
5. The old key now holds serial 7 of the same lineage, with 0 resources and no
   outputs. The previous version (6245 bytes) is kept in the versioned shared
   bucket, and the legacy leaf's files in `noisypigeon` are unchanged.
6. runway's auto-merge failed with the known job-token error
   (noisypigeon/noisypigeon#310), and #18 was merged by hand after the apply.
