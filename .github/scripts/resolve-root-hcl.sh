#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl).
# Reads root_hcl_version from that spoke.hcl and materializes ./root.hcl from
# terragrunt/root-hcl/root.hcl -- either the working-tree copy ("main") or the
# copy at tag terragrunt/root-hcl/v<version>. See
# terragrunt/root-hcl/README.md and LIB-0003. From v3.0.0 it does the same for
# ./secrets-schema.json, which that root.hcl reads from beside itself
# (LIB-0010); a version without one gets none, and a stale copy is removed.
#
# The spoke commits the result. Terragrunt's [main...HEAD] git filter plans
# every unit inside temporary git worktrees of both refs, so an untracked
# root.hcl does not exist where the plan actually runs -- and the base ref's
# own committed copy is what lets a removed leaf still plan its destroy.
#
# --check writes nothing: it exits 1 unless ./root.hcl and ./secrets-schema.json
# are byte-identical to the pinned template's, which is how CI keeps the
# committed copies honest. Without it, the script (re)writes both, which is how
# a spoke takes a version bump.
#
# Copied, never symlinked: the template locates spoke.hcl through
# get_parent_terragrunt_dir(), and a leaf's path_relative_to_include() -- which
# is the state key (LIB-0001 invariant 4) -- is relative to root.hcl's own
# directory. Both have to be the spoke's root, not the library clone's.
#
# The library root is resolved from this script's own location rather than by
# asking git, for the reason DEV-0154 gave resolve-theme.sh: the copy that runs
# is the one in the spoke's fetched .lib-src/, and `git rev-parse` from the
# spoke would find the spoke. Lives under .github/scripts/ so the workflows/
# track versions it -- resolve-theme.sh, under zola-site/, is covered by no
# release predicate at all.
set -euo pipefail

CHECK=false
case "${1:-}" in
  --check) CHECK=true ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="terragrunt/root-hcl"
# The template's files, each materialized at the spoke root under its own name.
FILES="root.hcl secrets-schema.json"
SPOKE_DIR="$(pwd)"

if [ ! -f "$SPOKE_DIR/spoke.hcl" ]; then
  echo "::error::No spoke.hcl in $SPOKE_DIR; run this from the spoke's repo root" >&2
  exit 1
fi

if [ "$SPOKE_DIR" = "$LIB_ROOT" ]; then
  echo "::error::Refusing to materialize root.hcl into the library itself" >&2
  exit 1
fi

VERSION=$(sed -nE 's/^[[:space:]]*root_hcl_version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$SPOKE_DIR/spoke.hcl" | head -n1)
if [ -z "$VERSION" ]; then
  echo "::error::spoke.hcl sets no root_hcl_version" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Fetch each file the pinned version has into $TMP_DIR. root.hcl is mandatory;
# secrets-schema.json exists from v3.0.0 on.
if [ "$VERSION" = "main" ]; then
  for f in $FILES; do
    if [ -f "$LIB_ROOT/$TEMPLATE_DIR/$f" ]; then
      cp "$LIB_ROOT/$TEMPLATE_DIR/$f" "$TMP_DIR/$f"
    fi
  done
  SOURCE="main (working tree)"
else
  TAG="terragrunt/root-hcl/v${VERSION#v}"
  if ! git -C "$LIB_ROOT" rev-parse --verify --quiet "$TAG" >/dev/null; then
    echo "::error::Unknown tag $TAG" >&2
    exit 1
  fi
  for f in $FILES; do
    if git -C "$LIB_ROOT" cat-file -e "${TAG}:${TEMPLATE_DIR}/$f" 2>/dev/null; then
      git -C "$LIB_ROOT" show "${TAG}:${TEMPLATE_DIR}/$f" > "$TMP_DIR/$f"
    fi
  done
  SOURCE="$TAG"
fi

if [ ! -f "$TMP_DIR/root.hcl" ]; then
  echo "::error::$SOURCE has no $TEMPLATE_DIR/root.hcl" >&2
  exit 1
fi

if [ "$CHECK" = true ]; then
  for f in $FILES; do
    if [ ! -f "$TMP_DIR/$f" ]; then
      if [ -e "$SPOKE_DIR/$f" ]; then
        echo "::error::$f is committed but $SOURCE has none; run resolve-root-hcl.sh and commit the result" >&2
        exit 1
      fi
      continue
    fi
    if [ ! -f "$SPOKE_DIR/$f" ]; then
      echo "::error::No committed $f; run resolve-root-hcl.sh and commit the result" >&2
      exit 1
    fi
    if ! cmp -s "$TMP_DIR/$f" "$SPOKE_DIR/$f"; then
      echo "::error::$f differs from $SOURCE; run resolve-root-hcl.sh and commit the result, never edit it by hand" >&2
      exit 1
    fi
    echo "$f matches $SOURCE"
  done
  exit 0
fi

for f in $FILES; do
  if [ -f "$TMP_DIR/$f" ]; then
    cp "$TMP_DIR/$f" "$SPOKE_DIR/$f"
    chmod 644 "$SPOKE_DIR/$f"
    echo "Resolved $f -> $SOURCE"
  elif [ -e "$SPOKE_DIR/$f" ]; then
    rm -f "$SPOKE_DIR/$f"
    echo "Removed $f: $SOURCE has none"
  fi
done
