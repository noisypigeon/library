# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-10-07

### Add self-deletion to compute-instance and new pigeon-cluster module

Adds the compute-instance and module pieces from ADR-0138 (`docs/adr/0138-autoscale-compute-instances-per-job.md`, `Status: Exploration`): scaling the number of `pigeon-cli` job instances to the number of pending jobs, with each instance tearing itself down the moment its job finishes, success or failure.

**`compute-instance`** gains an optional `self_delete_on_exit` boolean (default `false`). When `true`, the instance deletes itself -- server, IP(s), block volume -- once `post_provision_commands` finishes, using its own internally-composed IAM API key. Requires `iam_config` to be set; the module automatically folds `InstancesFullAccess` into the composed policy so callers don't need to request that permission themselves. Implemented as a `trap ... EXIT` prepended to the generated post-provision script (ahead of any caller-supplied commands), so it fires regardless of the script's own `set -e` exit path -- the same ordering gotcha ADR-0125 already documented for this module's cloud-init rendering. Purely additive; unchanged behavior for every existing caller.

**New module `pigeon-cluster`** composes one self-deleting `compute-instance` plus one dedicated `iam-application` per entry in a `jobs` map, replacing the one-hand-wired-leaf-per-job pattern with a fleet that scales to however many jobs are pending. Each job gets its own IAM scope and its own keyring, isolated from every other job in the same cluster -- a compromised or misbehaving job instance's blast radius never extends to a sibling job's credentials. This is a broader use of the "modules don't compose modules, except..." exception ADR-0122 already carved out narrowly for `compute-instance`'s own internal composition.

One piece is explicitly left unverified, consistent with the ADR's `Exploration` status: the exact Scaleway instance-metadata-service JSON field path for an instance's own zone (`instance.tf`'s `self_delete_script` local guesses `.location.zone_id`, flagged inline) -- a wrong guess means an instance never actually self-deletes. First real validation step before relying on this: boot one throwaway instance with `self_delete_on_exit = true`, curl `http://169.254.42.42/conf?format=json` by hand, and correct the filter if needed.

`terraform fmt`/`terraform validate` pass on both modules (pigeon-cluster validated structurally against a local copy of compute-instance, since v5.4.0 doesn't exist as a real tag until this merges).


[#237](https://github.com/noisypigeon/noisypigeon/pull/237)
