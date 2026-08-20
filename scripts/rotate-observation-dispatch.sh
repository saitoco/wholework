#!/usr/bin/env bash
# rotate-observation-dispatch.sh
# Rotate observation-dispatch candidate Issue numbers by a persisted cursor
# (the last dispatched Issue number) before applying the dispatch cap, so
# chronically-stalled Issues at the head of the ascending candidate list do
# not permanently occupy every dispatch slot.
#
# Usage:
#   <candidates, one issue number per line> | scripts/rotate-observation-dispatch.sh \
#     --threshold <N> [--cursor-file <path>]
#
# --threshold <N>: required. Missing, non-numeric, or <=0 is a caller bug
#   (the caller is expected to pass a value already resolved via
#   detect-config-markers.md) — hard error, not fail-open.
# --cursor-file <path>: optional, default .tmp/observation-dispatch-cursor
#   (CWD-relative).
#
# Rotation: candidates greater than the cursor (ascending), followed by
# candidates less than or equal to the cursor (ascending). When the cursor is
# at or beyond the largest candidate, this degrades to the original ascending
# order (wrap-around). Cursor read/write is fail-open best-effort — a missing
# or unreadable cursor file is treated as cursor=0; a write failure only
# warns on stderr and does not affect the exit code.
#
# Output: the rotated, capped dispatch set, one Issue number per line, in
# rotated order (not re-sorted to ascending). Always exits 0 once past
# argument validation.

set -euo pipefail

THRESHOLD=""
CURSOR_FILE=".tmp/observation-dispatch-cursor"

while [ $# -gt 0 ]; do
    case "$1" in
        --threshold)
            if [ $# -lt 2 ]; then
                echo "Error: --threshold requires an argument" >&2
                exit 1
            fi
            THRESHOLD="$2"
            shift 2
            ;;
        --cursor-file)
            if [ $# -lt 2 ]; then
                echo "Error: --cursor-file requires an argument" >&2
                exit 1
            fi
            CURSOR_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -le 0 ]; then
    echo "Error: --threshold must be a positive integer (got: '${THRESHOLD}')" >&2
    exit 1
fi

CANDIDATES="$(cat | grep -E '^[0-9]+$' | sort -un || true)"

if [ -z "$CANDIDATES" ]; then
    exit 0
fi

CURSOR=0
if [ -f "$CURSOR_FILE" ]; then
    RAW_CURSOR="$(cat "$CURSOR_FILE" 2>/dev/null || true)"
    if [[ "$RAW_CURSOR" =~ ^[0-9]+$ ]]; then
        CURSOR="$RAW_CURSOR"
    else
        echo "Warning: rotate-observation-dispatch.sh: cursor file '$CURSOR_FILE' has no valid cursor — treating cursor as 0" >&2
    fi
fi

AFTER_CURSOR="$(printf '%s\n' "$CANDIDATES" | awk -v c="$CURSOR" '$1 > c')"
UP_TO_CURSOR="$(printf '%s\n' "$CANDIDATES" | awk -v c="$CURSOR" '$1 <= c')"

ROTATED="$(printf '%s\n%s\n' "$AFTER_CURSOR" "$UP_TO_CURSOR" | grep -E '^[0-9]+$' || true)"

DISPATCH_SET="$(printf '%s\n' "$ROTATED" | head -n "$THRESHOLD")"

if [ -n "$DISPATCH_SET" ]; then
    NEW_CURSOR="$(printf '%s\n' "$DISPATCH_SET" | tail -n 1)"
    if ! mkdir -p "$(dirname "$CURSOR_FILE")" 2>/dev/null || ! printf '%s\n' "$NEW_CURSOR" > "$CURSOR_FILE" 2>/dev/null; then
        echo "Warning: rotate-observation-dispatch.sh: failed to write cursor file '$CURSOR_FILE' — continuing without persisting cursor" >&2
    fi
fi

printf '%s\n' "$DISPATCH_SET"

exit 0
