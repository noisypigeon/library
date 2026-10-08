# Changelog

All notable changes to this module are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [5.6.1] - 2026-10-08

### Fix compute-instance's private_ips output to read from the private NIC

Confirmed by a real apply failure (wiring a bastion's private IP into a \`scaleway_vpc_public_gateway_pat_rule\`): \`compute-instance\`'s \`private_ips\` output returns an empty list even after \`scaleway_instance_private_nic\` successfully attaches a Private Network.

ADR-0145's original text assumed \`scaleway_instance_server\`'s own \`private_ips\` attribute would reflect a NIC attached via the separate \`scaleway_instance_private_nic\` resource, based on reading the provider's schema rather than a live test. It doesn't — that attribute only ever reflected the deprecated inline \`private_network\` block, which this module has never used. The private NIC resource has its own, separate \`private_ips\` computed block that was never read.

This fixes the output to read from \`scaleway_instance_private_nic.private_nic[0].private_ips\` first, falling back to the server's own attribute and then \`null\` — same \`try()\`-chain convention already used by every other conditional-resource output in this module. No shape/interface change, bug fix only.

[#249](https://github.com/noisypigeon/noisypigeon/pull/249)

## [5.6.0] - 2026-10-08

### Fix compute-instance: private NIC count must not depend on private_network_id's nullness

Attaching an instance to a Private Network that's created in the *same* apply (exactly what \`pigeon-cluster\` does — it provisions one shared Private Network per cluster and attaches every job instance to it) fails to plan at all:

\`\`\`
Error: Invalid count argument
  on instance.tf line 23, in resource "scaleway_instance_private_nic" "private_nic":
  23:   count = var.enabled && var.private_network_id != null ? 1 : 0
The "count" value depends on resource attributes that cannot be determined until apply...
\`\`\`

This is a real-world failure hit on the first live apply of a \`pigeon-cluster\` job. The root cause: \`count\`/\`for_each\` must be fully determinable at plan time, but a newly-created resource's \`.id\` (like the Private Network's) is unknown until apply — and because \`private_network_id\`'s nullable \`string\` type can't be statically proven non-null from an unknown value, gating \`count\` on \`private_network_id != null\` can never resolve for a same-apply Private Network.

This adds a new \`enable_private_network\` boolean (default \`false\`) that decouples "should this instance attach to a Private Network" from "what ID should it use" — the former is always statically known by the caller, the latter is allowed to stay apply-time-unknown since it's now just an ordinary resource argument, not part of a \`count\` expression. A validation block ensures \`private_network_id\` is set whenever \`enable_private_network\` is true.

Any existing caller using \`private_network_id\` must now also set \`enable_private_network = true\` to get the same behavior as before. Verified by reproducing the exact error in a scratch config (a real, not-yet-applied \`scaleway_vpc_private_network\` composed with this module) and confirming the fix produces a clean plan instead.

See \`docs/adr/0145-private-network-access-to-pigeon-cli-job-buckets.md\` (amended in a follow-up PR) for the full incident writeup.

[#246](https://github.com/noisypigeon/noisypigeon/pull/246)

## [5.5.0] - 2026-10-08

### Add Private Network support to compute-instance and pigeon-cluster

Adds Scaleway Private Network support so `pigeon-cli` job instances can reach Object Storage buckets over Scaleway's internal network instead of the public internet, avoiding egress billing on same-datacenter bucket traffic (ADR-0145, `docs/adr/0145-private-network-access-to-pigeon-cli-job-buckets.md`).

**`compute-instance`** gains an optional `private_network_id` input (default `null`). When set, the instance attaches to that Private Network via a dedicated `scaleway_instance_private_nic`, alongside its normal public IP(s) if any. This is a bring-your-own-ID input, matching the module's existing `additional_volume_ids` pattern — the module does not create the Private Network itself. Purely additive; no change for any existing caller.

**`pigeon-cluster`** now provisions one shared Private Network, Public Gateway, and gateway-network attachment per cluster (not per job), and wires every job's `compute-instance` call to that shared Private Network. Job instances no longer attach a public IP by default — the cluster's Public Gateway NATs outbound internet access for cloud-init's provisioning steps instead — but a new per-job `enable_ipv4` field (default `false`) lets you re-attach a public IP to any individual job, e.g. for debugging a stuck or failed instance.

Also in this change: `jobs` moves from a map keyed by job name to a list of objects, each naming its own `job_name` (e.g. `jobs = [{ job_name = "my-job", ... }]` instead of `jobs = { "my-job" = { ... } }`). `job_name` values must be unique within a cluster; per-job resource addressing is unaffected since the module converts the list to a job-name-keyed map internally. This is a breaking change to an existing input.

See ADR-0145 for the full research and design rationale, including why job buckets still need their `endpoint` manually switched to `https://<bucket>.s3-vpc.<region>.scw.eu` per keyring entry, and the one-time manual Scaleway VPC API step required before that endpoint is actually reachable.

[#244](https://github.com/noisypigeon/noisypigeon/pull/244)

## [5.4.0] - 2026-10-07

### Add self-deletion to compute-instance and new pigeon-cluster module

Adds the compute-instance and module pieces from ADR-0138 (`docs/adr/0138-autoscale-compute-instances-per-job.md`, `Status: Exploration`): scaling the number of `pigeon-cli` job instances to the number of pending jobs, with each instance tearing itself down the moment its job finishes, success or failure.

**`compute-instance`** gains an optional `self_delete_on_exit` boolean (default `false`). When `true`, the instance deletes itself -- server, IP(s), block volume -- once `post_provision_commands` finishes, using its own internally-composed IAM API key. Requires `iam_config` to be set; the module automatically folds `InstancesFullAccess` into the composed policy so callers don't need to request that permission themselves. Implemented as a `trap ... EXIT` prepended to the generated post-provision script (ahead of any caller-supplied commands), so it fires regardless of the script's own `set -e` exit path -- the same ordering gotcha ADR-0125 already documented for this module's cloud-init rendering. Purely additive; unchanged behavior for every existing caller.

**New module `pigeon-cluster`** composes one self-deleting `compute-instance` plus one dedicated `iam-application` per entry in a `jobs` map, replacing the one-hand-wired-leaf-per-job pattern with a fleet that scales to however many jobs are pending. Each job gets its own IAM scope and its own keyring, isolated from every other job in the same cluster -- a compromised or misbehaving job instance's blast radius never extends to a sibling job's credentials. This is a broader use of the "modules don't compose modules, except..." exception ADR-0122 already carved out narrowly for `compute-instance`'s own internal composition.

One piece is explicitly left unverified, consistent with the ADR's `Exploration` status: the exact Scaleway instance-metadata-service JSON field path for an instance's own zone (`instance.tf`'s `self_delete_script` local guesses `.location.zone_id`, flagged inline) -- a wrong guess means an instance never actually self-deletes. First real validation step before relying on this: boot one throwaway instance with `self_delete_on_exit = true`, curl `http://169.254.42.42/conf?format=json` by hand, and correct the filter if needed.

`terraform fmt`/`terraform validate` pass on both modules (pigeon-cluster validated structurally against a local copy of compute-instance, since v5.4.0 doesn't exist as a real tag until this merges).


[#237](https://github.com/noisypigeon/noisypigeon/pull/237)

## [5.3.1] - 2026-10-06

### Move module-redirect short URLs from noisypigeon.com to pigeon.dev

This moves the ADR-0109/0110/0114 short module-source redirect mechanism
(`noisypigeon.com/modules/<provider>/<module>/vX.Y.Z` and
`noisypigeon.com/templates/zola-site/vX.Y.Z`) off the personal-blog domain
and onto `pigeon.dev`, which already runs the identical Zola/zola-site
hosting pipeline (ADR-0130) with zero new Terraform resources needed.

`generate-module-redirects.sh`, its two templates (`module-redirect.html`,
`theme-redirect.html`), and its two generated-content directories
(`content/modules/`, `content/theme-versions/`) move from
`workloads/noisypigeon.com/src/` to `workloads/pigeon.dev/src/`.
`.mise.toml`'s `pigeon-dev-build`/`pigeon-dev-serve` tasks,
`pigeon-dev-pages.yml`, `noisypigeon-com-deploy.yml`, and
`template-release.yml`'s post-tag deploy dispatch are rewired accordingly.
The public URL path convention (`modules/<provider>/<module>/vX.Y.Z`) stays
exactly as ADR-0110 fixed it — only the hostname changes, and every short
URL still resolves to the identical `git::...?ref=...` target it did before.

This PR also updates `compute-instance`'s own internal composition
(`iam.tf`, `instance.tf`, which source `iam-policy`/`iam-api-key`/
`block-volume` via the short URL) and every `templates/terraform/` module
README's usage example from `noisypigeon.com` to `pigeon.dev`. Because
`compute-instance` already has prior tags, this PR's edit to its tracked
`.tf` content will trigger a real (if purely cosmetic) `v5.3.1` patch
release via the existing changed-module release automation — see
ADR-0136 for why that's accepted rather than avoided.

This is PR A of a two-PR cutover (see ADR-0136's "Decision" section). A
second PR will sweep every `workloads/*/terraform/**` consumer leaf's
`source =` line from `noisypigeon.com` to `pigeon.dev`, opened only once
this PR has merged and `pigeon-dev-pages.yml` has deployed the new
redirect pages live.

New ADR: `docs/adr/0136-move-module-redirect-urls-to-pigeon-dev.md`.

[#223](https://github.com/noisypigeon/noisypigeon/pull/223)

## [5.3.0] - 2026-10-04

### Add enabled kill switch to compute-instance

`compute-instance` gains an optional top-level `enabled` boolean (default `true`). Setting it to `false` destroys every resource this module instance manages — the server, its IP address(es), its block volume (and the volume's data), and its IAM policy/API key — while the module block itself stays in the caller's configuration; flipping it back to `true` recreates everything from the same config, with the instance's name (random suffix) staying stable across the cycle.

`scaleway_instance_server.server` moves from a singleton resource to `count = var.enabled ? 1 : 0` internally, with a `moved` block protecting any existing state through the addressing change.

Purely additive — defaults to `true`, unchanged behavior for every existing caller. See ADR-0126.

[#173](https://github.com/noisypigeon/noisypigeon/pull/173)

## [5.2.0] - 2026-10-04

### Add post_provision_commands to compute-instance

`compute-instance` gains an optional `instance_config.post_provision_commands` list of shell command strings, run in order. When set, they're wired up as a systemd oneshot unit (`pigeon-post-provision.service`, `RemainAfterExit=yes`, self-disabling after a successful run) ordered `After=cloud-final.service`/`Wants=cloud-final.service` and enabled via `runcmd --no-block`, so a long-running command (e.g. a `pigeon-cli` job) doesn't block cloud-init's own completion status and doesn't re-run on later reboots.

The commands are base64-encoded into their own `write_files` entry (`encoding: b64`) rather than embedded in YAML or in the unit's `ExecStart=` line, avoiding quoting/indentation pitfalls for arbitrary shell content. Secrets already written to `/etc/environment` (ADR-0104) reach the unit via `EnvironmentFile=-/etc/environment`. Output is inspected with `journalctl -u pigeon-post-provision.service`.

Purely additive — defaults to `[]`, unchanged behavior for every existing caller. See ADR-0125.

[#172](https://github.com/noisypigeon/noisypigeon/pull/172)

## [5.1.0] - 2026-10-04

### Compose iam-policy and iam-api-key inside compute-instance

\`compute-instance\` gains an optional \`iam_config\` input that composes \`scaleway/iam-policy\` and \`scaleway/iam-api-key\` internally, exposing the resulting API key as new \`access_key_id\`/\`secret_key\` outputs.

A census of every real \`compute-instance\` consumer finds exactly one pairing with IAM, ever — \`pigeon-cli/job\` — and it always wires the same project-scoped policy + API key 1:1 with the same instance, composing them externally and passing the outputs through by hand. This is the same shape ADR-0120 found for \`block-volume\`, so this extends that same narrow exception to the "no internal composition" principle (ADR-0081/ADR-0085) to this pairing too.

\`iam_config\` is deliberately scoped to project-level grants only (\`project_ids\`/\`project_permission_sets\`), matching what the one real consumer actually uses — organization-scoped grants stay available only via external composition, same as \`block-volume\` remains independently callable for any caller not wanting it folded into \`compute-instance\`.

Unlike \`block-volume\`'s first landing, this composition pins released tags (\`iam-policy/v4.0.0\`, \`iam-api-key/v0.1.0\`) from the start rather than a relative path — ADR-0121 already root-caused why a relative \`source\` breaks once \`compute-instance\` itself is fetched over HTTP via its short URL.

This is purely additive: a new optional input defaulting to \`null\`, two new outputs. No existing consumer's behavior changes.

See ADR-0122 for the full decision record.

[#167](https://github.com/noisypigeon/noisypigeon/pull/167)

## [5.0.1] - 2026-10-04

### Pin block-volume source in compute-instance

`compute-instance`'s internal `block_volume` composition (ADR-0120) used a relative source, `source = "../block-volume"`. That only resolves within whatever package `compute-instance` itself was fetched as — a local clone or `git::...` source happens to include the whole repo tree, but go-getter's HTTP installer (what the `noisypigeon.com` short-URL redirects resolve to) fetches only `compute-instance`'s own module directory. The first real consumer to fetch `compute-instance` that way (`workloads/pigeon-cli/terraform/job`, sourcing `compute-instance/v5.0.0`) hit `tofu init` failing outright with "Local module path escapes module package".

This pins the internal `block_volume` module to the released `block-volume` v4.0.0 tag (`https://noisypigeon.com/modules/scaleway/block-volume/v4.0.0`) instead, matching the short-URL pin convention every other cross-module reference in this repo already uses. No input/output change to `compute-instance` itself — any consumer already on `v5.0.0` can bump straight to the patch release this produces with no other changes needed.

See ADR-0121 for the full root cause and decision record; ADR-0120 is amended in place to strike through its now-superseded relative-path description.

[#165](https://github.com/noisypigeon/noisypigeon/pull/165)

## [5.0.0] - 2026-10-04

### Rename block-volume's naming inputs and compose it inside compute-instance

`block-volume` still took `namespace`/`name`, the naming convention every sibling module in this provider root (`compute-instance`, `object-bucket`, `iam-application`) has already moved to `name_prefix`/`name_suffix`. This PR renames them to match.

It also folds volume creation into `compute-instance` itself. A repo-wide census found `block-volume` has had exactly one consumer, ever, and that consumer always paired it 1:1 with the same `compute-instance` call -- composing the two separately bought no real flexibility, just a second module block and manual `additional_volume_ids = [module.volume.id]` plumbing every caller had to repeat. `compute-instance`'s top-level `additional_volume_ids` input is replaced by a new `instance_config.block_volume` object:

- `block_volume` left unset: no managed volume, nothing extra attached.
- `block_volume.size` unset: no managed volume is created, but `block_volume.additional_volume_ids` (pre-created IDs from elsewhere) still attach.
- `block_volume.size` set: `compute-instance` creates the volume itself by composing `scaleway/block-volume` internally, passing through the instance's own `name_prefix`/`name_suffix` so the volume's name matches the instance's -- exactly what the one real past consumer always did by hand. `block_volume.project_id` becomes required in this case, enforced via a `validation` block.

This is a narrow, named exception to ADR-0081/ADR-0085's "no local module composes another internally" principle, which otherwise still holds for every other module pairing in this provider root (`object-bucket`/`iam-policy` keep composing externally -- they're genuinely reused across many leaves, unlike `block-volume`). `block-volume` itself isn't removed; it stays independently callable.

Breaking for both modules:
- `block-volume`: `namespace`/`name` renamed to `name_prefix`/`name_suffix`.
- `compute-instance`: `additional_volume_ids` removed; use `instance_config.block_volume.{size,iops,project_id,additional_volume_ids}` instead.

The one live consumer (`workloads/bucket/terraform/noisypigeon/poisoned/mega-storage-consolidation/deduplication`) stays pinned to its old `compute-instance/v4.0.0`/`block-volume/v2.0.0` tags rather than being migrated here -- its compute/volume/IAM are already being removed entirely on a separate, not-yet-merged branch, so migrating it now would be wasted effort.

See docs/adr/0120-compose-scaleway-block-volume-inside-compute-instance.md for the full decision record, including strikethrough amendments to ADR-0081 and ADR-0085 marking the principle exception.

[#163](https://github.com/noisypigeon/noisypigeon/pull/163)

## [4.0.0] - 2026-10-04

### Simplify scaleway/compute-instance's interface (ADR-0118)

A census of every `scaleway/compute-instance` consumer (live and historical, via `git log -S`) found exactly one real caller, and it was already working around the module's own redundancy: it hardcoded `profile = "pigeon-cli"` (`profile = "docker"` has never been instantiated anywhere), and re-declared the same bucket secret three separate times across `buckets`, `keyring_entries`, and `environment_variables` just to keep their aliases in sync by hand.

This PR:
- Drops the `docker` profile and the `profile` variable entirely — `pigeon-cli` provisioning (rclone/neovim, the bootstrap script, keyring/rclone config, Cockpit/Alloy) is now the module's only, unconditional behavior.
- Renames `namespace`/`name` to `name_prefix`/`name_suffix`.
- Groups SSH access under a new `user_config` object; `ssh_keys` (a list) becomes `user_config.ssh_key` (a single string) — the only real caller ever passed one key.
- Groups `image` (now optional, defaulting to `"ubuntu_jammy"`), `type`, and `cockpit` under a new `instance_config` object.
- Collapses `buckets` + `keyring_entries` + `environment_variables` into one `keyring` list. A `kind = "bucket"` entry now also renders an rclone.conf remote; any entry's `secret_key` (never written into `keyring.toml` itself) now auto-exports `PIGEON_SECRET_<ALIAS>` on the instance, replacing the free-form `environment_variables` map.

Full rationale and the exact rendering changes: [docs/adr/0118-simplify-scaleway-compute-instance-interface.md](docs/adr/0118-simplify-scaleway-compute-instance-interface.md).

Breaking change — every top-level input except `enable_ipv4`/`enable_ipv6`/`additional_volume_ids` is renamed, regrouped, or removed. A follow-up PR migrates the one real consumer to the new interface and the new tag.

## Test plan

- [x] `mise run fmt-check-terraform` passes.
- [x] `tofu validate` passes against the rewritten module in isolation.
- [ ] After merge: confirm the `v4.0.0` tag/GitHub Release and regenerated README Inputs/Outputs tables.

[#157](https://github.com/noisypigeon/noisypigeon/pull/157)

## [2.3.4] - 2026-10-03

### Fix environment_variables/PIGEON_LOG_DIR not reaching non-login SSH invocations

`scaleway/compute-instance` has only ever delivered `environment_variables` (and the cockpit-gated `PIGEON_LOG_DIR`, ADR-0102) via `/etc/profile.d/pigeon-env.sh` (ADR-0101). That file is auto-sourced only by an interactive **login** shell. A one-off `ssh host 'pigeon job run dedupe ...'` — an ordinary way to kick off a job and disconnect — opens a non-login shell and never sources it, so the process falls through to `pigeon-cli`'s own XDG-based default log directory instead of the pinned `/var/log/pigeon` path Alloy's Loki config expects. This was caught live on a real `pigeon-cli` instance: its JSONL log landed under `~/.local/share/pigeon/logs/` instead of `/var/log/pigeon/pigeon.jsonl`, even though a separate, later interactive SSH session correctly showed `PIGEON_LOG_DIR=/var/log/pigeon` — two different shell sessions, two different environments.

This PR also writes the same key/value pairs to `/etc/environment`, alongside (not replacing) the existing `/etc/profile.d` file. `/etc/environment` is read by PAM's `pam_env` module during session setup for *any* SSH-authenticated session — login shell or a direct `ssh host cmd` — because PAM's session phase runs regardless of whether a shell actually starts. This is Ubuntu/Debian's default `sshd` PAM stack, so no new package or config is needed beyond writing the file.

Since `environment_variables` already carries secret material by design (it's `sensitive = true`, e.g. this repo's own `deduplication/media` leaf passes real bucket secret keys through it), the new `/etc/environment` entry is permissioned `0600` rather than the conventional world-readable `0644` — matching the level `pigeon-env.sh` already uses. `sshd`'s own PAM read happens while it's still running as root, before dropping privileges, so the tighter permission doesn't break the mechanism.

No input/output signature change — purely a cloud-init rendering fix. Full writeup: [docs/adr/0104-fix-env-vars-not-reaching-non-login-ssh-invocations.md](docs/adr/0104-fix-env-vars-not-reaching-non-login-ssh-invocations.md).

Note for whoever applies this: like any `local.cloud_init` content change, this force-replaces every existing instance that picks up the new module version on its next `terragrunt apply` (`lifecycle.replace_triggered_by`) — bump a leaf's version pin and apply it deliberately, not as a surprise.

[#133](https://github.com/noisypigeon/noisypigeon/pull/133)

## [2.3.3] - 2026-10-03

### Add a shared Cockpit metrics/logs store for pigeon-cli instances

Adds `workloads/pigeon-cli/terraform/observability/` (ADR-0103): one shared `scaleway_cockpit_source` (metrics) + one (logs) + one push token for every pigeon-cli compute instance, replacing ADR-0102's per-leaf private Cockpit sources now that pigeon-cli (`noisypigeon/pigeon-cli` ADR-0093) carries real `pigeon_job`/`instance` identity on every metric and log line — there's no longer a reason for each instance to have its own separate data store.

Fanned out via three new `workloads/root.hcl` generated locals (`PIGEON_COCKPIT_METRICS_PUSH_URL`/`PIGEON_COCKPIT_LOGS_PUSH_URL`/`PIGEON_COCKPIT_TOKEN_SECRET`, hand-copied from this leaf's outputs into the shared root `.env`), following this repo's only established sharing convention — confirmed via research that this repo has never used a Terragrunt `dependency` block anywhere. Deliberately not `ENV_SW_`-prefixed, to avoid colliding with `root.hcl`'s generic per-bucket-name secret-promotion mechanism (the exact collision class ADR-0098 already navigated around once).

Also fixes two `modules/scaleway/compute-instance` Alloy config gaps that only matter once every instance shares one store:
- The default Prometheus `instance` label (the scrape address, identical on every host) is overridden to the real hostname via `discovery.relabel`.
- A new `loki.process` stage extracts pigeon-cli's own JSON `timestamp` field as Loki's real entry time (fixing the redundant double-timestamp display previously reported) and extracts `command`/`instance` into real Loki labels.

Not done here (left to the user, see the ADR's Out of scope): migrating `deduplication/macbook-scratch`'s existing private Cockpit resources over to the shared ones — that leaf has unrelated uncommitted local changes right now.

Full details: [docs/adr/0103-shared-cockpit-store.md](docs/adr/0103-shared-cockpit-store.md)

## Test plan

- [x] `terraform validate`/`fmt -check` clean on the module and new leaf
- [x] Real `terragrunt plan` against this project's Scaleway credentials for the new leaf: 3 to add, 0 to change/destroy
- [x] Confirmed an unrelated leaf (`workloads/blog/terraform`) still plans clean (`No changes`) after the `root.hcl` addition
- [ ] Alloy river syntax (`discovery.relabel`, `stage.json` JMESPath expressions) not independently verified against a real `alloy` binary — flagged explicitly in the ADR, to check at first real apply

[#132](https://github.com/noisypigeon/noisypigeon/pull/132)

## [2.3.2] - 2026-10-03

### Fix doubled Cockpit push path and non-resilient log tailing in compute-instance

Two confirmed bugs found applying v2.3.1's `cockpit` wiring to a real test-bed instance and inspecting `alloy`'s live logs:

**Doubled push path, every push 404ing.** `scaleway_cockpit_source.push_url` is already the complete ingest endpoint ("Ingest endpoint for transmitting data" per its schema), not a bare host. `instance.tf`'s Alloy config appended `/api/v1/push`/`/loki/api/v1/push` on top of it a second time, producing URLs like `.../metrics.cockpit.fr-par.scw.cloud/api/v1/push/api/v1/push`. Confirmed via `journalctl -u alloy`: `level=error msg="non-recoverable error" ... err="server returned HTTP status 404 Not Found: not found"`, repeating every minute with growing `failedSampleCount`. Fix: use `push_url` directly, no appended path.

**Log file never got picked up.** `loki.source.file "pigeon_logs"` used a static inline `targets = [{"__path__" = "/var/log/pigeon/pigeon.jsonl"}]`. Alloy starts at first boot, before any `pigeon` job has run and created that file — confirmed via `journalctl`: `error="failed to tail file, stat failed: stat /var/log/pigeon/pigeon.jsonl: no such file or directory"`, logged as `"failed to create source, skipping"`, with no further retry visible afterward. Fix: route through `local.file_match`, which periodically re-globs the path and feeds `loki.source.file` updated targets as the file appears — the standard Alloy idiom for exactly this race.

Patch release — no input/output/behavior change beyond fixing both previously-broken cases.

[#131](https://github.com/noisypigeon/noisypigeon/pull/131)

## [2.3.1] - 2026-10-03

### Fix alloy install failing on a dpkg conffile prompt in compute-instance

ADR-0102's `cockpit` wiring (v2.3.0) writes `/etc/alloy/config.alloy` via cloud-init `write_files` before `runcmd` installs the `alloy` package. The `alloy` `.deb` also ships `/etc/alloy/config.alloy` as a conffile, so `dpkg` detects the pre-existing file and tries to prompt interactively asking whether to keep it or take the package's default. cloud-init's `runcmd` script has no attached stdin, so dpkg hits EOF on the prompt and aborts configuring the package — `alloy.service` is left half-installed and fails to start (`Result: resources`), confirmed live against a real applied test-bed instance (`cloud-init status --long` showed `Runparts: 1 failures (runcmd)`, and `/var/log/cloud-init-output.log` showed the exact `*** config.alloy (Y/I/N/O/D/Z)` prompt followed by `end of file on stdin at conffile prompt`).

Fix: pass dpkg's `--force-confold` option (keep the already-present file, don't prompt) to the `alloy` install, plus `DEBIAN_FRONTEND=noninteractive` for good measure. This is exactly the outcome we want, since the whole point of pre-writing the file was to have our rendered config win over the package's default.

Patch release — no input/output/behavior change beyond fixing a previously-broken case.

[#130](https://github.com/noisypigeon/noisypigeon/pull/130)

## [2.3.0] - 2026-10-03

### Add Scaleway Cockpit wiring to compute-instance via Grafana Alloy

Adds a new optional `cockpit` input to `scaleway/compute-instance` (ADR-0102): when set, the module writes `/etc/alloy/config.alloy` and installs Grafana Alloy on first boot, scraping `pigeon-cli`'s local Prometheus metrics endpoint (`noisypigeon/pigeon-cli` ADR-0092) and tailing its JSONL log (pinned to a stable `/var/log/pigeon/pigeon.jsonl` path via a new `PIGEON_LOG_DIR` export), forwarding both to a Scaleway Cockpit project's metrics/logs sources. A whole-instance `node_exporter` scrape is included as a low-cost addition once Alloy is installed anyway.

`cockpit` is `null` by default (fully opt-in) and only used when `profile = "pigeon-cli"`, matching the existing `buckets`/`keyring_entries` gating pattern. Applying this to an existing instance will force-replace it (cloud-init content change, per this module's existing `replace_triggered_by` behavior) — something to call out explicitly in whichever leaf PR actually sets `cockpit`.

The actual `scaleway_cockpit_source`/`scaleway_cockpit_token` resources and wiring `cockpit = {...}` into a real leaf are a deliberate follow-up, not part of this PR — they need this module's new tag to reference.

See [docs/adr/0102-compute-instance-cockpit-alloy.md](docs/adr/0102-compute-instance-cockpit-alloy.md) for full rationale, including one unverified assumption (the Loki-side auth header) flagged explicitly in the ADR's Out of scope section.

[#128](https://github.com/noisypigeon/noisypigeon/pull/128)

## [2.2.0] - 2026-10-02

### Make keyring bucket encryption key optional; add environment_variables

Two follow-ups to `scaleway/compute-instance`'s `keyring_entries` (ADR-0100):

1. **`encryption_key_alias` is now actually optional for `kind = "bucket"` entries.** The type already declared it `optional(string)`, but the render unconditionally interpolated it, which errors on `null`. A bucket entry with no associated encryption key now renders cleanly without that field.

2. **New `environment_variables` input** — a generic `map(string)` of key/value environment variables, usable with any profile (not just `pigeon-cli`), written to `/etc/profile.d/pigeon-env.sh` and sourced both early in `runcmd` (so it's available at first boot) and automatically by later interactive login shells (so it's available to a manual `pigeon-cli` SSH session too). Marked `sensitive = true`. This lets callers inject secrets such as `pigeon-cli`'s `PIGEON_SECRET_<ALIAS>`-named keyring secrets without this module hardcoding that naming convention.

Both changes are backwards compatible (`environment_variables` defaults to `{}`; the encryption-key fix only makes a previously-erroring case succeed). See ADR-0101 (`docs/adr/0101-add-environment-variables-and-optional-keyring-encryption-key.md`) for full rationale.

[#127](https://github.com/noisypigeon/noisypigeon/pull/127)

## [2.1.0] - 2026-10-02

### Add keyring_entries input for pigeon-cli keyring.toml

Adds a `keyring_entries` input to `scaleway/compute-instance`, used when `profile = "pigeon-cli"`. It renders `/root/.config/pigeon/keyring.toml` on first boot from a list of entries, following the same `write_files` + templating pattern already used for `rclone.conf`/`buckets`.

Each entry has a `kind` (`"email"`, `"bucket"`, or `"encryption-key"`) plus an `alias`, and the fields relevant to that kind:

- `email`: `email`, `provider`, `host`, `port`, optional `max_imap_connections`.
- `bucket`: `endpoint`, `bucket`, `access_key_id`, `encryption_key_alias`.
- `encryption-key`: `created_at`.

As with `buckets`, this module never creates or stores secrets itself — callers resolve any credentials externally (e.g. via `scaleway/iam-policy`) and pass in already-populated values. `keyring_entries` defaults to `[]`, so this is fully backwards compatible.

See ADR-0100 (`docs/adr/0100-add-keyring-toml-templating-to-scaleway-compute-instance.md`) for the full design rationale.

[#126](https://github.com/noisypigeon/noisypigeon/pull/126)

## [2.0.0] - 2026-10-02

### Merge rclone cloud-init profile into pigeon-cli

## Summary

`scaleway/compute-instance`'s `profile` input drops `"rclone"` as a distinct value. `"pigeon-cli"` now absorbs everything `"rclone"` used to do:

- Installs `rclone` and `neovim` via cloud-init `packages:` (previously only under `profile = "rclone"`).
- Writes `/root/.config/rclone/rclone.conf` from `var.buckets` (previously only under `profile = "rclone"`).
- Still runs the `pigeon-cli` bootstrap script in `runcmd` on first boot, unchanged.

`"docker"` is untouched. `buckets`' validation gate moves from `profile == "rclone"` to `profile == "pigeon-cli"`. The `profile` default changes from `"rclone"` to `"pigeon-cli"` — the closest equivalent to preserving "omit `profile`, get rclone+neovim+bucket config," since `"pigeon-cli"` is now a strict superset of the old default's behavior.

**Why:** no live caller used `profile = "rclone"` or relied on the old default (confirmed via a repo-wide grep before making this change), but a real in-progress leaf (`workloads/pigeon-cli/terraform/sort/macbook-scratch`) already needs `profile = "pigeon-cli"` **and** a non-empty `buckets` list at the same time — a combination the prior version rejected outright. This unblocks it.

Full rationale in [ADR-0099](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0099-merge-rclone-profile-into-pigeon-cli.md).

**Breaking change:** `profile = "rclone"` is no longer a valid value (rejected by the input's own validation block). Existing callers using `"docker"` or `"pigeon-cli"` are unaffected except that `"pigeon-cli"` now also installs `rclone`/`neovim` and accepts `buckets`. As with every prior cloud-init content change to this module (ADR-0084's force-replace lifecycle), any existing instance is replaced on its next apply.

## Test plan
- [x] `terraform fmt -check` clean
- [x] `terraform init -backend=false && terraform validate` clean
- [x] Rendered the cloud-init `locals` block standalone (no provider needed) for both remaining profiles: `docker` output is byte-identical to before; `pigeon-cli` with a sample `buckets` entry now renders the `rclone`/`neovim` packages, the populated `write_files` block, and the unchanged bootstrap `runcmd` line
- [x] Exercised the real module's own validation via `terraform plan`: `profile = "rclone"` rejected (invalid enum value), `profile = "docker"` + non-empty `buckets` rejected (updated error message), `profile = "pigeon-cli"` + non-empty `buckets` plans cleanly

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#125](https://github.com/noisypigeon/noisypigeon/pull/125)

## [1.0.0] - 2026-10-02

### Move scaleway modules to top-level modules/, major release each

Moves `terraform/modules/scaleway/*` to top-level `modules/scaleway/*` and cuts a major release for every module, fixing the stale `noisypigeon/pigeon.git` repo name (a prior name of this same repo) to the real current name, `noisypigeon/noisypigeon.git`, in every source string along the way.

**Version bumps** (next available major per module, not a blanket v1.0.0 — two modules were already past 1.0):

| Module | Before | After |
|---|---|---|
| `project` | 0.2.1 | **1.0.0** |
| `object-bucket` | 0.2.0 | **1.0.0** |
| `iam-policy` | 1.1.1 | **2.0.0** |
| `compute-instance` | 0.9.1 | **1.0.0** |
| `block-volume` | 1.0.0 | **2.0.0** |

To make the existing automation compute these correctly (its version lookup is tag-prefix-based and all 22 existing tags live under the old `terraform/modules/scaleway/*` prefix), 5 bookkeeping-only seed tags mirroring each module's current version were pushed directly to origin under the new prefix before this PR — no GitHub Release, no CHANGELOG entry, just enough for `module-release.yml`'s `$LATEST` lookup to find a baseline.

**All 16 live consumers** across `terraform/infrastructure/scaleway/**` updated to the new repo name, new path, and new major tag — this also converges pre-existing version drift (`iam-policy` had one consumer on v0.1.0 against five on v1.1.1; `object-bucket` had three different pinned versions across seven consumers). Verified safe: every variable beyond the always-supplied required ones has a default in both modules, so no consumer needs a new argument added.

Also: `module-release.yml`/`module-docs.yml`'s hardcoded `terraform/modules/scaleway` paths, the `release-pr` skill's path references, `modules/README.md` (moved, repo name and tag-scheme examples fixed), and `terraform/README.md` deleted (its "two independent trees" premise no longer holds once `modules/` isn't under `terraform/`).

Checked every other repo in the `noisypigeon` org (`pigeon-cli`, `pigeon-os`, `dotfiles`) for external consumers — none found.

Full rationale in [ADR-0093](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0093-move-scaleway-modules-to-top-level-modules.md).

## Test plan
- [x] `terraform fmt -check -recursive` clean on `modules/` and `terraform/infrastructure/scaleway/`
- [x] `terragrunt hcl format --check` clean on `modules/`
- [x] `grep -rn "terraform/modules/scaleway\|noisypigeon/pigeon\.git"` returns nothing outside historical ADRs/CHANGELOGs
- [x] All 16 consumer leaves + 1 dead/commented reference verified updated
- [ ] User to run `terragrunt init` on affected leaves to confirm the new module source resolves correctly (not performed here — would need real credentials)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#120](https://github.com/noisypigeon/noisypigeon/pull/120)

## [0.9.1] - 2026-10-02

### Fix missing $HOME in scaleway/compute-instance cloud-init runcmd

`cloud-init status --long` was reporting `status: error` on every instance using this module. `cloud-init-output.log` pinpoints the root cause (confirmed from the actual log, not guessed — an initial hypothesis about an interactive `mkfs.ext4` prompt was ruled out; the volume mount block completes cleanly):

```
mise: selected 2026.9.18 (minimum release age: 24h)
sh: 325: HOME: parameter not set
/var/lib/cloud/instance/scripts/runcmd: 9: cannot create ~/.bashrc: Directory nonexistent
bash: line 6: HOME: unbound variable
```

cloud-init's `runcmd` module bundles every list item into one shell script and runs it once, in an environment with **no `$HOME` set**. That broke three independent things in the same script: the `mise.run` installer (references `$HOME` internally), this module's own `echo '...' >> ~/.bashrc` line (tilde expansion needs `$HOME`), and the `pigeon-cli` profile's bootstrap script (also references `$HOME`, under `bash`'s strict mode).

Fix: `export HOME=/root` as the first `runcmd` line (inherited by every later line in the same script), plus switching this module's own `~/.bashrc` reference to the absolute `/root/.bashrc`.

Full root-cause writeup in [ADR-0090](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0090-fix-missing-home-in-compute-instance-cloud-init-runcmd.md).

No input/output changes — pure bugfix to existing, previously-broken behavior.

## Test plan
- [x] `terraform fmt -check` clean
- [x] `terraform init -backend=false && terraform validate` clean
- [x] Rendered cloud-init and confirmed `export HOME=/root` is the first `runcmd` line and the mise line now targets `/root/.bashrc`
- [ ] User to re-apply and confirm `cloud-init status --long` reports `status: done` on a fresh instance

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#117](https://github.com/noisypigeon/noisypigeon/pull/117)

## [0.9.0] - 2026-10-02

### Auto-mount attached volume and inline pigeon-cli bootstrap on scaleway/compute-instance

Two behavior changes, no interface changes:

**Auto-mount the attached volume.** When `additional_volume_ids` is non-empty, cloud-init now formats and mounts the first attached volume automatically on first boot:

```
mkfs.ext4 -L data /dev/sdb
mkdir -p /mnt/data
mount /dev/sdb /mnt/data
UUID=$(blkid -s UUID -o value /dev/sdb)
echo "UUID=$UUID /mnt/data ext4 defaults,nofail 0 2" >> /etc/fstab
mount -a
```

**⚠️ `mkfs.ext4` is unconditional.** This module already force-replaces the instance on any cloud-init content change (ADR-0084), and this PR is itself a cloud-init change — so every existing instance with an attached volume will have that volume **reformatted from scratch** on its next apply after upgrading. This is a deliberate, confirmed tradeoff (no "format only if unformatted" guard), documented in [ADR-0089](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0089-auto-mount-volume-and-inline-pigeon-cli-bootstrap.md). Scope is also limited to exactly one volume at a fixed `/dev/sdb` path and a hardcoded `/mnt/data` mount point / `data` label.

**Fix `pigeon-cli`: inline the bootstrap script.** The `BOOTSTRAP` env var from the previous release (meant to be run via `eval $BOOTSTRAP`) didn't work in practice. `profile = "pigeon-cli"` now runs the bootstrap pipeline directly in `runcmd` on first boot instead:

```
curl -fsSL https://gist.githubusercontent.com/noisypigeon/1e96e8ef94380f913f6ae02782965149/raw/pigeon.sh | bash
```

Full rationale in [ADR-0089](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0089-auto-mount-volume-and-inline-pigeon-cli-bootstrap.md).

## Test plan
- [x] `terraform fmt -check` clean
- [x] `terraform init -backend=false && terraform validate` clean
- [x] Rendered cloud-init for: no volume (no mount commands), with volume (mount sequence appears before mise), and `profile = "pigeon-cli"` with volume (mount sequence + direct bootstrap curl|bash, no stray `BOOTSTRAP` export)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#116](https://github.com/noisypigeon/noisypigeon/pull/116)

## [0.8.0] - 2026-10-02

### Add pigeon-cli cloud-init profile and ipv4_address output to scaleway/compute-instance

`scaleway/compute-instance`'s `profile` input gains a third value, `"pigeon-cli"`, alongside the existing `"rclone"`/`"docker"` (ADR-0087). Unlike those two, it installs no packages — it only appends an export line to `~/.bashrc` setting a `BOOTSTRAP` environment variable to:

```
curl -fsSL https://gist.githubusercontent.com/noisypigeon/1e96e8ef94380f913f6ae02782965149/raw/pigeon.sh | bash
```

**Invocation note:** run it as `eval $BOOTSTRAP`, not bare `$BOOTSTRAP`. Unquoted shell variable expansion doesn't get re-parsed for operators like `|`, so typing `$BOOTSTRAP` directly would pass `-fsSL`, the URL, `|`, and `bash` as literal arguments to `curl` rather than piping to it. `eval` re-parses the expanded string and runs the pipeline correctly.

Supporting this profile required making the cloud-init template's `packages:` key itself conditional (previously always emitted; `pigeon-cli` needs zero packages, and an empty `packages:` key is invalid/null in cloud-init YAML). Rendered output for `"rclone"`/`"docker"` is unchanged.

Also adds a new `ipv4_address` output, sourced from the existing routed-IPv4 resource — `null` when `enable_ipv4 = false`. Purely additive; `public_ips`/`private_ips` are unchanged.

Full design rationale in [ADR-0088](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0088-add-pigeon-cli-profile-to-scaleway-compute-instance.md).

Existing callers are unaffected by the interface change (new enum value, new output, both default-preserving), but — as with every prior change to this module's cloud-init content — any existing instance gets replaced on its next apply (ADR-0084's force-replace-on-cloud-init-change lifecycle).

## Test plan
- [x] `terraform fmt -check` clean
- [x] `terraform init -backend=false && terraform validate` clean
- [x] Rendered all three profiles via a scratch config: `rclone`/`docker` output unchanged, `pigeon-cli` correctly omits `packages:` and sets the `BOOTSTRAP` export

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#115](https://github.com/noisypigeon/noisypigeon/pull/115)

## [0.7.0] - 2026-10-02

### Add cloud-init profiles (rclone/docker) to scaleway/compute-instance

`scaleway/compute-instance` gains a new `profile` input (`"rclone"` or `"docker"`, defaults to `"rclone"`) that selects between two cloud-init provisioning shapes:

- **`profile = "rclone"`** (default, matches prior behavior): installs `rclone` and `neovim`, and writes `/root/.config/rclone/rclone.conf` from `var.buckets` exactly as before.
- **`profile = "docker"`**: installs Docker CE (official apt repo/key bootstrap) plus `docker-ce-cli`, `containerd.io`, and `docker-compose-plugin`, and enables + starts the `docker` service.

`build-essential`, `pkg-config`, and `libssl-dev` are removed from the cloud-init package list entirely, under both profiles — they were only ever installed to support `mise`'s build-toolchain use case, not rclone, and aren't needed by either new profile. Any existing instance relying on those packages being present will lose them on its next apply.

`buckets` now has a validation guard: it's rejected (non-empty) when `profile != "rclone"`, since bucket config would otherwise silently do nothing.

Full design rationale in [ADR-0087](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0087-add-cloud-init-profiles-to-scaleway-compute-instance.md).

Existing callers are unaffected by the interface change (new input defaults to `"rclone"`), but — as with every prior change to this module's cloud-init content — any existing instance gets replaced on its next apply (ADR-0084's force-replace-on-cloud-init-change lifecycle).

## Test plan
- [x] `terraform fmt -check` clean
- [x] `terraform init -backend=false && terraform validate` clean
- [x] Rendered both profiles via a scratch config and confirmed correct package lists / `write_files` / `runcmd` branching, and that `buckets` + `profile = "docker"` is rejected by the new validation

🤖 Generated with [Claude Code](https://claude.com/claude-code)

[#114](https://github.com/noisypigeon/noisypigeon/pull/114)

## [0.6.0] - 2026-10-01

### Pre-install mise and a build toolchain in compute-instance's cloud-init

Every instance created by `scaleway/compute-instance` now gets, unconditionally (same posture as the existing `rclone`/`neovim` install), a Rust/C build toolchain (`build-essential`, `pkg-config`, `libssl-dev`) and [mise](https://mise.jdx.dev/) pre-installed via its official quick-install script, with bash activation wired into `~/.bashrc`.

No new module input — this follows the same unconditional-provisioning pattern already used for `rclone`/`neovim`.

Since this edits the instance's cloud-init content, and the module already forces instance replacement whenever that content changes (ADR-0084), any existing instance using this module will be destroyed and recreated on its next `terragrunt apply` after upgrading to this version.

[#112](https://github.com/noisypigeon/noisypigeon/pull/112)

## [0.5.0] - 2026-10-01

### Attach a routed IPv4 address to compute-instance by default

Adds a new `enable_ipv4` input to `scaleway/compute-instance` (defaults to `true`), creating and attaching a routed IPv4 address to the instance by default, alongside the existing `enable_ipv6` (defaults to `false`).

`scaleway_instance_server`'s `ip_id` argument only ever holds a single reserved IP, and is mutually exclusive with `ip_ids`, the list-valued equivalent. Since `enable_ipv4` defaults to `true`, an instance can now have both an IPv4 and an IPv6 address enabled at once, which `ip_id` can't express. The server's attachment argument switches from `ip_id` to `ip_ids`, built from whichever of the two IPs are enabled (`compact([...])`, dropping disabled ones) — functionally identical to before when only one or neither is enabled.

Existing callers that already set `enable_ipv6 = true` will pick up a new default IPv4 address on their next apply (and will see `scaleway_instance_server`'s IP attachment move from `ip_id` to `ip_ids`); set `enable_ipv4 = false` to opt out and keep IPv6-only.

[#111](https://github.com/noisypigeon/noisypigeon/pull/111)

## [0.4.0] - 2026-10-01

### Add scaleway/block-volume module and compute-instance volume attachment

Adds a new `scaleway/block-volume` module wrapping `scaleway_block_volume`, and extends `scaleway/compute-instance` so a volume it creates can be attached to an instance.

`block-volume`'s initial interface is required-fields-only, with two deliberate exceptions: the resource's `size_in_gb` is renamed to `size` (required — this module doesn't support creating from a snapshot yet, so omitting a size would be unsafe), and `iops`, though required by the underlying resource, defaults to `15000` (Scaleway's standard tier) rather than being required of every caller. Naming follows the same `{namespace}-{random}-{name}` scheme as every other module in this provider root. Outputs are `id` and `name`.

`compute-instance` gains one new, backwards-compatible input: `additional_volume_ids` (`list(string)`, default `[]`), wired straight through to `scaleway_instance_server`'s existing argument of the same name. Per this repo's established composition rule, `compute-instance` does not call `block-volume` internally — callers create a volume and pass its `id` through themselves, e.g.:

```hcl
module "scratch_volume" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/block-volume?ref=terraform/modules/scaleway/block-volume/v0.1.0"
  namespace = "import"
  name      = "scratch"
  size      = 100
}

module "instance" {
  source = "git::https://github.com/noisypigeon/pigeon.git//terraform/modules/scaleway/compute-instance?ref=..."
  ...
  additional_volume_ids = [module.scratch_volume.id]
}
```

Existing `compute-instance` callers are unaffected unless they opt in. Full design rationale in [ADR-0085](https://github.com/noisypigeon/noisypigeon/blob/main/docs/adr/0085-add-scaleway-block-volume-module.md).

[#109](https://github.com/noisypigeon/noisypigeon/pull/109)

## [0.3.1] - 2026-09-30

### Force instance replacement when compute-instance cloud-init changes

Root-caused (see ADR-0084 for the full investigation and citations): `scaleway_instance_server.user_data` has no `ForceNew` in the Terraform provider schema, so changing its `cloud-init` content on an *existing* instance just PATCHes the metadata in place via Scaleway's API — the instance keeps its instance-id. cloud-init only runs package-install and `write_files` modules once per instance-id, on first boot, so an in-place `user_data` update (or a plain reboot) is silently never applied. This is exactly what DigitalOcean's `digitalocean_droplet.user_data` avoids by being `ForceNew: true`, which ADR-0081 didn't carry over when porting the cloud-init pattern to Scaleway.

Fix: the cloud-config content moves into `local.cloud_init`, a new `terraform_data.cloud_init` resource hashes it, and `scaleway_instance_server.server` gets `lifecycle { replace_triggered_by = [terraform_data.cloud_init.output] }`. Any future change to the rendered cloud-init content (packages, buckets, write_files) now forces a fresh instance, guaranteeing cloud-init gets a genuine first boot on it — matching DigitalOcean's behavior.

No input or output changes. Note this doesn't retroactively fix any instance already running with skipped cloud-init modules — those need a one-time manual rebuild.

[#108](https://github.com/noisypigeon/noisypigeon/pull/108)

## [0.3.0] - 2026-09-30

### Add routed IPv6 and instance-specific SSH keys to scaleway/compute-instance

`scaleway/compute-instance` gains two new opt-in inputs:

- **`enable_ipv6`** (bool, default `false`): when true, creates a `scaleway_instance_ip` of type `routed_ipv6` and attaches it to the instance via `ip_id`. The address shows up in the existing `public_ips` output once attached (filter by `family == "inet6"`) -- no new output was added. Note: the originally-proposed `scaleway_flexible_ip` resource does *not* apply here -- it's scoped to Elastic Metal (bare metal) servers only, confirmed directly against the Terraform provider's source. `scaleway_instance_ip` is the correct mechanism for a standard Instance's routed IP.

- **`ssh_keys`** (list of strings, default `[]`): raw SSH public keys that get instance-specific access, in addition to account-wide keys that already apply automatically. The module encodes each into Scaleway's `AUTHORIZED_KEY=<key-with-underscores>` tag convention, so callers don't have to hand-escape spaces themselves.

Both inputs default to their no-op values, so this is fully backwards compatible. See ADR-0082 and ADR-0083 for the full design rationale.

[#105](https://github.com/noisypigeon/noisypigeon/pull/105)

## [0.2.0] - 2026-09-30

### Add rclone/neovim cloud-init and bucket access to scaleway/compute-instance

`scaleway/compute-instance` now installs `rclone` and `neovim` via cloud-init on every instance, and accepts a new optional `buckets` input (default `[]`) that populates `/root/.config/rclone/rclone.conf` with one `alias` + one `s3` remote per bucket -- the same schema and rendering approach `digitalocean/droplet` already uses for its own rclone config.

Bucket-scoped access-key creation stays outside this module: compose a `scaleway/iam-policy` module call (its `bucket_names`/`bucket_actions`/`admin_project_id` inputs and `access_key`/`secret_key` outputs are unchanged) and pass the resolved credentials into `buckets` yourself.

See ADR-0081 for the full design rationale, including why bucket-credential creation stays external and why `rclone.conf` lands under `/root` rather than a created non-root user.

This PR also fixes stale `docs/archived/adr/` references in `CLAUDE.md`/`docs/USAGE.md` -- that directory no longer exists on `main` (ADRs were flattened back into `docs/adr/` a while back); unrelated to the module change itself but caught while writing ADR-0081.

[#104](https://github.com/noisypigeon/noisypigeon/pull/104)

## [0.1.0] - 2026-09-29

### docs(adr-0079): add scaleway/compute-instance module

## Context

`terraform/modules/scaleway/` has `project`, `object-bucket`, and `iam-policy`, but no compute module. `digitalocean/droplet` is the DigitalOcean analog, but it bundles DigitalOcean-specific machinery (cloud-init, an access-key sub-module, SSH-key data source, Cloudflare DNS alias) not wanted yet. This adds a deliberately minimal wrapper around `scaleway_instance_server`, using `droplet` only for structural/naming inspiration.

## Decision

- New module `terraform/modules/scaleway/compute-instance`: `namespace`/`name`/`image` required, `type` defaults to `STARDUST1-S` (overridable) — the one deliberate exception to "required fields only," per the user's request.
- `image` is a required *module* input even though it's an optional *resource* argument on `scaleway_instance_server` — the resource only allows skipping it when attaching an existing root volume, a path this module doesn't support yet (same kind of call ADR-0044 made for `object-bucket`'s `storage_class`).
- Outputs are pass-through only (`id`, `name`, `public_ips`, `private_ips`) — no invented indexing, since no IP is attached by default.
- `terraform/modules/README.md` gains a row; `module-docs.yml`'s hand-maintained `working-dir:` list gains an entry. `module-release.yml` needs no change — its module discovery and changelog/tagging automation already generalize to any provider root with a `versions.tf`.
- No hand-written `CHANGELOG.md` — `module-release.yml` creates one on first merge.

Full ADR: [`docs/adr/0079-add-scaleway-compute-instance-module.md`](../blob/adr-0079-add-scaleway-compute-instance-module/docs/adr/0079-add-scaleway-compute-instance-module.md)

## Test plan

- [x] `terraform fmt -check` clean.
- [x] `terraform init -backend=false && terraform validate` clean.
- [x] `mise run ci` clean.

[#86](https://github.com/noisypigeon/noisypigeon/pull/86)
