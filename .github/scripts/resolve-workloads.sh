#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl).
# Turns each workloads/<workload>/values.yaml into the stub leaves LIB-0023 §5
# describes, one per kind instance, at
# workloads/<workload>/<provider>/<module>/<instance>/terragrunt.hcl.
#
# A stub holds structure only: it includes root.hcl, declares the dependency
# blocks its kind implies (§4's wiring), and passes their IDs on as inputs.
# Every workload has a project, a deployer and a state bucket, whatever its
# values.yaml declares (LIB-0028 §1). A stub whose state lives in that bucket
# (LIB-0028 §4) also declares its own remote_state, which replaces root.hcl's:
# the bucket comes from its state dependency, and it signs in with the
# workload deployer's key (LIB-0028 §5).
# Backblaze kinds (LIB-0029) sign in with the spoke's Backblaze key and keep
# their state in that same workload bucket. An API key depends on each
# bucket its `buckets` list names, and gets their IDs as bucket_ids.
# Cloudflare kinds (LIB-0030) do the same with the spoke's Cloudflare token.
# A workload's records may land only in a zone whose zone.yaml names it, and a
# zone's entrypoints and records are checked for clashes.
# A workload that a zone names, or that declares an R2 bucket, also gets its own
# Cloudflare token, cloudflare/api-token/deployer, which its Cloudflare leaves
# sign in with (LIB-0033 §4).
# A site workload's features.githubPages (LIB-0034 §§1-2) implies two
# cloudflare.dnsRecord entries, github-pages-root-cname and
# github-pages-www-cname, the CNAMEs at @ and www that point the workload's
# zone at its Pages host. An explicit entry under either key is merged over
# its default, field by field. expand_values applies them before anything
# reads values.yaml, so every check and stub counts them.
# A zone is a unit too (LIB-0036): zones/<zone>/zone.yaml becomes stubs at
# zones/<zone>/<provider>/<module>/<instance>/, the same way. It gets a
# workload's project, deployer, state bucket and Cloudflare token, and takes
# only zone kinds: its records, rulesets and redirects, on its own zone. It
# names at most one workload, which may then write records in it too, and the
# clash checks below run across every unit, so a zone's file and its
# workload's are checked together. Rulesets and redirects are a zone's alone
# (LIB-0036 §3), and a root zones.yaml is refused (LIB-0036 §1).
# Since LIB-0037 a workload may also live in its zone, as
# workloads/<zone>/<workload>/workload.yaml with secrets.workload.yaml beside
# it, or with no zone under workloads/private/<workload>/. Its stubs are one
# segment deeper. expand_workload reads it as a values.yaml: prefix and suffix
# come from its zone, its zone from its directory, and its Pages records from
# the host the zone's `hosts` gives it. A zoned workload has no project of its
# own unless deployments.scaleway.project names one, and its deployer and state
# bucket then depend on the zone's project. Both layouts work side by side
# while a spoke moves.
# Values, defaults and the module version are root.hcl's, at plan time: it
# writes them into the leaf's generated module block as literals, since a
# `type = any` variable set through TF_VAR_ arrives as a string.
#
# Dependencies carry no mock_outputs (LIB-0023's 2026-10-20 amendment, item
# 3): apply runs the saved plan (LIB-0022), and a mock baked into one would be
# applied. A dependent plans once its dependencies are applied.
#
# The stubs are generated, never committed: a workload commits only its
# values.yaml, and the spoke gitignores /workloads/*/*/ (LIB-0023's second
# 2026-10-20 amendment), and a zone's /zones/*/scaleway/ and
# /zones/*/cloudflare/. A workload in its zone (LIB-0037) is ignored by
# provider, /workloads/*/*/scaleway/ and the like, never /workloads/*/*/*/,
# which would hide a site's content/ too. A spoke's terraform-prepare task runs this before
# terragrunt, and terragrunt-run.yml runs it in CI. Terragrunt's [main...HEAD]
# filter plans in worktrees holding only tracked files, so it can't see a stub;
# terragrunt-run.yml selects workload leaves by their values.yaml instead, and
# plans the destroy of an instance values.yaml no longer has from stubs this
# script generates in a worktree of the base.
#
# Without a flag, the script (re)writes every stub and removes the ones
# values.yaml no longer implies -- only files carrying the GENERATED header
# below, so a hand-written file under workloads/ is never deleted.
#
# --list writes nothing and prints each stub directory values.yaml implies,
# one per line, for terragrunt-run.yml to compare a base with its head.
#
# --check writes nothing. It exits 1 if values.yaml is malformed, if any input
# in it isn't one of its module's inputs at the version it resolves to, read
# from that version's published inputs.schema.json (LIB-0023 §6), and if any
# stub is tracked by git. Types are left to terraform plan.
#
# It also checks a workload's secrets.yaml (LIB-0025 §2) without decrypting
# it: sops YAML encrypts values and keeps keys in clear. It fails on a file
# without sops metadata or with a plaintext value, on keys other than `env`
# and the kind paths, on a kind path values.yaml doesn't declare, on an input
# set in both files, and on a `secretRef` to a name `env` doesn't have.
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
#   implicit kind's is `main` in every workload, with or without an entry
#   (LIB-0024 §1, LIB-0028 §1), and `state` is the workload's state bucket,
#   whose instance is `state` (LIB-0028 §2), and `cfimplicit` is the
#   workload's Cloudflare token, whose instance is `deployer`, present when
#   a zone.yaml names the workload or it declares an R2 bucket (LIB-0033 §4),
#   and always present in a zone.
# - credentials (LIB-0024 §2): `spoke` kinds sign in with the spoke's key;
#   `workload` kinds with their provider's workload credential, which they
#   then also depend on: a Scaleway kind the deployer's key, a Cloudflare kind
#   the workload's token, cf_token (LIB-0033 §4).
# - state (LIB-0028 §4): `spoke` kinds keep state in the spoke's bucket;
#   `workload` kinds in the workload's, so they also depend on the state
#   bucket and on the deployer whose key signs in to it.
# - `buckets` (LIB-0029 §3) stands for one bucket_<key> dependency per entry
#   in the instance's own `buckets` list, resolved per instance.
# - units (LIB-0036): `w` if only a workload takes the kind, `z` if only a
#   zone does, `wz` if both do.
KINDS=(
  "scaleway.project|scaleway/project|implicit||spoke|spoke|wz"
  "scaleway.deployer|scaleway/terraform-deployer-iam|implicit|project|spoke|spoke|wz"
  "scaleway.state|scaleway/bucket|state|project|workload|spoke|wz"
  "scaleway.iam.application|scaleway/iam-application|singleton||spoke|workload|w"
  "scaleway.bucket|scaleway/bucket|map|project|workload|workload|w"
  "scaleway.iam.apiKey|scaleway/iam-api-key|singleton|project application|spoke|workload|w"
  "backblaze.bucket|backblaze/bucket|map||spoke|workload|w"
  "backblaze.apiKey|backblaze/api-key|map|buckets|spoke|workload|w"
  "cloudflare.deployer|cloudflare/api-token|cfimplicit||spoke|workload|wz"
  "cloudflare.bucket|cloudflare/bucket|map||workload|workload|w"
  "cloudflare.dnsRecord|cloudflare/dns-record|map||workload|workload|wz"
  "cloudflare.ruleset|cloudflare/ruleset|map||workload|workload|z"
  "cloudflare.apexRedirect|cloudflare/apex-redirect|map||workload|workload|z"
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
    deployer) echo "scaleway/terraform-deployer-iam/main" ;;
    state) echo "scaleway/bucket/state" ;;
    cf_token) echo "cloudflare/api-token/deployer" ;;
    bucket_*) echo "backblaze/bucket/$(echo "${1#bucket_}" | tr _ -)" ;;
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
    scaleway/terraform-deployer-iam:project)
      echo "project_ids|[dependency.project.outputs.module.id]"
      echo "default_project_id|dependency.project.outputs.module.id"
      ;;
    cloudflare/*:cf_token) echo "cloudflare_api_token|dependency.cf_token.outputs.module.token" ;;
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

# values.yaml as JSON, with what its features imply (LIB-0034 §2). A malformed
# features.githubPages is passed through as it is, for the structural check
# to name.
expand_values() {
  yq -o=json '.' "$1" | jq -c '
    (try .features.githubPages catch null) as $p |
    if ($p | type) == "object" and ($p.pagesShim | type) == "string" and ($p.pagesBaseUrl | type) == "string" then
      ({
        "github-pages-root-cname": {name: "@", type: "CNAME", content: $p.pagesBaseUrl, ttl: 1, proxied: false, comment: "github pages root cname (apex, cloudflare-flattened)"},
        "github-pages-www-cname": {name: "www", type: "CNAME", content: $p.pagesBaseUrl, ttl: 1, proxied: false, comment: "github pages www cname"}
      }) as $d |
      .cloudflare = ((.cloudflare // {}) | .dnsRecord = (
        (.dnsRecord // {}) as $e |
        if ($e | type) != "object" then $e
        else $e + ($d | with_entries(.value += (($e[.key] // {}) | if type == "object" then . else {} end))) end))
    else . end'
}

# zone.yaml as JSON, read as a workload's file (LIB-0036 §§1-2): `name`
# defaults to the zone, `prefix` to that name with every character a resource
# name can't hold turned into a dash, and every zone kind acts on the zone.
# root.hcl's workload_values is its twin.
expand_zone() {
  yq -o=json '.' "$1" | jq -c --arg z "$2" '
    if type != "object" then . else
      ((.name // $z) | tostring) as $n |
      (if has("prefix") then . else .prefix = ($n | gsub("[^a-z0-9-]"; "-")) end) |
      .cloudflare = ((.cloudflare // {}) | if type == "object" then . + {zone: $z} else . end)
    end'
}

# workload.yaml as JSON, read as a values.yaml (LIB-0037 §§1-4): `prefix`
# and `suffix` from deployments.scaleway.project, else the zone's; the zone
# from the directory; a project entry only when the workload has its own; and
# the Pages records its host implies, under any explicit entry of the same key.
# root.hcl's workload_values is its twin.
# expand_workload <file> <zone or private> <zone file JSON> <host> <username>
expand_workload() {
  yq -o=json '.' "$1" | jq -c --arg z "$2" --argjson zf "$3" --arg host "$4" --arg user "$5" '
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
    end'
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

# zones/<zone>/zone.yaml (LIB-0036 §1): each registers its zone to the
# workload it names, or to none, and since LIB-0037 §3 gives each host to the
# workload under workloads/<zone>/ that serves it.
APEX='^[a-z0-9-]+(\.[a-z0-9-]+)+$'
LABEL='^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'
for zone_file in "$SPOKE_DIR"/zones/*/zone.yaml; do
  zone="$(basename "$(dirname "$zone_file")")"
  [[ "$zone" =~ $APEX ]] || continue
  entry=$(yq -o=json '.' "$zone_file" 2>/dev/null | jq -c '
    if type != "object" then {workload: "", hosts: {}} else
      {workload: (if (.workload | type) == "string" then .workload else "" end),
       hosts: (if (.hosts | type) == "object" then (.hosts | with_entries(select(.value | type == "string"))) else {} end)}
    end') || entry='{"workload":"","hosts":{}}'
  ZONES=$(jq -c --arg z "$zone" --argjson e "$entry" '.[$z] = $e' <<<"$ZONES")
done

# Each unit, a workload's values.yaml or a zone's zone.yaml, validated and
# rendered into $EXPECTED_DIR at the path its stubs have in the spoke. A
# unit's expanded file is cached for --check, and its zone entries are
# collected for the spoke-wide clash checks below.
instances=()   # "<unit dir>|<unit file>|<module>|<instance>|<jq path>|<declared dependencies>|<credentials>"
unit_files=()
# A workload's directory under workloads/ is a zone, `private`, or, in the old
# layout, the workload itself (LIB-0037 §1).
is_parent() { [[ "$1" =~ $APEX ]] || [ "$1" = private ]; }
for f in "$SPOKE_DIR"/workloads/*/values.yaml "$SPOKE_DIR"/workloads/*/*/workload.yaml "$SPOKE_DIR"/zones/*/zone.yaml; do
  rel="${f#"$SPOKE_DIR"/}"
  parent=$(cut -d/ -f2 <<<"$rel")
  case "$rel" in
    workloads/*/values.yaml)
      if is_parent "$parent"; then fail "$rel: workloads/$parent/ holds workloads, each in its own directory with a workload.yaml (LIB-0037 §1)"; continue; fi ;;
    workloads/*/*/workload.yaml)
      if ! is_parent "$parent"; then fail "$rel: workloads/$parent/ isn't a zone or private, so it can't hold a workload.yaml (LIB-0037 §1)"; continue; fi ;;
  esac
  unit_files+=("$rel")
done
for f in "$SPOKE_DIR"/workloads/*/workload.yaml "$SPOKE_DIR"/workloads/*/*/values.yaml; do
  rel="${f#"$SPOKE_DIR"/}"
  case "$rel" in
    workloads/*/workload.yaml) fail "$rel: a workload.yaml lives in workloads/<zone>/<workload>/ or workloads/private/<workload>/ (LIB-0037 §1)" ;;
    *) is_parent "$(cut -d/ -f2 <<<"$rel")" && fail "$rel: a workload under workloads/<zone>/ or workloads/private/ has a workload.yaml, not a values.yaml (LIB-0037 §1)" ;;
  esac
done
: >"$EXPECTED_DIR/.cache/clash.jsonl"
for rel in ${unit_files[@]+"${unit_files[@]}"}; do
  unit_root="${rel%%/*}"
  workload="$(basename "$(dirname "$rel")")"
  unit_dir="$(dirname "$rel")"
  # A workload in its zone (LIB-0037): its zone or `private`, and its host.
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
    # What a zone's file can't say, read before its defaults fill it in.
    zone_problems=$(jq -r --arg kebab "$KEBAB" '
      if type != "object" then "the file must be a mapping"
      else
        (if has("name") and ((.name | type) != "string" or .name == "") then "name must be a non-empty string (LIB-0036 §1)" else empty end),
        (if has("prefix") and ((.prefix | type) != "string" or (.prefix | test("^[a-z0-9-]+$") | not)) then "prefix may hold only a-z, 0-9 and - (LIB-0036 §1)" else empty end),
        (if has("workload") and ((.workload | type) != "string" or (.workload | test($kebab) | not)) then "workload must name one workload (LIB-0036 §1)" else empty end),
        (.cloudflare // {} | objects |
          (if has("zone") then "cloudflare.zone can'"'"'t be set; the directory names the zone (LIB-0036 §1)" else empty end),
          (("dnsRecord", "ruleset", "apexRedirect") as $m | .[$m] // {} | objects | to_entries[]
            | select(.value | objects | has("zone")) | "cloudflare.\($m).\(.key) can'"'"'t set zone; the directory names it (LIB-0036 §1)"))
      end' <<<"$raw")
    # Its hosts (LIB-0037 §3): who serves the apex and each subdomain.
    host_problems=$(jq -r --arg kebab "$KEBAB" --arg label "$LABEL" '
      objects | select(has("hosts")) |
      if (.hosts | type) != "object" then "hosts must be a mapping of host to workload (LIB-0037 §3)" else
        # Beside hosts, workload still names a workloads/<w>/ unit, so a
        # spoke can bootstrap a workload in its zone before it moves; hosts
        # names only workloads/<zone>/<w>/ ones (LIB-0037 §3).
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
    owner=$(jq -r --arg kebab "$KEBAB" 'if type == "object" and (.workload | type) == "string" and (.workload | test($kebab)) then .workload else "" end' <<<"$raw")
    if [ -n "$owner" ] && [ ! -f "$SPOKE_DIR/workloads/$owner/values.yaml" ]; then
      zone_problems="${zone_problems:+$zone_problems$'\n'}workload $owner has no workloads/$owner/values.yaml (LIB-0036 §1)"
    fi
    if [ -e "$SPOKE_DIR/$unit_dir/secrets.yaml" ]; then
      zone_problems="${zone_problems:+$zone_problems$'\n'}a zone has no secrets.yaml; delete $unit_dir/secrets.yaml (LIB-0036, Out of scope)"
    fi
    if [ -n "$zone_problems" ]; then
      while IFS= read -r msg; do fail "$rel: $msg"; done <<<"$zone_problems"
      continue
    fi
    json=$(expand_zone "$SPOKE_DIR/$rel" "$workload")
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
    if [ "$parent" = private ]; then zf='{}'; else zf=$(yq -o=json '. // {}' "$SPOKE_DIR/zones/$parent/zone.yaml" 2>/dev/null | jq -c 'objects') || zf='{}'; [ -n "$zf" ] || zf='{}'; fi
    host=$(jq -r --arg z "$parent" --arg w "$workload" '.[$z].hosts // {} | to_entries[] | select(.value == $w) | .key' <<<"$ZONES" | head -n1)
    # What a workload.yaml can't say, read before its defaults fill it in.
    workload_problems=$(jq -r --arg kebab "$KEBAB" --arg z "$parent" --arg host "$host" '
      def keys_in($where; $allowed): (keys - $allowed)[] | "unknown key \($where).\(.); known: \($allowed | join(", "))";
      if type != "object" then "the file must be a mapping"
      else
        (if has("features") then "features is replaced by deployments; githubPages moves to deployments.githubPages (LIB-0037 §4)" else empty end),
        ((["prefix", "suffix"] - (keys - ["prefix", "suffix"]))[] as $k | select(has($k)) | "\($k) moves to deployments.scaleway.project.\($k) (LIB-0037 §2)"),
        ((keys - ["name", "deployments", "scaleway", "backblaze", "cloudflare", "features", "prefix", "suffix"])[] | "unknown key \(.); known: name, deployments, scaleway, backblaze, cloudflare"),
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
          (if has("zone") then "cloudflare.zone can'"'"'t be set; the directory names the zone (LIB-0037 §1)" else empty end),
          (if $z == "private" and (.dnsRecord // {} | objects | length > 0) then "cloudflare.dnsRecord needs a zone, which a private workload has none of (LIB-0037 §1)" else empty end),
          (.dnsRecord // {} | objects | to_entries[] | select(.value | objects | has("zone")) | "cloudflare.dnsRecord.\(.key) can'"'"'t set zone; the directory names it (LIB-0037 §1)"))
      end' <<<"$raw")
    if [ -e "$SPOKE_DIR/$unit_dir/secrets.yaml" ]; then
      workload_problems="${workload_problems:+$workload_problems$'\n'}secrets.yaml is now secrets.workload.yaml; rename it (LIB-0037 §1)"
    fi
    if [ -n "$workload_problems" ]; then
      while IFS= read -r msg; do fail "$rel: $msg"; done <<<"$workload_problems"
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
    json=$(expand_workload "$SPOKE_DIR/$rel" "$parent" "$zf" "$host" "$user")
  else
    unit=workload
    if [[ ! "$workload" =~ $KEBAB ]]; then
      fail "$rel: workload name '$workload' must be kebab-case"
      continue
    fi
    if ! json=$(expand_values "$SPOKE_DIR/$rel"); then
      fail "$rel: not valid YAML"
      continue
    fi
  fi
  # A nested workload's names carry its name (LIB-0037 §2).
  if [ "$nested" = true ]; then tag="-$name"; else tag=""; fi

  structural=$(jq -r --arg kebab "$KEBAB" --arg workload "$workload" --arg unit "$unit" --argjson zones "$ZONES" --arg nested "$nested" --arg host "$host" --arg tag "$tag" '
    def entry_ok($where): if . == null or type == "object" then empty else "\($where) must be a mapping of module inputs" end;
    def keys_in($where; $allowed): (keys - $allowed)[] | "unknown key \($where).\(.); known: \($allowed | join(", "))";
    if type != "object" then "the file must be a mapping"
    else
      keys_in(""; if $unit == "zone" then ["name", "prefix", "suffix", "workload", "hosts", "scaleway", "cloudflare"]
                  else ["prefix", "suffix", "features", "scaleway", "backblaze", "cloudflare"] end),
      # What a workload is for, beyond its kinds (LIB-0034 §1).
      (.features // {} | if type != "object" then "features must be a mapping" else
        keys_in("features"; ["githubPages"]),
        (.githubPages | if . == null then empty elif type != "object" then "features.githubPages must be a mapping of pagesShim and pagesBaseUrl (LIB-0034 §1)" else
          keys_in("features.githubPages"; ["pagesShim", "pagesBaseUrl"]),
          (if (.pagesShim | type) == "string" and (.pagesShim | test("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$")) then empty
           else "features.githubPages.pagesShim must be the shim repo, as owner/name (LIB-0034 §1)" end),
          (if (.pagesBaseUrl | type) == "string" and (.pagesBaseUrl | test("^[a-z0-9-]+(\\.[a-z0-9-]+)+$")) then empty
           else "features.githubPages.pagesBaseUrl must be the Pages host, e.g. owner.github.io (LIB-0034 §1)" end)
        end)
      end),
      (if (.features.githubPages? | type) == "object" and ((.cloudflare.zone? // "") == "") then
         "features.githubPages needs cloudflare.zone, the zone its records land in (LIB-0034 §1)" else empty end),
      (if (.prefix | type) != "string" or .prefix == "" then "prefix must be a non-empty string" else empty end),
      (if (.suffix | type) != "string" or .suffix == "" then "suffix must be a non-empty string" else empty end),
      (.scaleway // {} | if type != "object" then "scaleway must be a mapping" else
        keys_in("scaleway"; if $unit == "zone" then ["project", "deployer", "state"] else ["project", "deployer", "state", "bucket", "iam"] end),
        (.project | entry_ok("scaleway.project")),
        (.deployer | entry_ok("scaleway.deployer")),
        (.state | entry_ok("scaleway.state")),
        # The workload state bucket (LIB-0028 §§2-3, §5).
        (.state // {} | objects |
          (if has("prefix") and ((.prefix | type) != "string" or (.prefix | test("^[^/].*/$") | not))
           then "scaleway.state.prefix must not start with / and must end with one (LIB-0028 §3)" else empty end),
          (if .enable_versioning == false then "scaleway.state.enable_versioning can'"'"'t be false: versioning is the state'"'"'s only protection (LIB-0028 §2)" else empty end),
          (if .storage_class == "glacier" then "scaleway.state.storage_class can'"'"'t be glacier: state moved to GLACIER after 90 days can'"'"'t be read without a restore (LIB-0028 §2)" else empty end)),
        (.deployer // {} | objects | select(.project_permission_sets | type == "array")
          | if (.project_permission_sets | index("ObjectStorageFullAccess")) == null
            then "scaleway.deployer.project_permission_sets must keep ObjectStorageFullAccess: the deployer'"'"'s key signs in to the workload'"'"'s state bucket (LIB-0028 §5)" else empty end),
        (.iam // {} | if type != "object" then "scaleway.iam must be a mapping" else
          keys_in("scaleway.iam"; ["application", "apiKey"]),
          (.application | entry_ok("scaleway.iam.application")),
          (.apiKey | entry_ok("scaleway.iam.apiKey"))
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
        keys_in("backblaze"; ["bucket", "apiKey"]),
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
        (if has("zone") and ((.zone | type) != "string" or (.zone | test("\\.") | not)) then "cloudflare.zone must be a zone apex domain (LIB-0030 §3)"
         elif $unit == "workload" and $nested != "true" and has("zone") and ($zones[.zone].workload // "") != $workload then "cloudflare.zone: \(.zone) is not registered to workload \($workload), in zones/\(.zone)/zone.yaml (LIB-0036 §3)"
         else empty end),
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
               elif $unit == "workload" and $nested == "true" then
                 # A nested workload writes only at its host (LIB-0037 §3).
                 ((($e | objects | .name) // $k) | tostring) as $n |
                 if $host == "" then "cloudflare.\($m).\($k): this workload has no host in zones/\($z)/zone.yaml, so it can'"'"'t write records (LIB-0037 §3)"
                 elif $host == "@" and ($n == "@" or $n == "www" or ($n | test("^_[^.]+(\\.www)?$"))) then empty
                 elif $host != "@" and ($n == $host or ($n | endswith(".\($host)"))) then empty
                 else "cloudflare.\($m).\($k): \($n) is outside this workload'"'"'s host, \($host), in zones/\($z)/zone.yaml (LIB-0037 §3)" end
               elif $unit == "workload" and ($zones[$z].workload // "") != $workload then "cloudflare.\($m).\($k): zone \($z) is not registered to workload \($workload), in zones/\($z)/zone.yaml (LIB-0036 §3)"
               else empty end
             end),
            ({dnsRecord: ["type", "content"], ruleset: ["kind", "phase", "rules"], apexRedirect: ["target_url"]}[$m] // [] | .[] as $r
              | select(($e | objects | has($r)) | not) | "cloudflare.\($m).\($k) needs \($r) (LIB-0030 §4)")
          end),
        # The clash checks (§6) run spoke-wide, after every unit.
        empty
      end),
      ([.scaleway.project, .scaleway.deployer, .scaleway.state, .scaleway.iam.application, .scaleway.iam.apiKey, (.scaleway.bucket // {} | .[]?), (.backblaze.bucket // {} | .[]?), (.backblaze.apiKey // {} | .[]?), (.cloudflare.deployer), (.cloudflare // {} | (.bucket, .dnsRecord, .ruleset, .apexRedirect) // {} | .[]?)]
        | .[] | objects | select(has("version")) | .version
        | if type == "string" and test("^[0-9]+(\\.[0-9]+){0,2}$") then empty
          else "version \(tojson) must be a quoted X, X.Y or X.Y.Z" end)
    end
  ' <<<"$json")
  if [ -n "$structural" ]; then
    while IFS= read -r msg; do fail "$rel: $msg"; done <<<"$structural"
    continue
  fi
  printf '%s\n' "$json" >"$(unit_cache "$unit_dir")"

  # Its zone entries, each with its zone, for the clash checks (LIB-0030 §6),
  # which group them across every unit (LIB-0036 §3).
  jq -c --arg rel "$rel" '
    (.cloudflare // {}) as $c | ($c.zone // "") as $dz |
    def zone_of: (.value | objects | .zone) // $dz;
    {
      rs: [$c.ruleset // {} | to_entries[] | {k: "\($rel) cloudflare.ruleset.\(.key)", z: zone_of, p: (.value | objects | .phase)}],
      ar: [$c.apexRedirect // {} | to_entries[] | {k: "\($rel) cloudflare.apexRedirect.\(.key)", z: zone_of, www: ((.value | objects | .include_www) // true)}],
      dr: [$c.dnsRecord // {} | to_entries[] | {k: "\($rel) cloudflare.dnsRecord.\(.key)", z: zone_of, n: ((.value | objects | .name) // .key), t: ((.value | objects | .type) // "" | tostring | ascii_upcase), c: (.value | objects | .content)}]
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
        *) deps="$deps deployer" ;;
      esac
    fi
    [ "$state" = workload ] && deps="$deps deployer state"
    deps=$(tr ' ' '\n' <<<"$deps" | awk 'NF && !seen[$0]++' | tr '\n' ' ')
    if [ "$shape" = map ]; then
      names=$(jq -r "$jq_path // {} | keys[]" <<<"$json")
    elif [ "$shape" = implicit ]; then
      names=main
    elif [ "$shape" = cfimplicit ] && [ "$unit" = zone ]; then
      names=deployer
    elif [ "$shape" = cfimplicit ] && [ "$nested" = true ]; then
      # A host, or an R2 bucket (LIB-0037 §3).
      names=$(jq -r --arg host "$host" 'if $host != "" or ((.cloudflare.bucket // {}) | length) > 0 then "deployer" else empty end' <<<"$json")
    elif [ "$shape" = cfimplicit ]; then
      names=$(jq -r --arg w "$workload" --argjson zones "$ZONES" '
        if ([$zones | to_entries[] | select(.value.workload? == $w)] | length) > 0
           or ((.cloudflare.bucket // {}) | length) > 0 then "deployer" else empty end' <<<"$json")
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
      # `buckets` becomes this instance's own bucket_<key> dependencies.
      instance_deps=()
      for dep in ${declared[@]+"${declared[@]}"}; do
        if [ "$dep" = buckets ]; then
          while IFS= read -r b; do
            [ -n "$b" ] && instance_deps+=("bucket_$(tr - _ <<<"$b")")
          done < <(jq -r --arg n "$name" "${jq_path}[\$n].buckets[]?" <<<"$json")
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
  ($rs | group_by([.z, .p])[] | select(length > 1) | "\(map(.k) | join(", ")) share zone \(.[0].z) and phase \(.[0].p); a zone has one entrypoint per phase (LIB-0030 §6)"),
  ($ar | group_by(.z)[] | select(length > 1) | "\(map(.k) | join(", ")) share zone \(.[0].z) (LIB-0030 §6)"),
  ($rs[] | select(.p == "http_request_dynamic_redirect") | . as $r | select($ar | any(.z == $r.z)) | "\(.k): the http_request_dynamic_redirect entrypoint of \(.z) belongs to its apexRedirect (LIB-0030 §6)"),
  ($dr | group_by([.z, .n, .t])[] | select(length > 1) | select(([.[0].t] | inside(["MX", "TXT", "CAA", "SRV", "NS"]) | not) or ((map(.c) | unique | length) < length))
    | "\(map(.k) | join(", ")) are one record, \(.[0].n) \(.[0].t) in \(.[0].z) (LIB-0030 §6)"),
  # An apexRedirect holds a placeholder A at @, which an A, AAAA or CNAME
  # there would clash with, and a CNAME at www, which nothing may share.
  ($dr[] as $d | $ar[] | select(.z == $d.z and (($d.n == "@" and ([$d.t] | inside(["A", "AAAA", "CNAME"]))) or ($d.n == "www" and .www)))
    | "\($d.k): the apexRedirect \(.k) already holds a placeholder \(if $d.n == "@" then "A" else "CNAME" end) record at \($d.n) in \($d.z) (LIB-0030 §6)")
' "$EXPECTED_DIR/.cache/clash.jsonl")
while IFS= read -r msg; do [ -n "$msg" ] && fail "$msg"; done <<<"$clashes"

if [ "$errors" -gt 0 ]; then
  echo "::error::$errors problem(s) in values.yaml or zone.yaml; nothing written" >&2
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
      fail "$f is committed, but stubs are generated, never committed (LIB-0023); git rm --cached it and gitignore its provider's stub directory, e.g. /workloads/*/scaleway/, /workloads/*/*/scaleway/ or /zones/*/scaleway/"
    done < <(git -C "$SPOKE_DIR" ls-files -- 'workloads/*/*/*/*/terragrunt.hcl' 'zones/*/*/*/*/terragrunt.hcl')
  fi

  # Each secrets.yaml's shape, by its clear-text keys (LIB-0025 §2).
  # A nested workload's is secrets.workload.yaml (LIB-0037 §1).
  for secrets in "$SPOKE_DIR"/workloads/*/secrets.yaml "$SPOKE_DIR"/workloads/*/*/secrets.workload.yaml; do
    rel="${secrets#"$SPOKE_DIR"/}"
    unit_dir="$(dirname "$rel")"
    case "$rel" in */secrets.workload.yaml) values="$SPOKE_DIR/$unit_dir/workload.yaml" ;; *) values="$SPOKE_DIR/$unit_dir/values.yaml" ;; esac
    if [ ! -f "$values" ]; then
      fail "$rel has no $(basename "$values") beside it"
      continue
    fi
    if ! sjson=$(yq -o=json '.' "$secrets"); then
      fail "$rel: not valid YAML"
      continue
    fi
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
          if $k.key == "project" or $k.key == "deployer" or $k.key == "state" then
            empty
          elif $k.key == "bucket" then
            ($k.value // {} | keys[] as $b | select($v.scaleway.bucket // {} | has($b) | not) | "scaleway.bucket.\($b): values.yaml declares no such bucket")
          elif $k.key == "iam" then
            ($k.value // {} | keys[] | select(. != "application" and . != "apiKey") | "unknown key scaleway.iam.\(.)"),
            ($k.value // {} | keys[] as $i | select($v.scaleway.iam // {} | has($i) | not) | "scaleway.iam.\($i): values.yaml declares no such entry")
          else "unknown key scaleway.\($k.key)" end),
        (.backblaze // {} | to_entries[] as $k |
          if $k.key == "bucket" or $k.key == "apiKey" then
            ($k.value // {} | keys[] as $i | select($v.backblaze[$k.key] // {} | has($i) | not) | "backblaze.\($k.key).\($i): values.yaml declares no such entry"),
            (if $k.key == "apiKey" then ($k.value // {} | to_entries[] | select(.value | objects | has("bucket_ids")) | "backblaze.apiKey.\(.key).bucket_ids can'"'"'t be set (LIB-0029 §3)") else empty end)
          else "unknown key backblaze.\($k.key)" end),
        (.cloudflare // {} | to_entries[] as $k |
          if $k.key == "deployer" then
            ($k.value // {} | objects | select(has("account_id")) | "cloudflare.deployer cannot set account_id (LIB-0033 §4)")
          elif ($k.key | IN("bucket", "dnsRecord", "ruleset", "apexRedirect")) then
            ($k.value // {} | keys[] as $i | select($v.cloudflare[$k.key] // {} | has($i) | not) | "cloudflare.\($k.key).\($i): values.yaml declares no such entry"),
            ($k.value // {} | to_entries[] | select(.value | objects | has("account_id") or has("zone_id")) | "cloudflare.\($k.key).\(.key) cannot set account_id or zone_id (LIB-0030 §§4-5)")
          else "unknown key cloudflare.\($k.key)" end),
        ([.scaleway.project, .scaleway.deployer, .scaleway.state, .scaleway.iam.application, .scaleway.iam.apiKey, (.scaleway.bucket // {} | .[]?), (.backblaze.bucket // {} | .[]?), (.backblaze.apiKey // {} | .[]?), (.cloudflare // {} | (.bucket, .dnsRecord, .ruleset, .apexRedirect) // {} | .[]?)]
          | .[] | objects | to_entries[] | select((.value | type) == "object" or (.value | type) == "array")
          | "\(.key) must be one value, not a list or a map")
      end
    ' <<<"$sjson")
    if [ -n "$problems" ]; then
      while IFS= read -r msg; do fail "$rel: $msg"; done <<<"$problems"
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
      sentry=$(yq -o=json '.' "$secrets" | jq -c "$jq_path // {}")
      env_names=$(yq -o=json '.' "$secrets" | jq -c '.env // {} | keys')
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
    # the provider in with them (LIB-0024 §2, LIB-0033 §4).
    missing_wiring=""
    for dep in $declared_deps; do
      while IFS='|' read -r input _; do
        case "$input" in "" | scaleway_access_key | scaleway_secret_key | cloudflare_api_token) continue ;; esac
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
    case "$module" in
      cloudflare/dns-record | cloudflare/ruleset | cloudflare/apex-redirect)
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
  echo "Workload values.yaml and zone.yaml files are valid"
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
    [ -f "$dir/values.yaml" ] || [ -f "$dir/zone.yaml" ] && break
    rmdir "$dir"
    dir="$(dirname "$dir")"
  done
  echo "Removed $f"
done < <(generated_stubs)
