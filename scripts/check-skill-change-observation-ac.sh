#!/usr/bin/env bash
# check-skill-change-observation-ac.sh - Detect observation ACs missing session=next
# when the Issue body references skills/*/SKILL.md
#
# The scope gate scans the whole body, so a mere mention (not only a declared
# change) triggers the scan. This is a deliberate best-effort proxy: at /issue
# time no Spec exists, so there is no ## Changed Files section to scope against.
# False positives are acceptable because the caller treats the result as a
# warning, not a gate.
#
# Usage: check-skill-change-observation-ac.sh <issue-body-md-path>
#
# Exit codes:
#   0 — no skills/*/SKILL.md reference in the body, or every matching unchecked
#       observation AC already carries session=next
#   1 — usage error (missing argument or unreadable file)
#   2 — one or more unchecked observation AC lines lack session=next (printed to
#       stdout, one per line). Already-checked (`- [x]`) lines are not scanned.

set -euo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]] || [[ ! -r "$FILE" ]]; then
  echo "Usage: check-skill-change-observation-ac.sh <issue-body-md-path>" >&2
  exit 1
fi

if ! grep -qE 'skills/[A-Za-z0-9_*-]+/SKILL\.md' "$FILE"; then
  exit 0
fi

untagged_found=false
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    "- [ ]"*) ;;
    *) continue ;;
  esac
  tag=$(printf '%s\n' "$line" | grep -oE '<!--.*-->' || true)
  case "$tag" in
    *"verify-type: observation"*) ;;
    *) continue ;;
  esac
  case "$tag" in
    *"session=next"*) continue ;;
  esac
  echo "$line"
  untagged_found=true
done < "$FILE"

if [[ "$untagged_found" == "true" ]]; then
  exit 2
fi

exit 0
