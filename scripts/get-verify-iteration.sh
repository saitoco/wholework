#!/usr/bin/env bash
# get-verify-iteration.sh
# Read the highest <!-- verify-iteration: N --> marker from Issue comments.
# Usage: get-verify-iteration.sh <issue-number>
# Output: the maximum N found, or 0 if no markers exist.
# Exit codes: 0 on success, 1 on invalid argument.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

if [ $# -ne 1 ]; then
  echo "Usage: $(basename "$0") <issue-number>" >&2
  exit 1
fi

ISSUE_NUMBER="$1"

if ! echo "$ISSUE_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "Error: issue number must be a positive integer, got: $ISSUE_NUMBER" >&2
  exit 1
fi

max_iteration=0

while IFS= read -r marker; do
  # Extract the numeric part from <!-- verify-iteration: N -->
  n="${marker//[^0-9]/}"
  if [ -n "$n" ] && [ "$n" -gt "$max_iteration" ] 2>/dev/null; then
    max_iteration="$n"
  fi
done < <(gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments[].body' 2>/dev/null \
  | grep -oE '<!-- verify-iteration: [0-9]+ -->' || true)

echo "$max_iteration"
