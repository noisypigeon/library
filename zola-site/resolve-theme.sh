#!/usr/bin/env bash
# Run from a consuming site's source directory (the one holding config.toml),
# before `zola build`/`zola serve`. Reads [extra].theme_version from that
# site's config.toml and materializes themes/<name> directly as either a live
# symlink to <name>/ ("main", the default) or a materialized checkout of a
# specific <name>/v<version> tag. Nothing under themes/<name> is ever
# committed -- this script is the only thing that populates it. See
# zola-site/README.md.
#
# Everything is resolved relative to this script's own location, not the
# invoking site's -- since ADR-0154 the consuming site lives in a different
# repo, so the library root is wherever this copy of the script was fetched
# to, and asking git for the *site's* toplevel would find the wrong repo.
# LIB-0002 flattened templates/zola-site/ to zola-site/, so that root is one
# level up from this script, not two.
set -euo pipefail

THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="$(basename "$THEME_DIR")"
REPO_ROOT="$(cd "$THEME_DIR/.." && pwd)"
SITE_DIR="$(pwd)"

VERSION=$(awk '/^\[extra\]/{f=1; next} f && /^theme_version[[:space:]]*=/{print; exit}' config.toml \
  | sed -E 's/^theme_version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
VERSION="${VERSION:-main}"

RESOLVED_DIR="$SITE_DIR/themes/$THEME_NAME"
rm -rf "$RESOLVED_DIR"
mkdir -p "$(dirname "$RESOLVED_DIR")"

if [ "$VERSION" = "main" ]; then
  ln -s "$REPO_ROOT/$THEME_NAME" "$RESOLVED_DIR"
  echo "Resolved $THEME_NAME -> main (live symlink)"
else
  TAG="${THEME_NAME}/v${VERSION#v}"
  if ! git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "::error::Unknown tag $TAG for theme $THEME_NAME" >&2
    exit 1
  fi
  mkdir -p "$RESOLVED_DIR"
  git -C "$REPO_ROOT" archive "$TAG" -- "$THEME_NAME" \
    | tar -x -C "$RESOLVED_DIR" --strip-components=1
  echo "Resolved $THEME_NAME -> $TAG (materialized)"
fi
