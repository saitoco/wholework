#!/usr/bin/env bash
# resolve-preview-ac-fallback.sh
# Resolve the latest type=preview-ac-unverified marker from Issue comments and
# print the 1-based AC indices that still need /verify fallback.
# Usage: resolve-preview-ac-fallback.sh <issue-number>
# Output: comma-separated 1-based AC indices needing fallback, or empty when
#   there is no marker, the marker's ac= is empty, or ac=none.
# Exit codes: 0 on success (including "no fallback needed" empty output),
#   1 on invalid argument. Fails open on gh errors (empty output, exit 0).

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

latest_marker_body="$(gh issue view "$ISSUE_NUMBER" --json comments \
  --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=preview-ac-unverified"))] | sort_by(.createdAt) | .[-1].body // empty' \
  2>/dev/null || true)"

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
