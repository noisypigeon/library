#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl).
# Checks the key names in the spoke's sops dotenv secrets files,
# terraform/secrets/<name>.enc, against the secrets-schema.json that
# resolve-root-hcl.sh copied beside its root.hcl (LIB-0012 §4), and exits 1
# listing every required file that is missing, and every file whose keys
# aren't exactly its own.
#
# It never decrypts anything, so it needs no SOPS_AGE_KEY: a sops dotenv file
# encrypts values only and keeps each key name in plaintext. It prints file and
# key names, never values.
#
# Which files are required, and which keys each holds, follows from spoke.hcl
# spoke-wide: "always", "backend.<state_backend>" (default scaleway),
# "provider.<name>" for every key of the providers map however its leaves are
# scoped, and "state_backup" when spoke.hcl sets state_backup = true. A file
# none of whose conditions hold is reported as ignored, because root.hcl never
# reads it, and doesn't fail. root.hcl applies the same schema again per leaf
# at render time, where it also catches an empty value -- which only
# decryption can show.
#
# A spoke runs it in terragrunt-run.yml's prepare_cmd, after
# resolve-root-hcl.sh --check, so a key in the wrong file fails the PR before
# the first plan. Lives under .github/scripts/ so the workflows/ track versions
# it, like resolve-root-hcl.sh.
#
# --allow-v3-file tolerates a leftover v3 terraform/secrets.enc, which
# split-secrets.sh needs while the owner hasn't yet deleted it. SECRETS_SCHEMA
# overrides the schema's path, for the same reason: before the spoke takes
# root.hcl v4, its own copy is still v3's.
set -euo pipefail

ALLOW_V3=false
case "${1:-}" in
  --allow-v3-file) ALLOW_V3=true ;;
  "") ;;
  -h|--help) echo "usage: $0 [--allow-v3-file]"; exit 0 ;;
  *) echo "usage: $0 [--allow-v3-file]" >&2; exit 2 ;;
esac

SPOKE_DIR="$(pwd)"
SECRETS_DIR="terraform/secrets"
SCHEMA="${SECRETS_SCHEMA:-$SPOKE_DIR/secrets-schema.json}"

for f in "$SPOKE_DIR/spoke.hcl" "$SCHEMA"; do
  if [ ! -f "$f" ]; then
    echo "::error::No $f; run this from the spoke's repo root, after resolve-root-hcl.sh" >&2
    exit 1
  fi
done
if ! jq -e '.files | type == "object"' "$SCHEMA" >/dev/null; then
  echo "::error::$SCHEMA has no per-file \"files\" map; it predates root.hcl v4 (LIB-0012)" >&2
  exit 1
fi

# spoke.hcl is HCL, read without an HCL parser: state_backend and state_backup
# are one `name = value` line each, and the providers map's keys are the names
# assigned at its first level of braces. Comments are stripped first.
backend=$(sed -nE 's/^[[:space:]]*state_backend[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$SPOKE_DIR/spoke.hcl" | head -n1)
backend="${backend:-scaleway}"
backup=$(sed -nE 's/^[[:space:]]*state_backup[[:space:]]*=[[:space:]]*([a-z]+).*/\1/p' "$SPOKE_DIR/spoke.hcl" | head -n1)
backup="${backup:-false}"

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

conditions=$(printf '%s\n' always "backend.$backend"; for p in $providers; do echo "provider.$p"; done; [ "$backup" = true ] && echo state_backup || true)

echo "spoke.hcl: state_backend=$backend, state_backup=$backup, providers: $(paste -sd, - <<<"$providers")"
status=0
fail() { echo "::error::$*" >&2; status=1; }

# The same two guards root.hcl applies, here so they fail before any render.
if [ "$backend" = cloudflare ]; then
  [ "$backup" = true ] || fail "spoke.hcl state_backend is cloudflare but state_backup is not true; R2 can't version objects (LIB-0007, LIB-0012)"
  grep -qx cloudflare <<<"$providers" || fail "spoke.hcl state_backend is cloudflare but providers has no cloudflare; the R2 endpoint needs cloudflare.enc's CLOUDFLARE_PROVIDER_ACCOUNT_ID (LIB-0010)"
fi

if [ -e terraform/secrets.enc ]; then
  if [ "$ALLOW_V3" = true ]; then
    echo "terraform/secrets.enc: v3's single file, still present; git rm it once the split files are committed"
  else
    fail "terraform/secrets.enc is v3's single file, which root.hcl v4 never reads; run split-secrets.sh, then git rm it (LIB-0012)"
  fi
fi

# Every key some non-optional file owns: an env.enc key with one of these
# names is a value in the wrong file.
owned=$(jq -r '.files[] | select(has("required_when")) | (.keys // []), ((.keys_when // {}) | .[]) | .[]' "$SCHEMA" | sort -u)

# Key names only: everything before the first "=", on lines that hold one.
# sops' own metadata (sops_mac, sops_version, ...) is not a secret.
file_keys() {
  sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/\1/p' "$1" | sort -u
}

for name in $(jq -r '.files | keys[]' "$SCHEMA"); do
  path="$SECRETS_DIR/$name.enc"
  conds=$(jq -r --arg n "$name" '.files[$n].required_when // [] | .[]' "$SCHEMA")
  optional=false; [ -z "$conds" ] && optional=true
  required=false
  for c in $conds; do grep -qxF "$c" <<<"$conditions" && required=true; done

  if [ ! -f "$path" ]; then
    [ "$required" = true ] && fail "$path is missing; required by $(grep -xF -f <(echo "$conds") <<<"$conditions" | paste -sd, -) (LIB-0012)"
    continue
  fi
  if [ "$required" = false ] && [ "$optional" = false ]; then
    echo "$path: ignored, no condition requires it ($(paste -sd, - <<<"$conds")); root.hcl never decrypts it"
    continue
  fi

  keys=$(file_keys "$path")
  if ! grep -qx 'sops_mac' <<<"$keys"; then
    fail "$path has no sops_mac; it is not a sops dotenv file"
    continue
  fi
  keys=$(grep -v '^sops_' <<<"$keys" || true)

  if [ "$optional" = true ]; then
    pattern=$(jq -r --arg n "$name" '.files[$n].pattern' "$SCHEMA")
    bad=""; reserved=""; misplaced=""
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      grep -qE "$pattern" <<<"$key" || bad="$bad $key"
      jq -e --arg n "$name" --arg l "$(tr '[:upper:]' '[:lower:]' <<<"$key")" '.files[$n].reserved // [] | index($l)' "$SCHEMA" >/dev/null && reserved="$reserved $key"
      grep -qxF "$key" <<<"$owned" && misplaced="$misplaced $key"
    done <<<"$keys"
    [ -n "$bad" ] && fail "$path has keys not matching $pattern:$bad (LIB-0012)"
    [ -n "$reserved" ] && fail "$path has keys whose local would shadow a generated one:$reserved (LIB-0012)"
    [ -n "$misplaced" ] && fail "$path has keys another file owns:$misplaced; move them there (LIB-0012)"
    [ -z "$bad$reserved$misplaced" ] && echo "$path: $(grep -c . <<<"$keys" || true) keys, all leaf locals"
    continue
  fi

  expected=$(jq -r --arg n "$name" --arg c "$conditions" '
    ($c | split("\n")) as $on
    | .files[$n] | (.keys // []), ((.keys_when // {}) | to_entries[] | select(.key as $k | $on | index($k)) | .value) | .[]
  ' "$SCHEMA" | sort -u)
  missing=$(comm -23 <(echo "$expected") <(echo "$keys") | grep . || true)
  extra=$(comm -13 <(echo "$expected") <(echo "$keys") | grep . || true)
  [ -n "$missing" ] && fail "$path lacks $(paste -sd, - <<<"$missing") (LIB-0012)"
  if [ -n "$extra" ]; then
    hint=""
    if [ "$backup" != true ] && jq -e --arg n "$name" '.files[$n].keys_when.state_backup' "$SCHEMA" >/dev/null &&
      grep -qxF -f <(jq -r --arg n "$name" '.files[$n].keys_when.state_backup[]' "$SCHEMA") <<<"$extra"; then
      hint="; backup keys need state_backup = true in spoke.hcl"
    fi
    fail "$path has keys outside its own: $(paste -sd, - <<<"$extra")$hint (LIB-0012)"
  fi
  [ -z "$missing$extra" ] && echo "$path: exactly its $(grep -c . <<<"$keys") keys"
done

# A .enc the schema doesn't name is a typo or a concern with no contract yet.
if [ -d "$SECRETS_DIR" ]; then
  for path in "$SECRETS_DIR"/*.enc; do
    [ -e "$path" ] || continue
    name=$(basename "$path" .enc)
    jq -e --arg n "$name" '.files | has($n)' "$SCHEMA" >/dev/null ||
      fail "$path is not a file secrets-schema.json knows; known: $(jq -r '.files | keys | join(", ")' "$SCHEMA") (LIB-0012)"
  done
fi

[ "$status" = 0 ] && echo "terraform/secrets/ matches secrets-schema.json"
exit "$status"
