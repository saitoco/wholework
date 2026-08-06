#!/usr/bin/env bash
# check-ac-checkbox-format.sh - Detect non-checkbox acceptance criteria lines
# under ### Pre-merge / ### Post-merge sections of an Issue body
#
# Plain bullet lines (`- text`) in these sections are unresolvable downstream:
# /verify has no checkbox to mark PASS on, so the Issue stays in phase/verify
# forever even after the underlying condition is satisfied. This script
# detects the format violation regardless of whether a verify-type/verify
# marker is present on the line.
#
# Usage: check-ac-checkbox-format.sh <issue-body-md-path>
#
# Exit codes:
#   0 — no ### Pre-merge / ### Post-merge section in the body, or every
#       condition line under those sections is already checkbox format
#   1 — usage error (missing argument or unreadable file)
#   2 — one or more non-checkbox condition lines detected (printed to
#       stdout, one per line)

set -euo pipefail

FILE="${1:-}"

if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]] || [[ ! -r "$FILE" ]]; then
  echo "Usage: check-ac-checkbox-format.sh <issue-body-md-path>" >&2
  exit 1
fi

VIOLATIONS=$(awk '
  BEGIN { in_section = 0 }
  /^### Pre-merge/ { in_section = 1; next }
  /^### Post-merge/ { in_section = 1; next }
  /^## / || /^### / {
    in_section = 0
    next
  }
  /^- / {
    if (in_section && $0 !~ /^- \[[ xX]\]/) {
      print
    }
    next
  }
  { next }
' "$FILE")

if [[ -n "$VIOLATIONS" ]]; then
  printf '%s\n' "$VIOLATIONS"
  exit 2
fi

exit 0
