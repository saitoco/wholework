#!/bin/bash
# set-blocked-by.sh
# Set a GitHub blocked-by relationship between two issues
#
# Usage:
#   scripts/set-blocked-by.sh <issue-number> <blocking-issue-number>
#
# Exit codes:
#   0 -- relationship set successfully (or already set)
#   1 -- error (bad arguments, API error, etc.)

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

usage() {
    echo "Usage: $(basename "$0") <issue-number> <blocking-issue-number>"
    echo ""
    echo "Set a GitHub blocked-by relationship: <issue-number> is blocked by <blocking-issue-number>."
    echo ""
    echo "Exit codes:"
    echo "  0 -- success"
    echo "  1 -- error"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ $# -lt 2 ]; then
    echo "Error: two arguments required: <issue-number> <blocking-issue-number>" >&2
    usage >&2
    exit 1
fi

ISSUE_NUM="$1"
BLOCKING_NUM="$2"

if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
    echo "Error: issue-number must be a positive integer: $ISSUE_NUM" >&2
    exit 1
fi

if ! [[ "$BLOCKING_NUM" =~ ^[0-9]+$ ]]; then
    echo "Error: blocking-issue-number must be a positive integer: $BLOCKING_NUM" >&2
    exit 1
fi

GH_GRAPHQL="$SCRIPT_DIR/gh-graphql.sh"

ISSUE_ID=$("$GH_GRAPHQL" --cache --query get-issue-id -F num="$ISSUE_NUM" --jq '.data.repository.issue.id') || {
    echo "Error: failed to get node ID for issue #$ISSUE_NUM" >&2
    exit 1
}

if [ -z "$ISSUE_ID" ]; then
    echo "Error: issue #$ISSUE_NUM not found" >&2
    exit 1
fi

BLOCKING_ID=$("$GH_GRAPHQL" --cache --query get-issue-id -F num="$BLOCKING_NUM" --jq '.data.repository.issue.id') || {
    echo "Error: failed to get node ID for issue #$BLOCKING_NUM" >&2
    exit 1
}

if [ -z "$BLOCKING_ID" ]; then
    echo "Error: issue #$BLOCKING_NUM not found" >&2
    exit 1
fi

"$GH_GRAPHQL" --query add-blocked-by -F issueId="$ISSUE_ID" -F blockingId="$BLOCKING_ID" > /dev/null || {
    echo "Error: addBlockedBy mutation failed (#$ISSUE_NUM blocked by #$BLOCKING_NUM)" >&2
    exit 1
}
