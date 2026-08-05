#!/bin/bash
# observation-trigger.sh
# Dispatch observation-type ACs when a named event fires.
#
# Usage:
#   scripts/observation-trigger.sh --event <event-name> [--dry-run] [--context-file <path>] [--facts-file <path>]
#
# --context-file is forwarded as-is to opportunistic-search.sh, which gates
# matches carrying a `keyword=<text>` AC attribute against the file's content
# (case-insensitive substring match). See modules/observation-trigger.md § Condition Check Gate.
#
# --facts-file is forwarded as-is to opportunistic-search.sh, which gates
# matches carrying a `when=<axis>:<value>` AC attribute against /auto run facts
# (route / mode / recovery-tier). See modules/observation-trigger.md § Condition
# Check Gate (when=).
#
# For each matched Issue, posts a comment recommending the user re-run /verify,
# unless a `<!-- wholework-event: type=observation-trigger ... event=<name> -->`
# marker for the same event was already posted to that Issue within the last
# 24 hours (idempotency guard — skipped Issues are still included below).
# Errors are non-fatal (2>/dev/null || true pattern throughout).
#
# stdout contract: matched Issue numbers only, one per line, ascending order
# (numbers whose comment was skipped by the idempotency guard are still
# included). No other output (e.g. comment URLs) is written to stdout.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

EVENT_NAME=""
DRY_RUN=false
CONTEXT_FILE=""
FACTS_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --event)
            if [ $# -lt 2 ]; then
                echo "Error: --event requires an argument" >&2
                exit 1
            fi
            EVENT_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --context-file)
            if [ $# -lt 2 ]; then
                echo "Error: --context-file requires an argument" >&2
                exit 1
            fi
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --facts-file)
            if [ $# -lt 2 ]; then
                echo "Error: --facts-file requires an argument" >&2
                exit 1
            fi
            FACTS_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Usage: $0 --event <event-name> [--dry-run] [--context-file <path>] [--facts-file <path>]" >&2
            exit 1
            ;;
    esac
done

if [ -z "$EVENT_NAME" ]; then
    echo "Error: --event <event-name> is required" >&2
    echo "Usage: $0 --event <event-name> [--dry-run]" >&2
    exit 1
fi

SEARCH_ARGS=(--event "$EVENT_NAME")
if [ -n "$CONTEXT_FILE" ]; then
    SEARCH_ARGS+=(--context-file "$CONTEXT_FILE")
fi
if [ -n "$FACTS_FILE" ]; then
    SEARCH_ARGS+=(--facts-file "$FACTS_FILE")
fi
RESULTS=$("${SCRIPT_DIR}/opportunistic-search.sh" "${SEARCH_ARGS[@]}" 2>/dev/null || true)

if [ -z "$RESULTS" ] || [ "$RESULTS" = "[]" ]; then
    exit 0
fi

NUMBERS=$(echo "$RESULTS" | jq -r '.[].number' 2>/dev/null | sort -un || true)
if [ -z "$NUMBERS" ]; then
    exit 0
fi

for N in $NUMBERS; do
    SKIP=false
    MARKER_TS=$(MARKER_N="$N" MARKER_EVENT="$EVENT_NAME" gh issue view "$N" --json comments \
        --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=" + env.MARKER_N + " event=" + env.MARKER_EVENT + " -->"))] | sort_by(.createdAt) | .[-1].createdAt // empty' \
        2>/dev/null || true)
    if [ -n "$MARKER_TS" ]; then
        if MARKER_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$MARKER_TS" "+%s" 2>/dev/null) || \
           MARKER_EPOCH=$(date -d "$MARKER_TS" "+%s" 2>/dev/null); then
            NOW_EPOCH=$(date +%s)
            ELAPSED=$(( NOW_EPOCH - MARKER_EPOCH ))
            if [ "$ELAPSED" -lt 86400 ]; then
                SKIP=true
            fi
        fi
    fi
    if [ "$SKIP" = false ] && [ "$DRY_RUN" = false ]; then
        BODY=$(printf '<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=%s event=%s -->\nobservation event `%s` detected. Run `/verify %s` to verify the condition and update the checkbox.' "$N" "$EVENT_NAME" "$EVENT_NAME" "$N")
        gh issue comment "$N" --body "$BODY" >/dev/null 2>/dev/null || true
    fi
done

echo "$NUMBERS"
