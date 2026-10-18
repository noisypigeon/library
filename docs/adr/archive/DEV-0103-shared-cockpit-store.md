# DEV-0103: one shared Cockpit metrics/logs store for every pigeon-cli instance

- **Author**: Willow Graysen ([@noisypigeon](https://github.com/noisypigeon)).
- **Date**: 2026-10-03.
- **Status**: Accepted.

## Context

ADR-0102 wired `scaleway/compute-instance`'s new `cockpit` input to a
*private* `scaleway_cockpit_source`/`scaleway_cockpit_token` pair created
directly inside the `deduplication/macbook-scratch` leaf (PR #129) — every
instance would get its own Mimir/Loki data source. Once `noisypigeon/pigeon-cli`
ADR-0093 landed, every metric/log line from a pigeon-cli process now carries
real job/instance identity (`pigeon_job`-labeled counters, a `command`+
`instance` field on every log event) — there's no longer a reason for
Mimir/Loki data from different machines to live in physically separate
Cockpit sources; one shared store, disambiguated by those labels, is both
simpler to operate (one source to configure dashboards against, not one
per instance) and the more standard Prometheus/Loki multi-tenant-via-labels
model.

Before designing the sharing mechanism, confirmed via research: this repo
has **never used a Terragrunt `dependency` block** — zero hits anywhere,
reaffirmed explicitly across ADR-0094/0095/0097/0098. Every existing
"shared resource" (the deployer IAM identity, the project ID) flows through
hand-copying a value into the shared root `.env`, which `workloads/root.hcl`
fans out as generated locals to every leaf. That's the pattern this ADR
follows, not a novel cross-leaf state read.

## Decision

### A new, dedicated leaf: `workloads/pigeon-cli/terraform/observability/`

```hcl
resource "scaleway_cockpit_source" "pigeon_metrics" {
  project_id     = local.scaleway_project_id
  name           = "pigeon-cli-metrics"
  type           = "metrics"
  retention_days = 31
}

resource "scaleway_cockpit_source" "pigeon_logs" {
  project_id     = local.scaleway_project_id
  name           = "pigeon-cli-logs"
  type           = "logs"
  retention_days = 31
}

resource "scaleway_cockpit_token" "pigeon_push" {
  project_id = local.scaleway_project_id
  name       = "pigeon-cli-push"
  scopes {
    write_metrics = true
    write_logs    = true
  }
}
```
plus `metrics_push_url`/`logs_push_url`/`token_secret` outputs. Sibling to
`sort/`, `deduplication/`, `import/*` — matches the existing
`workloads/<workload>/terraform/<leaf>` convention, no `root.hcl` leaf-depth
change needed (ADR-0096 already widened it to any depth). Verified with a
real `terragrunt plan` against this project's Scaleway credentials: 3 to
add, 0 to change/destroy.

### Fan-out via `root.hcl`, not a `dependency` block

Once applied, the three output values get hand-copied into the shared root
`.env` (same manual step as `SCALEWAY_ACCESS_KEY`/`SCALEWAY_SECRET_KEY`,
ADR-0094), and `workloads/root.hcl`'s `generate "scaleway_ids"` block gains
three new locals reading them — same shape as ADR-0098's `custodian_dj_name`
addition:
```hcl
pigeon_cockpit_metrics_push_url = "${get_env("PIGEON_COCKPIT_METRICS_PUSH_URL", lookup(local.secrets, "PIGEON_COCKPIT_METRICS_PUSH_URL", ""))}"
pigeon_cockpit_logs_push_url    = "${get_env("PIGEON_COCKPIT_LOGS_PUSH_URL", lookup(local.secrets, "PIGEON_COCKPIT_LOGS_PUSH_URL", ""))}"
pigeon_cockpit_token_secret     = "${get_env("PIGEON_COCKPIT_TOKEN_SECRET", lookup(local.secrets, "PIGEON_COCKPIT_TOKEN_SECRET", ""))}"
```
**Deliberately not `ENV_SW_`-prefixed**, unlike `ssh_key_alias`/
`ssh_key_public_key`'s env vars: `root.hcl`'s generic
`bucket_name_secrets` mechanism (lines 71-76) promotes *every*
`ENV_SW_`-prefixed `.env` key into its own generated local automatically —
using that prefix here would risk the exact "duplicate local defined in
two different generated files" collision ADR-0098 explicitly navigated
around for `custodian_dj_name`. Every other hand-generated secret in this
file (`SCALEWAY_ACCESS_KEY`, `SCALEWAY_PROJECT_ID_NOISYPIGEON`,
`CLOUDFLARE_*`) also avoids that prefix for the same reason; these three
follow that existing precedent instead. Verified: an unrelated leaf
(`workloads/blog/terraform`) still plans clean (`No changes`) after this
addition.

Every pigeon-cli compute-instance leaf references these shared locals
directly in its `cockpit = {...}` block going forward — no leaf creates its
own source/token. **Not done in this PR**: migrating
`deduplication/macbook-scratch/cockpit.tf`'s existing private resources to
the shared ones — that leaf has unrelated uncommitted local changes at the
time of this ADR, left untouched; switching it over (and orphaning its old
private Cockpit source/token, same treatment ADR-0098 gave prior orphaned
state) is a follow-up left to the user's timing.

### Alloy: making the shared store actually disambiguate instances

Two fixes in `modules/scaleway/compute-instance/instance.tf`'s rendered
`/etc/alloy/config.alloy`, now that logs/metrics from every instance land
in the same place:

**Metrics** — `prometheus.scrape`'s default `instance` label is the
scraped address (`localhost:9091`), identical on every machine. Overridden
to the real hostname via `discovery.relabel` (the standard Alloy/Prometheus
idiom for this — `target_label = "instance"`, `replacement =
constants.hostname`), applied to both the `pigeon_cli` and `node` scrape
targets.

**Logs** — `loki.source.file`/`loki.write` had no label-setting and no
timestamp handling at all. A new `loki.process "pigeon_logs"` stage, now
sitting between them, does two things in one pass:
1. `stage.json` + `stage.timestamp` extract the JSON body's own
   `timestamp` field and use it as Loki's real per-entry timestamp,
   instead of Loki defaulting to "time Alloy read the line" — fixing the
   redundant double-timestamp display (the JSON body's field shown a
   second time next to Loki's own clock) without touching pigeon-cli's
   JSONL schema at all (ADR-0078's local `jq` workflow is unaffected).
2. `stage.json` + `stage.labels` extract pigeon-cli's `command`/`instance`
   span fields (ADR-0093) into real Loki labels (`pigeon_job`/`instance`),
   so the shared store stays filterable the same way the shared metrics
   store now is.

**Not independently verified**: the exact JMESPath expression
(`spans[0].command`/`spans[0].instance`) for reaching into pigeon-cli's
JSON body, and the `discovery.relabel` river syntax — both should be
checked against Alloy's current docs the first time this is actually
applied, the same "flag it, verify at implementation" treatment ADR-0102
already gave the logs-side `X-TOKEN` header. `terraform validate` only
confirms the surrounding HCL structure; the embedded Alloy config is a
plain string from Terraform's point of view and isn't syntax-checked by
it.

**Known gap, not fixed here**: on the one auto-emitted span-close event
per run (`FmtSpan::CLOSE`, ADR-0073), pigeon-cli's `spans` array is empty
(`span` still names the closing span) — that single log line per run
won't get `pigeon_job`/`instance` labels from this extraction. Negligible
in practice (one line out of a whole run), not worth the added complexity
of a fallback expression.

## Consequences

- One Cockpit source per data kind for all of pigeon-cli, not one per
  instance — dashboards get built once, against one source, filterable by
  `pigeon_job`/`instance` labels rather than by picking a different data
  source per machine.
- `deduplication/macbook-scratch`'s existing private Cockpit resources
  become a planned-but-not-yet-executed migration, explicitly deferred
  (see above), not silently left inconsistent without documentation.
- `root.hcl` gains its first explicitly-non-`ENV_SW_`-prefixed trio of
  hand-generated secrets since `SCALEWAY_*`/`CLOUDFLARE_*` — a precedent
  worth remembering for any future shared-resource addition following this
  same pattern.

## Out of scope

- Actually switching `deduplication/macbook-scratch` (or any future
  `sort/macbook-scratch` Cockpit wiring) over to the shared locals —
  follow-up, left to the user.
- Any non-pigeon-cli consumer of this leaf or pattern — pigeon-cli-scoped
  by name and by need, per this repo's repeatedly-stated "wire only what's
  needed" philosophy (ADR-0098).
- Verifying the Alloy river syntax (`discovery.relabel`, `stage.json`
  JMESPath expressions) against a real `alloy` binary or live apply —
  flagged above, deferred to first real application.
