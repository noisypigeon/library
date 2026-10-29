#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl).
# Turns each unit file into the stub leaves LIB-0023 §5 describes, one per
# kind instance, at <unit>/<provider>/<module>/<instance>/terragrunt.hcl. A
# unit is a workload, workloads/<zone>/<workload>/workload.yaml with
# secrets.workload.yaml beside it, or with no zone
# workloads/private/<workload>/ (LIB-0037), or a zone, zones/<zone>/zone.yaml
# (LIB-0036).
#
# A stub holds structure only: it includes root.hcl, declares the dependency
# blocks its kind implies (§4's wiring), and passes their IDs on as inputs.
# Every unit has a project, a deployer and a state bucket, whatever its file
# declares (LIB-0028 §1). The deployer is three leaves at the instance
# `deployer`: an IAM application, its policy and its API key (LIB-0038 §1).
# A stub whose state lives in the state bucket (LIB-0028 §4) also declares
# its own remote_state, which replaces root.hcl's: the bucket comes from its
# state dependency, and it signs in with the deployer's API key (LIB-0028
# §5).
# Backblaze kinds (LIB-0029) sign in with the workload's own Backblaze key,
# backblaze/api-key/deployer, which any workload declaring one has
# (LIB-0041), and keep their state in that same workload bucket. An API key
# depends on each bucket its `buckets` list names, and gets their IDs as
# bucket_ids.
# Cloudflare kinds (LIB-0030) sign in with the unit's own Cloudflare token,
# cloudflare/api-token/deployer (LIB-0033 §4). A zone always has one; a
# workload has one when its zone's `hosts` gives it a host, or when it
# declares an R2 bucket (LIB-0037 §3).
# A zone takes only zone kinds: its records and rulesets, on its own zone.
# Its cloudflare.apexRedirect is a shorthand that expand_zone turns into a
# ruleset and its placeholder records (LIB-0038 §3). A workload in it writes
# records only at its host, and its deployments.githubPages implies its
# Pages CNAMEs (LIB-0037 §§3-4). The clash checks below run across every
# unit, so a zone's file and its workloads' are checked together.
# A unit file holds its content under one key, `zone` or `workload`, with
# its records at `dnsRecords` directly under it (LIB-0039); unwrap reads it
# into the shape below, records at cloudflare.dnsRecord, and relabel names
# them back in messages. A zone's `services` each imply their provider's
# records (service_dns), beside apexRedirect's.
# A zoned workload has no project of its own unless
# deployments.scaleway.project names one, and its deployer and state bucket
# then depend on the zone's project (LIB-0037 §2).
# A workload may also declare compute (LIB-0043): IAM policies and API keys
# on its one application, block volumes, Cockpit, a Private Network, a Public
# Gateway that turns on and off on its own, and instances. expand_compute
# turns each instance into its compute-instance and compute-instance-config
# leaves, a self-deleting one's own application, policy and key, and its
# sshViaGateway's PAT rule, and compute_problems refuses what can't work:
# above all an instance with no way out, and, with the gateway off, any
# instance that doesn't set network.publicIpv4: true itself.
# The old layout is refused (LIB-0037 §6): a workloads/<w>/values.yaml, a
# secrets.yaml, zone.yaml's `workload`, `features`, and a workload's
# cloudflare.zone. So are the retired kinds' keys (LIB-0038): a module input
# directly under scaleway.deployer, and anything but the four shorthand
# inputs under an apexRedirect entry. A root zones.yaml is refused
# (LIB-0036 §1).
# Values, defaults and the module version are root.hcl's, at plan time: it
# writes them into the leaf's generated module block as literals, since a
# `type = any` variable set through TF_VAR_ arrives as a string.
#
# Dependencies carry no mock_outputs (LIB-0023's 2026-10-20 amendment, item
# 3): apply runs the saved plan (LIB-0022), and a mock baked into one would be
# applied. A dependent plans once its dependencies are applied.
#
# The stubs are generated, never committed: a unit commits only its file. The
# spoke gitignores them by provider, /workloads/*/*/scaleway/,
# /zones/*/scaleway/ and the like, never /workloads/*/*/*/, which would hide a
# site's content/ too. A spoke's terraform-prepare task runs this before
# terragrunt, and terragrunt-run.yml runs it in CI. Terragrunt's [main...HEAD]
# filter plans in worktrees holding only tracked files, so it can't see a stub;
# terragrunt-run.yml selects unit leaves by their unit file instead, and
# plans the destroy of an instance the file no longer has from stubs this
# script generates in a worktree of the base.
#
# Without a flag, the script (re)writes every stub and removes the ones no
# unit file implies any more -- only files carrying the GENERATED header
# below, so a hand-written file under workloads/ is never deleted.
#
# --list writes nothing and prints each stub directory the unit files imply,
# one per line, for terragrunt-run.yml to compare a base with its head.
#
# --check writes nothing. It exits 1 if a unit file is malformed, if any input
# in it isn't one of its module's inputs at the version it resolves to, read
# from that version's published inputs.schema.json (LIB-0023 §6), and if any
# stub is tracked by git. Types are left to terraform plan.
#
# It also checks a workload's secrets.workload.yaml (LIB-0025 §2) without
# decrypting it: sops YAML encrypts values and keeps keys in clear. It fails on
# a file without sops metadata or with a plaintext value, on keys other than
# `env` and the kind paths, on a kind path workload.yaml doesn't declare, on
# an input set in both files, and on a `secretRef` to a name `env` doesn't
# have.
#
# The kind table below has a twin in terragrunt/root-hcl/root.hcl
# (workload_kinds) and a third copy in generate-module-redirects.sh
# (workload and zone schemas). Change one and change all three.
#
# Environment, for tests:
#   LIB_TAG_REMOTE        where module tags are listed (default: the library on GitHub)
#   WORKLOAD_SCHEMA_BASE  where inputs.schema.json is fetched (default: https://noisypigeon.garden)
set -euo pipefail

CHECK=false
LIST=false
case "${1:-}" in
  --check) CHECK=true ;;
  --list) LIST=true ;;
  "") ;;
  *) echo "usage: $0 [--check | --list]" >&2; exit 2 ;;
esac

SPOKE_DIR="$(pwd)"
TAG_REMOTE="${LIB_TAG_REMOTE:-https://github.com/noisypigeon/library}"
SCHEMA_BASE="${WORKLOAD_SCHEMA_BASE:-https://noisypigeon.garden}"
HEADER="# GENERATED by resolve-workloads.sh from values.yaml (LIB-0023) -- do not edit."

if [ ! -f "$SPOKE_DIR/spoke.hcl" ]; then
  echo "::error::No spoke.hcl in $SPOKE_DIR; run this from the spoke's repo root" >&2
  exit 1
fi
for tool in yq jq; do
  if ! command -v "$tool" >/dev/null; then
    echo "::error::resolve-workloads.sh needs $tool on PATH" >&2
    exit 1
  fi
done

# YAML path | module | shape | dependencies | credentials | state | units. The
# twin of root.hcl's workload_kinds; see the header.
#
# - shape: a singleton's instance is `main`, a map's is each key, an
#   implicit kind's is `main` in every unit, with or without an entry
#   (LIB-0028 §1), `deployer` is one of the unit's three deployer leaves,
#   whose instance is `deployer` in every unit (LIB-0038 §1), and `state` is
#   the unit's state bucket, whose instance is `state` (LIB-0028 §2), and
#   `cfimplicit` is the unit's Cloudflare token, whose instance is `deployer`,
#   present when the workload has a host or declares an R2 bucket (LIB-0037
#   §3), and always present in a zone. `b2implicit` is the workload's
#   Backblaze key, whose instance is `deployer`, present when it declares a
#   Backblaze bucket or key (LIB-0041 §1).
# - credentials (LIB-0024 §2): `spoke` kinds sign in with the spoke's key;
#   `workload` kinds with their provider's workload credential, which they
#   then also depend on: a Scaleway kind the deployer's API key, a Cloudflare
#   kind the workload's token, cf_token (LIB-0033 §4), a Backblaze kind the
#   workload's key, b2_key (LIB-0041 §2).
# - state (LIB-0028 §4): `spoke` kinds keep state in the spoke's bucket;
#   `workload` kinds in the workload's, so they also depend on the state
#   bucket and on the deployer whose key signs in to it.
# - `buckets` (LIB-0029 §3) stands for one bucket_<key> dependency per entry
#   in the instance's own `buckets` list, resolved per instance.
# - `config_deps` and `instance_deps` (LIB-0043 §1) stand for an instance's
#   own dependencies, resolved per instance from expand_compute's _meta: its
#   keyring's API keys and buckets, Cockpit and self-delete key for its
#   config; its config, volumes, Private Network and, when the gateway is its
#   only way out, the gateway for its server. A `scaleway._implied` path is
#   expand_compute's, never the file's.
# - units (LIB-0036): `w` if only a workload takes the kind, `z` if only a
#   zone does, `wz` if both do.
KINDS=(
  "scaleway.project|scaleway/project|implicit||spoke|spoke|wz"
  "scaleway.deployer.application|scaleway/iam-application|deployer||spoke|spoke|wz"
  "scaleway.deployer.policy|scaleway/iam-policy|deployer|project deployer_application|spoke|spoke|wz"
  "scaleway.deployer.apiKey|scaleway/iam-api-key|deployer|project deployer_application|spoke|spoke|wz"
  "scaleway.state|scaleway/bucket|state|project|workload|spoke|wz"
  "scaleway.iam.application|scaleway/iam-application|singleton||spoke|workload|w"
  "scaleway.bucket|scaleway/bucket|map|project|workload|workload|w"
  "scaleway.iam.apiKey|scaleway/iam-api-key|map|project application|spoke|workload|w"
  "scaleway.iam.policy|scaleway/iam-policy|map|project application|spoke|workload|w"
  "scaleway._implied.selfDeleteApplication|scaleway/iam-application|map||spoke|workload|w"
  "scaleway._implied.selfDeletePolicy|scaleway/iam-policy|map|project sd_application|spoke|workload|w"
  "scaleway._implied.selfDeleteApiKey|scaleway/iam-api-key|map|project sd_application|spoke|workload|w"
  "scaleway.blockVolume|scaleway/block-volume|map|project|workload|workload|w"
  "scaleway.cockpit|scaleway/cockpit-observability|singleton|project|workload|workload|w"
  "scaleway.privateNetwork|scaleway/private-network|singleton|project|workload|workload|w"
  "scaleway.publicGateway|scaleway/public-gateway|singleton|project private_network|workload|workload|w"
  "scaleway._implied.instanceConfig|scaleway/compute-instance-config|map|config_deps|workload|workload|w"
  "scaleway.instance|scaleway/compute-instance|map|project instance_deps|workload|workload|w"
  "scaleway._implied.patRule|scaleway/gateway-pat-rule|map|gateway instance|workload|workload|w"
  "backblaze.deployer|backblaze/api-key|b2implicit||spoke|workload|w"
  "backblaze.bucket|backblaze/bucket|map||workload|workload|w"
  "backblaze.apiKey|backblaze/api-key|map|buckets|workload|workload|w"
  "cloudflare.deployer|cloudflare/api-token|cfimplicit||spoke|workload|wz"
  "cloudflare.bucket|cloudflare/bucket|map||workload|workload|w"
  "cloudflare.dnsRecord|cloudflare/dns-record|map||workload|workload|wz"
  "cloudflare.ruleset|cloudflare/ruleset|map||workload|workload|z"
)

# A dependency's stub, relative to its workload directory, so a Backblaze
# stub reaches the Scaleway state bucket too (LIB-0029). bucket_<key> is a
# Backblaze bucket, its key's dashes written as underscores.
dep_dir() {
  case "$1" in
    project)
      # A workload in its zone's project (LIB-0037 §2) takes the zone's.
      if [ -n "$ZONE_PROJECT" ]; then echo "../../../zones/$ZONE_PROJECT/scaleway/project/main"; else echo "scaleway/project/main"; fi
      ;;
    application) echo "scaleway/iam-application/main" ;;
    deployer_application) echo "scaleway/iam-application/deployer" ;;
    deployer) echo "scaleway/iam-api-key/deployer" ;;
    state) echo "scaleway/bucket/state" ;;
    cf_token) echo "cloudflare/api-token/deployer" ;;
    b2_key) echo "backblaze/api-key/deployer" ;;
    bucket_*) echo "backblaze/bucket/$(echo "${1#bucket_}" | tr _ -)" ;;
    # LIB-0043: a Scaleway bucket, block volume or API key by its key, and
    # the leaves an instance's name gives, CUR_NAME being the stub's instance.
    sbucket_*) echo "scaleway/bucket/$(echo "${1#sbucket_}" | tr _ -)" ;;
    volume_*) echo "scaleway/block-volume/$(echo "${1#volume_}" | tr _ -)" ;;
    apikey_*) echo "scaleway/iam-api-key/$(echo "${1#apikey_}" | tr _ -)" ;;
    sd_application) echo "scaleway/iam-application/$CUR_NAME" ;;
    sd_key) echo "scaleway/iam-api-key/self-delete-$CUR_NAME" ;;
    private_network) echo "scaleway/private-network/main" ;;
    gateway) echo "scaleway/public-gateway/main" ;;
    cockpit) echo "scaleway/cockpit-observability/main" ;;
    config) echo "scaleway/compute-instance-config/$CUR_NAME" ;;
    instance) echo "scaleway/compute-instance/$CUR_NAME" ;;
  esac
}

# The inputs a dependency fills (LIB-0023 §4, LIB-0024 §§1-2), one
# "<input>|<expression>" per line, for a kind with the given credentials.
# scaleway_access_key and scaleway_secret_key aren't module inputs: root.hcl
# signs the leaf's provider in with them. A spoke-credentials kind can depend
# on the deployer too, for its backend alone (LIB-0028 §5), and the state
# dependency fills no input: both feed the stub's remote_state instead.
wiring_lines() {
  case "$1:$2" in
    scaleway/bucket:project) echo "project_id|dependency.project.outputs.module.id" ;;
    scaleway/iam-api-key:project) echo "default_project_id|dependency.project.outputs.module.id" ;;
    scaleway/iam-api-key:application) echo "application_id|dependency.application.outputs.module.id" ;;
    scaleway/iam-policy:project) echo "project_ids|[dependency.project.outputs.module.id]" ;;
    scaleway/iam-policy:deployer_application | scaleway/iam-api-key:deployer_application) echo "application_id|dependency.deployer_application.outputs.module.id" ;;
    # LIB-0043 §1.
    scaleway/iam-policy:application) echo "application_id|dependency.application.outputs.module.id" ;;
    scaleway/iam-policy:sd_application | scaleway/iam-api-key:sd_application) echo "application_id|dependency.sd_application.outputs.module.id" ;;
    scaleway/block-volume:project | scaleway/cockpit-observability:project | scaleway/private-network:project | scaleway/public-gateway:project | scaleway/compute-instance:project) echo "project_id|dependency.project.outputs.module.id" ;;
    scaleway/public-gateway:private_network | scaleway/compute-instance:private_network) echo "private_network_id|dependency.private_network.outputs.module.id" ;;
    scaleway/compute-instance:config) echo "cloud_init|dependency.config.outputs.module.cloud_init" ;;
    scaleway/compute-instance-config:cockpit) echo "cockpit|{ metrics_push_url = dependency.cockpit.outputs.module.metrics_push_url, logs_push_url = dependency.cockpit.outputs.module.logs_push_url, token_secret = dependency.cockpit.outputs.module.token_secret }" ;;
    scaleway/compute-instance-config:sd_key) echo "self_delete_credentials|{ access_key = dependency.sd_key.outputs.module.access_key, secret_key = dependency.sd_key.outputs.module.secret_key, project_id = dependency.project.outputs.module.id }" ;;
    scaleway/gateway-pat-rule:gateway) echo "gateway_id|dependency.gateway.outputs.module.id" ;;
    scaleway/gateway-pat-rule:instance) echo "private_ip|dependency.instance.outputs.module.private_ipv4" ;;
    cloudflare/*:cf_token) echo "cloudflare_api_token|dependency.cf_token.outputs.module.token" ;;
    backblaze/*:b2_key)
      echo "backblaze_application_key_id|dependency.b2_key.outputs.module.application_key_id"
      echo "backblaze_application_key|dependency.b2_key.outputs.module.application_key"
      ;;
    scaleway/*:deployer)
      if [ "$3" = workload ]; then
        echo "scaleway_access_key|dependency.deployer.outputs.module.access_key"
        echo "scaleway_secret_key|dependency.deployer.outputs.module.secret_key"
      fi
      ;;
  esac
}

# Whether this workload has a dependency: its YAML key for a declared kind,
# or nothing for an implicit one, which every workload has.
dep_yaml_path() {
  case "$1" in
    application) echo "scaleway.iam.application" ;;
  esac
}

KEBAB='^[a-z0-9]+(-[a-z0-9]+)*$'
errors=0
fail() { echo "::error::$*" >&2; errors=$((errors + 1)); }

# A unit file's shape (LIB-0039): its content under one key, `zone` or
# `workload`, with `dnsRecords` directly under it. Each check below reads the
# file unwrapped, with dnsRecords at cloudflare.dnsRecord, the path the kind
# table and root.hcl use. Since v8.0.0 an unwrapped file is refused
# (LIB-0039 §4). root.hcl's workload_raw is unwrap's twin.
# shape_problems names what a file can't say about its shape; services,
# services_problems and service_dns are LIB-0039 §3's services, whose twin
# is root.hcl's workload_cf_service_dns.
# shellcheck disable=SC2016 # a jq program, expanded by jq
UNIT_JQ='
  def unwrap($w):
    if type == "object" and has($w) then .[$w] |
      if type == "object" and has("dnsRecords") then .dnsRecords as $d | del(.dnsRecords)
        | .cloudflare = ((.cloudflare // {}) | if type == "object" then . + {dnsRecord: $d} else . end)
      else . end
    else . end;
  def shape_problems($w):
    if type != "object" then empty
    elif has($w) then
      ((keys - [$w])[] | "\(.) sits beside \($w); everything goes under \($w) (LIB-0039 §1)"),
      (.[$w] | if type != "object" then "\($w) must be a mapping (LIB-0039 §1)" else
        (.cloudflare // {} | objects | select(has("dnsRecord")) | "\($w).cloudflare.dnsRecord moves to \($w).dnsRecords (LIB-0039 §2)"),
        (if $w == "workload" and has("services") then "services is a zone'"'"'s alone; declare a workload'"'"'s records in workload.dnsRecords (LIB-0039 §3)" else empty end)
      end)
    else "everything goes under one key, \($w); move every key of the file under it (LIB-0039 §§1, 4)"
    end;
  def services_known: {proton: ["enabled", "verification", "dmarc"], fastmail: ["enabled", "dmarc"], googleSearch: ["enabled", "verification"], bluesky: ["enabled", "did"]};
  def services_problems:
    (.services // {}) as $s |
    if ($s | type) != "object" then "services must be a mapping of service names (LIB-0039 §3)" else
      ($s | to_entries[] | .key as $n | .value as $v |
        if (services_known | has($n) | not) then "services.\($n) isn'"'"'t a service; known: \(services_known | keys_unsorted | join(", ")) (LIB-0039 §3)"
        elif ($v | type) != "object" then "services.\($n) must be a mapping (LIB-0039 §3)"
        else
          services_known[$n] as $allowed |
          ((($v | keys) - $allowed)[] | "services.\($n).\(.) isn'"'"'t one of \($allowed | join(", ")) (LIB-0039 §3)"),
          (if ($v | has("enabled")) and (($v.enabled | type) != "boolean") then "services.\($n).enabled must be true or false (LIB-0039 §3)" else empty end),
          (if ($v | has("dmarc")) and (($v.dmarc | type) != "boolean") and (($v.dmarc | type) != "string" or ($v.dmarc | startswith("v=DMARC1") | not)) then "services.\($n).dmarc must be true, false or a DMARC policy (LIB-0039 §3)" else empty end),
          (if $v.enabled != true then empty
           elif $n == "proton" then
             (if ($v.verification | type) != "object" then "services.proton.verification must hold pm and protonmail (LIB-0039 §3)"
              else
                ((($v.verification | keys) - ["pm", "protonmail"])[] | "services.proton.verification.\(.) isn'"'"'t one of pm, protonmail (LIB-0039 §3)"),
                (("pm", "protonmail") as $r | select(($v.verification[$r] | type) != "string" or $v.verification[$r] == "") | "services.proton.verification.\($r) must be a non-empty string (LIB-0039 §3)")
              end)
           elif $n == "googleSearch" then
             (if ($v.verification | type) != "string" or $v.verification == "" then "services.googleSearch.verification must be a non-empty string (LIB-0039 §3)" else empty end)
           elif $n == "bluesky" then
             (if ($v.did | type) != "string" or $v.did == "" then "services.bluesky.did must be a non-empty string (LIB-0039 §3)" else empty end)
           else empty end)
        end),
      (if ($s.proton | objects | .enabled) == true and ($s.fastmail | objects | .enabled) == true then "services.proton and services.fastmail are both enabled, and both claim MX and SPF at @; enable one (LIB-0039 §3)" else empty end)
    end;
  def service_on($s; $n): ($s | type) == "object" and ($s[$n] | type) == "object" and $s[$n].enabled == true;
  def service_dmarc($s; $n):
    (if ($s[$n] | has("dmarc")) then $s[$n].dmarc else true end) as $d |
    if $d == false then null elif ($d | type) == "string" then $d else "v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s" end;
  def service_dns($z):
    (.services // {}) as $s |
    (if service_on($s; "proton") then {
      "proton-mx-primary": {name: "@", type: "MX", content: "mx1.alias.proton.me", priority: 10, ttl: 1, comment: "proton primary mx"},
      "proton-mx-secondary": {name: "@", type: "MX", content: "mx2.alias.proton.me", priority: 20, ttl: 1, comment: "proton secondary mx"},
      "proton-dkim-primary": {name: "dkim._domainkey", type: "CNAME", content: "dkim._domainkey.alias.proton.me", ttl: 1, proxied: false, comment: "proton primary dkim"},
      "proton-dkim-secondary": {name: "dkim02._domainkey", type: "CNAME", content: "dkim02._domainkey.alias.proton.me", ttl: 1, proxied: false, comment: "proton secondary dkim"},
      "proton-dkim-tertiary": {name: "dkim03._domainkey", type: "CNAME", content: "dkim03._domainkey.alias.proton.me", ttl: 1, proxied: false, comment: "proton tertiary dkim"},
      "proton-spf": {name: "@", type: "TXT", content: "v=spf1 include:alias.proton.me ~all", ttl: 1, comment: "proton spf"},
      "proton-pm-verification": {name: "@", type: "TXT", content: "pm-verification=\($s.proton.verification.pm)", ttl: 1, comment: "proton pm verification"},
      "proton-protonmail-verification": {name: "@", type: "TXT", content: "protonmail-verification=\($s.proton.verification.protonmail)", ttl: 1, comment: "proton protonmail verification"}
    } + (service_dmarc($s; "proton") | if . == null then {} else {"proton-dmarc": {name: "_dmarc", type: "TXT", content: ., ttl: 1, comment: "proton dmarc"}} end) else {} end)
    + (if service_on($s; "fastmail") then {
      "fastmail-mx-primary": {name: "@", type: "MX", content: "in1-smtp.messagingengine.com", priority: 10, ttl: 1, comment: "fastmail primary mx"},
      "fastmail-mx-secondary": {name: "@", type: "MX", content: "in2-smtp.messagingengine.com", priority: 20, ttl: 1, comment: "fastmail secondary mx"},
      "fastmail-dkim-fm1": {name: "fm1._domainkey", type: "CNAME", content: "fm1.\($z).dkim.fmhosted.com", ttl: 1, proxied: false, comment: "fastmail primary dkim"},
      "fastmail-dkim-fm2": {name: "fm2._domainkey", type: "CNAME", content: "fm2.\($z).dkim.fmhosted.com", ttl: 1, proxied: false, comment: "fastmail secondary dkim"},
      "fastmail-dkim-fm3": {name: "fm3._domainkey", type: "CNAME", content: "fm3.\($z).dkim.fmhosted.com", ttl: 1, proxied: false, comment: "fastmail tertiary dkim"},
      "fastmail-spf": {name: "@", type: "TXT", content: "\"v=spf1 include:spf.messagingengine.com ?all\"", ttl: 1, comment: "fastmail spf"}
    } + (service_dmarc($s; "fastmail") | if . == null then {} else {"fastmail-dmarc": {name: "_dmarc", type: "TXT", content: ., ttl: 1, comment: "fastmail dmarc"}} end) else {} end)
    + (if service_on($s; "googleSearch") then {
      "googlesearch-site-verification": {name: "@", type: "TXT", content: "\"google-site-verification=\($s.googleSearch.verification)\"", ttl: 1, comment: "google search site verification"}
    } else {} end)
    + (if service_on($s; "bluesky") then {
      "bluesky-did": {name: "_atproto", type: "TXT", content: "did=\($s.bluesky.did)", ttl: 1, comment: "bluesky domain handle"}
    } else {} end);
'

# A workload's compute (LIB-0043), read from its unwrapped file. on() is
# whether a network singleton is declared and not enabled: false.
# compute_problems($env; $kebab) names what can't work, with a line starting
# "warning: " for what only might not; expand_compute turns each instance
# into its leaves' entries under scaleway._implied, and keeps what the stubs
# need under scaleway._meta. root.hcl's wc_* locals are their twin.
# shellcheck disable=SC2016 # a jq program, expanded by jq
COMPUTE_JQ='
  def is_ref: type == "object" and keys == ["secretRef"] and (.secretRef | type) == "string";
  def on($s; $k): ($s | type) == "object" and ($s | has($k)) and ($s[$k] | if type == "object" then .enabled else null end) != false;
  def passthrough: ["type", "image", "enabled", "ssh_key", "version", "name_prefix", "name_suffix"];
  def interface: ["network", "volumes", "cockpit", "transcoding", "selfDelete", "commands", "keyring"];
  def wired: ["project_id", "cloud_init", "additional_volume_ids", "private_network_id", "enable_private_network", "public_ipv4", "ip_ids"];
  def alias_refs: [scan("\\$\\{keyring(?:\\.([a-z0-9-]+)|\\[\"([a-z0-9-]+)\"\\])\\.alias\\}")[] | select(. != null)];
  def keyring_problems($p; $refs; $apikeys; $buckets):
    if type != "object" then "\($p) must be a mapping of alias to entry (LIB-0043 §4)" else
    to_entries[] | .key as $a | .value as $e | "\($p).\($a)" as $w |
    (if ($a | test("^[a-z0-9][a-z0-9-]*[a-z0-9]$")) then empty else "\($w): an alias is lowercase alphanumeric with hyphens (LIB-0043 §4)" end),
    (if ($e | type) != "object" then "\($w) must be a mapping (LIB-0043 §4)"
     elif ($e.kind | IN("email", "bucket") | not) then "\($w).kind must be email or bucket (LIB-0043 §4)"
     else
       (if $e.kind == "email" then ["kind", "email", "provider", "host", "port", "secret", "max_imap_connections"] else ["kind", "endpoint", "bucket", "access_key_id", "secret_key", "apiKey"] end) as $allowed |
       ((($e | keys) - $allowed)[] | "\($w).\(.) isn'"'"'t a field of a \($e.kind) entry; known: \($allowed | join(", ")) (LIB-0043 §4)"),
       ($e | to_entries[] | select(.key | IN("kind", "port", "max_imap_connections", "apiKey") | not) | .key as $f | .value |
         if type == "string" then empty
         elif is_ref then (.secretRef as $r | if ($refs | index($r)) == null then "\($w).\($f): secretRef \(.secretRef) isn'"'"'t in secrets.workload.yaml'"'"'s env (LIB-0025, LIB-0043 §4)" else empty end)
         else "\($w).\($f) must be a string or a secretRef (LIB-0043 §4)" end),
       (if $e.kind == "email" then
          (("email", "provider", "host", "port", "secret") as $r | select($e | has($r) | not) | "\($w) needs \($r): an email entry has email, provider, host, port and secret (LIB-0043 §6)"),
          (if ($e.provider | type) == "string" and ($e.provider | IN("gmail", "fastmail", "icloud", "proton", "custom") | not) then "\($w).provider must be one of gmail, fastmail, icloud, proton, custom (LIB-0043 §6)" else empty end),
          (if $e | has("port") and (($e.port | type) != "number") then "\($w).port must be a number (LIB-0043 §6)" else empty end)
        else
          (if $e | has("bucket") | not then "\($w) needs bucket: a scaleway.bucket key, or the name of a bucket outside the workload (LIB-0043 §4)" else empty end),
          (if ($e | has("apiKey")) and (($e | has("access_key_id")) or ($e | has("secret_key"))) then "\($w) takes apiKey, or both access_key_id and secret_key, never both (LIB-0043 §4)"
           elif ($e | has("apiKey") | not) and (($e | has("access_key_id") | not) or ($e | has("secret_key") | not)) then "\($w) needs its credentials: apiKey, or both access_key_id and secret_key (LIB-0043 §4)"
           else empty end),
          (if ($e | has("apiKey")) and ((($e.apiKey | type) != "string") or ($apikeys | has($e.apiKey) | not)) then "\($w).apiKey must name one of scaleway.iam.apiKey'"'"'s keys (LIB-0043 §6)" else empty end),
          (if (($e.bucket | type) == "string" and ($buckets | has($e.bucket))) or ($e | has("endpoint")) then empty else "\($w): bucket \($e.bucket | tojson) isn'"'"'t a scaleway.bucket key, so it needs endpoint (LIB-0043 §4)" end)
        end)
     end)
    end;
  def compute_problems($env; $kebab):
    (.scaleway // {} | if type == "object" then . else {} end) as $s |
    on($s; "privateNetwork") as $pn | on($s; "publicGateway") as $gw |
    ($s.iam // {} | if type == "object" then . else {} end) as $iam |
    ($iam.apiKey // {} | if type == "object" then . else {} end) as $keys |
    ($iam.policy // {} | if type == "object" then . else {} end) as $policies |
    ($s.bucket // {} | if type == "object" then . else {} end) as $buckets |
    ($s.blockVolume // {} | if type == "object" then . else {} end) as $vols |
    ($s | has("cockpit")) as $cockpit |
    ($s.instance // {} | if type == "object" then . else {} end) as $inst |
    ($s.sharedKeyring // {} | if type == "object" then . else {} end) as $shared |
    # IAM (LIB-0043 §§1, 6).
    (("policy", "apiKey") as $m | $iam[$m] // {} |
      if type != "object" then "scaleway.iam.\($m) must be a mapping of \(if $m == "policy" then "policy" else "key" end) names (LIB-0043 §1)" else
      to_entries[] | .key as $k | .value as $e |
        (if ($k | test($kebab)) then empty else "scaleway.iam.\($m).\($k): name must be kebab-case" end),
        (if $k == "deployer" or ($k | startswith("self-delete-")) then "scaleway.iam.\($m).\($k): deployer and self-delete-* are the implied leaves'"'"' (LIB-0043 §1)" else empty end),
        (if $e == null or ($e | type) == "object" then empty
         elif $m == "apiKey" then "scaleway.iam.apiKey is a mapping of key names since workflows/v9.0.0; move a single key'"'"'s inputs under a name of its own, e.g. scaleway.iam.apiKey.main (LIB-0043 §1)"
         else "scaleway.iam.policy.\($k) must be a mapping of module inputs" end),
        ($e | objects | ((if $m == "policy" then ["application_id", "project_ids"] else ["application_id", "default_project_id"] end)[]) as $i | select(has($i)) | "scaleway.iam.\($m).\($k).\($i) can'"'"'t be set; it'"'"'s wired from the workload (LIB-0043 §1)")
      end),
    (if (($policies | length) + ($keys | length)) > 0 and ($iam | has("application") | not) then "scaleway.iam.policy and scaleway.iam.apiKey hang off scaleway.iam.application, which this workload doesn'"'"'t declare (LIB-0043 §6)" else empty end),
    ($policies | to_entries[] | select(.value | objects | (.project_permission_sets // []) + (.organization_permission_sets // []) | index("InstancesFullAccess") != null)
      | "warning: scaleway.iam.policy.\(.key) grants InstancesFullAccess, which reaches every key on the workload'"'"'s application; a self-deleting instance should set selfDelete instead (LIB-0043 §3)"),
    # Volumes, Cockpit and the network (LIB-0043 §§1, 5).
    ($s.blockVolume // {} | if type != "object" then "scaleway.blockVolume must be a mapping of volume names" else
      to_entries[] | .key as $k |
        (if ($k | test($kebab)) then empty else "scaleway.blockVolume.\($k): name must be kebab-case" end),
        (.value | if type != "object" then "scaleway.blockVolume.\($k) must be a mapping of module inputs, with size" else
          (if has("size") then empty else "scaleway.blockVolume.\($k) needs size, in GB" end),
          (select(has("project_id")) | "scaleway.blockVolume.\($k).project_id can'"'"'t be set; it'"'"'s wired from the workload (LIB-0043 §1)")
        end)
    end),
    (("cockpit", "privateNetwork", "publicGateway") as $m | select($s | has($m)) | $s[$m] |
      if . != null and type != "object" then "scaleway.\($m) must be a mapping of module inputs" else (. // {}) |
        ((["project_id", "private_network_id"][]) as $i | select(has($i)) | "scaleway.\($m).\($i) can'"'"'t be set; it'"'"'s wired from the workload (LIB-0043 §1)"),
        (if $m != "cockpit" and has("enabled") and ((.enabled | type) != "boolean") then "scaleway.\($m).enabled must be true or false (LIB-0043 §5)" else empty end),
        (if $m == "cockpit" and has("enabled") then "scaleway.cockpit has no enabled; remove it to turn Cockpit off (LIB-0043 §1)" else empty end),
        (if $m == "publicGateway" and has("type") and ((.type | IN("VPC-GW-S", "VPC-GW-M", "VPC-GW-L", "VPC-GW-XL")) | not) then "scaleway.publicGateway.type must be one of VPC-GW-S, VPC-GW-M, VPC-GW-L, VPC-GW-XL (LIB-0043 §5)" else empty end)
      end),
    (if $gw and ($pn | not) then "scaleway.publicGateway is on, so scaleway.privateNetwork must be on too: the gateway reaches instances only through it (LIB-0043 §5, E3)" else empty end),
    ($s.sharedKeyring // {} | keyring_problems("scaleway.sharedKeyring"; $env; $keys; $buckets)),
    # Instances (LIB-0043 §§2, 5, 6).
    ($s.instance // {} | if type != "object" then "scaleway.instance must be a mapping of instance names" else
      to_entries[] | .key as $k | (.value // {}) as $v | "scaleway.instance.\($k)" as $w |
      (if ($k | test($kebab)) and ($k | length) <= 40 then empty else "\($w): an instance name is kebab-case and at most 40 characters (LIB-0043 §6, M3)" end),
      (if $k == "main" or $k == "deployer" then "\($w): main and deployer are reserved (LIB-0043 §1)" else empty end),
      if ($v | type) != "object" then "\($w) must be a mapping" else
      (($v | keys) - passthrough - interface - wired)[] as $x | "\($w).\($x) isn'"'"'t an instance key; known: \(passthrough + interface | join(", ")) (LIB-0043 §2)"
      end,
      ($v | objects | (wired[]) as $x | select(has($x)) | "\($w).\($x) can'"'"'t be set; it'"'"'s wired, or set by network (LIB-0043 §§1-2)"),
      ($v | objects |
        (.network // {}) as $n |
        (if ($n | type) != "object" then "\($w).network must be a mapping of privateNetwork, publicIpv4 and sshViaGateway (LIB-0043 §2)" else
          ((($n | keys) - ["privateNetwork", "publicIpv4", "sshViaGateway"])[] | "\($w).network.\(.) isn'"'"'t one of privateNetwork, publicIpv4, sshViaGateway (LIB-0043 §2)"),
          (("privateNetwork", "publicIpv4") as $b | select($n | has($b)) | select(($n[$b] | type) != "boolean") | "\($w).network.\($b) must be true or false (LIB-0043 §2)"),
          (if ($n | has("sshViaGateway")) and ((($n.sshViaGateway | type) != "number") or $n.sshViaGateway < 1 or $n.sshViaGateway > 65535 or ($n.sshViaGateway | floor) != $n.sshViaGateway) then "\($w).network.sshViaGateway must be a port number (LIB-0043 §2)" else empty end)
        end),
        ($n | objects | (if has("privateNetwork") then .privateNetwork == true else $pn end)) as $attached |
        ($n | objects | .publicIpv4 == true) as $ipv4 |
        (if ($n | objects | .privateNetwork) == true and ($pn | not) then "\($w).network.privateNetwork needs scaleway.privateNetwork on (LIB-0043 §5, E6)" else empty end),
        (if ($gw | not) and (($n | objects | .publicIpv4) != true) then "\($w): the public gateway is off, so every instance sets network.publicIpv4: true itself (LIB-0043 §5, E2)"
         elif $gw and ($ipv4 | not) and ($attached | not) then "\($w) has no way out: set network.publicIpv4: true, or attach it to the private network (LIB-0043 §5, E1)"
         else empty end),
        (if ($n | objects | has("sshViaGateway")) and (($gw | not) or ($attached | not)) then "\($w).network.sshViaGateway needs the public gateway on and the instance on the private network (LIB-0043 §5, E5)" else empty end),
        (.volumes // [] | if type != "array" then "\($w).volumes must be a list of scaleway.blockVolume keys (LIB-0043 §2)" else
          (if length > 1 then "\($w).volumes takes at most one volume: cloud-init mounts /dev/sdb alone (LIB-0043 §6, S1)" else empty end),
          (.[] | . as $x | select((type != "string") or ($vols | has($x) | not)) | "\($w).volumes: \(tojson) isn'"'"'t a scaleway.blockVolume key (LIB-0043 §6, S1)")
        end),
        (("cockpit", "transcoding", "selfDelete") as $b | select(has($b)) | select((.[$b] | type) != "boolean") | "\($w).\($b) must be true or false (LIB-0043 §2)"),
        (if .cockpit == true and ($cockpit | not) then "\($w).cockpit needs scaleway.cockpit (LIB-0043 §6, M2)" else empty end),
        (if .transcoding == true and ((.type // "") | tostring | startswith("COPARM")) then "\($w).transcoding is x86_64 only, and \(.type) is arm64 (ADR-0152, LIB-0043 §6, M1)" else empty end),
        (.commands // [] | if type != "array" or (map(type == "string") | all | not) then "\($w).commands must be a list of strings (LIB-0043 §2)" else empty end),
        (.keyring // {} | keyring_problems("\($w).keyring"; $env; $keys; $buckets)),
        ((($shared + ((.keyring // {}) | objects)) | keys) as $aliases |
          (.commands // [] | arrays | .[] | strings | alias_refs[] | select(. as $a | $aliases | index($a) | not)
            | "\($w).commands: ${keyring...} names \(.), which isn'"'"'t in its keyring or scaleway.sharedKeyring (LIB-0043 §2)"))
      )
    end),
    # Spoke-wide over the instances: one volume and one port each (S1, E5).
    ([$inst | to_entries[] | .key as $k | .value | objects | (.volumes // []) | arrays | .[] | strings | {k: $k, v: .}] | group_by(.v)[] | select(length > 1)
      | "scaleway.blockVolume.\(.[0].v) is attached to \(map(.k) | join(" and ")); a volume attaches to one instance (LIB-0043 §6, S1)"),
    ([$inst | to_entries[] | .key as $k | .value | objects | .network | objects | select(has("sshViaGateway")) | {k: $k, p: .sshViaGateway}] | group_by(.p)[] | select(length > 1)
      | "\(map("scaleway.instance.\(.k)") | join(" and ")) share sshViaGateway \(.[0].p) (LIB-0043 §5, E5)");
  def expand_compute:
    if type != "object" or (.scaleway | type) != "object" then . else
    on(.scaleway; "privateNetwork") as $pn | on(.scaleway; "publicGateway") as $gw |
    (.scaleway | has("cockpit")) as $cockpit |
    (.scaleway.sharedKeyring // {} | objects) as $shared |
    (.scaleway.bucket // {} | objects) as $buckets |
    (.scaleway.instance // {} | objects | with_entries(.value |= (. // {}))) as $inst |
    def keyring_of($v): $shared + (($v.keyring // {}) | objects);
    def config_entry($v):
      keyring_of($v) as $kr |
      {
        keyring: [$kr | to_entries[] | .key as $a | .value |
          (.bucket as $b | ($b | type) == "string" and ($buckets | has($b))) as $wb |
          (with_entries(select(.key != "apiKey" and (.value | is_ref | not) and ((.key == "bucket" and $wb) | not)))
           + {alias: $a} + (if $wb and (has("endpoint") | not) then {endpoint: "https://s3.<region>.scw.cloud"} else {} end))],
        enable_transcoding: ($v.transcoding == true),
        self_delete_on_exit: ($v.selfDelete == true),
        post_provision_commands: ($v.commands // []),
        has_attached_volume: ((($v.volumes // []) | length) > 0)
      } + (if [$kr[] | objects | .[] | select(is_ref)] | length > 0 then {keyring_secrets: {}} else {} end);
    .scaleway |= (
      (if has("privateNetwork") then (if $pn then .privateNetwork = ((.privateNetwork // {}) | del(.enabled)) else del(.privateNetwork) end) else . end)
      | (if has("publicGateway") then (if $gw then .publicGateway = ((.publicGateway // {}) | del(.enabled)) else del(.publicGateway) end) else . end)
      | ._implied = {
          selfDeleteApplication: ($inst | to_entries | map(select(.value.selfDelete == true) | {key: "self-delete-\(.key)", value: {}}) | from_entries),
          selfDeletePolicy: ($inst | to_entries | map(select(.value.selfDelete == true) | {key: "self-delete-\(.key)", value: {project_permission_sets: ["InstancesFullAccess"]}}) | from_entries),
          selfDeleteApiKey: ($inst | to_entries | map(select(.value.selfDelete == true) | {key: "self-delete-\(.key)", value: {}}) | from_entries),
          instanceConfig: ($inst | with_entries(.value |= config_entry(.))),
          patRule: ($inst | to_entries | map(select(.value.network.sshViaGateway? != null) | {key, value: {public_port: .value.network.sshViaGateway}}) | from_entries)
        }
      | ._meta = {instance: ($inst | with_entries(.value |= (
          (if (.network // {}) | has("privateNetwork") then .network.privateNetwork == true else $pn end) as $attached |
          ((.network // {}).publicIpv4 == true) as $ipv4 |
          {
            attached: $attached,
            gatewayWait: ($gw and $attached and ($ipv4 | not)),
            volumes: (.volumes // []),
            cockpit: (if has("cockpit") then .cockpit == true else $cockpit end),
            selfDelete: (.selfDelete == true),
            keyringWiring: (keyring_of(.) | to_entries | map(select(.value.kind == "bucket")) | map({key, value: {
              bucket: (.value.bucket as $b | if ($b | type) == "string" and ($buckets | has($b)) then $b else null end),
              apiKey: (.value.apiKey // null)
            }} | select(.value.bucket != null or .value.apiKey != null)) | from_entries)
          })))}
      | .instance = ($inst | with_entries(.value |= (with_entries(select(.key | IN(passthrough[]))) + {
          public_ipv4: ((.network // {}).publicIpv4 == true),
          enable_private_network: (if (.network // {}) | has("privateNetwork") then .network.privateNetwork == true else $pn end)
        })))
      | (if (.instance | length) == 0 then del(.instance) else . end)
      | del(.sharedKeyring)
    ) end;
'

# relabel reads messages and names a file's records by its own key,
# dnsRecords, where the checks read them at cloudflare.dnsRecord. A path that
# is already the wrapper's, zone.cloudflare.dnsRecord, is the file's own and
# stays.
relabel() {
  sed -E 's/(^|[^.])cloudflare\.dnsRecord([^s]|$)/\1dnsRecords\2/g'
}

# stub_content <module> <credentials> <state> <declared dependencies...>
stub_content() {
  local module="$1" credentials="$2" state="$3"; shift 3
  local deps=("$@")
  printf '%s\n' "$HEADER"
  if [ "$state" = workload ]; then
    cat <<'EOF'
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}
EOF
  else
    cat <<'EOF'
include "root" {
  path = find_in_parent_folders("root.hcl")
}
EOF
  fi
  cat <<'EOF'

terraform {
  source = get_terragrunt_dir()
}
EOF
  local dep lines="" width=0 input expr
  for dep in ${deps[@]+"${deps[@]}"}; do
    printf '\ndependency "%s" {\n  config_path = "../../../%s"\n}\n' "$dep" "$(dep_dir "$dep")"
    lines="$lines$(wiring_lines "$module" "$dep" "$credentials")"$'\n'
  done
  # A Backblaze key's buckets become one list (LIB-0029 §3).
  local ids=""
  for dep in ${deps[@]+"${deps[@]}"}; do
    case "$dep" in bucket_*) ids="${ids:+$ids, }dependency.$dep.outputs.module.bucket_id" ;; esac
  done
  if [ -n "$ids" ]; then lines="${lines}bucket_ids|[$ids]"$'\n'; fi
  # An instance's volumes become one list, and its keyring's buckets and API
  # keys one map by alias (LIB-0043 §§1, 4), from CUR_KEYRING_WIRING.
  ids=""
  for dep in ${deps[@]+"${deps[@]}"}; do
    case "$dep" in volume_*) ids="${ids:+$ids, }dependency.$dep.outputs.module.id" ;; esac
  done
  if [ -n "$ids" ]; then lines="${lines}additional_volume_ids|[$ids]"$'\n'; fi
  if [ "$module" = scaleway/compute-instance-config ] && [ -n "${CUR_KEYRING_WIRING:-}" ] && [ "$CUR_KEYRING_WIRING" != "{}" ]; then
    lines="${lines}keyring_wiring|$(jq -r '
      to_entries | map(.key as $a | .value as $w |
        ([(if $w.bucket then "bucket = dependency.sbucket_\($w.bucket | gsub("-"; "_")).outputs.module.name" else empty end),
          (if $w.apiKey then
             "access_key_id = dependency.apikey_\($w.apiKey | gsub("-"; "_")).outputs.module.access_key",
             "secret_key = dependency.apikey_\($w.apiKey | gsub("-"; "_")).outputs.module.secret_key"
           else empty end)] | join(", ")) as $f |
        "\($a | tojson) = { \($f) }") | "{ " + join(", ") + " }"' <<<"$CUR_KEYRING_WIRING")"$'\n'
  fi
  # Aligned on `=`, as terragrunt hcl format would leave it.
  while IFS='|' read -r input expr; do
    [ -z "$input" ] && continue
    if [ "${#input}" -gt "$width" ]; then width=${#input}; fi
  done <<<"$lines"
  if [ "$width" -gt 0 ]; then
    printf '\ninputs = {\n'
    while IFS='|' read -r input expr; do
      [ -z "$input" ] && continue
      printf '  %-*s = %s\n' "$width" "$input" "$expr"
    done <<<"$lines"
    printf '}\n'
  fi
  [ "$state" = workload ] || return 0
  cat <<'EOF'

# State in the workload's own bucket, signed in with its deployer's key
# (LIB-0028 §5). Replaces root.hcl's remote_state, whose other settings it
# keeps.
remote_state {
  backend = "s3"

  config = merge(include.root.locals.scaleway_state_config, {
    bucket     = dependency.state.outputs.module.name
    key        = include.root.locals.workload_state_key
    access_key = dependency.deployer.outputs.module.access_key
    secret_key = dependency.deployer.outputs.module.secret_key
  })

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
}
EOF
}

# Lookups are cached in files, not associative arrays: macOS's bash 3.2 runs
# this too, through a spoke's mise tasks.
cache_file() { echo "$EXPECTED_DIR/.cache/$(echo "$1" | tr '/@' '__')"; }

# resolve_version <module> [<pin>] prints X.Y.Z, the same way root.hcl does.
resolve_version() {
  local module="$1" pin="${2:-}" pattern cache
  cache=$(cache_file "version-$module@$pin")
  if [ -f "$cache" ]; then
    cat "$cache"
    return
  fi
  if [ -z "$pin" ]; then
    pattern="refs/tags/terraform/$module/v*"
  elif [[ "$pin" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pattern="refs/tags/terraform/$module/v$pin"
  else
    pattern="refs/tags/terraform/$module/v$pin.*"
  fi
  local line
  line=$(git ls-remote --sort=-v:refname --tags "$TAG_REMOTE" "$pattern" | head -n1)
  if [[ ! "$line" =~ /v([0-9]+\.[0-9]+\.[0-9]+)(\^\{\})?$ ]]; then
    return 1
  fi
  echo "${BASH_REMATCH[1]}" | tee "$cache"
}

schema_properties() {
  local module="$1" version="$2" cache props
  cache=$(cache_file "schema-$module@$version")
  if [ ! -f "$cache" ]; then
    props=$(curl -fsSL "$SCHEMA_BASE/terraform/$module/v$version/inputs.schema.json" | jq -c '.properties | keys') || return 1
    echo "$props" >"$cache"
  fi
  cat "$cache"
}

# A zone's file, unwrapped, read as a workload's (LIB-0036 §§1-2): `name`
# defaults to the zone, `prefix` to that name with every character a resource
# name can't hold turned into a dash, and every zone kind acts on the zone.
# Each enabled service implies its records (LIB-0039 §3), and each apexRedirect <key> (LIB-0038 §3) implies dnsRecord <key>-apex and, with
# include_www, <key>-www, and ruleset <key>, with the strings
# cloudflare/apex-redirect generated, each under any explicit entry of the
# same key, field by field. An entry that isn't a mapping is passed through,
# for the structural check to name. root.hcl's workload_values,
# workload_cf_dns and workload_cf_rulesets are its twins.
# expand_zone <unwrapped JSON> <zone>
expand_zone() {
  jq -c --arg z "$2" "$UNIT_JQ"'
    def merge_under($d): (. // {}) as $e |
      if ($e | type) != "object" then $e
      else $e + ($d | with_entries(.value += (($e[.key] // {}) | if type == "object" then . else {} end))) end;
    if type != "object" then . else
      ((.name // $z) | tostring) as $n |
      (if has("prefix") then . else .prefix = ($n | gsub("[^a-z0-9-]"; "-")) end) |
      .cloudflare = ((.cloudflare // {}) | if type == "object" then . + {zone: $z} else . end) |
      service_dns($z) as $sdns |
      (if ($sdns | length) > 0 and (.cloudflare | type) == "object" then .cloudflare.dnsRecord = (.cloudflare.dnsRecord | merge_under($sdns)) else . end) |
      del(.services) |
      ((.cloudflare.apexRedirect? // {}) | if type == "object" then with_entries(select(.value | type == "object" and (.target_url | type) == "string" and (.target_url | test("^[a-zA-Z][a-zA-Z0-9+.-]*://.")))) else {} end) as $r |
      if ($r | length) == 0 or (.cloudflare | type) != "object" then . else
        ($r | with_entries(.value |= (.target_url | capture("^[a-zA-Z][a-zA-Z0-9+.-]*://(?<h>.*)$").h | sub("/$"; "")))) as $host |
        ($r | with_entries(.value |= (if .include_www == false then false else true end))) as $www |
        ([$r | keys[] as $k | {key: "\($k)-apex", value: {name: "@", type: "A", content: "192.0.2.1", proxied: true, ttl: 1, comment: "placeholder so Cloudflare intercepts apex traffic for the \($host[$k]) redirect"}}]
         + [$r | keys[] as $k | select($www[$k]) | {key: "\($k)-www", value: {name: "www", type: "CNAME", content: $z, proxied: true, ttl: 1, comment: "placeholder so Cloudflare intercepts www traffic for the \($host[$k]) redirect"}}]
         | from_entries) as $dns |
        ($r | to_entries | map(.key as $k | .value as $e | {key: $k, value: {
          name: "\($z) to \($host[$k]) redirect", kind: "zone", phase: "http_request_dynamic_redirect",
          rules: [{
            expression: ((if $www[$k] then [$z, "www.\($z)"] else [$z] end) | map("(http.host eq \"\(.)\")") | join(" or ")),
            description: "redirect \(if $www[$k] then "\($z) and www" else $z end) to the \($host[$k]) homepage",
            action: "redirect",
            action_parameters: {from_value: {status_code: ($e.status_code // 301), target_url: {value: $e.target_url}, preserve_query_string: ($e.preserve_query_string // false)}}
          }]}}) | from_entries) as $rs |
        .cloudflare.dnsRecord = (.cloudflare.dnsRecord | merge_under($dns)) |
        .cloudflare.ruleset = (.cloudflare.ruleset | merge_under($rs))
      end
    end' <<<"$1"
}

# workload.yaml as JSON, read as a values.yaml (LIB-0037 §§1-4): `prefix`
# and `suffix` from deployments.scaleway.project, else the zone's; the zone
# from the directory; a project entry only when the workload has its own; and
# the Pages records its host implies, under any explicit entry of the same key.
# root.hcl's workload_values is its twin.
# expand_workload <unwrapped JSON> <zone or private> <zone file JSON> <host> <username>
expand_workload() {
  jq -c --arg z "$2" --argjson zf "$3" --arg host "$4" --arg user "$5" '
    if type != "object" then . else
      ((.deployments.scaleway.project? // {}) | if type == "object" then . else {} end) as $p |
      ($z == "private" or ($p | has("name") or has("prefix") or has("suffix"))) as $own |
      (($zf.prefix // (($zf.name // $z) | tostring | gsub("[^a-z0-9-]"; "-"))) | tostring) as $zp |
      (.deployments.githubPages? // {} | if type == "object" then . else {} end) as $gp |
      ((.deployments // {}) | objects | has("githubPages")) as $pages |
      ($gp.url // "\($user).github.io") as $url |
      (if $host == "@" then {
         "github-pages-root-cname": {name: "@", type: "CNAME", content: $url, ttl: 1, proxied: false, comment: "github pages root cname (apex, cloudflare-flattened)"},
         "github-pages-www-cname": {name: "www", type: "CNAME", content: $url, ttl: 1, proxied: false, comment: "github pages www cname"}}
       else {"github-pages-cname": {name: $host, type: "CNAME", content: $url, ttl: 1, proxied: false, comment: "github pages cname"}} end) as $d |
      .prefix = (($p.prefix // (if $z == "private" then "" else $zp end)) | tostring) |
      .suffix = (($p.suffix // (if $z == "private" then "" else ($zf.suffix // "") end)) | tostring) |
      (if $own then .scaleway = ((.scaleway // {}) | if type == "object" then . + {project: ($p | del(.prefix, .suffix))} else . end) else . end) |
      (if $z != "private" then .cloudflare = ((.cloudflare // {}) | if type == "object" then . + {zone: $z} else . end) else . end) |
      (if $pages and $host != "" then
        .cloudflare = (.cloudflare | .dnsRecord = (
          (.dnsRecord // {}) as $e |
          if ($e | type) != "object" then $e
          else $e + ($d | with_entries(.value += (($e[.key] // {}) | if type == "object" then . else {} end))) end))
       else . end) |
      del(.name, .deployments)
    end' <<<"$1"
}

# The spoke repo's owner, githubPages' default username (LIB-0037 §4): CI's
# GITHUB_REPOSITORY_OWNER, else the owner in origin's URL. root.hcl's
# spoke_owner is its twin.
spoke_owner() {
  if [ -n "${GITHUB_REPOSITORY_OWNER:-}" ]; then echo "$GITHUB_REPOSITORY_OWNER"; return; fi
  { git -C "$SPOKE_DIR" remote get-url origin 2>/dev/null || true; } | sed -nE 's#^.*github\.com[:/]([^/]+)/.*$#\1#p'
}

# A unit's cached, expanded file, by its directory.
unit_cache() { echo "$EXPECTED_DIR/.cache/unit-$(tr / _ <<<"$1").json"; }

EXPECTED_DIR="$(mktemp -d)"
trap 'rm -rf "$EXPECTED_DIR"' EXIT
mkdir -p "$EXPECTED_DIR/.cache"

# A zone is registered only by its zones/<zone>/zone.yaml. The root zones.yaml
# that did it before (LIB-0030 §2) is refused, not read beside them.
ZONES='{}'
if [ -e "$SPOKE_DIR/zones.yaml" ]; then
  fail "zones.yaml is refused: each zone is zones/<zone>/zone.yaml, naming the workload that may write in it (LIB-0036 §1)"
fi

shopt -s nullglob

# zones/<zone>/zone.yaml (LIB-0036 §1): each gives each of its hosts to the
# workload under workloads/<zone>/ that serves it (LIB-0037 §3).
APEX='^[a-z0-9-]+(\.[a-z0-9-]+)+$'
LABEL='^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'
for zone_file in "$SPOKE_DIR"/zones/*/zone.yaml; do
  zone="$(basename "$(dirname "$zone_file")")"
  [[ "$zone" =~ $APEX ]] || continue
  entry=$(yq -o=json '.' "$zone_file" 2>/dev/null | jq -c "$UNIT_JQ"' unwrap("zone") |
    if type != "object" then {hosts: {}} else
      {hosts: (if (.hosts | type) == "object" then (.hosts | with_entries(select(.value | type == "string"))) else {} end)}
    end') || entry='{"hosts":{}}'
  ZONES=$(jq -c --arg z "$zone" --argjson e "$entry" '.[$z] = $e' <<<"$ZONES")
done

# Each unit, a workload's workload.yaml or a zone's zone.yaml, validated and
# rendered into $EXPECTED_DIR at the path its stubs have in the spoke. A
# unit's expanded file is cached for --check, and its zone entries are
# collected for the spoke-wide clash checks below.
instances=()   # "<unit dir>|<unit file>|<module>|<instance>|<jq path>|<declared dependencies>|<credentials>"
unit_files=()
# A workload's directory under workloads/ is a zone or `private` (LIB-0037
# §1). The old layout, workloads/<w>/values.yaml, is refused (LIB-0037 §6).
is_parent() { [[ "$1" =~ $APEX ]] || [ "$1" = private ]; }
for f in "$SPOKE_DIR"/workloads/*/*/workload.yaml "$SPOKE_DIR"/zones/*/zone.yaml; do
  rel="${f#"$SPOKE_DIR"/}"
  parent=$(cut -d/ -f2 <<<"$rel")
  case "$rel" in
    workloads/*/*/workload.yaml)
      if ! is_parent "$parent"; then fail "$rel: workloads/$parent/ isn't a zone or private, so it can't hold a workload.yaml (LIB-0037 §1)"; continue; fi ;;
  esac
  unit_files+=("$rel")
done
for f in "$SPOKE_DIR"/workloads/*/values.yaml "$SPOKE_DIR"/workloads/*/secrets.yaml "$SPOKE_DIR"/workloads/*/workload.yaml "$SPOKE_DIR"/workloads/*/*/values.yaml; do
  rel="${f#"$SPOKE_DIR"/}"
  case "$rel" in
    workloads/*/values.yaml | workloads/*/secrets.yaml) fail "$rel: the old layout, workloads/<workload>/, is refused since workflows/v7.0.0; move it to workloads/<zone>/<workload>/workload.yaml and secrets.workload.yaml (LIB-0037 §6)" ;;
    workloads/*/workload.yaml) fail "$rel: a workload.yaml lives in workloads/<zone>/<workload>/ or workloads/private/<workload>/ (LIB-0037 §1)" ;;
    *) fail "$rel: a workload has a workload.yaml, not a values.yaml (LIB-0037 §§1, 6)" ;;
  esac
done
: >"$EXPECTED_DIR/.cache/clash.jsonl"
for rel in ${unit_files[@]+"${unit_files[@]}"}; do
  unit_root="${rel%%/*}"
  workload="$(basename "$(dirname "$rel")")"
  unit_dir="$(dirname "$rel")"
  # A workload lives in its zone or in `private` (LIB-0037), with its host.
  nested=false; parent=""; host=""; ZONE_PROJECT=""
  case "$rel" in workloads/*/*/workload.yaml) nested=true; parent=$(cut -d/ -f2 <<<"$rel") ;; esac
  if [ "$unit_root" = zones ]; then
    unit=zone
    if [[ ! "$workload" =~ $APEX ]]; then
      fail "$rel: a zone's directory must be its apex domain (LIB-0036 §1)"
      continue
    fi
    if ! raw=$(yq -o=json '.' "$SPOKE_DIR/$rel"); then
      fail "$rel: not valid YAML"
      continue
    fi
    # Its shape (LIB-0039 §1), then the file unwrapped.
    shape_msgs=$(jq -r "$UNIT_JQ"' shape_problems("zone")' <<<"$raw")
    raw=$(jq -c "$UNIT_JQ"' unwrap("zone")' <<<"$raw")
    # What a zone's file can't say, read before its defaults fill it in.
    zone_problems=$(jq -r --arg kebab "$KEBAB" "$UNIT_JQ"'
      if type != "object" then "the file must be a mapping"
      else
        services_problems,
        (if has("name") and ((.name | type) != "string" or .name == "") then "name must be a non-empty string (LIB-0036 §1)" else empty end),
        (if has("prefix") and ((.prefix | type) != "string" or (.prefix | test("^[a-z0-9-]+$") | not)) then "prefix may hold only a-z, 0-9 and - (LIB-0036 §1)" else empty end),
        (if has("workload") then "workload is refused since workflows/v7.0.0; hosts names the workloads under workloads/<zone>/ (LIB-0037 §§3, 6)" else empty end),
        (.cloudflare.apexRedirect? // {} | objects | to_entries[] | .key as $k | .value | objects |
          ((keys - ["target_url", "status_code", "include_www", "preserve_query_string"])[] | "cloudflare.apexRedirect.\($k).\(.) isn'"'"'t one of target_url, status_code, include_www, preserve_query_string; set it on the entry it expands into (LIB-0038 §3)"),
          (if has("target_url") and ((.target_url | type) != "string" or (.target_url | test("^https?://[^/]+") | not)) then "cloudflare.apexRedirect.\($k).target_url must be an absolute http:// or https:// URL (LIB-0038 §3)" else empty end)),
        (.cloudflare // {} | objects |
          (if has("zone") then "cloudflare.zone can'"'"'t be set; the directory names the zone (LIB-0036 §1)" else empty end),
          (("dnsRecord", "ruleset", "apexRedirect") as $m | .[$m] // {} | objects | to_entries[]
            | select(.value | objects | has("zone")) | "cloudflare.\($m).\(.key) can'"'"'t set zone; the directory names it (LIB-0036 §1)"))
      end' <<<"$raw")
    # Its hosts (LIB-0037 §3): who serves the apex and each subdomain.
    host_problems=$(jq -r --arg kebab "$KEBAB" --arg label "$LABEL" '
      objects | select(has("hosts")) |
      if (.hosts | type) != "object" then "hosts must be a mapping of host to workload (LIB-0037 §3)" else
        (.hosts | to_entries[] |
          (if .key == "@" or (.key | test($label)) then empty else "hosts.\(.key) must be @ or one DNS label (LIB-0037 §3)" end),
          (if (.value | type) == "string" and (.value | test($kebab)) then empty else "hosts.\(.key) must name one workload (LIB-0037 §3)" end)),
        ([.hosts | to_entries[] | .value] | group_by(.)[] | select(length > 1) | "workload \(.[0]) holds more than one host; a workload serves one (LIB-0037 §3)"),
        (if (.hosts | has("@")) and ((.cloudflare.apexRedirect // {}) | objects | length > 0) then "hosts.@ and cloudflare.apexRedirect both claim the apex and www; keep one (LIB-0037 §3)" else empty end),
        # A host is its workload'"'"'s: no zone record at a subdomain host or
        # under it, and none at www or an A, AAAA or CNAME at the apex
        # beside an @ host (LIB-0037 §3).
        ([.hosts | keys[] | select(. != "@")]) as $subs | (.hosts | has("@")) as $apex |
        (.cloudflare.dnsRecord // {} | objects | to_entries[] | ((.value | objects | .name) // .key | tostring) as $n |
          ((.value | objects | .type) // "" | tostring | ascii_upcase) as $t |
          (if ($subs | any(. as $h | $n == $h or ($n | endswith(".\($h)")))) then "cloudflare.dnsRecord.\(.key): \($n) is a host'"'"'s, in hosts (LIB-0037 §3)"
           elif $apex and ($n == "www" or ($n | endswith(".www")) or ($n == "@" and ([$t] | inside(["A", "AAAA", "CNAME"])))) then "cloudflare.dnsRecord.\(.key): \($n) \($t) is the apex host'"'"'s, in hosts (LIB-0037 §3)"
           else empty end))
      end' <<<"$raw")
    while IFS= read -r h; do
      [ -z "$h" ] && continue
      [ -f "$SPOKE_DIR/workloads/$workload/$h/workload.yaml" ] || host_problems="${host_problems:+$host_problems$'\n'}a host names workload $h, which has no workloads/$workload/$h/workload.yaml (LIB-0037 §3)"
    done < <(jq -r --arg kebab "$KEBAB" 'objects | .hosts? // {} | objects | .[] | strings | select(test($kebab))' <<<"$raw" | sort -u)
    zone_problems="${zone_problems:+$zone_problems${host_problems:+$'\n'}}$host_problems"
    zone_problems="${shape_msgs:+$shape_msgs${zone_problems:+$'\n'}}$zone_problems"
    if [ -e "$SPOKE_DIR/$unit_dir/secrets.yaml" ]; then
      zone_problems="${zone_problems:+$zone_problems$'\n'}a zone has no secrets.yaml; delete $unit_dir/secrets.yaml (LIB-0036, Out of scope)"
    fi
    if [ -n "$zone_problems" ]; then
      while IFS= read -r msg; do fail "$rel: $msg"; done < <(relabel <<<"$zone_problems")
      continue
    fi
    json=$(expand_zone "$raw" "$workload")
  elif [ "$nested" = true ]; then
    unit=workload
    if [[ ! "$workload" =~ $KEBAB ]]; then
      fail "$rel: workload name '$workload' must be kebab-case"
      continue
    fi
    if [ "$parent" != private ] && [ ! -f "$SPOKE_DIR/zones/$parent/zone.yaml" ]; then
      fail "$rel: zone $parent has no zones/$parent/zone.yaml (LIB-0037 §1)"
      continue
    fi
    if ! raw=$(yq -o=json '.' "$SPOKE_DIR/$rel"); then
      fail "$rel: not valid YAML"
      continue
    fi
    # Its shape (LIB-0039 §1), then the file unwrapped, and its zone's.
    shape_msgs=$(jq -r "$UNIT_JQ"' shape_problems("workload")' <<<"$raw")
    raw=$(jq -c "$UNIT_JQ"' unwrap("workload")' <<<"$raw")
    if [ "$parent" = private ]; then zf='{}'; else zf=$(yq -o=json '. // {}' "$SPOKE_DIR/zones/$parent/zone.yaml" 2>/dev/null | jq -c "$UNIT_JQ"' unwrap("zone") | objects') || zf='{}'; [ -n "$zf" ] || zf='{}'; fi
    host=$(jq -r --arg z "$parent" --arg w "$workload" '.[$z].hosts // {} | to_entries[] | select(.value == $w) | .key' <<<"$ZONES" | head -n1)
    # What a workload.yaml can't say, read before its defaults fill it in.
    workload_problems=$(jq -r --arg kebab "$KEBAB" --arg z "$parent" --arg host "$host" '
      def keys_in($where; $allowed): (keys - $allowed)[] | "unknown key \($where).\(.); known: \($allowed | join(", "))";
      if type != "object" then "the file must be a mapping"
      else
        (if has("features") then "features is refused since workflows/v7.0.0; githubPages moves to deployments.githubPages (LIB-0037 §§4, 6)" else empty end),
        ((["prefix", "suffix"] - (keys - ["prefix", "suffix"]))[] as $k | select(has($k)) | "\($k) moves to deployments.scaleway.project.\($k) (LIB-0037 §2)"),
        ((keys - ["name", "deployments", "scaleway", "backblaze", "cloudflare", "features", "prefix", "suffix", "services"])[] | "unknown key \(.); known: name, deployments, scaleway, backblaze, cloudflare"),
        (if has("name") and ((.name | type) != "string" or (.name | test($kebab) | not)) then "name must be kebab-case (LIB-0037 §1)"
         elif .name == "zone" then "name can'"'"'t be zone, which a zone'"'"'s own resources carry (LIB-0036 §2, LIB-0037 §1)" else empty end),
        (.scaleway // {} | objects | select(has("project")) | "scaleway.project moves to deployments.scaleway.project (LIB-0037 §2)"),
        (.deployments // {} | if type != "object" then "deployments must be a mapping" else
          keys_in("deployments"; ["scaleway", "githubPages"]),
          (.scaleway // {} | if type != "object" then "deployments.scaleway must be a mapping" else
            keys_in("deployments.scaleway"; ["project"]),
            (.project // {} | if type != "object" then "deployments.scaleway.project must be a mapping of module inputs" else
              ((["name", "prefix", "suffix"][]) as $k | select(has($k)) | select((.[$k] | type) != "string" or .[$k] == "") | "deployments.scaleway.project.\($k) must be a non-empty string")
            end)
          end),
          (if has("githubPages") then
            (.githubPages // {} | if type != "object" then "deployments.githubPages must be a mapping" else
              keys_in("deployments.githubPages"; ["username", "shim", "url"]),
              (to_entries[] | select((.value | type) != "string" or .value == "") | "deployments.githubPages.\(.key) must be a non-empty string")
            end),
            (if $z == "private" then "deployments.githubPages needs a host, which a private workload never has (LIB-0037 §§1, 4)"
             elif $host == "" then "deployments.githubPages needs a host; give this workload one in zones/\($z)/zone.yaml (LIB-0037 §4)" else empty end)
          else empty end)
        end),
        (if $z == "private" then
          ((["prefix", "suffix"][]) as $k | select((.deployments.scaleway.project[$k]? // "") == "") | "a private workload has its own project, so it needs deployments.scaleway.project.\($k) (LIB-0037 §1)")
         else empty end),
        (.cloudflare // {} | objects |
          (if has("zone") then "cloudflare.zone is refused; the directory names the zone (LIB-0037 §§1, 6)" else empty end),
          (if $z == "private" and (.dnsRecord // {} | objects | length > 0) then "cloudflare.dnsRecord needs a zone, which a private workload has none of (LIB-0037 §1)" else empty end),
          (.dnsRecord // {} | objects | to_entries[] | select(.value | objects | has("zone")) | "cloudflare.dnsRecord.\(.key) can'"'"'t set zone; the directory names it (LIB-0037 §1)"))
      end' <<<"$raw")
    if [ -e "$SPOKE_DIR/$unit_dir/secrets.yaml" ]; then
      workload_problems="${workload_problems:+$workload_problems$'\n'}secrets.yaml is refused; rename it secrets.workload.yaml (LIB-0037 §§1, 6)"
    fi
    workload_problems="${shape_msgs:+$shape_msgs${workload_problems:+$'\n'}}$workload_problems"
    if [ -n "$workload_problems" ]; then
      while IFS= read -r msg; do fail "$rel: $msg"; done < <(relabel <<<"$workload_problems")
      continue
    fi
    user=""
    if jq -e '(.deployments // {}) | has("githubPages")' <<<"$raw" >/dev/null; then
      user=$(jq -r '.deployments.githubPages.username? // ""' <<<"$raw")
      [ -n "$user" ] || user=$(spoke_owner)
      if [ -z "$user" ]; then
        fail "$rel: deployments.githubPages.username defaults to the spoke repo's owner, but neither GITHUB_REPOSITORY_OWNER nor origin's URL gives one (LIB-0037 §4)"
        continue
      fi
    fi
    if [ "$parent" != private ] && ! jq -e '(.deployments.scaleway.project? // {}) | objects | has("name") or has("prefix") or has("suffix")' <<<"$raw" >/dev/null; then
      ZONE_PROJECT="$parent"
    fi
    name=$(jq -r --arg w "$workload" '.name // $w' <<<"$raw")
    json=$(expand_workload "$raw" "$parent" "$zf" "$host" "$user")
  fi
  # A nested workload's names carry its name in its zone's project (LIB-0037
  # §2), and none in a project of its own (LIB-0040's 2026-10-27 amendment).
  # The test is expand_workload's $own; root.hcl's workload_name_tag is the twin.
  tag=""
  if [ "$nested" = true ] && [ "$parent" != private ] && ! jq -e '(.deployments.scaleway.project? // {}) | objects | has("name") or has("prefix") or has("suffix")' <<<"$raw" >/dev/null; then tag="-$name"; fi

  structural=$(jq -r --arg kebab "$KEBAB" --arg workload "$workload" --arg unit "$unit" --argjson zones "$ZONES" --arg nested "$nested" --arg host "$host" --arg tag "$tag" '
    def entry_ok($where): if . == null or type == "object" then empty else "\($where) must be a mapping of module inputs" end;
    def keys_in($where; $allowed): (keys - $allowed)[] | "unknown key \($where).\(.); known: \($allowed | join(", "))";
    if type != "object" then "the file must be a mapping"
    else
      keys_in(""; if $unit == "zone" then ["name", "prefix", "suffix", "hosts", "scaleway", "cloudflare"]
                  else ["prefix", "suffix", "scaleway", "backblaze", "cloudflare"] end),
      (if (.prefix | type) != "string" or .prefix == "" then "prefix must be a non-empty string" else empty end),
      (if (.suffix | type) != "string" or .suffix == "" then "suffix must be a non-empty string" else empty end),
      (.scaleway // {} | if type != "object" then "scaleway must be a mapping" else
        keys_in("scaleway"; if $unit == "zone" then ["project", "deployer", "state"] else ["project", "deployer", "state", "bucket", "iam", "blockVolume", "cockpit", "privateNetwork", "publicGateway", "instance", "sharedKeyring"] end),
        (.project | entry_ok("scaleway.project")),
        # The deployer is three leaves, each overridden by its own key (LIB-0038 §1).
        (.deployer // {} | if type != "object" then "scaleway.deployer must be a mapping of application, policy and apiKey (LIB-0038 §1)" else
          ((keys - ["application", "policy", "apiKey"])[] | "scaleway.deployer.\(.): the deployer is three leaves, so each input goes under scaleway.deployer.application, .policy or .apiKey, by its module'"'"'s own name (LIB-0038 §1)"),
          (.application | entry_ok("scaleway.deployer.application")),
          (.policy | entry_ok("scaleway.deployer.policy")),
          (.apiKey | entry_ok("scaleway.deployer.apiKey"))
        end),
        (.state | entry_ok("scaleway.state")),
        # The workload state bucket (LIB-0028 §§2-3, §5).
        (.state // {} | objects |
          (if has("prefix") and ((.prefix | type) != "string" or (.prefix | test("^[^/].*/$") | not))
           then "scaleway.state.prefix must not start with / and must end with one (LIB-0028 §3)" else empty end),
          (if .enable_versioning == false then "scaleway.state.enable_versioning can'"'"'t be false: versioning is the state'"'"'s only protection (LIB-0028 §2)" else empty end),
          (if .storage_class == "glacier" then "scaleway.state.storage_class can'"'"'t be glacier: state moved to GLACIER after 90 days can'"'"'t be read without a restore (LIB-0028 §2)" else empty end)),
        (.deployer // {} | objects | .policy // {} | objects | select(.project_permission_sets | type == "array")
          | if (.project_permission_sets | index("ObjectStorageFullAccess")) == null
            then "scaleway.deployer.policy.project_permission_sets must keep ObjectStorageFullAccess: the deployer'"'"'s key signs in to the workload'"'"'s state bucket (LIB-0028 §5, LIB-0038 §1)" else empty end),
        (.iam // {} | if type != "object" then "scaleway.iam must be a mapping" else
          keys_in("scaleway.iam"; ["application", "policy", "apiKey"]),
          (.application | entry_ok("scaleway.iam.application"))
        end),
        (.bucket // {} | if type != "object" then "scaleway.bucket must be a mapping of bucket names" else
          to_entries[] |
            (if (.key | test($kebab)) then empty else "scaleway.bucket.\(.key): bucket name must be kebab-case" end),
            (if .key == "state" then "scaleway.bucket.state: `state` is the workload state bucket'"'"'s instance; configure it as scaleway.state (LIB-0028)" else empty end),
            (.value | entry_ok("scaleway.bucket.\(.key)"))
        end)
      end),
      # Backblaze kinds (LIB-0029 §§1-5).
      (. as $file | .backblaze // {} | if type != "object" then "backblaze must be a mapping" else
        keys_in("backblaze"; ["deployer", "bucket", "apiKey"]),
        (.deployer | entry_ok("backblaze.deployer")),
        (.bucket // {} | if type != "object" then "backblaze.bucket must be a mapping of bucket names" else
          to_entries[] |
            (if (.key | test($kebab)) then empty else "backblaze.bucket.\(.key): bucket name must be kebab-case" end),
            (.value | entry_ok("backblaze.bucket.\(.key)")),
            (.key as $k | .value // {} | objects | select(has("exact_name") | not)
              | ((.name_prefix // "\($file.prefix)\($tag)-\($k)") + "-xxxxxx-" + (.name_suffix // $file.suffix)) as $n
              | if ($n | length) > 50 then "backblaze.bucket.\($k): its name, \($n | length) characters with the random code, is longer than B2'"'"'s 50; shorten the key or set exact_name (LIB-0029 §5)" else empty end)
        end),
        (.bucket // {} | objects | keys) as $buckets |
        (.apiKey // {} | if type != "object" then "backblaze.apiKey must be a mapping of key names" else
          to_entries[] | .key as $k |
            (if ($k | test($kebab)) then empty else "backblaze.apiKey.\($k): key name must be kebab-case" end),
            (if $k == "deployer" then "backblaze.apiKey.deployer: `deployer` is the workload'"'"'s own key'"'"'s instance; configure it as backblaze.deployer (LIB-0041 §1)" else empty end),
            (.value | entry_ok("backblaze.apiKey.\($k)")),
            (.value // {} | objects |
              (if (.buckets | type) != "array" or (.buckets | length) == 0
               then "backblaze.apiKey.\($k).buckets must list at least one of this workload'"'"'s backblaze.bucket keys (LIB-0029 §3)"
               else (.buckets[] | select(type != "string" or (. as $b | $buckets | index($b) | not))
                 | "backblaze.apiKey.\($k).buckets: \(tojson) is not one of this workload'"'"'s backblaze.bucket keys (LIB-0029 §3)") end),
              (if has("bucket_ids") then "backblaze.apiKey.\($k).bucket_ids can'"'"'t be set; list the buckets in buckets instead (LIB-0029 §3)" else empty end),
              (if (.capabilities | type) != "array" or (.capabilities | length) == 0 then "backblaze.apiKey.\($k).capabilities must list what the key may do (LIB-0029 §2)" else empty end)),
            (if .value == null then "backblaze.apiKey.\($k) needs buckets and capabilities (LIB-0029 §§2-3)" else empty end)
        end)
      end),
      # Cloudflare kinds (LIB-0030 §§1-6).
      (. as $file | .cloudflare // {} | if type != "object" then "cloudflare must be a mapping" else
        keys_in("cloudflare"; if $unit == "zone" then ["zone", "deployer", "dnsRecord", "ruleset", "apexRedirect"] else ["zone", "deployer", "bucket", "dnsRecord", "ruleset", "apexRedirect"] end),
        (.deployer | entry_ok("cloudflare.deployer")),
        (.deployer // {} | objects | select(has("account_id")) | "cloudflare.deployer cannot set account_id; the account is the spoke one (LIB-0033 §4)"),
        # A phase entrypoint belongs to the zone, so only a zone holds one (LIB-0036 §3).
        (if $unit == "workload" then ("ruleset", "apexRedirect") as $m | select(has($m))
           | "cloudflare.\($m) is a zone'"'"'s alone; move it into zones/<zone>/zone.yaml (LIB-0036 §3)" else empty end),
        (if has("zone") and ((.zone | type) != "string" or (.zone | test("\\.") | not)) then "cloudflare.zone must be a zone apex domain (LIB-0030 §3)" else empty end),
        (.zone // "") as $dz |
        (("bucket", "dnsRecord", "ruleset", "apexRedirect") as $m | .[$m] // {} |
          if type != "object" then "cloudflare.\($m) must be a mapping of names" else
          to_entries[] | .key as $k | (.value // {}) as $e |
            (if ($k | test($kebab)) then empty else "cloudflare.\($m).\($k): name must be kebab-case" end),
            (.value | entry_ok("cloudflare.\($m).\($k)")),
            ($e | objects | select(has("account_id") or has("zone_id")) | "cloudflare.\($m).\($k) cannot set account_id or zone_id; the account is the spoke one, and a zone is named (LIB-0030 §§4-5)"),
            (if $m == "bucket" then
               ($e | objects | select(has("exact_name") | not)
                 | ((.name_prefix // "\($file.prefix)\($tag)-\($k)") + "-xxxxxx-" + (.name_suffix // $file.suffix)) as $n
                 | if ($n | length) > 63 then "cloudflare.bucket.\($k): its name, \($n | length) characters with the random code, is longer than the 63 R2 allows; shorten the key or set exact_name (LIB-0030 §4)" else empty end)
             else
               (($e | objects | .zone) // $dz) as $z |
               if $z == "" then "cloudflare.\($m).\($k) has no zone, and cloudflare.zone is not set (LIB-0030 §3)"
               elif $unit == "workload" then
                 # A nested workload writes only at its host (LIB-0037 §3).
                 ((($e | objects | .name) // $k) | tostring) as $n |
                 if $host == "" then "cloudflare.\($m).\($k): this workload has no host in zones/\($z)/zone.yaml, so it can'"'"'t write records (LIB-0037 §3)"
                 elif $host == "@" and ($n == "@" or $n == "www" or ($n | test("^_[^.]+(\\.www)?$"))) then empty
                 elif $host != "@" and ($n == $host or ($n | endswith(".\($host)"))) then empty
                 else "cloudflare.\($m).\($k): \($n) is outside this workload'"'"'s host, \($host), in zones/\($z)/zone.yaml (LIB-0037 §3)" end
               else empty end
             end),
            ({dnsRecord: ["type", "content"], ruleset: ["kind", "phase", "rules"], apexRedirect: ["target_url"]}[$m] // [] | .[] as $r
              | select(($e | objects | has($r)) | not) | "cloudflare.\($m).\($k) needs \($r) (LIB-0030 §4)")
          end),
        # The clash checks (§6) run spoke-wide, after every unit.
        empty
      end),
      ([.scaleway.project, (.scaleway.deployer // {} | objects | .application, .policy, .apiKey), .scaleway.state, .scaleway.iam.application, (.scaleway.iam.apiKey // {} | .[]?), (.scaleway.iam.policy // {} | .[]?), (.scaleway.bucket // {} | .[]?), (.scaleway.blockVolume // {} | .[]?), .scaleway.cockpit, .scaleway.privateNetwork, .scaleway.publicGateway, (.scaleway.instance // {} | .[]?), (.backblaze.deployer), (.backblaze.bucket // {} | .[]?), (.backblaze.apiKey // {} | .[]?), (.cloudflare.deployer), (.cloudflare // {} | (.bucket, .dnsRecord, .ruleset) // {} | .[]?)]
        | .[] | objects | select(has("version")) | .version
        | if type == "string" and test("^[0-9]+(\\.[0-9]+){0,2}$") then empty
          else "version \(tojson) must be a quoted X, X.Y or X.Y.Z" end)
    end
  ' <<<"$json")
  if [ -n "$structural" ]; then
    while IFS= read -r msg; do fail "$rel: $msg"; done < <(relabel <<<"$structural")
    continue
  fi
  # A workload's compute (LIB-0043): what can't work, then its leaves.
  if [ "$unit" = workload ]; then
    env_names='[]'
    if [ -f "$SPOKE_DIR/$unit_dir/secrets.workload.yaml" ]; then
      env_names=$(yq -o=json '.' "$SPOKE_DIR/$unit_dir/secrets.workload.yaml" 2>/dev/null | jq -c "$UNIT_JQ"' unwrap("workload") | (.env? // {}) | objects | keys') || env_names='[]'
      [ -n "$env_names" ] || env_names='[]'
    fi
    compute_msgs=$(jq -r --argjson env "$env_names" --arg kebab "$KEBAB" "$COMPUTE_JQ"' compute_problems($env; $kebab)' <<<"$json")
    compute_failed=false
    while IFS= read -r msg; do
      [ -z "$msg" ] && continue
      case "$msg" in
        "warning: "*) echo "::warning::$rel: ${msg#warning: }" >&2 ;;
        *) fail "$rel: $msg"; compute_failed=true ;;
      esac
    done <<<"$compute_msgs"
    [ "$compute_failed" = true ] && continue
    json=$(jq -c "$COMPUTE_JQ"' expand_compute' <<<"$json")
  fi
  printf '%s\n' "$json" >"$(unit_cache "$unit_dir")"

  # Its zone entries, each with its zone, for the clash checks (LIB-0030 §6),
  # which group them across every unit (LIB-0036 §3).
  # An apexRedirect's own placeholders (LIB-0038 §3) are marked, so only
  # someone else's record beside them is a clash.
  jq -c --arg rel "$rel" --arg dp dnsRecords '
    (.cloudflare // {}) as $c | ($c.zone // "") as $dz |
    def zone_of: (.value | objects | .zone) // $dz;
    ([$c.apexRedirect // {} | objects | keys[] | "\(.)-apex", "\(.)-www"]) as $implied |
    {
      rs: [$c.ruleset // {} | to_entries[] | {k: "\($rel) cloudflare.ruleset.\(.key)", z: zone_of, p: (.value | objects | .phase)}],
      ar: [$c.apexRedirect // {} | to_entries[] | {k: "\($rel) cloudflare.apexRedirect.\(.key)", z: zone_of, www: ((.value | objects | .include_www) // true)}],
      dr: [$c.dnsRecord // {} | to_entries[] | {k: "\($rel) \($dp).\(.key)", z: zone_of, n: ((.value | objects | .name) // .key), t: ((.value | objects | .type) // "" | tostring | ascii_upcase), c: (.value | objects | .content), own: (.key as $k | $implied | index($k) != null)}]
    }' <<<"$json" >>"$EXPECTED_DIR/.cache/clash.jsonl"

  for kind in "${KINDS[@]}"; do
    IFS='|' read -r yaml_path module shape deps credentials state units <<<"$kind"
    [ "$unit" = zone ] && [[ "$units" != *z* ]] && continue
    [ "$unit" = workload ] && [[ "$units" != *w* ]] && continue
    # A workload in its zone's project has no project leaf (LIB-0037 §2).
    [ "$module" = scaleway/project ] && [ -n "$ZONE_PROJECT" ] && continue
    jq_path=".${yaml_path}"
    if [ "$credentials" = workload ]; then
      case "$module" in
        cloudflare/*) deps="$deps cf_token" ;;
        backblaze/*) deps="$deps b2_key" ;;
        *) deps="$deps deployer" ;;
      esac
    fi
    [ "$state" = workload ] && deps="$deps deployer state"
    deps=$(tr ' ' '\n' <<<"$deps" | awk 'NF && !seen[$0]++' | tr '\n' ' ')
    if [ "$shape" = map ]; then
      names=$(jq -r "$jq_path // {} | keys[]" <<<"$json")
    elif [ "$shape" = implicit ]; then
      names=main
    elif [ "$shape" = deployer ]; then
      names=deployer
    elif [ "$shape" = cfimplicit ] && [ "$unit" = zone ]; then
      names=deployer
    elif [ "$shape" = cfimplicit ]; then
      # A host, or an R2 bucket (LIB-0037 §3).
      names=$(jq -r --arg host "$host" 'if $host != "" or ((.cloudflare.bucket // {}) | length) > 0 then "deployer" else empty end' <<<"$json")
    elif [ "$shape" = b2implicit ]; then
      # A Backblaze bucket or key (LIB-0041 §1).
      names=$(jq -r 'if ((.backblaze.bucket // {}) | length) + ((.backblaze.apiKey // {}) | length) > 0 then "deployer" else empty end' <<<"$json")
    elif [ "$shape" = state ]; then
      names=state
    else
      names=$(jq -r "if ($jq_path | type) == \"null\" and ((${jq_path%.*} // {}) | has(\"${yaml_path##*.}\") | not) then empty else \"main\" end" <<<"$json")
    fi
    [ -z "$names" ] && continue

    declared=()
    for dep in $deps; do
      dpath=$(dep_yaml_path "$dep")
      if [ -z "$dpath" ] || jq -e "(.${dpath%.*} // {}) | has(\"${dpath##*.}\")" <<<"$json" >/dev/null; then
        declared+=("$dep")
      fi
    done

    while IFS= read -r name; do
      stub="$unit_dir/$module/$name"
      CUR_NAME="$name"
      CUR_KEYRING_WIRING=""
      # `buckets` becomes this instance's own bucket_<key> dependencies, and
      # `config_deps` and `instance_deps` an instance's own (LIB-0043 §1).
      instance_deps=()
      for dep in ${declared[@]+"${declared[@]}"}; do
        if [ "$dep" = buckets ]; then
          while IFS= read -r b; do
            [ -n "$b" ] && instance_deps+=("bucket_$(tr - _ <<<"$b")")
          done < <(jq -r --arg n "$name" "${jq_path}[\$n].buckets[]?" <<<"$json")
        elif [ "$dep" = config_deps ] || [ "$dep" = instance_deps ]; then
          while IFS= read -r d; do
            [ -n "$d" ] && instance_deps+=("$d")
          done < <(jq -r --arg n "$name" --arg which "$dep" '.scaleway._meta.instance[$n] as $m |
            if $which == "config_deps" then
              (if $m.selfDelete then "project", "sd_key" else empty end),
              (if $m.cockpit then "cockpit" else empty end),
              ([$m.keyringWiring[] | .apiKey | strings] | unique[] | "apikey_\(gsub("-"; "_"))"),
              ([$m.keyringWiring[] | .bucket | strings] | unique[] | "sbucket_\(gsub("-"; "_"))")
            else
              "config",
              ($m.volumes[] | "volume_\(gsub("-"; "_"))"),
              (if $m.attached then "private_network" else empty end),
              (if $m.gatewayWait then "gateway" else empty end)
            end' <<<"$json")
          if [ "$dep" = config_deps ]; then CUR_KEYRING_WIRING=$(jq -c --arg n "$name" '.scaleway._meta.instance[$n].keyringWiring' <<<"$json"); fi
        else
          instance_deps+=("$dep")
        fi
      done
      mkdir -p "$EXPECTED_DIR/$stub"
      stub_content "$module" "$credentials" "$state" ${instance_deps[@]+"${instance_deps[@]}"} >"$EXPECTED_DIR/$stub/terragrunt.hcl"
      if [ "$shape" = map ]; then
        instances+=("$unit_dir|$rel|$module|$name|${jq_path}[\"$name\"]|${instance_deps[*]-}|$credentials")
      else
        instances+=("$unit_dir|$rel|$module|$name|$jq_path|${instance_deps[*]-}|$credentials")
      fi
    done <<<"$names"
  done
done

# One entrypoint per zone and phase, one record per name and type (LIB-0030
# §6), across every unit: a zone's own file and its workload's (LIB-0036 §3).
clashes=$(jq -rs '
  (map(.rs) | add // []) as $rs | (map(.ar) | add // []) as $ar | (map(.dr) | add // []) as $dr |
  # The ruleset an apexRedirect implies is among the rulesets (LIB-0038 §3),
  # so two redirects, or a redirect and a ruleset in its phase, share an
  # entrypoint.
  ($rs | group_by([.z, .p])[] | select(length > 1) | "\(map(.k) | join(", ")) share zone \(.[0].z) and phase \(.[0].p); a zone has one entrypoint per phase (LIB-0030 §6)"),
  ($dr | group_by([.z, .n, .t])[] | select(length > 1) | select(([.[0].t] | inside(["MX", "TXT", "CAA", "SRV", "NS"]) | not) or ((map(.c) | unique | length) < length))
    | "\(map(.k) | join(", ")) are one record, \(.[0].n) \(.[0].t) in \(.[0].z) (LIB-0030 §6)"),
  # A name holds one SPF and one DMARC policy, so a service'"'"'s record and a
  # hand-written one can'"'"'t both set it (LIB-0039 §3).
  (("v=spf1", "v=DMARC1") as $p | $dr | map(select(.t == "TXT" and ((.c // "") | tostring | ltrimstr("\"") | startswith($p))))
    | group_by([.z, .n])[] | select(length > 1)
    | "\(map(.k) | join(", ")) are each a \($p) policy at \(.[0].n) in \(.[0].z), which holds one (LIB-0039 §3)"),
  # An apexRedirect holds a placeholder A at @, which an A, AAAA or CNAME
  # there would clash with, and a CNAME at www, which nothing may share.
  (($dr[] | select(.own | not)) as $d | $ar[] | select(.z == $d.z and (($d.n == "@" and ([$d.t] | inside(["A", "AAAA", "CNAME"]))) or ($d.n == "www" and .www)))
    | "\($d.k): the apexRedirect \(.k) already holds a placeholder \(if $d.n == "@" then "A" else "CNAME" end) record at \($d.n) in \($d.z) (LIB-0030 §6)")
' "$EXPECTED_DIR/.cache/clash.jsonl")
while IFS= read -r msg; do [ -n "$msg" ] && fail "$msg"; done <<<"$clashes"

if [ "$errors" -gt 0 ]; then
  echo "::error::$errors problem(s) in workload.yaml or zone.yaml; nothing written" >&2
  exit 1
fi

# Every generated stub on disk, by its GENERATED header.
generated_stubs() {
  local roots=()
  for r in workloads zones; do [ -d "$SPOKE_DIR/$r" ] && roots+=("$r"); done
  [ ${#roots[@]} -gt 0 ] || return 0
  (cd "$SPOKE_DIR" && find "${roots[@]}" -mindepth 5 -maxdepth 6 -name terragrunt.hcl -type f) |
    while IFS= read -r f; do
      if [ "$(head -n1 "$SPOKE_DIR/$f")" = "$HEADER" ]; then echo "$f"; fi
    done | LC_ALL=C sort
}
# A spoke may have workloads and no zones, or the reverse, and find fails on
# a root that doesn't exist, so each is listed only when it does.
expected_stubs() {
  local roots=()
  for r in workloads zones; do [ -d "$EXPECTED_DIR/$r" ] && roots+=("$r"); done
  [ ${#roots[@]} -gt 0 ] || return 0
  (cd "$EXPECTED_DIR" && find "${roots[@]}" -name terragrunt.hcl -type f) | LC_ALL=C sort
}

if [ "$LIST" = true ]; then
  expected_stubs | sed 's|/terragrunt.hcl$||'
  exit 0
fi

if [ "$CHECK" = true ]; then
  if git -C "$SPOKE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      fail "$f is committed, but stubs are generated, never committed (LIB-0023); git rm --cached it and gitignore its provider's stub directory, e.g. /workloads/*/*/scaleway/ or /zones/*/scaleway/"
    done < <(git -C "$SPOKE_DIR" ls-files -- 'workloads/*/*/*/*/terragrunt.hcl' 'zones/*/*/*/*/terragrunt.hcl')
  fi

  # Each secrets.workload.yaml's shape, by its clear-text keys (LIB-0025 §2,
  # LIB-0037 §1).
  for secrets in "$SPOKE_DIR"/workloads/*/*/secrets.workload.yaml; do
    rel="${secrets#"$SPOKE_DIR"/}"
    unit_dir="$(dirname "$rel")"
    values="$SPOKE_DIR/$unit_dir/workload.yaml"
    if [ ! -f "$values" ]; then
      fail "$rel has no $(basename "$values") beside it"
      continue
    fi
    if ! sjson=$(yq -o=json '.' "$secrets"); then
      fail "$rel: not valid YAML"
      continue
    fi
    # Wrapped like its workload.yaml (LIB-0039 §1), with sops beside the
    # wrapper, since sops writes its metadata at the root.
    while IFS= read -r msg; do [ -n "$msg" ] && fail "$rel: $msg"; done < <(jq -r "$UNIT_JQ"' del(.sops?) | shape_problems("workload")' <<<"$sjson" | relabel)
    sjson=$(jq -c "$UNIT_JQ"' (.sops?) as $m | unwrap("workload") | if type == "object" and $m != null then . + {sops: $m} else . end' <<<"$sjson")
    # A unit that failed above has no cache, and its failure already stands.
    [ -f "$(unit_cache "$unit_dir")" ] || continue
    vjson=$(cat "$(unit_cache "$unit_dir")")
    problems=$(jq -r --argjson v "$vjson" '
      def leaves: paths(scalars) as $p | {path: $p, value: getpath($p)};
      if (type != "object") or (has("sops") | not) then
        "has no sops metadata: encrypt it with sops, never commit a secret in clear"
      else
        (del(.sops) | leaves | select((.value | type) != "string" or (.value | test("^ENC\\[") | not))
          | "\(.path | map(tostring) | join(".")) is not encrypted"),
        ((keys - ["sops", "env", "scaleway", "backblaze", "cloudflare"])[] | "unknown key \(.); known: env, scaleway, backblaze, cloudflare"),
        (.env // {} | to_entries[] | select((.value | type) != "string") | "env.\(.key) must be one value, not a list or a map"),
        (.scaleway // {} | to_entries[] as $k |
          if $k.key == "project" or $k.key == "state" then
            empty
          elif $k.key == "deployer" then
            ($k.value // {} | keys[] | select(IN("application", "policy", "apiKey") | not) | "scaleway.deployer.\(.): the deployer is three leaves, so each secret goes under scaleway.deployer.application, .policy or .apiKey (LIB-0038 §1)")
          elif $k.key == "bucket" then
            ($k.value // {} | keys[] as $b | select($v.scaleway.bucket // {} | has($b) | not) | "scaleway.bucket.\($b): values.yaml declares no such bucket")
          elif $k.key == "iam" then
            ($k.value // {} | keys[] | select(IN("application", "policy", "apiKey") | not) | "unknown key scaleway.iam.\(.)"),
            ($k.value // {} | keys[] as $i | select($v.scaleway.iam // {} | has($i) | not) | "scaleway.iam.\($i): values.yaml declares no such entry")
          else "unknown key scaleway.\($k.key)" end),
        (.backblaze // {} | to_entries[] as $k |
          if $k.key == "deployer" then
            empty
          elif $k.key == "bucket" or $k.key == "apiKey" then
            ($k.value // {} | keys[] as $i | select($v.backblaze[$k.key] // {} | has($i) | not) | "backblaze.\($k.key).\($i): values.yaml declares no such entry"),
            (if $k.key == "apiKey" then ($k.value // {} | to_entries[] | select(.value | objects | has("bucket_ids")) | "backblaze.apiKey.\(.key).bucket_ids can'"'"'t be set (LIB-0029 §3)") else empty end)
          else "unknown key backblaze.\($k.key)" end),
        (.cloudflare // {} | to_entries[] as $k |
          if $k.key == "deployer" then
            ($k.value // {} | objects | select(has("account_id")) | "cloudflare.deployer cannot set account_id (LIB-0033 §4)")
          elif ($k.key | IN("bucket", "dnsRecord", "ruleset")) then
            ($k.value // {} | keys[] as $i | select($v.cloudflare[$k.key] // {} | has($i) | not) | "cloudflare.\($k.key).\($i): workload.yaml declares no such entry"),
            ($k.value // {} | to_entries[] | select(.value | objects | has("account_id") or has("zone_id")) | "cloudflare.\($k.key).\(.key) cannot set account_id or zone_id (LIB-0030 §§4-5)")
          else "unknown key cloudflare.\($k.key)" end),
        ([.scaleway.project, (.scaleway.deployer // {} | objects | .application, .policy, .apiKey), .scaleway.state, .scaleway.iam.application, (.scaleway.iam.apiKey // {} | .[]?), (.scaleway.iam.policy // {} | .[]?), (.scaleway.bucket // {} | .[]?), (.backblaze.deployer), (.backblaze.bucket // {} | .[]?), (.backblaze.apiKey // {} | .[]?), (.cloudflare // {} | (.bucket, .dnsRecord, .ruleset) // {} | .[]?)]
          | .[] | objects | to_entries[] | select((.value | type) == "object" or (.value | type) == "array")
          | "\(.key) must be one value, not a list or a map")
      end
    ' <<<"$sjson")
    if [ -n "$problems" ]; then
      while IFS= read -r msg; do fail "$rel: $msg"; done < <(relabel <<<"$problems")
    fi
  done

  for inst in ${instances[@]+"${instances[@]}"}; do
    IFS='|' read -r unit_dir rel module name jq_path declared_deps credentials <<<"$inst"
    case "$rel" in */workload.yaml) secrets="$SPOKE_DIR/$unit_dir/secrets.workload.yaml" ;; *) secrets="$SPOKE_DIR/$unit_dir/secrets.yaml" ;; esac
    entry=$(jq -c "$jq_path // {}" "$(unit_cache "$unit_dir")")
    # scaleway.state.prefix is the stub's state key, not a module input
    # (LIB-0028 §3).
    if [ "$jq_path" = .scaleway.state ]; then entry=$(jq -c 'del(.prefix)' <<<"$entry"); fi
    # backblaze.apiKey.<key>.buckets is the stub's dependencies, not a module
    # input (LIB-0029 §3).
    if [ "$module" = backblaze/api-key ]; then entry=$(jq -c 'del(.buckets)' <<<"$entry"); fi
    sentry='{}'
    env_names='[]'
    if [ -f "$secrets" ]; then
      sentry=$(yq -o=json '.' "$secrets" | jq -c "$UNIT_JQ"' unwrap("workload") | '"$jq_path // {}")
      env_names=$(yq -o=json '.' "$secrets" | jq -c "$UNIT_JQ"' unwrap("workload") | .env // {} | keys')
    fi
    both=$(jq -r --argjson s "$sentry" 'del(.version) | keys - (keys - ($s | keys)) | join(", ")' <<<"$entry")
    if [ -n "$both" ]; then
      fail "$unit_dir: $module/$name sets $both in both values.yaml and secrets.yaml; keep each input in one"
    fi
    refs=$(jq -r --argjson env "$env_names" 'to_entries[] | select((.value | type) == "object" and (.value | has("secretRef"))) | .value.secretRef | select(. as $n | $env | index($n) | not)' <<<"$entry")
    while IFS= read -r ref; do
      [ -n "$ref" ] && fail "$rel: $module/$name has secretRef $ref, which secrets.yaml's env doesn't have"
    done <<<"$refs"
    entry=$(jq -c --argjson s "$sentry" '. + $s' <<<"$entry")
    pin=$(jq -r '.version // empty' <<<"$entry")
    where="$unit_dir: $module/$name"
    if ! version=$(resolve_version "$module" "$pin"); then
      fail "$where: no terraform/$module tag matches version '${pin:-<newest>}'"
      continue
    fi
    if ! props=$(schema_properties "$module" "$version"); then
      fail "$where: could not fetch $SCHEMA_BASE/terraform/$module/v$version/inputs.schema.json"
      continue
    fi
    unknown=$(jq -r --argjson props "$props" 'keys - $props | join(", ")' <<<"$entry")
    # A wiring input the stub sets has to exist at this version too: an older
    # pin can predate it (iam-api-key v0.1.0 has no default_project_id). The
    # provider credentials a stub passes aren't module inputs: root.hcl signs
    # the provider in with them (LIB-0024 §2, LIB-0033 §4, LIB-0041 §2).
    missing_wiring=""
    for dep in $declared_deps; do
      while IFS='|' read -r input _; do
        case "$input" in "" | scaleway_access_key | scaleway_secret_key | cloudflare_api_token | backblaze_application_key_id | backblaze_application_key) continue ;; esac
        if ! jq -e --arg i "$input" 'has($i)' <<<"$entry" >/dev/null &&
           ! jq -e --arg i "$input" 'index($i) != null' <<<"$props" >/dev/null; then
          missing_wiring="${missing_wiring:+$missing_wiring, }$input"
        fi
      done < <(wiring_lines "$module" "$dep" "$credentials")
    done
    if [[ " $declared_deps " == *" bucket_"* ]] && ! jq -e 'index("bucket_ids") != null' <<<"$props" >/dev/null; then
      missing_wiring="${missing_wiring:+$missing_wiring, }bucket_ids"
    fi
    # A Cloudflare zone kind always gets `zone`, from the entry or the
    # workload default (LIB-0030 §3), so its version must take it:
    # cloudflare/ruleset does from v0.2.0.
    # An instance's config takes its keyring's wiring, from v1.1.1 (LIB-0043 §4).
    if [ "$module" = scaleway/compute-instance-config ] && ! jq -e 'index("keyring_wiring") != null' <<<"$props" >/dev/null; then
      missing_wiring="${missing_wiring:+$missing_wiring, }keyring_wiring"
    fi
    case "$module" in
      cloudflare/dns-record | cloudflare/ruleset)
        if ! jq -e 'index("zone") != null' <<<"$props" >/dev/null; then
          missing_wiring="${missing_wiring:+$missing_wiring, }zone"
        fi
        ;;
    esac
    if [ -n "$unknown" ]; then
      fail "$where: $module v$version has no input(s) $unknown"
    elif [ -n "$missing_wiring" ]; then
      fail "$where: $module v$version has no input(s) $missing_wiring, which this workload wires from its dependencies; pin a newer version"
    else
      echo "$where matches $module v$version"
    fi
  done

  if [ "$errors" -gt 0 ]; then
    exit 1
  fi
  echo "Workload workload.yaml and zone.yaml files are valid"
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$SPOKE_DIR/$(dirname "$f")"
  if ! cmp -s "$EXPECTED_DIR/$f" "$SPOKE_DIR/$f" 2>/dev/null; then
    cp "$EXPECTED_DIR/$f" "$SPOKE_DIR/$f"
    chmod 644 "$SPOKE_DIR/$f"
    echo "Wrote $f"
  fi
done < <(expected_stubs)

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$EXPECTED_DIR/$f" ] && continue
  dir="$SPOKE_DIR/$(dirname "$f")"
  rm -f "$SPOKE_DIR/$f"
  rm -rf "$dir/.terragrunt-cache"
  # Remove the instance directory and any provider/module directories it
  # leaves empty, never the unit directory itself.
  while [ "$dir" != "$SPOKE_DIR/workloads" ] && [ "$dir" != "$SPOKE_DIR/zones" ] && [ -z "$(ls -A "$dir")" ] && [ "$(dirname "$(dirname "$dir")")" != "$SPOKE_DIR" ]; do
    [ -f "$dir/workload.yaml" ] || [ -f "$dir/zone.yaml" ] && break
    rmdir "$dir"
    dir="$(dirname "$dir")"
  done
  echo "Removed $f"
done < <(generated_stubs)
