#!/usr/bin/env bash
# Run once, from a consuming spoke's repo root (the directory holding
# spoke.hcl), by the spoke's owner: the one person with its age key. Turns
# root.hcl v3's single terraform/secrets.enc into v4's per-concern files,
# terraform/secrets/<name>.enc (LIB-0012 §5).
#
# Every key goes to the file that owns it in secrets-schema.json, and every
# ENV_<NAME> key goes to env.enc as <NAME>. A key with no owner stops the run
# before anything is written. Values never change, and never land on disk or
# in the output: each file is `sops -d | filter | sops -e`, one pipe, written
# as ciphertext. It's encrypted to exactly the source file's age recipients,
# read from its plaintext sops metadata, whatever .sops.yaml says, so it works
# before or after the spoke's creation rule moves to terraform/secrets/.
#
# The schema is the hub's own copy beside this script, so the spoke needn't
# take root.hcl v4 first. It writes every file it has keys for, whether or not
# spoke.hcl requires it, and refuses to overwrite one that exists. Then it runs
# check-secrets.sh against the result, which says what spoke.hcl still needs:
# `state_backup = true` where terraform.enc holds backup keys, for instance.
# Deleting terraform/secrets.enc is left to the spoke's PR.
set -euo pipefail

case "${1:-}" in
  "") ;;
  -h|--help) echo "usage: $0   (from the spoke's repo root; needs its age key)"; exit 0 ;;
  *) echo "usage: $0" >&2; exit 2 ;;
esac

LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA="$LIB_ROOT/terragrunt/root-hcl/secrets-schema.json"
SOURCE="terraform/secrets.enc"
OUT_DIR="terraform/secrets"

if [ ! -f spoke.hcl ]; then
  echo "::error::No spoke.hcl here; run this from the spoke's repo root" >&2
  exit 1
fi
if [ "$(pwd)" = "$LIB_ROOT" ]; then
  echo "::error::Refusing to split secrets in the library itself" >&2
  exit 1
fi
if [ ! -f "$SOURCE" ]; then
  echo "::error::No $SOURCE to split" >&2
  exit 1
fi

# Key names and recipients, from the plaintext parts of the sops file.
src_keys=$(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$SOURCE" | grep -v '^sops_' || true)
recipients=$(sed -nE 's/^sops_age__list_[0-9]+__map_recipient=(.*)$/\1/p' "$SOURCE" | paste -sd, -)
if [ -z "$recipients" ]; then
  echo "::error::$SOURCE names no age recipient; only age-encrypted files can be split" >&2
  exit 1
fi
if grep -qE '^sops_(pgp|kms|gcp_kms|azure_kv|hc_vault)' "$SOURCE"; then
  echo "::error::$SOURCE has non-age sops keys, which this script doesn't carry over" >&2
  exit 1
fi

# Which file each key goes to, and its name there: "<file> <src> <dst>".
plan=""
unplaced=""
while IFS= read -r key; do
  [ -z "$key" ] && continue
  owner=$(jq -r --arg k "$key" '
    [.files | to_entries[] | select(((.value.keys // []) + ((.value.keys_when // {}) | [.[]] | add // [])) | index($k)) | .key] | first // empty
  ' "$SCHEMA")
  if [ -n "$owner" ]; then
    plan="$plan$owner $key $key"$'\n'
  elif [[ "$key" == ENV_?* ]]; then
    plan="${plan}env $key ${key#ENV_}"$'\n'
  else
    unplaced="$unplaced $key"
  fi
done <<<"$src_keys"

if [ -n "$unplaced" ]; then
  echo "::error::$SOURCE has keys no file owns:$unplaced; rename or delete them, then rerun (nothing was written)" >&2
  exit 1
fi

files=$(awk 'NF { print $1 }' <<<"$plan" | sort -u)
for name in $files; do
  if [ -e "$OUT_DIR/$name.enc" ]; then
    echo "::error::$OUT_DIR/$name.enc already exists; refusing to overwrite it (nothing was written)" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"
for name in $files; do
  out="$OUT_DIR/$name.enc"
  # "<src> <dst>" pairs for this file; the awk filter keeps those lines only,
  # renamed, and the rest never leave the pipe.
  map=$(awk -v n="$name" '$1 == n { print $2, $3 }' <<<"$plan")
  tmp="$out.tmp.$$"
  if ! sops --decrypt --input-type dotenv --output-type dotenv "$SOURCE" |
    MAP="$map" awk '
      BEGIN { n = split(ENVIRON["MAP"], l, "\n"); for (i = 1; i <= n; i++) { split(l[i], p, " "); if (p[1] != "") to[p[1]] = p[2] } }
      { eq = index($0, "="); if (eq == 0) next; k = substr($0, 1, eq - 1); if (k in to) print to[k] substr($0, eq) }
    ' |
    sops --config /dev/null encrypt --input-type dotenv --output-type dotenv \
      --age "$recipients" --filename-override "$out" /dev/stdin > "$tmp"; then
    rm -f "$tmp"
    echo "::error::Writing $out failed; the files written so far are under $OUT_DIR" >&2
    exit 1
  fi
  mv "$tmp" "$out"
  echo "Wrote $out: $(awk '{ print $2 }' <<<"$map" | paste -sd, -)"
done

echo
echo "Checking the result (check-secrets.sh, against $SCHEMA):"
SECRETS_SCHEMA="$SCHEMA" "$LIB_ROOT/.github/scripts/check-secrets.sh" --allow-v3-file
