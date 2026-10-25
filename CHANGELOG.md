# Changelog

One line per PR across this whole repo, sectioned by date, newest first. Every
merged PR gets exactly one line here; a PR that changes a releasable unit
additionally gets its full PR body in that unit's own `CHANGELOG.md`. DEV-0160 is
the contract, inherited with the automation when LIB-0002 moved it here.

Not versioned — for versioned, package-scoped changelogs see
`terraform/*/*/CHANGELOG.md` (each Terraform module),
[`zola-site/CHANGELOG.md`](zola-site/CHANGELOG.md) (the theme),
[`terragrunt/root-hcl/CHANGELOG.md`](terragrunt/root-hcl/CHANGELOG.md) (the
`root.hcl` template) and
[`.github/workflows/CHANGELOG.md`](.github/workflows/CHANGELOG.md) (the
reusable CI). Those files
predate this repo: they travelled with their modules through every move since
`pigeon-tf`, so their older entries cite paths and PR numbers from repos this
one never was. That is deliberate — rewriting published release notes to match
a later layout would be a worse lie than a stale path.

Entry format is `- [<tag>] <PR title> ([#N](pr-url))`, where `<tag>` is one of:

- `<provider>/<module>` — a released Terraform module
- `zola-site` — a released theme version
- `workflows` — a released version of the reusable CI
- `terragrunt/root-hcl` — a released version of the spokes' `root.hcl` template
- `grafana-dashboards/<set>` — a released version of a Grafana dashboard set
- `terraform` — a `terraform/` change that releases nothing (e.g. a README)
- `terragrunt` — a `terragrunt/` change that releases nothing
- `grafana-dashboards` — a `grafana-dashboards/` change that releases nothing (e.g. a README)
- `adr` — decision records under `docs/adr/`
- `ci` — `.github/` workflows and scripts
- `repo` — anything else (root docs, `.mise.toml`, tooling)

The first five are written by `template-release.yml` as part of tagging a
release; the rest by `root-changelog.yml`, which runs on every merged PR and
stands down when `template-release.yml` owns the entry. Both go through
`.github/scripts/root-changelog.sh`, which inserts below the marker at the end
of this header — keep that line where it is.

This file starts at this repo's own beginning. Entries predating LIB-0002,
which created this repo from `noisypigeon/pigeon.dev`, stayed in that repo's
root `CHANGELOG.md` rather than being untangled from it — the same call
ADR-0154 and ADR-0084 each made before it.

<!-- entries below; newest first -->

## 2026-10-25

- [adr] Record LIB-0036's verification and what the import taught ([#182](https://github.com/noisypigeon/library/pull/182))
- [workflows] Refuse zones.yaml, workload rulesets and redirects, and hand-written zone leaves ([#181](https://github.com/noisypigeon/library/pull/181))
- [terragrunt/root-hcl] Refuse zones.yaml, workload rulesets and redirects, and hand-written zone leaves ([#181](https://github.com/noisypigeon/library/pull/181))

## 2026-10-24

- [workflows] Announce a staged apply's next-stage plan as it starts ([#180](https://github.com/noisypigeon/library/pull/180))
- [workflows] Acknowledge a terragrunt comment at once, outside the PR's queue ([#179](https://github.com/noisypigeon/library/pull/179))
- [workflows] Auto-merge only after an apply that ran and succeeded ([#178](https://github.com/noisypigeon/library/pull/178))
- [workflows] Fix resolve-workloads.sh --list failing in a spoke without zones ([#177](https://github.com/noisypigeon/library/pull/177))
- [workflows] Add zone units, zones/<zone>/zone.yaml (LIB-0036) ([#176](https://github.com/noisypigeon/library/pull/176))
- [terragrunt/root-hcl] Add zone units, zones/<zone>/zone.yaml (LIB-0036) ([#176](https://github.com/noisypigeon/library/pull/176))
- [adr] docs(adr): LIB-0036, zones are units of their own ([#174](https://github.com/noisypigeon/library/pull/174))
- [workflows] A release regenerates noisypigeon.garden in runway (LIB-0035) ([#173](https://github.com/noisypigeon/library/pull/173))
- [workflows] Reusable site-generate.yml and site-pages.yml (LIB-0035) ([#172](https://github.com/noisypigeon/library/pull/172))
- [adr] docs(adr): LIB-0035, move garden into runway ([#171](https://github.com/noisypigeon/library/pull/171))
- [adr] docs(adr): record LIB-0034's verification and accept it ([#170](https://github.com/noisypigeon/library/pull/170))
- [workflows] A theme release dispatches pages.yml in noisypigeon/noisypigeon.com (LIB-0034) ([#169](https://github.com/noisypigeon/library/pull/169))
- [workflows] Read each site's Pages shim from values.yaml and write the blog changelog one line per PR ([#167](https://github.com/noisypigeon/library/pull/167))
- [workflows] A site workload's features.githubPages implies its Pages CNAMEs (LIB-0034) ([#168](https://github.com/noisypigeon/library/pull/168))
- [terragrunt/root-hcl] A site workload's features.githubPages implies its Pages CNAMEs (LIB-0034) ([#168](https://github.com/noisypigeon/library/pull/168))
- [adr] docs(adr): LIB-0034, a site workload declares its Pages shim ([#166](https://github.com/noisypigeon/library/pull/166))
- [repo] docs(runbooks): import a hand-written leaf into a workload ([#154](https://github.com/noisypigeon/library/pull/154))
- [adr] docs(adr): record LIB-0030 to LIB-0033's verification and accept them ([#163](https://github.com/noisypigeon/library/pull/163))

## 2026-10-23

- [workflows] resolve-workloads.sh --check accepts a Cloudflare stub's workload token ([#162](https://github.com/noisypigeon/library/pull/162))
- [adr] docs(adr): LIB-0033's bootstrap token also reads zones ([#161](https://github.com/noisypigeon/library/pull/161))
- [terragrunt/root-hcl] A workload's Cloudflare token is minted with the breakglass token (LIB-0033) ([#160](https://github.com/noisypigeon/library/pull/160))
- [workflows] Workloads sign in to Cloudflare with their own token; bootstrap keys only mint (LIB-0033) ([#159](https://github.com/noisypigeon/library/pull/159))
- [terragrunt/root-hcl] Workloads sign in to Cloudflare with their own token; bootstrap keys only mint (LIB-0033) ([#159](https://github.com/noisypigeon/library/pull/159))
- [cloudflare/api-token] Workloads sign in to Cloudflare with their own token; bootstrap keys only mint (LIB-0033) ([#159](https://github.com/noisypigeon/library/pull/159))
- [adr] docs(adr): LIB-0033, self-bootstrapped Cloudflare and Backblaze keys ([#158](https://github.com/noisypigeon/library/pull/158))
- [workflows] Site workloads deploy through a Pages shim repo (LIB-0031) ([#153](https://github.com/noisypigeon/library/pull/153))
- [workflows] Workloads can own Cloudflare zones, records, rulesets and redirects (LIB-0030) ([#152](https://github.com/noisypigeon/library/pull/152))
- [terragrunt/root-hcl] Workloads can own Cloudflare zones, records, rulesets and redirects (LIB-0030) ([#152](https://github.com/noisypigeon/library/pull/152))
- [cloudflare/ruleset] Workloads can own Cloudflare zones, records, rulesets and redirects (LIB-0030) ([#152](https://github.com/noisypigeon/library/pull/152))

## 2026-10-22

- [adr] docs(adr): LIB-0030 to LIB-0032, moving the blog into runway ([#151](https://github.com/noisypigeon/library/pull/151))
- [workflows] Comment-triggered runs check out the PR's head commit from the API ([#146](https://github.com/noisypigeon/library/pull/146))
- [workflows] Workloads can declare Backblaze buckets and API keys (LIB-0029) ([#145](https://github.com/noisypigeon/library/pull/145))
- [terragrunt/root-hcl] Workloads can declare Backblaze buckets and API keys (LIB-0029) ([#145](https://github.com/noisypigeon/library/pull/145))
- [adr] docs(adr): record LIB-0028's verification and accept it ([#144](https://github.com/noisypigeon/library/pull/144))
- [workflows] A workload's state bucket uses the standard storage class (LIB-0028) ([#143](https://github.com/noisypigeon/library/pull/143))
- [terragrunt/root-hcl] A workload's state bucket uses the standard storage class (LIB-0028) ([#143](https://github.com/noisypigeon/library/pull/143))
- [terragrunt/root-hcl] Workload state moves into each workload's own bucket (LIB-0028) ([#142](https://github.com/noisypigeon/library/pull/142))
- [workflows] Every workload gets its own project, deployer and state bucket (LIB-0028) ([#141](https://github.com/noisypigeon/library/pull/141))
- [adr] docs(adr): LIB-0028, every workload gets its own project and state bucket ([#140](https://github.com/noisypigeon/library/pull/140))
- [workflows] Merge a settled automatic re-plan without a last apply (LIB-0027) ([#136](https://github.com/noisypigeon/library/pull/136))
- [adr] Accept LIB-0027, and record LIB-0024's rotation check ([#135](https://github.com/noisypigeon/library/pull/135))
- [workflows] Fix the apply's merge-gate step crashing on getOctokit ([#134](https://github.com/noisypigeon/library/pull/134))
- [workflows] Re-plan staged applies automatically, and merge with the bot token (LIB-0027) ([#133](https://github.com/noisypigeon/library/pull/133))
- [adr] Propose LIB-0027, automatic re-plan and bot-token merge ([#132](https://github.com/noisypigeon/library/pull/132))
- [workflows] Count unchanged leaves instead of listing them in Terragrunt comments ([#129](https://github.com/noisypigeon/library/pull/129))
- [adr] Accept LIB-0026 ([#128](https://github.com/noisypigeon/library/pull/128))
- [workflows] Segment Terragrunt plan and apply comments by leaf, never truncated (LIB-0026) ([#127](https://github.com/noisypigeon/library/pull/127))
- [adr] Propose LIB-0026, plan and apply comments segmented by leaf ([#126](https://github.com/noisypigeon/library/pull/126))

## 2026-10-21

- [adr] Accept LIB-0025 ([#121](https://github.com/noisypigeon/library/pull/121))
- [adr] Record LIB-0023, LIB-0024 and LIB-0025 verification ([#120](https://github.com/noisypigeon/library/pull/120))
- [workflows] Add a workload secrets.yaml in SOPS YAML (LIB-0025) ([#119](https://github.com/noisypigeon/library/pull/119))
- [terragrunt/root-hcl] Add a workload secrets.yaml in SOPS YAML (LIB-0025) ([#119](https://github.com/noisypigeon/library/pull/119))
- [adr] Propose LIB-0025, a workload's secrets.yaml ([#118](https://github.com/noisypigeon/library/pull/118))

## 2026-10-20

- [workflows] Give each workload its own deployer, and stage its applies (LIB-0024) ([#114](https://github.com/noisypigeon/library/pull/114))
- [terragrunt/root-hcl] Give each workload its own deployer, and stage its applies (LIB-0024) ([#114](https://github.com/noisypigeon/library/pull/114))
- [scaleway/terraform-deployer-iam] Rotate the deployer API key every rotation_days ([#113](https://github.com/noisypigeon/library/pull/113))
- [adr] Propose LIB-0024, workload deployers and staged applies ([#112](https://github.com/noisypigeon/library/pull/112))
- [terragrunt/root-hcl] Stop telling spokes to commit workload stubs ([#106](https://github.com/noisypigeon/library/pull/106))
- [workflows] Generate workload stubs in CI and plan removals as destroys (LIB-0023) ([#107](https://github.com/noisypigeon/library/pull/107))
- [adr] Record LIB-0022's Scaleway lock check ([#105](https://github.com/noisypigeon/library/pull/105))
- [terragrunt/root-hcl] Support workload leaves in the root.hcl template (LIB-0023) ([#104](https://github.com/noisypigeon/library/pull/104))
- [workflows] Generate workload stubs and publish module inputs schemas (LIB-0023) ([#103](https://github.com/noisypigeon/library/pull/103))
- [adr] Amend LIB-0023 with what planning the build found ([#102](https://github.com/noisypigeon/library/pull/102))
- [adr] Propose LIB-0023, a workload values.yaml for Scaleway modules ([#101](https://github.com/noisypigeon/library/pull/101))
- [zola-site] Add an optional site banner ([#94](https://github.com/noisypigeon/library/pull/94))
- [workflows] fix(workflows): write changelogs on the newest main, not the merge commit ([#93](https://github.com/noisypigeon/library/pull/93))
- [workflows] feat(workflows): apply only the saved plan, and re-plan on comment (LIB-0022) ([#92](https://github.com/noisypigeon/library/pull/92))
- [terragrunt/root-hcl] feat(root-hcl): lock Terraform state on both backends (LIB-0022) ([#91](https://github.com/noisypigeon/library/pull/91))
- [adr] docs(adr): LIB-0022 re-plan on comment and locked, saved-plan applies ([#90](https://github.com/noisypigeon/library/pull/90))
- [adr] LIB-0020: verification, and the freeze must hold every apply during a state move ([#87](https://github.com/noisypigeon/library/pull/87))
- [adr] docs(adr): LIB-0021 spoke prose is minimal ([#86](https://github.com/noisypigeon/library/pull/86))
- [scaleway/compute-cluster] Rename scaleway/pigeon-cluster to compute-cluster and scaleway/object-bucket to bucket ([#85](https://github.com/noisypigeon/library/pull/85))
- [scaleway/bucket] Rename scaleway/pigeon-cluster to compute-cluster and scaleway/object-bucket to bucket ([#85](https://github.com/noisypigeon/library/pull/85))
- [workflows] Continue a renamed module's version track from its predecessor's last tag ([#84](https://github.com/noisypigeon/library/pull/84))
- [workflows] Add a reusable container image release workflow ([#83](https://github.com/noisypigeon/library/pull/83))

## 2026-10-19

- [workflows] Add pigeon-cli's observability stack and Claude Code plugin ([#82](https://github.com/noisypigeon/library/pull/82))
- [observability/pigeon-cli] Add pigeon-cli's observability stack and Claude Code plugin ([#82](https://github.com/noisypigeon/library/pull/82))
- [grafana-dashboards/pigeon-cli] Add pigeon-cli's observability stack and Claude Code plugin ([#82](https://github.com/noisypigeon/library/pull/82))
- [claude-plugins/pigeon-cli] Add pigeon-cli's observability stack and Claude Code plugin ([#82](https://github.com/noisypigeon/library/pull/82))
- [workflows] Add a reusable Rust crate release workflow ([#81](https://github.com/noisypigeon/library/pull/81))
- [adr] Amend LIB-0001 and LIB-0017 for pigeon-cli's hub alignment (CLI-0161) ([#80](https://github.com/noisypigeon/library/pull/80))
- [scaleway/pigeon-cluster] Take pigeon-cli's keyring shape and repin compute-instance-config to v1.0.0 ([#79](https://github.com/noisypigeon/library/pull/79))
- [scaleway/compute-instance-config] Write secrets into keyring.toml and stop rendering rclone.conf in compute-instance-config ([#78](https://github.com/noisypigeon/library/pull/78))
- [adr] docs(adr): LIB-0018 pigeon instances use pigeon-cli's keyring and rclone config ([#77](https://github.com/noisypigeon/library/pull/77))

## 2026-10-18

- [adr] LIB-0017: spokes don't get their own ADRs ([#76](https://github.com/noisypigeon/library/pull/76))

## 2026-10-17

- [adr] LIB-0016 records the rollout ([#74](https://github.com/noisypigeon/library/pull/74))
- [backblaze/bucket] Add exact_name input to backblaze/bucket ([#73](https://github.com/noisypigeon/library/pull/73))
- [adr] LIB-0016: state bucket names follow the repo names ([#72](https://github.com/noisypigeon/library/pull/72))
- [adr] docs(adr): LIB-0015 records the rollout ([#71](https://github.com/noisypigeon/library/pull/71))
- [workflows] Name the hub noisypigeon/library ([#70](https://github.com/noisypigeon/library/pull/70))
- [terragrunt/root-hcl] Name the hub noisypigeon/library ([#70](https://github.com/noisypigeon/library/pull/70))
- [zola-site] Name the hub noisypigeon/library ([#70](https://github.com/noisypigeon/library/pull/70))
- [adr] docs(adr): LIB-0015 renames noisypigeon/pigeon-lib to library ([#69](https://github.com/noisypigeon/pigeon-lib/pull/69))
- [adr] docs(adr): LIB-0014 records the rollout; runway needs no breakglass ([#68](https://github.com/noisypigeon/pigeon-lib/pull/68))
- [workflows] Add per-leaf breakglass credentials to root.hcl and check-secrets ([#67](https://github.com/noisypigeon/pigeon-lib/pull/67))
- [terragrunt/root-hcl] Add per-leaf breakglass credentials to root.hcl and check-secrets ([#67](https://github.com/noisypigeon/pigeon-lib/pull/67))
- [scaleway/terraform-deployer-iam] Add terraform-deployer-iam: a spoke's deployer application, policy and API key in one module ([#66](https://github.com/noisypigeon/pigeon-lib/pull/66))
- [adr] docs(adr): LIB-0014 moves the deployer IAM to runway behind a breakglass key ([#65](https://github.com/noisypigeon/pigeon-lib/pull/65))
- [adr] docs(adr): LIB-0013 renames noisypigeon/willowgraysen to runway ([#64](https://github.com/noisypigeon/pigeon-lib/pull/64))
- [adr] docs(adr): LIB-0012 records the rollout; LIB-0010 amended ([#63](https://github.com/noisypigeon/pigeon-lib/pull/63))
- [workflows] Split spoke secrets into one sops file per concern ([#62](https://github.com/noisypigeon/pigeon-lib/pull/62))
- [terragrunt/root-hcl] Split spoke secrets into one sops file per concern ([#62](https://github.com/noisypigeon/pigeon-lib/pull/62))
- [adr] docs(adr): LIB-0012 splits spoke secrets into one sops file per concern ([#61](https://github.com/noisypigeon/pigeon-lib/pull/61))
- [adr] docs(adr): LIB-0010 and LIB-0011 record the rollout ([#60](https://github.com/noisypigeon/pigeon-lib/pull/60))

## 2026-10-16

- [workflows] Fixed secret names checked against a schema (root.hcl v3, workflows v2) ([#59](https://github.com/noisypigeon/pigeon-lib/pull/59))
- [terragrunt/root-hcl] Fixed secret names checked against a schema (root.hcl v3, workflows v2) ([#59](https://github.com/noisypigeon/pigeon-lib/pull/59))
- [cloudflare/dns-record] Look Cloudflare zones up by apex in dns-record and add apex-redirect ([#58](https://github.com/noisypigeon/pigeon-lib/pull/58))
- [cloudflare/apex-redirect] Look Cloudflare zones up by apex in dns-record and add apex-redirect ([#58](https://github.com/noisypigeon/pigeon-lib/pull/58))
- [adr] docs(adr): LIB-0010 normalized spoke secrets, LIB-0011 zone lookup and apex-redirect ([#57](https://github.com/noisypigeon/pigeon-lib/pull/57))
- [workflows] Dispatch the blog deploy to noisypigeon/blog ([#56](https://github.com/noisypigeon/pigeon-lib/pull/56))
- [workflows] Drop pigeon.dev from comments and docs ([#55](https://github.com/noisypigeon/pigeon-lib/pull/55))
- [terragrunt/root-hcl] Drop pigeon.dev from comments and docs ([#55](https://github.com/noisypigeon/pigeon-lib/pull/55))
- [scaleway/project] Drop pigeon.dev from comments and docs ([#55](https://github.com/noisypigeon/pigeon-lib/pull/55))
- [adr] docs(adr): LIB-0009 and LIB-0008 record the noisypigeon.garden move ([#54](https://github.com/noisypigeon/pigeon-lib/pull/54))
- [scaleway/project] Use noisypigeon.garden/terraform/ short URLs ([#53](https://github.com/noisypigeon/pigeon-lib/pull/53))
- [scaleway/pigeon-cluster] Use noisypigeon.garden/terraform/ short URLs ([#53](https://github.com/noisypigeon/pigeon-lib/pull/53))
- [workflows] Publish module redirect pages under terraform/ instead of modules/ ([#52](https://github.com/noisypigeon/pigeon-lib/pull/52))
- [workflows] Dispatch the site deploy to noisypigeon/garden ([#51](https://github.com/noisypigeon/pigeon-lib/pull/51))
- [adr] docs(adr): LIB-0009 moves Terraform short URLs to noisypigeon.garden ([#50](https://github.com/noisypigeon/pigeon-lib/pull/50))
- [adr] docs(adr): LIB-0008 records willowgraysen.com's move ([#49](https://github.com/noisypigeon/pigeon-lib/pull/49))
- [adr] LIB-0008: record noisypigeon.com's adoption ([#48](https://github.com/noisypigeon/pigeon-lib/pull/48))
- [terragrunt/root-hcl] Zone leaves at terraform/cloudflare/<zone>/<module>/<instance>/, with their zone ID from the template (LIB-0008) ([#47](https://github.com/noisypigeon/pigeon-lib/pull/47))
- [adr] Add a runbook for restoring Terraform state from B2, and bring LIB-0007 up to date ([#46](https://github.com/noisypigeon/pigeon-lib/pull/46))
- [workflows] Fix state-backup.yml: compare state files by checksum ([#45](https://github.com/noisypigeon/pigeon-lib/pull/45))
- [workflows] Fix state-backup.yml: reach B2 through its S3-compatible API ([#44](https://github.com/noisypigeon/pigeon-lib/pull/44))

## 2026-10-15

- [adr] LIB-0007: state-backup.yml is workflows/v1.5.0 ([#43](https://github.com/noisypigeon/pigeon-lib/pull/43))
- [ci] Correct state-backup.yml's version to workflows/v1.5.0 in LIB-0007 and the changelog ([#42](https://github.com/noisypigeon/pigeon-lib/pull/42))
- [workflows] Stop terragrunt-run.yml running a leaf twice ([#41](https://github.com/noisypigeon/pigeon-lib/pull/41))
- [workflows] Add state-backup.yml: copy R2 Terraform state to a versioned B2 bucket (LIB-0007) ([#40](https://github.com/noisypigeon/pigeon-lib/pull/40))
- [terragrunt/root-hcl] State backend selectable in spoke.hcl: Scaleway or Cloudflare R2 (LIB-0007) ([#39](https://github.com/noisypigeon/pigeon-lib/pull/39))
- [workflows] Regenerate README tables for every module, not a hard-coded list ([#38](https://github.com/noisypigeon/pigeon-lib/pull/38))
- [cloudflare/bucket] Make cloudflare/bucket EU-only, with Standard storage by default (LIB-0006) ([#37](https://github.com/noisypigeon/pigeon-lib/pull/37))
- [terragrunt/root-hcl] Providers enabled and configured in spoke.hcl (LIB-0005) ([#36](https://github.com/noisypigeon/pigeon-lib/pull/36))
- [grafana/dashboard] Move scaleway/grafana-dashboard to grafana/dashboard ([#35](https://github.com/noisypigeon/pigeon-lib/pull/35))
- [cloudflare/bucket] Add cloudflare/bucket, a thin R2 bucket wrapper ([#34](https://github.com/noisypigeon/pigeon-lib/pull/34))
- [adr] Record willowgraysen.com's LIB-0004 adoption and the first leaf splits ([#33](https://github.com/noisypigeon/pigeon-lib/pull/33))
- [terragrunt/root-hcl] A latent Scaleway Cockpit Grafana provider in the root.hcl template ([#32](https://github.com/noisypigeon/pigeon-lib/pull/32))
- [scaleway/grafana-dashboard] grafana-dashboard: dashboards by URL, and an optional first-access hook ([#31](https://github.com/noisypigeon/pigeon-lib/pull/31))
- [cloudflare/ruleset] Add cloudflare/ruleset, a thin wrapper over cloudflare_ruleset ([#30](https://github.com/noisypigeon/pigeon-lib/pull/30))
- [grafana-dashboards/pigeon-cli] Add the pigeon-cli Grafana dashboard set ([#29](https://github.com/noisypigeon/pigeon-lib/pull/29))
- [workflows] Add a grafana-dashboards/<set>/vX.Y.Z release track ([#28](https://github.com/noisypigeon/pigeon-lib/pull/28))
- [adr] docs(lib-0004): record noisypigeon.com's adoption ([#27](https://github.com/noisypigeon/pigeon-lib/pull/27))
- [adr] docs(lib-0004): record pigeon.dev's adoption and link the fast follows ([#26](https://github.com/noisypigeon/pigeon-lib/pull/26))
- [workflows] Generate README tables for cloudflare/dns-record ([#25](https://github.com/noisypigeon/pigeon-lib/pull/25))
- [cloudflare/dns-record] Add cloudflare/dns-record, a thin wrapper over cloudflare_dns_record ([#24](https://github.com/noisypigeon/pigeon-lib/pull/24))
- [adr] docs(lib-0004): normalize the Terraform leaf layout ([#23](https://github.com/noisypigeon/pigeon-lib/pull/23))
- [adr] docs(lib-0001): record step 5's completion and the RUN- domain ([#22](https://github.com/noisypigeon/pigeon-lib/pull/22))
- [terragrunt/root-hcl] Optional extra providers and Backblaze support in the root.hcl template ([#21](https://github.com/noisypigeon/pigeon-lib/pull/21))
- [adr] docs(lib-0001): record step 4's completion in the amendments ([#20](https://github.com/noisypigeon/pigeon-lib/pull/20))
- [adr] docs(lib-0001): amend where the implementation deviated ([#19](https://github.com/noisypigeon/pigeon-lib/pull/19))
- [terragrunt/root-hcl] Mark the root.hcl template as generated and committed in spokes ([#18](https://github.com/noisypigeon/pigeon-lib/pull/18))
- [workflows] Add a --check mode to resolve-root-hcl.sh ([#17](https://github.com/noisypigeon/pigeon-lib/pull/17))
- [terragrunt/root-hcl] Add the spokes' Terragrunt root.hcl template ([#16](https://github.com/noisypigeon/pigeon-lib/pull/16))
- [workflows] Let a spoke run terragrunt CI against a materialized root.hcl ([#15](https://github.com/noisypigeon/pigeon-lib/pull/15))
- [workflows] Add a reusable spoke-root-changelog.yml ([#14](https://github.com/noisypigeon/pigeon-lib/pull/14))
- [workflows] Let blog-changelog.yml take a site root via src_dir ([#13](https://github.com/noisypigeon/pigeon-lib/pull/13))
- [workflows] Read release notes from the default branch, not the pinned tree ([#12](https://github.com/noisypigeon/pigeon-lib/pull/12))
- [scaleway/project] Note why the ssh key uses count, not for_each ([#11](https://github.com/noisypigeon/pigeon-lib/pull/11))
- [workflows] Stop the shared concurrency group dropping a release ([#10](https://github.com/noisypigeon/pigeon-lib/pull/10))
- [workflows] The Pages deploy timeout ceiling is hard, not a default ([#8](https://github.com/noisypigeon/pigeon-lib/pull/8))
- [workflows] Raise the Pages deploy timeout to 20 minutes ([#7](https://github.com/noisypigeon/pigeon-lib/pull/7))

## 2026-10-14

- [workflows] Follow pigeon.dev's DEV- prefix rename ([#6](https://github.com/noisypigeon/pigeon-lib/pull/6))

## 2026-10-13

- [workflows] Version the generator with the workflows track ([#5](https://github.com/noisypigeon/pigeon-lib/pull/5))
- [adr] Host the module-redirect generator, and file LIB-0002 ([#4](https://github.com/noisypigeon/pigeon-lib/pull/4))
- [workflows] Stand down root-changelog for the workflows release track ([#3](https://github.com/noisypigeon/pigeon-lib/pull/3))
- [ci] Version the reusable CI as a third release track ([#2](https://github.com/noisypigeon/pigeon-lib/pull/2))
- [repo] Give pigeon-lib its CLAUDE.md, README.md, CHANGELOG.md, .mise.toml and .gitignore ([#1](https://github.com/noisypigeon/pigeon-lib/pull/1))
