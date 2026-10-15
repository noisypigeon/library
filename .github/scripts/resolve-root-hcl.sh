#!/usr/bin/env bash
# Run from a consuming spoke's repo root (the directory holding spoke.hcl),
# before any terragrunt command. Reads root_hcl_version from that spoke.hcl and
# materializes ./root.hcl from terragrunt/root-hcl/root.hcl -- either the
# working-tree copy ("main") or the copy at tag terragrunt/root-hcl/v<version>.
# The spoke never commits root.hcl; this script is the only thing that writes
# it. See terragrunt/root-hcl/README.md and LIB-0003.
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

LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_PATH="terragrunt/root-hcl/root.hcl"
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

TARGET="$SPOKE_DIR/root.hcl"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ "$VERSION" = "main" ]; then
  if [ ! -f "$LIB_ROOT/$TEMPLATE_PATH" ]; then
    echo "::error::$LIB_ROOT has no $TEMPLATE_PATH" >&2
    exit 1
  fi
  cp "$LIB_ROOT/$TEMPLATE_PATH" "$TMP"
  SOURCE="main (working tree)"
else
  TAG="terragrunt/root-hcl/v${VERSION#v}"
  if ! git -C "$LIB_ROOT" rev-parse --verify --quiet "$TAG" >/dev/null; then
    echo "::error::Unknown tag $TAG" >&2
    exit 1
  fi
  git -C "$LIB_ROOT" show "${TAG}:${TEMPLATE_PATH}" > "$TMP"
  SOURCE="$TAG"
fi

mv "$TMP" "$TARGET"
trap - EXIT
echo "Resolved root.hcl -> $SOURCE"
