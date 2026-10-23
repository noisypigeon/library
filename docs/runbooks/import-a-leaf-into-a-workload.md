# Import a leaf into a workload

Moves the resources of a hand-written leaf, `terraform/<provider>/...` in some
spoke, into the leaves of a workload, `workloads/<w>/<provider>/<module>/<key>/`,
without recreating them ([LIB-0032](../adr/LIB-0032-move-the-blog-into-runway.md)
§3). The old leaf and the workload may be in different spokes.

A plain state copy doesn't work, because the leaves change shape:

- a hand-written leaf often calls a module with `for_each`, so a resource's
  address is `module.dns_record["mx_primary"].cloudflare_dns_record.this`;
- a workload leaf calls one module instance, so the same resource is
  `module.this.cloudflare_dns_record.this`, in a different leaf's state.

So each resource is imported into its new address by its provider ID, and
then removed from the old state.

## When to use it

Use it for resources that must not be destroyed: live DNS, buckets with data,
keys in use. A disposable resource is simpler to destroy and recreate, as
LIB-0028's `poc` was.

## The one rule

**Nothing applies in either spoke from the first import until the PR that
commits the entries merges.** Between an import and its `state rm`, both
states hold the resource. An apply on either side then can destroy it, or
create a duplicate. Tell everyone who can comment `terragrunt apply`.

## What you need

- Checkouts of both spokes, each after `./fetch-lib.sh` and
  `.lib-src/.github/scripts/resolve-root-hcl.sh`.
- Their sops age keys, so `root.hcl` can decrypt each spoke's secrets.
  `sops --decrypt terraform/secrets/terraform.enc >/dev/null` in each checks
  it, without writing anything.
- The workload's bootstrap applied: its project, deployer and state bucket
  (LIB-0028 §6). Its zones registered to it in `zones.yaml`, for Cloudflare
  (LIB-0030 §2).

## Steps

1. **Snapshot what the outside world sees.** For DNS, `dig +short <name>
   <type>` for every record, and `curl -sI` for every redirect, into a file
   outside both checkouts. You'll compare against it at the end.

2. **Write the entries, locally.** Add one `values.yaml` entry per resource
   group, copying every input the old leaf sets, including the ones a
   workload would otherwise default. A DNS record's `comment` is the usual
   one: the workload default, `workloads/<w>`, differs from the old comment,
   so leaving it out plans an update. Then generate the stubs and check them:

   ```bash
   .lib-src/.github/scripts/resolve-workloads.sh
   .lib-src/.github/scripts/resolve-workloads.sh --check
   ```

3. **For each resource**, in this order:

   1. **Read its IDs from the old leaf.**

      ```bash
      cd <old spoke>/terraform/<provider>/<...leaf>
      mise exec -- terragrunt state list
      mise exec -- terragrunt state show '<old address>'
      ```

   2. **Import it into the new leaf.**

      ```bash
      cd <new spoke>/workloads/<w>/<provider>/<module>/<key>
      mise exec -- terragrunt import '<new address>' '<import ID>'
      ```

   3. **Plan the new leaf.** It must show `No changes.`

      ```bash
      mise exec -- terragrunt plan
      ```

      If it shows a change, the entry differs from the resource. Fix the
      entry, regenerate the stubs and plan again. Never apply to make it
      match. To give up on this resource instead, run `terragrunt state rm
      '<new address>'` in the new leaf: the old state still holds it.

   4. **Remove it from the old leaf.**

      ```bash
      cd <old spoke>/terraform/<provider>/<...leaf>
      mise exec -- terragrunt state rm '<old address>'
      ```

4. **Open the PR that commits the entries.** Its plan must show
   `No changes.` for every imported leaf, and for every other leaf in the
   spoke. Merge it. That ends the freeze.

5. **Compare against step 1's snapshot.** Nothing may differ.

6. **Delete the old leaf's code** in its own spoke's PR. Its state is empty,
   so its plan shows nothing to destroy.

## Import IDs and addresses

| Resource | New address | Import ID |
| --- | --- | --- |
| `cloudflare/dns-record` | `module.this.cloudflare_dns_record.this` | `<zone_id>/<record_id>` |
| `cloudflare/apex-redirect`, apex | `module.this.cloudflare_dns_record.apex` | `<zone_id>/<record_id>` |
| `cloudflare/apex-redirect`, www | `module.this.cloudflare_dns_record.www[0]` | `<zone_id>/<record_id>` |
| `cloudflare/apex-redirect`, ruleset | `module.this.cloudflare_ruleset.this` | `zones/<zone_id>/<ruleset_id>` |
| `cloudflare/ruleset` | `module.this.cloudflare_ruleset.this` | `zones/<zone_id>/<ruleset_id>` |

`zone_id` and `id` are both in `terragrunt state show`'s output for the old
resource. Another module's address and ID are in its own source and its
provider's import documentation.
