# Release a stuck state lock

From `terragrunt/root-hcl` v4.2.0 a leaf's state is locked while Terraform
writes it. The lock is `<state key>.tflock`, stored next to the state in
either backend
([LIB-0022](../adr/LIB-0022-replan-on-comment-and-locked-saved-plan-applies.md)
§4). A run that dies mid-apply, or a local run that gets interrupted, can
leave that object behind. Every plan and apply of the leaf then fails with
`Error acquiring the state lock` until someone removes it.

## When to use it

Use this runbook only when the run named in the lock is no longer running.
Releasing a lock that a live apply holds lets a second apply write the same
state, and preventing that is the whole point of the lock.

## Steps

1. **Read the lock.** The error prints the lock's `ID`, `Who`, `Operation` and
   `Created`. `Who` is `runner@<host>` for a CI run, and your own user for a
   local run.

2. **Make sure nothing holds it.**
   - **For CI**, check the spoke's Actions tab for a `Terragrunt apply` or
     `Terragrunt plan` run that is still in progress. Wait for it, or cancel
     it, before going on. A cancelled run can leave the lock behind as well.
   - **For a local run**, check that the terminal or process that took the
     lock has exited.

3. **Release it from the leaf.**

   ```bash
   cd <spoke checkout>/terraform/<provider>/<module>/<instance>
   mise exec -- terragrunt force-unlock <ID>
   ```

   Answer `yes` when asked. This deletes the `.tflock` object and nothing
   else, so the state itself is untouched.

4. **Re-plan.** The run that died may have written part of its changes. On
   the PR, comment `terragrunt plan` and read the new plan before applying
   it. A saved plan from before the crash is stale, and apply refuses it
   anyway.

## Why there is no automatic release

A lock is never taken over automatically, because a lock that looks
abandoned may still belong to a slow apply. LIB-0022 accepts doing this
by hand as the cost of that guarantee.
