#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding .sops.yaml).
# Packs the saved plans `terragrunt run --all --out-dir <dir> -- plan` wrote
# into one encrypted archive, and unpacks it again for apply (LIB-0022 §2-3).
#
#   plan-archive.sh pack <out-dir> <units-file> <archive>
#   plan-archive.sh unpack <archive> <out-dir>
#
# A plan file holds sensitive values in plaintext, and the archive is uploaded
# as an artifact on a public repo, so it is encrypted with the spoke's own
# sops/age recipient. --filename-override makes sops pick the creation rule
# for terraform/secrets/*.enc, so the spoke needs no second recipient or tool.
# Unpacking decrypts with SOPS_AGE_KEY, as everything else here does.
#
# The archive carries units.txt, a copy of <units-file>: the units the plan
# selected, one leaf path per line, as terragrunt-run.yml's "Select units"
# writes them. Apply selects again and refuses to run when the two differ, so
# both sides of the comparison come from the same `terragrunt find`, whether or
# not a selected unit wrote a plan. It may be empty: a PR can select no units
# (one changing only .sops.yaml, say), and its apply then applies nothing.
#
# Lives under .github/scripts/ so the workflows/ track versions it.
set -euo pipefail

usage() { echo "usage: $0 pack <out-dir> <units-file> <archive> | unpack <archive> <out-dir>" >&2; exit 2; }
[ $# -ge 3 ] || usage

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

case "$1" in
  pack)
    [ $# -eq 4 ] || usage
    out_dir=$2 units_file=$3 archive=$4
    [ -f "$units_file" ] || { echo "::error::$units_file does not exist" >&2; exit 1; }
    mkdir -p "$out_dir" "$work/plans"
    (cd "$out_dir" && find . -name tfplan.tfplan -type f | sed 's|^\./||' | LC_ALL=C sort) > "$work/files.txt"
    while IFS= read -r file; do
      mkdir -p "$work/plans/$(dirname "$file")"
      cp "$out_dir/$file" "$work/plans/$file"
    done < "$work/files.txt"
    cp "$units_file" "$work/plans/units.txt"
    tar -C "$work/plans" -czf "$work/plans.tgz" .
    sops encrypt --input-type binary --output-type binary \
      --filename-override terraform/secrets/plan.enc "$work/plans.tgz" > "$archive"
    echo "Packed $(wc -l < "$work/files.txt" | tr -d ' ') plan(s) for $(wc -l < "$units_file" | tr -d ' ') selected unit(s) into $archive:"
    sed 's/^/  /' "$work/files.txt"
    ;;
  unpack)
    [ $# -eq 3 ] || usage
    archive=$2 out_dir=$3
    [ -f "$archive" ] || { echo "::error::$archive does not exist" >&2; exit 1; }
    sops decrypt --input-type binary --output-type binary "$archive" > "$work/plans.tgz"
    mkdir -p "$out_dir"
    tar -C "$out_dir" -xzf "$work/plans.tgz"
    [ -f "$out_dir/units.txt" ] || { echo "::error::$archive has no units.txt" >&2; exit 1; }
    echo "Unpacked the plans for $(wc -l < "$out_dir/units.txt" | tr -d ' ') selected unit(s) into $out_dir"
    ;;
  *) usage ;;
esac
