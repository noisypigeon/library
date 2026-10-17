#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl).
# Checks the key names in the spoke's sops dotenv secrets file against the
# secrets-schema.json that resolve-root-hcl.sh copied beside its root.hcl
# (LIB-0010 §4), and exits 1 listing every required key that is missing and
# every key the schema doesn't know.
#
# It never decrypts anything, so it needs no SOPS_AGE_KEY: a sops dotenv file
# encrypts values only and keeps each key name in plaintext. It prints key
# names, never values.
#
# Which keys are required follows from spoke.hcl, exactly as in root.hcl:
# "always", "backend.<state_backend>" (default scaleway), and
# "provider.<name>" for every key of the providers map, however its leaves are
# scoped. root.hcl applies the same schema again at render time, where it also
# catches an empty value -- which only decryption can show.
#
# A spoke runs it in terragrunt-run.yml's prepare_cmd, after
# resolve-root-hcl.sh --check, so a leftover old name fails the PR before the
# first plan. Lives under .github/scripts/ so the workflows/ track versions it,
# like resolve-root-hcl.sh.
set -euo pipefail

case "${1:-}" in
  -h|--help) echo "usage: $0 [secrets-file]   (default: terraform/secrets.enc)"; exit 0 ;;
esac

SPOKE_DIR="$(pwd)"
SECRETS_FILE="${1:-terraform/secrets.enc}"
SCHEMA="$SPOKE_DIR/secrets-schema.json"

for f in "$SPOKE_DIR/spoke.hcl" "$SCHEMA" "$SECRETS_FILE"; do
  if [ ! -f "$f" ]; then
    echo "::error::No $f; run this from the spoke's repo root, after resolve-root-hcl.sh" >&2
    exit 1
  fi
done

# Key names only: everything before the first "=", on lines that hold one.
# sops' own metadata (sops_mac, sops_version, ...) is not a secret.
keys=$(sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\1/p' "$SECRETS_FILE" | sort -u)
if ! grep -qx 'sops_mac' <<<"$keys"; then
  echo "::error::$SECRETS_FILE has no sops_mac; it is not a sops dotenv file" >&2
  exit 1
fi
keys=$(grep -v '^sops_' <<<"$keys" || true)

# spoke.hcl is HCL, read without an HCL parser: state_backend is one
# `name = "value"` line, and the providers map's keys are the names assigned at
# its first level of braces. Comments are stripped first.
backend=$(sed -nE 's/^[[:space:]]*state_backend[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$SPOKE_DIR/spoke.hcl" | head -n1)
backend="${backend:-scaleway}"

providers=$(awk '
  { line = $0; sub(/#.*/, "", line); sub(/\/\/.*/, "", line) }
  !inmap && !done && line ~ /^[[:space:]]*providers[[:space:]]*=[[:space:]]*\{/ {
    inmap = 1; depth = 0; line = substr(line, index(line, "{"))
  }
  inmap {
    buf = ""
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (c == "{") { depth++; buf = ""; continue }
      if (c == "}") { depth--; buf = ""; if (depth == 0) { inmap = 0; done = 1; break }; continue }
      if (depth != 1) continue
      if (c == "=") { gsub(/[[:space:]"]/, "", buf); if (buf != "") print buf; buf = "" }
      else if (c == ",") buf = ""
      else buf = buf c
    }
  }
' "$SPOKE_DIR/spoke.hcl")

conditions=$(printf '%s\n' always "backend.$backend"; for p in $providers; do echo "provider.$p"; done)

required=$(jq -r --arg c "$conditions" '
  ($c | split("\n")) as $on
  | .required | to_entries[] | select(.key as $k | $on | index($k)) | .value[]
' "$SCHEMA" | sort -u)
listed=$(jq -r '.required[][]' "$SCHEMA" | sort -u)
patterns=$(jq -r '.allowed_patterns[]' "$SCHEMA")

missing=$(comm -23 <(echo "$required") <(echo "$keys") | grep . || true)

unknown=""
while IFS= read -r key; do
  [ -z "$key" ] && continue
  grep -qxF "$key" <<<"$listed" && continue
  allowed=false
  while IFS= read -r pattern; do
    [ -n "$pattern" ] && grep -qE "$pattern" <<<"$key" && { allowed=true; break; }
  done <<<"$patterns"
  [ "$allowed" = true ] || unknown="$unknown$key"$'\n'
done <<<"$keys"
unknown=$(grep . <<<"$unknown" || true)

echo "spoke.hcl: state_backend=$backend, providers: $(paste -sd, - <<<"$providers")"
status=0
if [ -n "$missing" ]; then
  echo "::error::$SECRETS_FILE lacks keys this spoke requires (LIB-0010): $(paste -sd, - <<<"$missing")" >&2
  status=1
fi
if [ -n "$unknown" ]; then
  echo "::error::$SECRETS_FILE has keys outside secrets-schema.json (LIB-0010): $(paste -sd, - <<<"$unknown")" >&2
  status=1
fi
[ "$status" = 0 ] && echo "$SECRETS_FILE matches secrets-schema.json ($(grep -c . <<<"$keys") keys)"
exit "$status"
