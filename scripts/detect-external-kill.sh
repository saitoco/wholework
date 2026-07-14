#!/bin/bash
# detect-external-kill.sh - Detect the external-kill-parent-respawn signature
# (see modules/orchestration-fallbacks.md#external-kill-parent-respawn) mechanically.
#
# Usage: detect-external-kill.sh --log <wrapper-log-path> --events <auto-events-jsonl-path> \
#          --exit-code <N|unknown> --issue <N> --phase <name>
#
# Detection signature:
#   - exit code 137 (SIGKILL) alone is conclusive: the EXIT trap cannot run under SIGKILL
#   - exit code 143 (SIGTERM), or an unobserved exit code (unknown/empty), requires
#     corroborating evidence that the wrapper's own EXIT trap never ran: no "Exit code: "
#     trailer line in the wrapper log, AND no wrapper_exit event recorded for this
#     issue/phase in auto-events.jsonl
#
# Outputs "external-kill" to stdout and exits 0 when the signature matches.
# Outputs "no-match" to stdout and exits 1 when it does not.
# Bash 3.2+ compatible.

set -uo pipefail

LOG_FILE=""
EVENTS_FILE=""
EXIT_CODE=""
ISSUE_NUMBER=""
PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_FILE="${2:-}"
      shift 2
      ;;
    --events)
      EVENTS_FILE="${2:-}"
      shift 2
      ;;
    --exit-code)
      EXIT_CODE="${2:-}"
      shift 2
      ;;
    --issue)
      ISSUE_NUMBER="${2:-}"
      shift 2
      ;;
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$LOG_FILE" || -z "$EVENTS_FILE" || -z "$EXIT_CODE" || -z "$ISSUE_NUMBER" || -z "$PHASE" ]]; then
  echo "Usage: detect-external-kill.sh --log <path> --events <path> --exit-code <N|unknown> --issue <N> --phase <name>" >&2
  exit 2
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: log file not found: $LOG_FILE" >&2
  exit 2
fi

# exit code 137 (SIGKILL) is conclusive on its own.
if [[ "$EXIT_CODE" == "137" ]]; then
  echo "external-kill"
  exit 0
fi

if [[ "$EXIT_CODE" == "143" || "$EXIT_CODE" == "unknown" ]]; then
  if grep -q "^Exit code: " "$LOG_FILE" 2>/dev/null; then
    echo "no-match"
    exit 1
  fi
  # Each event is a single JSON line; chain greps through a pipe so each stage
  # narrows to matching lines only, requiring issue/event/phase to co-occur on
  # the same line rather than merely appearing somewhere in the file.
  if [[ -f "$EVENTS_FILE" ]] && grep -E "\"issue\":${ISSUE_NUMBER}[,}]" "$EVENTS_FILE" 2>/dev/null \
    | grep '"event":"wrapper_exit"' \
    | grep -q "\"phase\":\"${PHASE}\""; then
    echo "no-match"
    exit 1
  fi
  echo "external-kill"
  exit 0
fi

echo "no-match"
exit 1
