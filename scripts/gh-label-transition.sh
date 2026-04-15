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

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
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

# Check current labels if transitioning to a target phase
CURRENT_LABELS=""
if [ -n "$TARGET_PHASE" ]; then
    CURRENT_LABELS=$(gh issue view "$ISSUE_NUMBER" --json labels --jq '.labels[].name' 2>/dev/null || true)
fi

# If target label already exists, skip remove+add to avoid GitHub API race condition
# (remove+add of same label causes remove-only behavior)
TARGET_LABEL="phase/$TARGET_PHASE"
if [ -n "$TARGET_PHASE" ] && echo "$CURRENT_LABELS" | grep -qx "$TARGET_LABEL"; then
    # Target label already set: only remove other phase/* labels
    REMOVE_ARGS=()
    for label in $PHASE_LABELS; do
        if [ "$label" != "$TARGET_LABEL" ]; then
            REMOVE_ARGS+=(--remove-label "$label")
        fi
    done
    gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"
else
    # Build --remove-label flags for all phase/* labels except the target label
    REMOVE_ARGS=()
    for label in $PHASE_LABELS; do
        if [ "$label" != "$TARGET_LABEL" ]; then
            REMOVE_ARGS+=(--remove-label "$label")
        fi
    done

    # Auto-bootstrap: if target label doesn't exist in the repo, run setup-labels.sh
    if [ -n "$TARGET_PHASE" ]; then
        TARGET_LABEL_EXISTS=""
        TARGET_LABEL_EXISTS=$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null \
            | grep -x "phase/$TARGET_PHASE" || true)
        if [ -z "$TARGET_LABEL_EXISTS" ]; then
            "$SCRIPT_DIR/setup-labels.sh" || echo "Warning: label bootstrap failed, continuing" >&2
        fi
    fi

    # Add target phase label if specified
    if [ -n "$TARGET_PHASE" ]; then
        gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}" --add-label "phase/$TARGET_PHASE"
    else
        gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"
    fi
fi
