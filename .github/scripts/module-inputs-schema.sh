#!/usr/bin/env bash
# Prints a JSON Schema (draft-07) of one Terraform module directory's inputs,
# for a workload values.yaml entry of that module (LIB-0023 §6).
#
#   module-inputs-schema.sh <module-dir> [--id <url>]
#
# generate-module-redirects.sh runs it once per terraform/scaleway/*/v* tag,
# against that tag's module directory, and publishes the result beside the
# version's redirect page. resolve-workloads.sh --check reads the published
# copy back.
#
# The shape is LIB-0023's 2026-10-20 amendment, item 4:
#
# - additionalProperties is false, which is what catches a misspelt input.
# - So `version`, the workload's own pin, is listed as a property too.
# - No `required`. A workload's defaults (LIB-0023 §4) fill inputs a module
#   requires, such as name and application_id, and Terraform still rejects a
#   missing input at plan time.
#
# Any input may instead be `{ secretRef: NAME }`, which root.hcl resolves from
# the workload's secrets.yaml (LIB-0025 §3).
#
# Types are mapped coarsely from terraform-docs' type strings: primitives to
# their JSON types, list/set/tuple to array, map/object to object, anything
# else (any) to no constraint. Element and attribute types are left to
# Terraform.
set -euo pipefail

usage() { echo "usage: $0 <module-dir> [--id <url>]" >&2; exit 2; }

MODULE_DIR=""
ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --id) [ $# -ge 2 ] || usage; ID="$2"; shift 2 ;;
    -*) usage ;;
    *) [ -z "$MODULE_DIR" ] || usage; MODULE_DIR="$1"; shift ;;
  esac
done
[ -n "$MODULE_DIR" ] || usage

if [ ! -d "$MODULE_DIR" ]; then
  echo "::error::$MODULE_DIR is not a directory" >&2
  exit 1
fi

terraform-docs json --show inputs "$MODULE_DIR" | jq --arg id "$ID" --argjson secret_ref '{"type": "object", "required": ["secretRef"], "additionalProperties": false, "properties": {"secretRef": {"type": "string", "description": "A name in the workload secrets.yaml env map (LIB-0025)"}}}' '
  def json_type:
    if . == "string" then {type: "string"}
    elif . == "number" then {type: "number"}
    elif . == "bool" then {type: "boolean"}
    elif test("^(list|set|tuple)\\(") then {type: "array"}
    elif test("^(map|object)\\(") then {type: "object"}
    else {}
    end;

  {
    "$schema": "http://json-schema.org/draft-07/schema#",
    type: "object",
    additionalProperties: false,
    properties: (
      {
        version: {
          type: "string",
          pattern: "^[0-9]+(\\.[0-9]+){0,2}$",
          description: "Pins this module: X.Y.Z exactly, X.Y or X to the newest release within it. Omitted, the newest release (LIB-0023 §3)."
        }
      } + (
        [ (.inputs // [])[] | {
            key: .name,
            value: ({anyOf: [
                ((.type | json_type) + (if .default != null then {default: .default} else {} end)),
                $secret_ref
              ]}
              + (if (.description // "") != "" then {description: .description} else {} end))
          } ] | from_entries
      )
    )
  } + (if $id != "" then {"$id": $id} else {} end)
'
