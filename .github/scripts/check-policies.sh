#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl).
# Checks the spoke against the policies its policies.yaml turns on (LIB-0045),
# and exits 1 listing every violation.
#
# It builds one inventory of the spoke's leaves (§2), one record each:
#   {path, file, line, unit: {type, id}, provider, module, modules, instance,
#    resources}
# - unit leaves from resolve-workloads.sh --list, beside this script: every
#   leaf a workload.yaml or zone.yaml implies, implied ones included. A
#   workload's unit.id is <parent>/<workload>, a zone's its apex.
# - hand-written leaves, every terraform/**/terragrunt.hcl, whose unit is
#   {spoke, <leaf dir>}: module is the one its LIB-0004 path names, modules
#   that and every library module it sources, from terragrunt.hcl or a module
#   block in its own *.tf, and resources every `resource "<type>"` in its own
#   *.tf. A rule matches on modules and resources, never on module alone.
# line points at the leaf's entry in its unit file, best-effort.
#
# A policy is policies/<id>.jq beside this script (§3): a jq filter from the
# inventory, with $params the spoke's settings for it, to one
# {path, file, line?, message} per violation, calling error() when its params
# are wrong. Its params' JSON Schema is policies/<id>.schema.json, which
# generate-module-redirects.sh publishes as part of schemas/policies/v1.json.
#
# policies.yaml (§4) runs each policy its `policies` map names, with that
# entry as its params. An entry's `exempt` list drops one violation each by
# path, with a required reason the run prints; an exemption that matches no
# violation fails. Without policies.yaml nothing is checked.
#
# It never decrypts anything and needs no network: a spoke runs it in
# terragrunt-run.yml's prepare_cmd, after resolve-workloads.sh --check, so a
# violation fails the PR before the first plan. Lives under .github/scripts/
# so the workflows/ track versions it.
#
# --inventory prints the inventory as JSON and checks nothing.
set -euo pipefail

INVENTORY_ONLY=false
case "${1:-}" in
  --inventory) INVENTORY_ONLY=true ;;
  "") ;;
  -h|--help) echo "usage: $0 [--inventory]"; exit 0 ;;
  *) echo "usage: $0 [--inventory]" >&2; exit 2 ;;
esac

SPOKE_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_DIR="$SCRIPT_DIR/policies"
CONFIG="policies.yaml"

if [ ! -f "$SPOKE_DIR/spoke.hcl" ]; then
  echo "::error::No spoke.hcl in $SPOKE_DIR; run this from the spoke's repo root" >&2
  exit 1
fi
for tool in yq jq; do
  if ! command -v "$tool" >/dev/null; then
    echo "::error::check-policies.sh needs $tool on PATH" >&2
    exit 1
  fi
done

if [ "$INVENTORY_ONLY" = false ] && [ ! -f "$SPOKE_DIR/$CONFIG" ]; then
  echo "::notice::No $CONFIG; no policies to check (LIB-0045 §4)"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Unit leaves. resolve-workloads.sh fails on a malformed unit file, which
# --check has already reported.
if ! "$SCRIPT_DIR/resolve-workloads.sh" --list >"$WORK/stubs" 2>"$WORK/stubs.err"; then
  cat "$WORK/stubs.err" >&2
  echo "::error::resolve-workloads.sh --list failed, so the inventory is incomplete; fix the unit files first" >&2
  exit 1
fi

# Every YAML path in a unit file with its line, once per file, for the
# entries' lines.
unit_lines() {
  local cache
  cache="$WORK/lines-$(tr / _ <<<"$1").json"
  if [ ! -f "$cache" ]; then
    yq -o=json '[.. | {"p": path, "l": (key | line)}]' "$SPOKE_DIR/$1" 2>/dev/null >"$cache" || echo '[]' >"$cache"
  fi
  echo "$cache"
}

: >"$WORK/inventory.jsonl"
while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    workloads/*/*/*/*/*)
      IFS=/ read -r _ parent workload provider module instance <<<"$path"
      file="workloads/$parent/$workload/workload.yaml"
      unit=$(jq -nc --arg id "$parent/$workload" '{type: "workload", id: $id}')
      root=workload
      ;;
    zones/*/*/*/*)
      IFS=/ read -r _ zone provider module instance <<<"$path"
      file="zones/$zone/zone.yaml"
      unit=$(jq -nc --arg id "$zone" '{type: "zone", id: $id}')
      root=zone
      ;;
    *) continue ;;
  esac
  # The entry is the instance's key under its provider, when there is one.
  line=$(jq -r --arg r "$root" --arg p "$provider" --arg i "$instance" \
    'first(.[] | select(.p[0] == $r and .p[1] == $p and .p[-1] == $i) | .l) // empty' "$(unit_lines "$file")")
  jq -nc --arg path "$path" --arg file "$file" --arg line "$line" --argjson unit "$unit" \
    --arg provider "$provider" --arg module "$provider/$module" --arg instance "$instance" \
    '{path: $path, file: $file, line: (if $line == "" then null else ($line | tonumber) end), unit: $unit,
      provider: $provider, module: $module, modules: [$module], instance: $instance, resources: []}' >>"$WORK/inventory.jsonl"
done <"$WORK/stubs"

# Hand-written leaves, under terraform/ (LIB-0004).
if [ -d "$SPOKE_DIR/terraform" ]; then
  (cd "$SPOKE_DIR" && find terraform -name terragrunt.hcl -type f -not -path '*/.terragrunt-cache/*' -not -path '*/.terraform/*') |
    LC_ALL=C sort >"$WORK/leaves"
  while IFS= read -r f; do
    dir="$(dirname "$f")"
    IFS=/ read -r _ provider module instance <<<"$dir"
    module="$provider/$module"
    # Every library module the leaf sources, from terragrunt.hcl's terraform
    # block or a module block in its own *.tf, by the provider and module its
    # URL names: a short URL or a git:: ref (LIB-0009).
    modules=$({ cat "$SPOKE_DIR/$f" "$SPOKE_DIR/$dir"/*.tf 2>/dev/null || true; } |
      sed -nE 's#^[[:space:]]*source[[:space:]]*=[[:space:]]*".*terraform/([a-z0-9-]+)/([a-z0-9-]+)/v[0-9][^"]*".*#\1/\2#p' |
      LC_ALL=C sort -u | jq -Rsc 'split("\n") | map(select(. != ""))')
    resources=$({ cat "$SPOKE_DIR/$dir"/*.tf 2>/dev/null || true; } |
      sed -nE 's#^[[:space:]]*resource[[:space:]]+"([^"]+)".*#\1#p' | LC_ALL=C sort -u | jq -Rsc 'split("\n") | map(select(. != ""))')
    jq -nc --arg path "$dir" --arg file "$f" --arg provider "$provider" --arg module "$module" \
      --arg instance "${instance:-}" --argjson modules "$modules" --argjson resources "$resources" \
      '{path: $path, file: $file, line: null, unit: {type: "spoke", id: $path},
        provider: $provider, module: $module, modules: ([$module] + $modules | unique), instance: $instance, resources: $resources}' >>"$WORK/inventory.jsonl"
  done <"$WORK/leaves"
fi

jq -s '.' "$WORK/inventory.jsonl" >"$WORK/inventory.json"
if [ "$INVENTORY_ONLY" = true ]; then
  cat "$WORK/inventory.json"
  exit 0
fi

errors=0
fail() { echo "::error file=$CONFIG::$*" >&2; errors=$((errors + 1)); }

if ! config=$(yq -o=json '.' "$SPOKE_DIR/$CONFIG" 2>/dev/null); then
  fail "not valid YAML"
  exit 1
fi
shape=$(jq -r '
  if type != "object" then "the file must be a mapping with a policies key"
  else
    (keys - ["policies"] | .[] | "\(.) isn'"'"'t a key of policies.yaml; it holds only policies"),
    (.policies | if type != "object" then "policies must be a mapping of policy names" else
      to_entries[] | .key as $id | .value |
        if . != null and type != "object" then "policies.\($id) must be a mapping of its params"
        else (.exempt // [] |
          if type != "array" then "policies.\($id).exempt must be a list of {path, reason}"
          else .[] | select((type != "object") or ((.path | type) != "string") or ((.reason | type) != "string") or (.reason == "") or (keys - ["path", "reason"] != []))
            | "policies.\($id).exempt: \(tojson) needs a path and a reason, and nothing else"
          end)
        end
    end)
  end' <<<"$config")
while IFS= read -r msg; do [ -n "$msg" ] && fail "$msg"; done <<<"$shape"
if [ "$errors" -gt 0 ]; then exit 1; fi

policies=0
violations=0
while IFS= read -r id; do
  [ -z "$id" ] && continue
  if [ ! -f "$POLICY_DIR/$id.jq" ]; then
    fail "$id isn't a policy; the policies are $(cd "$POLICY_DIR" && ls -- *.jq 2>/dev/null | sed 's/\.jq$//' | paste -sd, - | sed 's/,/, /g') (LIB-0045 §4)"
    continue
  fi
  policies=$((policies + 1))
  params=$(jq -c --arg id "$id" '.policies[$id] // {} | del(.exempt)' <<<"$config")
  exempt=$(jq -c --arg id "$id" '.policies[$id].exempt? // []' <<<"$config")
  if ! found=$(jq -c --argjson params "$params" -f "$POLICY_DIR/$id.jq" "$WORK/inventory.json" 2>"$WORK/err"); then
    fail "$id: $(sed -E 's/^jq: error \(at [^)]*\): //' "$WORK/err" | head -n1)"
    continue
  fi
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    vpath=$(jq -r '.path' <<<"$v")
    reason=$(jq -r --arg p "$vpath" 'first(.[] | select(.path == $p) | .reason) // empty' <<<"$exempt")
    if [ -n "$reason" ]; then
      echo "::notice file=$CONFIG::$id: $vpath is exempt: $reason"
      continue
    fi
    jq -r --arg id "$id" '"::error file=\(.file)\(if .line then ",line=\(.line)" else "" end)::\($id): \(.message)"' <<<"$v" >&2
    violations=$((violations + 1))
  done <<<"$found"
  # An exemption must still excuse something (LIB-0045 §4).
  while IFS= read -r stale; do
    [ -n "$stale" ] && fail "$id: exempt path $stale matches no violation; remove it"
  done < <(jq -r --argjson found "$(jq -s '.' <<<"$found")" '.[].path | select(. as $p | $found | map(.path) | index($p) | not)' <<<"$exempt")
done < <(jq -r '.policies | keys[]' <<<"$config")

leaves=$(jq 'length' "$WORK/inventory.json")
echo "check-policies.sh: $policies polic$([ "$policies" -eq 1 ] && echo y || echo ies), $violations violation(s) across $leaves leaves"
if [ "$errors" -gt 0 ] || [ "$violations" -gt 0 ]; then exit 1; fi
