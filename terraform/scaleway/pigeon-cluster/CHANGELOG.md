# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.2] - 2026-10-08

### Wire pigeon-cluster to compute-instance's new enable_private_network flag

\`compute-instance\` v5.6.0 (#246) fixed the \`Invalid count argument\` error that broke \`pigeon-cluster\`'s private-network wiring on every real first apply, by replacing the implicit \`private_network_id != null\` gate with an explicit \`enable_private_network\` boolean.

This updates \`pigeon-cluster\`'s internal \`module "job"\` call to set \`enable_private_network = true\` (unconditionally — every job always attaches to the cluster's one shared Private Network) and bumps its pinned \`compute-instance\` source from \`v5.4.0\`/\`v5.5.0\` to the now-real \`v5.6.0\`. Confirmed via \`tofu validate\` against the real, published \`v5.6.0\` tag.

No public interface change to \`pigeon-cluster\` itself — purely an internal composition fix.

[#247](https://github.com/noisypigeon/noisypigeon/pull/247)

## [0.3.1] - 2026-10-08

### Fix pigeon-cluster's stale internal compute-instance pin

`pigeon-cluster` v0.3.0 (#244) added Private Network support by composing \`compute-instance\`'s new \`private_network_id\` input, but its internal \`module "job"\` block was left pinned to \`compute-instance/v5.4.0\` — the version that existed at the time #244 was written, before \`v5.5.0\` (the release that actually adds \`private_network_id\`) had been tagged.

As released, this meant \`pigeon-cluster\` v0.3.0's private-network wiring didn't actually work: it composed a version of \`compute-instance\` that has no \`private_network_id\` input at all, so the argument would be rejected by any real consumer.

This bumps that internal pin to \`compute-instance/v5.5.0\`, the version that was actually released alongside it. No other change — confirmed via \`tofu validate\` against the real, already-published \`v5.5.0\` tag.

[#245](https://github.com/noisypigeon/noisypigeon/pull/245)

## [0.3.0] - 2026-10-08

### Add Private Network support to compute-instance and pigeon-cluster

Adds Scaleway Private Network support so `pigeon-cli` job instances can reach Object Storage buckets over Scaleway's internal network instead of the public internet, avoiding egress billing on same-datacenter bucket traffic (ADR-0145, `docs/adr/0145-private-network-access-to-pigeon-cli-job-buckets.md`).

**`compute-instance`** gains an optional `private_network_id` input (default `null`). When set, the instance attaches to that Private Network via a dedicated `scaleway_instance_private_nic`, alongside its normal public IP(s) if any. This is a bring-your-own-ID input, matching the module's existing `additional_volume_ids` pattern — the module does not create the Private Network itself. Purely additive; no change for any existing caller.

**`pigeon-cluster`** now provisions one shared Private Network, Public Gateway, and gateway-network attachment per cluster (not per job), and wires every job's `compute-instance` call to that shared Private Network. Job instances no longer attach a public IP by default — the cluster's Public Gateway NATs outbound internet access for cloud-init's provisioning steps instead — but a new per-job `enable_ipv4` field (default `false`) lets you re-attach a public IP to any individual job, e.g. for debugging a stuck or failed instance.

Also in this change: `jobs` moves from a map keyed by job name to a list of objects, each naming its own `job_name` (e.g. `jobs = [{ job_name = "my-job", ... }]` instead of `jobs = { "my-job" = { ... } }`). `job_name` values must be unique within a cluster; per-job resource addressing is unaffected since the module converts the list to a job-name-keyed map internally. This is a breaking change to an existing input.

See ADR-0145 for the full research and design rationale, including why job buckets still need their `endpoint` manually switched to `https://<bucket>.s3-vpc.<region>.scw.eu` per keyring entry, and the one-time manual Scaleway VPC API step required before that endpoint is actually reachable.

[#244](https://github.com/noisypigeon/noisypigeon/pull/244)

## [0.2.1] - 2026-10-07

### Fix pigeon-cluster job_policy name colliding with compute-instance's internal policy

`v0.2.0` (ADR-0144) gave each `pigeon-cluster` job its own \`job_policy\`, named \`"\${name_prefix}-\${job}-iam-policy"\`. That's the exact same formula `compute-instance`'s own internal self-delete \`iam_policy\` composition already uses for the same job -- both resolve to the identical final Scaleway policy name once `iam-policy`'s own \`-policy\` suffix is applied. Scaleway rejects the second create with a 409 (\`resource policy: resource already exists\`), confirmed live against a real \`terragrunt apply\` of \`v0.2.0\`.

\`job_policy\`'s name now gets a distinct \`-work-\` segment so the two policies -- one scoped to the job's actual work permissions (object storage, etc.), one scoped to just self-delete -- coexist without colliding.

No interface change, no consumer update needed beyond bumping the version pin.

[#242](https://github.com/noisypigeon/noisypigeon/pull/242)

## [0.2.0] - 2026-10-07

### Give pigeon-cluster jobs their own IAM policy/key and a dictionary keyring

Each job in a `pigeon-cluster` fleet already got its own `iam-application`, but the policy and API key it actually ran with were composed two layers down inside `compute-instance`, purely to power that instance's self-delete call -- invisible to `pigeon-cluster` itself. In practice, that meant every keyring entry's `access_key_id`/`secret_key` had to be hand-supplied by the caller, usually by wiring in one shared key from outside the module.

`pigeon-cluster` now composes its own `iam-policy`/`iam-api-key` directly, one pair per job, scoped to that job's `extra_permission_sets` plus a new cluster-wide `shared_permission_sets`. That key becomes the default credential for any `kind = "bucket"` keyring entry that doesn't specify its own -- an entry can still override it explicitly to reach a bucket under a different, pre-existing auth stack.

`keyring` itself changes from a list to a map keyed by alias (the `alias` field is gone -- the map key is the alias now), which lets `job_commands` reference an entry by name instead of a hand-typed, unchecked literal: `"--source '${keyring.fastmail.alias}:'"` instead of `"--source 'fastmail:'"`. If the alias doesn't exist in that job's merged keyring, `terraform plan` fails outright instead of silently drifting. `cluster_config` also gains a `shared_keyring`, so a bucket every job needs (a shared `reports` destination, say) only needs declaring once.

One side effect worth calling out: `compute-instance`'s own internally-composed key (used solely for `self_delete_on_exit`) now carries only the instance-management permission it needs for that, instead of also carrying the job's full work permissions -- a smaller blast radius per key, split across two keys instead of one doing both jobs.

No changes to `compute-instance` or any `iam-*` module -- this is entirely a composition change inside `pigeon-cluster`. See ADR-0144 for the full design, including the circular-reference constraint that requires the new key to be minted inside `pigeon-cluster` rather than inside `compute-instance` (a module can't default its own input from its own output).

This PR intentionally does not migrate any real job leaf onto the new interface -- that's a separate, not-yet-opened change.

[#241](https://github.com/noisypigeon/noisypigeon/pull/241)

## [0.1.0] - 2026-10-07

### Add self-deletion to compute-instance and new pigeon-cluster module

Adds the compute-instance and module pieces from ADR-0138 (`docs/adr/0138-autoscale-compute-instances-per-job.md`, `Status: Exploration`): scaling the number of `pigeon-cli` job instances to the number of pending jobs, with each instance tearing itself down the moment its job finishes, success or failure.

**`compute-instance`** gains an optional `self_delete_on_exit` boolean (default `false`). When `true`, the instance deletes itself -- server, IP(s), block volume -- once `post_provision_commands` finishes, using its own internally-composed IAM API key. Requires `iam_config` to be set; the module automatically folds `InstancesFullAccess` into the composed policy so callers don't need to request that permission themselves. Implemented as a `trap ... EXIT` prepended to the generated post-provision script (ahead of any caller-supplied commands), so it fires regardless of the script's own `set -e` exit path -- the same ordering gotcha ADR-0125 already documented for this module's cloud-init rendering. Purely additive; unchanged behavior for every existing caller.

**New module `pigeon-cluster`** composes one self-deleting `compute-instance` plus one dedicated `iam-application` per entry in a `jobs` map, replacing the one-hand-wired-leaf-per-job pattern with a fleet that scales to however many jobs are pending. Each job gets its own IAM scope and its own keyring, isolated from every other job in the same cluster -- a compromised or misbehaving job instance's blast radius never extends to a sibling job's credentials. This is a broader use of the "modules don't compose modules, except..." exception ADR-0122 already carved out narrowly for `compute-instance`'s own internal composition.

One piece is explicitly left unverified, consistent with the ADR's `Exploration` status: the exact Scaleway instance-metadata-service JSON field path for an instance's own zone (`instance.tf`'s `self_delete_script` local guesses `.location.zone_id`, flagged inline) -- a wrong guess means an instance never actually self-deletes. First real validation step before relying on this: boot one throwaway instance with `self_delete_on_exit = true`, curl `http://169.254.42.42/conf?format=json` by hand, and correct the filter if needed.

`terraform fmt`/`terraform validate` pass on both modules (pigeon-cluster validated structurally against a local copy of compute-instance, since v5.4.0 doesn't exist as a real tag until this merges).


[#237](https://github.com/noisypigeon/noisypigeon/pull/237)
