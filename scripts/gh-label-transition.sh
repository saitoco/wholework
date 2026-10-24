#!/bin/bash
# gh-label-transition.sh
# Transition phase labels on an issue
#
# Usage:
#   scripts/gh-label-transition.sh <issue-number> [target-phase] [--assign]
#
# target-phase: issue, spec, ready, code, review, verify, done
# If target-phase is omitted: remove all phase/* labels without adding any
#
# --assign (opt-in, requires target-phase): after the label update succeeds, run
#   `gh-issue-assignee.sh assign` as a separate call to add the executing user as
#   assignee when the issue has none. A failed assignee update only prints a warning;
#   the transition still exits 0. Does nothing when `auto-assign: false` is set in
#   .wholework.yml. Never applied unless the caller passes it (the target phase does
#   not trigger it). The flag may appear anywhere in the arguments.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
PHASE_LABELS="phase/issue phase/spec phase/ready phase/code phase/review phase/verify phase/done"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 <issue-number> [target-phase] [--assign]"
    echo ""
    echo "target-phase: issue, spec, ready, code, review, verify, done"
    echo "If target-phase is omitted: remove all phase/* labels without adding any"
    echo ""
    echo "--assign: after the label update, add the executing user as assignee when the"
    echo "          issue has none (requires target-phase; failures only warn;"
    echo "          disabled by 'auto-assign: false' in .wholework.yml)"
    exit 0
fi

ISSUE_NUMBER=""
TARGET_PHASE=""
ASSIGN="false"
POSITIONAL_COUNT=0
for ARG in "$@"; do
    if [ "$ARG" = "--assign" ]; then
        ASSIGN="true"
        continue
    fi
    POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
    if [ "$POSITIONAL_COUNT" -eq 1 ]; then
        ISSUE_NUMBER="$ARG"
    elif [ "$POSITIONAL_COUNT" -eq 2 ]; then
        TARGET_PHASE="$ARG"
    fi
done

if [ "$POSITIONAL_COUNT" -lt 1 ]; then
    echo "Error: issue number is required" >&2
    echo "Usage: $0 <issue-number> [target-phase] [--assign]" >&2
    exit 1
fi

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

if [ "$ASSIGN" = "true" ] && [ -z "$TARGET_PHASE" ]; then
    echo "Error: --assign requires a target phase" >&2
    exit 1
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
    if ! gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"; then
        echo "Error: failed to update labels for issue #$ISSUE_NUMBER" >&2
        exit 1
    fi
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
        if ! gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}" --add-label "phase/$TARGET_PHASE"; then
            echo "Error: failed to update labels for issue #$ISSUE_NUMBER" >&2
            exit 1
        fi
    else
        if ! gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"; then
            echo "Error: failed to update labels for issue #$ISSUE_NUMBER" >&2
            exit 1
        fi
    fi
fi

# Opt-in assignee update: a separate call after the label update, never fatal.
# The result word on stdout is dropped (stdout of this script stays unchanged);
# warnings from the helper remain on stderr.
if [ "$ASSIGN" = "true" ]; then
    if ! "$SCRIPT_DIR/gh-issue-assignee.sh" assign "$ISSUE_NUMBER" >/dev/null; then
        echo "Warning: assignee update for issue #$ISSUE_NUMBER failed; continuing" >&2
    fi
fi
