#!/usr/bin/env bash
# check-pre-merge-ac.sh - Check pre-merge acceptance criteria checkbox state
#
# Usage: check-pre-merge-ac.sh <issue-number>
#
# Output (single JSON line):
#   {"resolved":true,"pre_merge_total":N,"unchecked_count":M,"unchecked_indices":"2,5","unchecked_items":[{"index":2,"text":"..."}]}
#
# Global index definition: 1-based count of every line matching ^- \[[ xX]\] across the
# entire issue body (same awk pattern as scripts/gh-issue-edit.sh), so indices returned
# here are directly usable with gh-issue-edit.sh --checkbox and the modules/l0-surfaces.md
# ac= marker attribute.
#
# Pre-merge subsection range: from the line after a heading matching ^### Pre-merge up to
# (but excluding) the next line matching ^## or ^### .
#
# exit codes:
#   0 - success, including fail-open cases (resolved:false / no Pre-merge heading / all checked)
#   1 - invalid arguments

set -euo pipefail

USAGE="Usage: $(basename "$0") <issue-number>"

if [[ $# -ne 1 ]]; then
  echo "Error: exactly one argument (issue number) is required." >&2
  echo "$USAGE" >&2
  exit 1
fi

ISSUE_NUMBER="$1"

if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: issue number must be a positive integer: $ISSUE_NUMBER" >&2
  echo "$USAGE" >&2
  exit 1
fi

fail_open() {
  echo '{"resolved":false,"pre_merge_total":0,"unchecked_count":0,"unchecked_indices":"","unchecked_items":[]}'
  exit 0
}

BODY=$(gh issue view "$ISSUE_NUMBER" --json body -q .body 2>/dev/null) || fail_open

if [[ -z "$BODY" ]]; then
  fail_open
fi

if ! printf '%s\n' "$BODY" | grep -q '^### Pre-merge'; then
  echo '{"resolved":true,"pre_merge_total":0,"unchecked_count":0,"unchecked_indices":"","unchecked_items":[]}'
  exit 0
fi

# Emit "<global_index>\t<checked:0|1>\t<text>" for every checkbox line that falls
# inside the ### Pre-merge subsection (the heading line itself is excluded).
RECORDS=$(printf '%s\n' "$BODY" | awk '
  BEGIN { idx = 0; in_section = 0 }
  /^### Pre-merge/ { in_section = 1; next }
  /^## / || /^### / {
    in_section = 0
    next
  }
  /^- \[[ xX]\]/ {
    idx++
    if (in_section) {
      checked = (substr($0, 4, 1) == " ") ? 0 : 1
      text = $0
      sub(/^- \[[ xX]\] /, "", text)
      gsub(/<!--[^>]*-->/, "", text)
      gsub(/^[ \t]+/, "", text)
      gsub(/[ \t]+$/, "", text)
      print idx "\t" checked "\t" text
    }
    next
  }
  { next }
')

if [[ -z "$RECORDS" ]]; then
  echo '{"resolved":true,"pre_merge_total":0,"unchecked_count":0,"unchecked_indices":"","unchecked_items":[]}'
  exit 0
fi

printf '%s\n' "$RECORDS" | jq -R -s '
  split("\n") | map(select(length > 0)) | map(split("\t"))
  | map({index: (.[0] | tonumber), checked: (.[1] == "1"), text: .[2]}) as $all
  | ($all | map(select(.checked | not))) as $unchecked
  | {
      resolved: true,
      pre_merge_total: ($all | length),
      unchecked_count: ($unchecked | length),
      unchecked_indices: ($unchecked | map(.index | tostring) | join(",")),
      unchecked_items: ($unchecked | map({index: .index, text: .text}))
    }
'
