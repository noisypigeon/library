#!/usr/bin/env bash
#
# Add a one-line rollup entry to the repo-root CHANGELOG.md, under a
# "## YYYY-MM-DD" section, newest first.
#
# This is the single home for logic that used to be copy-pasted into
# template-release.yml twice. See DEV-0160 for the contract it implements: every
# merged PR gets exactly one line in the root changelog, and a PR that changes a
# releasable unit additionally gets its full PR body in that unit's own
# CHANGELOG.md.
#
# Insertion is anchored on $SENTINEL rather than on the first "## " heading. The
# root file's prose header has no "## " of its own, so a first-"## " anchor
# never matches on an empty changelog and silently appends the first-ever entry
# to the *bottom* of the header -- the defect DEV-0160 fixes. Keep the sentinel
# line in CHANGELOG.md or this script refuses to guess.
#
# Not shared with blog-changelog.yml: that one is a reusable workflow running in
# a caller repo's checkout, which cannot see this repo's scripts.
set -euo pipefail

SENTINEL='<!-- entries below; newest first -->'

changelog="CHANGELOG.md"
tag=""
title=""
number=""
url=""
date=""

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --number) number="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --date) date="$2"; shift 2 ;;      # override "today"; also lets CI reuse the
    --file) changelog="$2"; shift 2 ;; # date it already computed for the unit entry
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for required in tag title number url; do
  if [ -z "$(eval "printf '%s' \"\$$required\"")" ]; then
    echo "missing required --${required}" >&2
    exit 2
  fi
done

today="${date:-$(TZ="America/Los_Angeles" date +%Y-%m-%d)}"
entry="- [${tag}] ${title} ([#${number}](${url}))"

if [ ! -f "$changelog" ]; then
  printf '%s\n' \
    '# Changelog' \
    '' \
    'One line per PR across this whole repo, sectioned by date, newest first.' \
    '' \
    "$SENTINEL" > "$changelog"
fi

if ! grep -qF "$SENTINEL" "$changelog"; then
  echo "::error::${changelog} has no '${SENTINEL}' line; cannot place the entry (see DEV-0160)." >&2
  exit 1
fi

if grep -q "^## ${today}\$" "$changelog"; then
  # Today already has a section -- this PR's line goes at the top of it.
  awk -v today="## ${today}" -v entry="$entry" '
    armed && $0 == "" { armed = 0; next }
    { print }
    !done && $0 == today { print ""; print entry; done = 1; armed = 1 }
  ' "$changelog" > "${changelog}.new"
else
  awk -v sentinel="$SENTINEL" -v today="## ${today}" -v entry="$entry" '
    { print }
    !done && $0 == sentinel { print ""; print today; print ""; print entry; done = 1 }
  ' "$changelog" > "${changelog}.new"
fi

mv "${changelog}.new" "$changelog"
