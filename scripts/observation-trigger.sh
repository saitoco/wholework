#!/bin/bash
# observation-trigger.sh
# Dispatch observation-type ACs when a named event fires.
#
# Usage:
#   scripts/observation-trigger.sh --event <event-name> [--dry-run] [--context-file <path>]
#
# --context-file is forwarded as-is to opportunistic-search.sh, which gates
# matches carrying a `keyword=<text>` AC attribute against the file's content
# (case-insensitive substring match). See modules/observation-trigger.md § Condition Check Gate.
#
# For each matched Issue, posts a comment recommending the user re-run /verify.
# Errors are non-fatal (2>/dev/null || true pattern throughout).

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

EVENT_NAME=""
DRY_RUN=false
CONTEXT_FILE=""

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
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Usage: $0 --event <event-name> [--dry-run] [--context-file <path>]" >&2
            exit 1
            ;;
    esac
done

if [ -z "$EVENT_NAME" ]; then
    echo "Error: --event <event-name> is required" >&2
    echo "Usage: $0 --event <event-name> [--dry-run]" >&2
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    exit 0
fi

CONTEXT_FILE_ARGS=()
if [ -n "$CONTEXT_FILE" ]; then
    CONTEXT_FILE_ARGS=(--context-file "$CONTEXT_FILE")
fi

RESULTS=$("${SCRIPT_DIR}/opportunistic-search.sh" --event "$EVENT_NAME" "${CONTEXT_FILE_ARGS[@]}" 2>/dev/null || true)

if [ -z "$RESULTS" ] || [ "$RESULTS" = "[]" ]; then
    exit 0
fi

NUMBERS=$(echo "$RESULTS" | jq -r '.[].number' 2>/dev/null | sort -un || true)
if [ -z "$NUMBERS" ]; then
    exit 0
fi

for N in $NUMBERS; do
    gh issue comment "$N" --body "observation event \`${EVENT_NAME}\` detected. Run \`/verify ${N}\` to verify the condition and update the checkbox." 2>/dev/null || true
done

echo "$NUMBERS"
