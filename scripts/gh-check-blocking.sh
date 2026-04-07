#!/bin/bash
# gh-check-blocking.sh
# Detect "Blocked by" patterns in issue body and set GitHub blockedBy relationships
#
# Usage:
#   scripts/gh-check-blocking.sh <issue-number> [--dry-run]
#
# Options:
#   --dry-run    Print detection results only; skip GraphQL mutations
#
# Output:
#   BLOCKING: #N (OPEN)             -- open blocker detected
#   BLOCKING: #N (CLOSED - skipped) -- closed blocker (skipped)
#
# Exit codes:
#   0 -- no open blockers (or all closed)
#   1 -- error (bad arguments, API error, etc.)
#   2 -- open blocker(s) found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: $(basename "$0") <issue-number> [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Print detection results only; skip GraphQL mutations"
    echo ""
    echo "Exit codes:"
    echo "  0 -- no open blockers"
    echo "  1 -- error"
    echo "  2 -- open blocker(s) found"
}

# Parse arguments
NUMBER=""
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        [0-9]*)
            NUMBER="$arg"
            ;;
        *)
            echo "Error: unknown argument: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$NUMBER" ]; then
    echo "Error: issue number is required" >&2
    usage >&2
    exit 1
fi

# Fetch issue body and detect "Blocked by" patterns
BODY=$(gh issue view "$NUMBER" --json body -q '.body' 2>/dev/null) || {
    echo "Error: failed to fetch issue #$NUMBER" >&2
    exit 1
}

# Extract issue numbers from "Blocked by #N" patterns (case-insensitive)
BLOCKERS=$(echo "$BODY" | grep -ioE "blocked by #[0-9]+" | grep -oE "[0-9]+" || true)

if [ -z "$BLOCKERS" ]; then
    exit 0
fi

HAS_OPEN=false

for BLOCKER_NUM in $BLOCKERS; do
    # Check blocker state
    BLOCKER_STATE=$(gh issue view "$BLOCKER_NUM" --json state -q '.state' 2>/dev/null) || {
        echo "Warning: issue #$BLOCKER_NUM not found; skipping blocked-by setup" >&2
        continue
    }

    if [ "$BLOCKER_STATE" = "CLOSED" ]; then
        echo "BLOCKING: #$BLOCKER_NUM (CLOSED - skipped)"
        continue
    fi

    echo "BLOCKING: #$BLOCKER_NUM (OPEN)"
    HAS_OPEN=true

    if [ "$DRY_RUN" = "true" ]; then
        continue
    fi

    # Set blockedBy relationship via GraphQL (PATH lookup first, then $SCRIPT_DIR)
    if command -v gh-graphql.sh &>/dev/null; then
        GH_GRAPHQL="$(command -v gh-graphql.sh)"
    else
        GH_GRAPHQL="$SCRIPT_DIR/gh-graphql.sh"
    fi

    ISSUE_ID=$("$GH_GRAPHQL" --cache --query get-issue-id -F num="$NUMBER" --jq '.data.repository.issue.id') || {
        echo "Error: failed to get ID for issue #$NUMBER" >&2
        exit 1
    }
    BLOCKER_ID=$("$GH_GRAPHQL" --cache --query get-issue-id -F num="$BLOCKER_NUM" --jq '.data.repository.issue.id') || {
        echo "Error: failed to get ID for issue #$BLOCKER_NUM" >&2
        exit 1
    }

    "$GH_GRAPHQL" --query add-blocked-by -F issueId="$ISSUE_ID" -F blockingId="$BLOCKER_ID" > /dev/null || {
        echo "Error: addBlockedBy mutation failed (#$NUMBER blocked by #$BLOCKER_NUM)" >&2
        exit 1
    }
done

if [ "$HAS_OPEN" = "true" ]; then
    exit 2
fi

exit 0
