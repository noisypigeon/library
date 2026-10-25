# Import a leaf into a workload or zone

Moves the resources of one leaf into the leaves of a unit, without recreating
them ([LIB-0032](../adr/LIB-0032-move-the-blog-into-runway.md) §3). The old
leaf is hand-written, `terraform/<provider>/...` in some spoke, or another
unit's. The unit is a workload, `workloads/<w>/<provider>/<module>/<key>/`, or
a zone, `zones/<zone>/cloudflare/<module>/<key>/`
([LIB-0036](../adr/LIB-0036-zones-are-units-of-their-own.md) §7). The old leaf
and the unit may be in different spokes.

Below, `<unit>` is `workloads/<w>` or `zones/<zone>`, and the unit's file is
its `values.yaml` or its `zone.yaml`.

A plain state copy doesn't work, because the leaves change shape:

- a hand-written leaf often calls a module with `for_each`, so a resource's
  address is `module.dns_record["mx_primary"].cloudflare_dns_record.this`;
- a unit leaf calls one module instance, so the same resource is
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
- Their sops age keys, so `root.hcl` can decrypt each spoke's secrets. This
  checks it in each, without writing anything. The `.enc` files are dotenv,
  which sops doesn't infer from the extension:

  ```bash
  sops --decrypt --input-type dotenv --output-type dotenv terraform/secrets/terraform.enc >/dev/null
  ```
- The unit's bootstrap applied: its project, deployer and state bucket
  (LIB-0028 §6), and for Cloudflare its token. A workload's zones name it in
  their `zone.yaml` (LIB-0036 §3). A zone's token always covers its own zone,
  redirects included (LIB-0036's 2026-10-25 amendment, item 2), so it can
  import them.

## Steps

1. **Snapshot what the outside world sees.** For DNS, `dig +short <name>
   <type>` for every record, and `curl -sI` for every redirect, into a file
   outside both checkouts. You'll compare against it at the end.

2. **Write the entries, locally.** Add one entry per resource group to the
   unit's file, copying every input the old leaf sets, including the ones a
   unit would otherwise default. A DNS record's `comment` is the usual one:
   the unit default, `<unit>` (`workloads/<w>` or `zones/<zone>`), differs
   from the old comment, so leaving it out plans an update. A record moving
   between units keeps its old comment the same way, or plans that update.
   Then generate the stubs and check them:

   ```bash
   .lib-src/.github/scripts/resolve-workloads.sh
   .lib-src/.github/scripts/resolve-workloads.sh --check
   ```

3. **For each resource**, in this order:

   1. **Read its IDs from the old leaf.**

      ```bash
      cd <old spoke>/<old leaf>
      mise exec -- terragrunt state list
      mise exec -- terragrunt state show '<old address>'
      ```

      `state list` also lists the module's data sources, such as
      `module.this.data.cloudflare_zone.this`. Skip them: a data source
      can't be imported, the new leaf reads its own on every plan, and the
      old one goes with the old leaf. In the new leaf, before its first
      import, `state list` fails with `No state file was found!`. That means
      it holds nothing yet, not that something is wrong.

   2. **Import it into the new leaf.**

      ```bash
      cd <new spoke>/<unit>/<provider>/<module>/<key>
      mise exec -- terragrunt import '<new address>' '<import ID>'
      ```

      Quote every address. `www[0]` unquoted is a shell glob.

      A leaf whose module holds several resources, such as an apex redirect's
      ruleset, apex record and `www` record, moves as one: import all of
      them, then plan once, then remove them all from the old leaf in one
      `state rm`. Planning after only some are imported shows the rest as
      creates.

   3. **Plan the new leaf.** It must show `No changes.`

      ```bash
      mise exec -- terragrunt plan -detailed-exitcode
      ```

      Exit 0 is no changes, 2 is changes and 1 is an error. A script that
      checks the plan's text instead must allow for Terragrunt's prefix:
      each line reads `<time> STDOUT terraform: No changes. ...`, so a
      pattern anchored at `^No changes` never matches.

      If it shows a change, the entry differs from the resource. Fix the
      entry, regenerate the stubs and plan again. Never apply to make it
      match. To give up on this resource instead, run `terragrunt state rm
      '<new address>'` in the new leaf: the old state still holds it.

   4. **Remove it from the old leaf.**

      ```bash
      cd <old spoke>/<old leaf>
      mise exec -- terragrunt state rm '<old address>'
      ```

4. **Open the PR that commits the entries.** Its plan must show
   `No changes.` for every imported leaf, and for every other leaf in the
   spoke. Merge it. That ends the freeze.

5. **Compare against step 1's snapshot.** Nothing may differ.

6. **Delete the old leaf's code** in its own spoke's PR. Its state is empty,
   so its plan shows nothing to destroy. When the old leaf is another unit's
   entry, step 4's PR already removes it from that unit's file, and its
   generated stub's empty state plans the same empty destroy. The plan comment
   still marks it `destroy (removed from values.yaml) +0 ~1 -0`: the one
   change is its module output going to null, and its detail says it changes
   no real infrastructure. Check that each one's detail says so.

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
