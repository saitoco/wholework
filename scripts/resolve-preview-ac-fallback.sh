#!/usr/bin/env bash
# resolve-preview-ac-fallback.sh
# Resolve the latest type=preview-ac-unverified marker from Issue comments and
# print the 1-based AC indices that still need /verify fallback.
# Usage: resolve-preview-ac-fallback.sh <issue-number>
# Output: comma-separated 1-based AC indices needing fallback, or empty when
#   there is no marker, the marker's ac= is empty, or ac=none.
# Exit codes: 0 on success (including "no fallback needed" empty output),
#   1 on invalid argument, 2 when `gh` itself fails (network/auth/rate-limit) —
#   distinct from "no marker", so callers can tell "unresolved" apart from
#   "could not be determined this run".

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <issue-number>" >&2
  exit 1
fi

ISSUE_NUMBER="$1"

if ! echo "$ISSUE_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "Error: issue number must be a positive integer, got: $ISSUE_NUMBER" >&2
  exit 1
fi

if ! latest_marker_body="$(gh issue view "$ISSUE_NUMBER" --json comments \
  --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=preview-ac-unverified"))] | sort_by(.createdAt) | .[-1].body // empty' \
  2>/dev/null)"; then
  echo "Error: gh issue view failed for issue $ISSUE_NUMBER (network/auth/rate-limit) — result is unknown, not \"no marker\"" >&2
  exit 2
fi

marker_line="$(echo "$latest_marker_body" | grep -F '<!-- wholework-event: type=preview-ac-unverified' | head -1 || true)"

if [ -z "$marker_line" ]; then
  echo ""
  exit 0
fi

ac_value="$(echo "$marker_line" | sed -n 's/.*[[:space:]]ac=\([^[:space:]]*\).*/\1/p' || true)"

if [ -z "$ac_value" ] || [ "$ac_value" = "none" ]; then
  echo ""
  exit 0
fi

echo "$ac_value"
exit 0
