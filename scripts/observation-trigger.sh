#!/bin/bash
# observation-trigger.sh
# Dispatch observation-type ACs when a named event fires.
#
# Usage:
#   scripts/observation-trigger.sh --event <event-name> [--dry-run]
#
# For each matched Issue, posts a comment recommending the user re-run /verify.
# Errors are non-fatal (2>/dev/null || true pattern throughout).

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

EVENT_NAME=""
DRY_RUN=false

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
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "Usage: $0 --event <event-name> [--dry-run]" >&2
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

RESULTS=$("${SCRIPT_DIR}/opportunistic-search.sh" --event "$EVENT_NAME" 2>/dev/null || true)

if [ -z "$RESULTS" ] || [ "$RESULTS" = "[]" ]; then
    exit 0
fi

NUMBERS=$(echo "$RESULTS" | jq -r '.[].number' 2>/dev/null || true)
if [ -z "$NUMBERS" ]; then
    exit 0
fi

for N in $NUMBERS; do
    gh issue comment "$N" --body "observation event \`${EVENT_NAME}\` detected. Run \`/verify ${N}\` to verify the condition and update the checkbox." 2>/dev/null || true
done

echo "$NUMBERS"
