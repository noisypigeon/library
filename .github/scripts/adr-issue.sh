#!/usr/bin/env bash
# File (or reuse) a GitHub issue for an ADR's "Out of scope" bullet, and link
# the issue back into the bullet's line(s) in-place. Hoisted from pigeon-cli
# by its CLI-0161; implements its CLI-0031.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: adr-issue.sh --title "..." --body "..." --label NAME [--label NAME ...]
                     --adr-line FILE:LINE [--adr-line FILE:LINE ...]
                     [--issue N] [--repo OWNER/NAME] [--label-meta FILE]

  --title      Issue title (required unless --issue is given).
  --body       Issue body (required unless --issue is given).
  --label      Label to ensure exists and attach; repeatable.
  --adr-line   ADR file and 1-based line number to annotate with the issue
               link, e.g. adr/CLI-0009-remote-storage.md:76; repeatable.
  --issue      Reuse an existing issue number instead of creating a new one.
  --repo       Repo to file in. Defaults to the current directory's repo.
  --label-meta File of `name|color|description` lines for labels this
               script may need to create. out-of-scope is built in.
EOF
}

title=""
body=""
issue_num=""
repo=""
label_meta_file=""
labels=()
adr_lines=()

while [ $# -gt 0 ]; do
  case "$1" in
    --title) title="$2"; shift 2 ;;
    --body) body="$2"; shift 2 ;;
    --label) labels+=("$2"); shift 2 ;;
    --adr-line) adr_lines+=("$2"); shift 2 ;;
    --issue) issue_num="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --label-meta) label_meta_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$issue_num" ] && { [ -z "$title" ] || [ -z "$body" ]; }; then
  echo "Either --issue, or both --title and --body, are required." >&2
  usage >&2
  exit 1
fi

if [ ${#adr_lines[@]} -eq 0 ]; then
  echo "At least one --adr-line is required." >&2
  exit 1
fi

repo_args=()
if [ -n "$repo" ]; then
  repo_args=(--repo "$repo")
fi

# name -> "color|description". out-of-scope is built in; anything else comes
# from --label-meta, a caller-owned file of `name|color|description` lines, so
# each repo keeps its own area:* taxonomy without the script knowing it.
label_meta() {
  if [ "$1" = "out-of-scope" ]; then
    echo "5319e7|Deferred item raised in an ADR's Out of scope section"
    return
  fi
  if [ -n "$label_meta_file" ] && [ -f "$label_meta_file" ]; then
    local meta
    meta="$(awk -F'|' -v n="$1" '$1 == n { print $2 "|" $3; exit }' "$label_meta_file")"
    if [ -n "$meta" ]; then
      echo "$meta"
      return
    fi
  fi
  echo "ededed|"
}

ensure_label() {
  local name="$1"
  if gh label list ${repo_args[@]+"${repo_args[@]}"} --limit 200 --json name -q '.[].name' | grep -qxF "$name"; then
    return
  fi
  local meta color desc
  meta="$(label_meta "$name")"
  color="${meta%%|*}"
  desc="${meta#*|}"
  gh label create ${repo_args[@]+"${repo_args[@]}"} "$name" --color "$color" --description "$desc"
  echo "Created label: $name"
}

for label in "${labels[@]}"; do
  ensure_label "$label"
done

issue_url=""
if [ -n "$issue_num" ]; then
  issue_url="$(gh issue view ${repo_args[@]+"${repo_args[@]}"} "$issue_num" --json url -q '.url')"
  echo "Reusing issue #$issue_num: $issue_url"
else
  label_args=()
  for label in "${labels[@]}"; do
    label_args+=(--label "$label")
  done
  issue_url="$(gh issue create ${repo_args[@]+"${repo_args[@]}"} --title "$title" --body "$body" "${label_args[@]}")"
  echo "Created issue: $issue_url"
fi

for entry in "${adr_lines[@]}"; do
  file="${entry%%:*}"
  line="${entry##*:}"
  if [ ! -f "$file" ]; then
    echo "ADR file not found, skipping: $file" >&2
    continue
  fi
  tmp="$(mktemp)"
  sed "${line}s@\$@ ([#${issue_url##*/}](${issue_url}))@" "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  echo "Annotated $file:$line"
done

echo "Done: $issue_url"
