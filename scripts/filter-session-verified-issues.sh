#!/usr/bin/env bash
# filter-session-verified-issues.sh
# Filter out candidate Issue numbers that already have a phase=verify
# phase_start/phase_complete event recorded for the current /auto session,
# so observation scan dispatch does not re-verify Issues already handled
# earlier in the same session.
#
# Usage:
#   <candidates, one issue number per line> | scripts/filter-session-verified-issues.sh
#
# Session resolution order: AUTO_SESSION_ID env var > .tmp/auto-session-current
#   pointer file. Events log: ${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}.
#
# Fail-open: if the session id cannot be resolved, or the events log does not
# exist, all candidates are passed through unchanged (with a warning on
# stderr) rather than blocking the observation scan. Always exits 0
# (best-effort).
#
# Output: filtered candidate Issue numbers, one per line, ascending order.

set -euo pipefail

SESSION_ID="${AUTO_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="$(cat .tmp/auto-session-current 2>/dev/null || true)"
fi

EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"

CANDIDATES="$(cat)"

if [ -z "$SESSION_ID" ]; then
    echo "Warning: filter-session-verified-issues.sh: could not resolve session id (AUTO_SESSION_ID / .tmp/auto-session-current both empty) — passing candidates through unfiltered" >&2
    printf '%s\n' "$CANDIDATES" | grep -v '^[[:space:]]*$' || true
    exit 0
fi

if [ ! -f "$EVENTS_LOG" ]; then
    echo "Warning: filter-session-verified-issues.sh: events log not found at $EVENTS_LOG — passing candidates through unfiltered" >&2
    printf '%s\n' "$CANDIDATES" | grep -v '^[[:space:]]*$' || true
    exit 0
fi

VERIFIED_ISSUES="$(jq -r --arg sid "$SESSION_ID" \
    'select(.session_id == $sid and .phase == "verify" and (.event == "phase_start" or .event == "phase_complete")) | .issue' \
    "$EVENTS_LOG" 2>/dev/null | sort -un || true)"

# Set difference via grep -Fxq (not comm — comm assumes lexicographic order,
# which disagrees with `sort -n` for issue numbers of differing digit counts).
printf '%s\n' "$CANDIDATES" | grep -v '^[[:space:]]*$' | sort -un | while IFS= read -r n; do
    if [ -n "$VERIFIED_ISSUES" ] && printf '%s\n' "$VERIFIED_ISSUES" | grep -Fxq "$n"; then
        continue
    fi
    printf '%s\n' "$n"
done

exit 0
