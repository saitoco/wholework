#!/usr/bin/env bash
# check-skill-change-observation-ac.sh - Detect observation ACs missing session=next
# when the Issue body changes skills/*/SKILL.md
#
# Usage: check-skill-change-observation-ac.sh <issue-body-md-path>
#
# Exit codes:
#   0 — no skills/*/SKILL.md reference in the body, or every matching observation
#       AC already carries session=next
#   1 — usage error (missing argument or unreadable file)
#   2 — one or more observation AC lines lack session=next (printed to stdout, one per line)

set -euo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]] || [[ ! -r "$FILE" ]]; then
  echo "Usage: check-skill-change-observation-ac.sh <issue-body-md-path>" >&2
  exit 1
fi

if ! grep -qE 'skills/[A-Za-z0-9_-]+/SKILL\.md' "$FILE"; then
  exit 0
fi

untagged_found=false
while IFS= read -r line; do
  case "$line" in
    "- [ ]"* | "- [x]"* | "- [X]"*) ;;
    *) continue ;;
  esac
  case "$line" in
    *"verify-type: observation"*) ;;
    *) continue ;;
  esac
  case "$line" in
    *"session=next"*) continue ;;
  esac
  echo "$line"
  untagged_found=true
done < "$FILE"

if [[ "$untagged_found" == "true" ]]; then
  exit 2
fi

exit 0
