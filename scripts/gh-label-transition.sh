#!/bin/bash
# gh-label-transition.sh
# Transition phase labels on an issue
#
# Usage:
#   scripts/gh-label-transition.sh <issue-number> [target-phase]
#
# target-phase: issue, spec, ready, code, review, verify, done
# If target-phase is omitted: remove all phase/* labels without adding any

set -euo pipefail

PHASE_LABELS="phase/issue phase/spec phase/ready phase/code phase/review phase/verify phase/done"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 <issue-number> [target-phase]"
    echo ""
    echo "target-phase: issue, spec, ready, code, review, verify, done"
    echo "If target-phase is omitted: remove all phase/* labels without adding any"
    exit 0
fi

if [ $# -lt 1 ]; then
    echo "Error: issue number is required" >&2
    echo "Usage: $0 <issue-number> [target-phase]" >&2
    exit 1
fi

ISSUE_NUMBER="$1"
TARGET_PHASE="${2:-}"

# Validate issue number is a positive integer
if ! [[ "$ISSUE_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: issue number must be a positive integer: $ISSUE_NUMBER" >&2
    exit 1
fi

# Validate target-phase if specified
if [ -n "$TARGET_PHASE" ]; then
    case "$TARGET_PHASE" in
        issue|spec|ready|code|review|verify|done) ;;
        *)
            echo "Error: invalid phase: $TARGET_PHASE" >&2
            echo "Valid phases: issue, spec, ready, code, review, verify, done" >&2
            exit 1
            ;;
    esac
fi

# Build --remove-label flags for all phase/* labels
REMOVE_ARGS=()
for label in $PHASE_LABELS; do
    REMOVE_ARGS+=(--remove-label "$label")
done

# Add target phase label if specified
if [ -n "$TARGET_PHASE" ]; then
    gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}" --add-label "phase/$TARGET_PHASE"
else
    gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"
fi
