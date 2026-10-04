#!/usr/bin/env bash
# Run from a consuming site's src/ directory (e.g. workloads/blog/src), before
# `zola build`/`zola serve`. Reads [extra].theme_version from that site's
# config.toml and points themes/<name> at either a live symlink to
# templates/<name> ("main", the default) or a materialized checkout of a
# specific templates/<name>/v<version> tag. See templates/zola-site/README.md.
set -euo pipefail

THEME_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(git rev-parse --show-toplevel)"
SITE_DIR="$(pwd)"

VERSION=$(awk '/^\[extra\]/{f=1; next} f && /^theme_version[[:space:]]*=/{print; exit}' config.toml \
  | sed -E 's/^theme_version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
VERSION="${VERSION:-main}"

RESOLVED_DIR="$SITE_DIR/.theme-resolved/$THEME_NAME"
rm -rf "$RESOLVED_DIR"
mkdir -p "$(dirname "$RESOLVED_DIR")"

if [ "$VERSION" = "main" ]; then
  ln -s "$REPO_ROOT/templates/$THEME_NAME" "$RESOLVED_DIR"
  echo "Resolved $THEME_NAME -> main (live symlink)"
else
  TAG="templates/${THEME_NAME}/v${VERSION#v}"
  if ! git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "::error::Unknown tag $TAG for theme $THEME_NAME" >&2
    exit 1
  fi
  mkdir -p "$RESOLVED_DIR"
  git -C "$REPO_ROOT" archive "$TAG" -- "templates/$THEME_NAME" \
    | tar -x -C "$RESOLVED_DIR" --strip-components=2
  echo "Resolved $THEME_NAME -> $TAG (materialized)"
fi
