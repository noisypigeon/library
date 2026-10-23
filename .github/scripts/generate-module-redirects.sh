#!/usr/bin/env bash
# Generates one Zola content page per
# terraform/<provider>/<module>/vX.Y.Z git tag. Each page is a static
# "redirect" page carrying a <meta name="terraform-get"> tag so
# `terraform init` can resolve a short noisypigeon.garden module source URL to
# the tagged git:: source. The public URL is "terraform/<provider>/<module>/vX.Y.Z"
# (LIB-0009).
# It matches the tag prefix by choice, not by derivation: it is a public
# interface of its own, so moving the repo's internal layout never changes it.
#
# Every module tag lives in THIS repo (library), under the terraform
# prefix -- DEV-0160 step 0 retired the last cross-repo mapping arm and
# LIB-0002 flattened the prefix, so the mapping is a single constant.
#
# This script lives in the library and runs against a consuming site, so it
# reads from two roots that are deliberately separate:
#
#   LIB_ROOT     -- the library clone this script was fetched into. Derived
#                   from ${BASH_SOURCE[0]} two levels up (this script lives in
#                   .github/scripts/), never from git rev-parse: the invoking
#                   site is a different repo, so asking git for *its* toplevel
#                   finds the wrong tree. Same property DEV-0154 gave
#                   resolve-theme.sh, and the same path arithmetic to keep
#                   right if this file ever moves again.
#   CONTENT_ROOT -- the consuming site's content/ directory, passed with
#                   --content-root. Required: only the caller knows it.
#
# Also generates one page per zola-site/vX.Y.Z tag (ADR-0114) — a
# separate loop since the tag shape doesn't fit the provider/module pattern
# above (zola-site is one flat unit, not a provider+module pair). Unlike the
# terraform pages, there is no fetch-by-URL protocol for Zola themes, so these
# pages are a human-facing redirect to the GitHub release page only, not a
# build input.
#
# Also generates one post per module release under content/releases/, derived
# from the modules' own CHANGELOG.md files (ADR-0141) — read off LIB_ROOT,
# which since LIB-0002 is a fetched clone, not the site's own repo.
#
# With --static-root (the site's static/ directory), also publishes LIB-0023
# §6's JSON Schemas there: one inputs.schema.json per terraform/scaleway
# module version a workload can use, beside that version's redirect page, and
# the workload schema at schemas/workload/v1.json that ties them together.
# Without it, nothing under static/ is touched.
#
# Regenerate-all semantics: every run wipes and rewrites every generated page
# under content/terraform/, content/theme-versions/ and content/releases/
# (except each directory's hand-authored _index.md) from the current set of
# tags and changelogs. Safe to run repeatedly; fully idempotent.
set -euo pipefail

LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAG_REPO="${TAG_REPO:-noisypigeon/library}"
CONTENT_ROOT=""
STATIC_ROOT=""
SCHEMA_BASE_URL="${SCHEMA_BASE_URL:-https://noisypigeon.garden}"

while [ $# -gt 0 ]; do
  case "$1" in
    --content-root) CONTENT_ROOT="$2"; shift 2 ;;
    --static-root) STATIC_ROOT="$2"; shift 2 ;;
    --lib-root) LIB_ROOT="$2"; shift 2 ;;
    --tag-repo) TAG_REPO="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CONTENT_ROOT" ]; then
  echo "::error::--content-root is required (the consuming site's content/ directory)" >&2
  exit 2
fi
if [ ! -d "$CONTENT_ROOT" ]; then
  echo "::error::--content-root $CONTENT_ROOT is not a directory" >&2
  exit 2
fi
if [ ! -d "$LIB_ROOT/terraform" ]; then
  echo "::error::No terraform/ under $LIB_ROOT -- is the library fetched?" >&2
  exit 1
fi

CONTENT_DIR="$CONTENT_ROOT/terraform"
THEME_CONTENT_DIR="$CONTENT_ROOT/theme-versions"
RELEASES_CONTENT_DIR="$CONTENT_ROOT/releases"

templates_tags() { git -C "$LIB_ROOT" tag --list "$@"; }

mkdir -p "$CONTENT_DIR"

# Wipe only generated pages; keep the hand-authored section marker.
find "$CONTENT_DIR" -maxdepth 1 -name '*.md' ! -name '_index.md' -delete

count=0
while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  # Explicit allowlist, not a generic catch-all: legacy terraform/modules/...
  # tags stay unredirected (ADR-0109's permanent boundary).
  if [[ ! "$tag" =~ ^(terraform)/([a-z0-9-]+)/([a-z0-9-]+)/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "::warning::Skipping tag with unexpected shape: $tag" >&2
    continue
  fi

  prefix="${BASH_REMATCH[1]}"
  provider="${BASH_REMATCH[2]}"
  module="${BASH_REMATCH[3]}"
  version="${BASH_REMATCH[4]}"

  slug="${provider}-${module}-v${version}"
  full_tag="${prefix}/${provider}/${module}/v${version}"
  repo="$TAG_REPO"
  # The public URL is a fixed interface (LIB-0009 §1), written out here rather
  # than built from ${prefix}, so a change of tag prefix can never move it.
  url_path="terraform/${provider}/${module}/v${version}"
  git_source="git::https://github.com/${repo}.git//${prefix}/${provider}/${module}?ref=${full_tag}"
  github_url="https://github.com/${repo}/releases/tag/${full_tag}"

  cat > "$CONTENT_DIR/${slug}.md" <<EOF
+++
title = "${provider}/${module} v${version}"
description = "Terraform module source redirect for terraform/${provider}/${module} v${version}."
path = "${url_path}"
template = "module-redirect.html"
in_search_index = false
include_in_feeds = false
hidden = true

[extra]
git_source = "${git_source}"
github_url = "${github_url}"
+++
EOF

  count=$((count + 1))
done < <(templates_tags 'terraform/*/*/v*' | sort)

echo "Generated ${count} module redirect page(s) under ${CONTENT_DIR#"$CONTENT_ROOT"/}."

# Also generate one *visible* overview page per module (not per version),
# alongside the hidden per-version redirect pages above — same directory, no
# naming collision since these are named "<provider>-<module>.md" with no
# "-vX.Y.Z" suffix. Each overview page carries a usage example extracted from
# the module's own README.md ("## Usage" fenced ```hcl block, verbatim — not
# rewritten to the latest version) when the README has one, and omits it
# otherwise (ADR-0141: shows what the README has today, no backfilling and
# no synthesized fallback).
toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

module_pairs="$(templates_tags 'terraform/*/*/v*' \
  | grep -E '^terraform/[a-z0-9-]+/[a-z0-9-]+/v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sed -E 's#^terraform/([a-z0-9-]+)/([a-z0-9-]+)/v.*#\1/\2#' \
  | sort -u)"

overview_count=0
while IFS= read -r pair; do
  [ -z "$pair" ] && continue
  provider="${pair%%/*}"
  module="${pair##*/}"

  versions="$(templates_tags "terraform/${provider}/${module}/v*" \
    | sed -E 's#.*/v([0-9]+\.[0-9]+\.[0-9]+)$#\1#' \
    | sort -t. -k1,1n -k2,2n -k3,3n -u)"
  latest_version="$(echo "$versions" | tail -1)"

  readme="$LIB_ROOT/terraform/${provider}/${module}/README.md"
  description=""
  usage_example=""
  if [ -f "$readme" ]; then
    description="$(awk '
      /^# / && !started { started = 1; next }
      started && /^## / { exit }
      started && /^<!-- BEGIN_TF_DOCS/ { exit }
      started { print }
    ' "$readme" | sed '/^$/d' | tr '\n' ' ' | sed -E 's/ +/ /g; s/^ //; s/ $//')"

    usage_example="$(awk '
      /^## Usage/ { in_usage = 1; next }
      in_usage && /^<!-- BEGIN_TF_DOCS/ { exit }
      in_usage && /^```hcl/ { in_block = 1; next }
      in_usage && in_block && /^```/ { exit }
      in_usage && in_block { print }
    ' "$readme")"
  fi

  slug="${provider}-${module}"
  github_url="https://github.com/${TAG_REPO}/tree/main/terraform/${provider}/${module}"

  {
    echo "+++"
    echo "title = \"${provider}/${module}\""
    echo "description = \"$(toml_escape "$description")\""
    echo "template = \"module.html\""
    echo "in_search_index = true"
    echo
    echo "[extra]"
    echo "kind = \"module\""
    echo "provider = \"${provider}\""
    echo "module = \"${module}\""
    echo "latest_version = \"${latest_version}\""
    echo "github_url = \"${github_url}\""
    if [ -n "$usage_example" ]; then
      printf 'usage_example = """\n%s\n"""\n' "$usage_example"
    else
      echo 'usage_example = ""'
    fi
    printf 'versions = ['
    first=1
    while IFS= read -r v; do
      [ -z "$v" ] && continue
      [ "$first" -eq 0 ] && printf ', '
      printf '{ version = "%s", path = "terraform/%s/%s/v%s" }' "$v" "$provider" "$module" "$v"
      first=0
    done <<<"$versions"
    printf ']\n'
    echo "+++"
  } >"$CONTENT_DIR/${slug}.md"

  overview_count=$((overview_count + 1))
done <<<"$module_pairs"

echo "Generated ${overview_count} module overview page(s) under ${CONTENT_DIR#"$CONTENT_ROOT"/}."

# Workload schemas (LIB-0023 §6). Each module version's inputs schema is
# generated from that tag's own module directory, so a pinned version
# validates against the inputs it really has. The workload schema validates
# each kind against its newest version, or the version its `version` pins.
#
# The module list is the third copy of the kind table; its twins are
# resolve-workloads.sh's KINDS and root.hcl's workload_kinds.
#
# The workload state bucket, scaleway.state (LIB-0028), is a scaleway/bucket
# with one input of its own, `prefix`. Each inputs schema refuses properties it
# doesn't list, which a $ref can't relax, so every scaleway/bucket version also
# gets a state.schema.json: its inputs schema plus `prefix`. Likewise each
# backblaze/api-key version gets a workload.schema.json (LIB-0029 §6): its
# inputs without bucket_ids, which a workload never writes, plus `buckets`.
# cloudflare/bucket and cloudflare/ruleset get one too (LIB-0030 §7): without
# account_id, which is the spoke's, and zone_id, since a workload names zones.
if [ -n "$STATIC_ROOT" ]; then
  if [ ! -d "$STATIC_ROOT" ]; then
    echo "::error::--static-root $STATIC_ROOT is not a directory" >&2
    exit 2
  fi
  find "$STATIC_ROOT/terraform" \( -name inputs.schema.json -o -name state.schema.json -o -name workload.schema.json \) -type f -delete 2>/dev/null || true
  rm -f "$STATIC_ROOT/schemas/workload/v1.json"

  kinds_json='{}'
  schema_count=0
  for wmodule in scaleway/project scaleway/iam-application scaleway/terraform-deployer-iam scaleway/bucket scaleway/iam-api-key backblaze/bucket backblaze/api-key cloudflare/bucket cloudflare/dns-record cloudflare/ruleset cloudflare/apex-redirect; do
    wversions="$(templates_tags "terraform/${wmodule}/v*" \
      | sed -nE 's#.*/v([0-9]+\.[0-9]+\.[0-9]+)$#\1#p' \
      | sort -t. -k1,1n -k2,2n -k3,3n -u)"
    [ -z "$wversions" ] && continue
    while IFS= read -r v; do
      out="$STATIC_ROOT/terraform/${wmodule}/v${v}"
      mkdir -p "$out"
      tree="$(mktemp -d)"
      git -C "$LIB_ROOT" archive "terraform/${wmodule}/v${v}" "terraform/${wmodule}" | tar -x -C "$tree"
      "$LIB_ROOT/.github/scripts/module-inputs-schema.sh" "$tree/terraform/${wmodule}" \
        --id "${SCHEMA_BASE_URL}/terraform/${wmodule}/v${v}/inputs.schema.json" >"$out/inputs.schema.json"
      rm -rf "$tree"
      schema_count=$((schema_count + 1))
      if [ "$wmodule" = scaleway/bucket ]; then
        jq --arg id "${SCHEMA_BASE_URL}/terraform/${wmodule}/v${v}/state.schema.json" '
          ."$id" = $id
          | .properties.prefix = {
              type: "string",
              pattern: "^[^/].*/$",
              description: "Where this workload'"'"'s state keys start in its state bucket (LIB-0028 §3). Default: workloads/<workload>/"
            }
        ' "$out/inputs.schema.json" >"$out/state.schema.json"
        schema_count=$((schema_count + 1))
      fi
      if [ "$wmodule" = backblaze/api-key ]; then
        jq --arg id "${SCHEMA_BASE_URL}/terraform/${wmodule}/v${v}/workload.schema.json" '
          ."$id" = $id
          | del(.properties.bucket_ids)
          | .properties.buckets = {
              type: "array",
              minItems: 1,
              items: {type: "string", pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
              description: "The workload'"'"'s backblaze.bucket keys this key may reach (LIB-0029 §3)"
            }
          | .required = ["buckets", "capabilities"]
        ' "$out/inputs.schema.json" >"$out/workload.schema.json"
        schema_count=$((schema_count + 1))
      fi
      if [ "$wmodule" = cloudflare/bucket ] || [ "$wmodule" = cloudflare/ruleset ]; then
        jq --arg id "${SCHEMA_BASE_URL}/terraform/${wmodule}/v${v}/workload.schema.json" '
          ."$id" = $id | del(.properties.account_id, .properties.zone_id)
        ' "$out/inputs.schema.json" >"$out/workload.schema.json"
        schema_count=$((schema_count + 1))
      fi
    done <<<"$wversions"

    # A kind: null (declared with no inputs), or a mapping whose `version`,
    # if any, is one of the pins that exist, checked against the schema of
    # the newest version that pin matches. $vs is oldest first.
    kinds=("$wmodule|inputs")
    if [ "$wmodule" = scaleway/bucket ]; then kinds+=("$wmodule#state|state"); fi
    case "$wmodule" in
      backblaze/api-key | cloudflare/bucket | cloudflare/ruleset) kinds=("$wmodule#workload|workload") ;;
    esac
    for wkind in "${kinds[@]}"; do
      kinds_json="$(jq --arg m "$wmodule" --arg key "${wkind%|*}" --arg file "${wkind#*|}" --arg versions "$wversions" --arg base "$SCHEMA_BASE_URL" '
        ($versions | split("\n") | map(select(. != ""))) as $vs
        | ([$vs[] | split(".") as $p | $p[0], "\($p[0]).\($p[1])", .] | unique) as $pins
        | def url($v): "\($base)/terraform/\($m)/v\($v)/\($file).schema.json";
        . + {($key): {anyOf: [
            {type: "null"},
            {
              type: "object",
              properties: {version: {type: "string", enum: $pins}},
              allOf: (
                [{if: {not: {required: ["version"]}}, then: {"$ref": url($vs[-1])}}]
                + [$pins[] as $pin | {
                    if: {properties: {version: {const: $pin}}, required: ["version"]},
                    then: {"$ref": url([$vs[] | select(. == $pin or startswith($pin + "."))] | last)}
                  }]
              )
            }
          ]}}
      ' <<<"$kinds_json")"
    done
  done

  mkdir -p "$STATIC_ROOT/schemas/workload"
  jq --arg base "$SCHEMA_BASE_URL" '. as $k | {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "$id": "\($base)/schemas/workload/v1.json",
    title: "Workload values.yaml (LIB-0023, LIB-0028, LIB-0029, LIB-0030)",
    type: "object",
    additionalProperties: false,
    required: ["prefix", "suffix"],
    properties: {
      prefix: {type: "string", minLength: 1},
      suffix: {type: "string", minLength: 1},
      scaleway: {
        type: ["object", "null"],
        additionalProperties: false,
        properties: {
          project: ($k["scaleway/project"] // {}),
          deployer: ($k["scaleway/terraform-deployer-iam"] // {}),
          state: ($k["scaleway/bucket#state"] // {}),
          bucket: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$", not: {const: "state"}},
            additionalProperties: ($k["scaleway/bucket"] // {})
          },
          iam: {
            type: ["object", "null"],
            additionalProperties: false,
            properties: {
              application: ($k["scaleway/iam-application"] // {}),
              apiKey: ($k["scaleway/iam-api-key"] // {})
            }
          }
        }
      },
      backblaze: {
        type: ["object", "null"],
        additionalProperties: false,
        properties: {
          bucket: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
            additionalProperties: ($k["backblaze/bucket"] // {})
          },
          apiKey: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
            additionalProperties: ($k["backblaze/api-key#workload"] // {})
          }
        }
      },
      cloudflare: {
        type: ["object", "null"],
        additionalProperties: false,
        properties: {
          zone: {type: "string", pattern: "^[a-z0-9-]+(\\.[a-z0-9-]+)+$", description: "The zone apex every zone entry uses unless it sets its own (LIB-0030 §3)"},
          bucket: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
            additionalProperties: ($k["cloudflare/bucket#workload"] // {})
          },
          dnsRecord: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
            additionalProperties: ($k["cloudflare/dns-record"] // {})
          },
          ruleset: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
            additionalProperties: ($k["cloudflare/ruleset#workload"] // {})
          },
          apexRedirect: {
            type: ["object", "null"],
            propertyNames: {pattern: "^[a-z0-9]+(-[a-z0-9]+)*$"},
            additionalProperties: ($k["cloudflare/apex-redirect"] // {})
          }
        }
      }
    }
  }' <<<"$kinds_json" >"$STATIC_ROOT/schemas/workload/v1.json"

  echo "Generated ${schema_count} module inputs schema(s) and the workload schema under ${STATIC_ROOT}."
fi

mkdir -p "$THEME_CONTENT_DIR"
find "$THEME_CONTENT_DIR" -maxdepth 1 -name '*.md' ! -name '_index.md' -delete

theme_count=0
while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  if [[ ! "$tag" =~ ^(zola-site)/v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "::warning::Skipping theme tag with unexpected shape: $tag" >&2
    continue
  fi

  theme="${BASH_REMATCH[1]}"
  version="${BASH_REMATCH[2]}"

  slug="${theme}-v${version}"
  url_path="templates/${theme}/v${version}"
  github_url="https://github.com/${TAG_REPO}/releases/tag/${tag}"

  cat > "$THEME_CONTENT_DIR/${slug}.md" <<EOF
+++
title = "templates/${theme} v${version}"
description = "templates/${theme} theme, version ${version}."
path = "${url_path}"
template = "theme-redirect.html"
in_search_index = false
include_in_feeds = false
hidden = true

[extra]
github_url = "${github_url}"
+++
EOF

  theme_count=$((theme_count + 1))
done < <(templates_tags 'zola-site/v*' | sort)

echo "Generated ${theme_count} theme-version redirect page(s) under ${THEME_CONTENT_DIR#"$CONTENT_ROOT"/}."

# One post per module release, from the modules' own CHANGELOG.md files
# (ADR-0141's content, ADR-0154's mechanism). Each "## [X.Y.Z] - YYYY-MM-DD"
# entry becomes a post: its "### " line is the description, everything after
# is the body verbatim. Note the split is on the versioned heading
# specifically, not any "## " -- at least one entry body contains its own
# "## Test plan" heading.
mkdir -p "$RELEASES_CONTENT_DIR"
find "$RELEASES_CONTENT_DIR" -maxdepth 1 -name '*.md' ! -name '_index.md' -delete

# Posts carry an America/Los_Angeles timestamp, matching what
# template-release.yml stamps on the day it cuts a release. The offset is
# whatever that date's was, so entries either side of a DST change differ --
# precompute one offset per distinct date (GNU date first, BSD fallback).
offset_for_date() {
  local raw
  raw="$(TZ="America/Los_Angeles" date -d "$1 12:00:00" +%z 2>/dev/null \
    || TZ="America/Los_Angeles" date -j -f "%Y-%m-%d %H:%M:%S" "$1 12:00:00" +%z 2>/dev/null)"
  if [ -z "$raw" ]; then
    echo "::error::Could not compute UTC offset for date $1" >&2
    exit 1
  fi
  echo "$raw" | sed -E 's/([+-][0-9]{2})([0-9]{2})/\1:\2/'
}

# Read each module's CHANGELOG.md from the library's default branch, not from the
# working tree. LIB_ROOT is checked out at whatever ref a spoke pins in
# .lib-version, which by construction predates any release cut after that pin --
# so the working-tree copy is missing exactly the newest entry, the one a fresh
# release most needs published. That asymmetry is subtle and bit once: a module
# release published its redirect page (tag-derived, and tags are fetched in full)
# while its release post silently did not appear (file-derived, and pinned).
#
# Deliberately origin/main rather than the version tag. The tag carries its own
# entry, but it does NOT carry entries backfilled for *older* tags afterwards --
# and four such entries exist, from the backfill of six previously undocumented
# module tags. Reading the tag alone silently dropped them. Neither the tag nor
# the pinned tree is a superset of the other; the default branch is a superset of
# both.
#
# Release notes are append-only published history, and the tag graph above is
# already read live, so pinning only the notes is what created the mismatch.
#
# Module list comes from the tag graph too, so a module released after the pin is
# still covered.
CHANGELOG_REF="${CHANGELOG_REF:-origin/main}"
if ! git -C "$LIB_ROOT" rev-parse --verify --quiet "$CHANGELOG_REF" >/dev/null; then
  echo "::error::$LIB_ROOT has no ref $CHANGELOG_REF to read release notes from" >&2
  exit 1
fi

changelog_src="$(mktemp -d)"
trap 'rm -rf "${changelog_src:?}"' EXIT

while IFS= read -r mdir; do
  [ -z "$mdir" ] && continue
  rel="${mdir#terraform/}"
  mkdir -p "${changelog_src}/${rel}"
  if ! git -C "$LIB_ROOT" show "${CHANGELOG_REF}:${mdir}/CHANGELOG.md" \
      > "${changelog_src}/${rel}/CHANGELOG.md" 2>/dev/null; then
    echo "::warning::No CHANGELOG.md at ${CHANGELOG_REF}:${mdir}; skipping its release posts" >&2
    rm -rf "${changelog_src:?}/${rel:?}"
  fi
done < <(templates_tags 'terraform/*/*/v*' \
  | sed -E 's#/v[0-9]+\.[0-9]+\.[0-9]+$##' | sort -u)

changelogs="$(find "$changelog_src" -mindepth 3 -maxdepth 3 -name CHANGELOG.md | sort)"

offset_map=""
while IFS= read -r d; do
  [ -z "$d" ] && continue
  offset_map="${offset_map}${d}=$(offset_for_date "$d");"
done < <(echo "$changelogs" | xargs grep -hE '^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' \
  | sed -E 's/^## \[[0-9.]+\] - ([0-9-]+)$/\1/' | sort -u)

release_count=0
while IFS= read -r changelog; do
  [ -z "$changelog" ] && continue
  module="$(basename "$(dirname "$changelog")")"
  provider="$(basename "$(dirname "$(dirname "$changelog")")")"

  written=$(awk -v provider="$provider" -v module="$module" \
                -v outdir="$RELEASES_CONTENT_DIR" -v offsets="$offset_map" '
    function offset_for(d,   n, i, parts, kv) {
      n = split(offsets, parts, ";")
      for (i = 1; i <= n; i++) {
        if (split(parts[i], kv, "=") == 2 && kv[1] == d) return kv[2]
      }
      print "::error::No offset for date " d > "/dev/stderr"
      exit 1
    }
    function flush(   path, i) {
      if (version == "") return
      while (nbody > 0 && body[nbody] == "") nbody--
      path = outdir "/" provider "-" module "-v" version ".md"
      printf "+++\n" > path
      printf "title = \"%s/%s v%s\"\n", provider, module, version > path
      printf "date = %sT12:00:00%s\n", date, offset_for(date) > path
      printf "slug = \"%s-%s-v%s\"\n", provider, module, version > path
      printf "description = \"%s\"\n", escaped_title > path
      printf "+++\n\n" > path
      for (i = 1; i <= nbody; i++) print body[i] > path
      close(path)
      written++
    }
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {
      flush()
      version = $0; sub(/^## \[/, "", version); sub(/\].*$/, "", version)
      date = $0; sub(/^.* - /, "", date)
      escaped_title = ""; nbody = 0; seen_title = 0
      next
    }
    version == "" { next }
    !seen_title && /^### / {
      escaped_title = substr($0, 5)
      gsub(/\\/, "\\\\", escaped_title)
      gsub(/"/, "\\\"", escaped_title)
      seen_title = 1
      skip_blank = 1
      next
    }
    !seen_title { next }
    skip_blank && $0 == "" { skip_blank = 0; next }
    { skip_blank = 0; body[++nbody] = $0 }
    END { flush(); print written + 0 }
  ' "$changelog")

  release_count=$((release_count + written))
done <<<"$changelogs"

echo "Generated ${release_count} release post(s) under ${RELEASES_CONTENT_DIR#"$CONTENT_ROOT"/}."
