#!/bin/bash
# emit-skill-event.sh - Single-command wrapper for skill/module event emission.
#
# Replaces the `source emit-event.sh` + restore_auto_session_pointer + guard +
# emit_event compound snippet that skills/verify/SKILL.md (#1458) and
# modules/opportunistic-verify.md / modules/retro-proposals.md (#1461)
# previously embedded inline (rejected by the worktree isolation guard as
# "too complex to verify that it stays inside the worktree").
#
# Usage:
#   emit-skill-event.sh <issue> <event> [--require-session-id|--unconditional]
#                       [--emit-issue <N>] [--session-id <SID>] [key=value ...]
#   emit-skill-event.sh --persist-session <sid-or-empty> <issue>
set -uo pipefail
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
if [[ ! -f "$SCRIPT_DIR/emit-event.sh" ]]; then
  echo "Error: emit-event.sh not found under $SCRIPT_DIR" >&2
  exit 1
fi
source "$SCRIPT_DIR/emit-event.sh"

if [[ "${1:-}" == "--persist-session" ]]; then
  SID="${2:-}"
  ISSUE="${3:?usage: emit-skill-event.sh --persist-session <sid-or-empty> <issue>}"
  persist_auto_session_pointer "$SID" "$ISSUE"
  exit 0
fi

ISSUE="${1:?usage: emit-skill-event.sh <issue> <event> [--require-session-id|--unconditional] [--emit-issue <N>] [--session-id <SID>] [key=value ...]}"
EVENT="${2:?event name required}"
shift 2

MODE="standard"
EMIT_ISSUE_OVERRIDE=""
SESSION_ID_ARG=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --require-session-id) MODE="require-session-id"; shift ;;
    --unconditional)      MODE="unconditional"; shift ;;
    --emit-issue)
      if [[ $# -lt 2 ]]; then echo "Error: --emit-issue requires an argument" >&2; exit 1; fi
      EMIT_ISSUE_OVERRIDE="$2"; shift 2 ;;
    --session-id)
      if [[ $# -lt 2 ]]; then echo "Error: --session-id requires an argument" >&2; exit 1; fi
      SESSION_ID_ARG="$2"; shift 2 ;;
    *) echo "Error: unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$SESSION_ID_ARG" ]]; then
  AUTO_SESSION_ID="$SESSION_ID_ARG"
  export AUTO_SESSION_ID
fi

if [[ "$ISSUE" =~ ^[0-9]+$ ]]; then
  restore_auto_session_pointer "$ISSUE"
  EMIT_ISSUE="$ISSUE"
else
  restore_auto_session_pointer
  EMIT_ISSUE="0"
fi

if [[ -n "$EMIT_ISSUE_OVERRIDE" ]]; then
  if [[ "$EMIT_ISSUE_OVERRIDE" =~ ^[0-9]+$ ]]; then
    EMIT_ISSUE="$EMIT_ISSUE_OVERRIDE"
  else
    echo "Warning: --emit-issue is not a positive integer, using 0: $EMIT_ISSUE_OVERRIDE" >&2
    EMIT_ISSUE="0"
  fi
fi

if [[ "$MODE" == "standard" ]]; then
  if [[ -z "${AUTO_EVENTS_LOG:-}" ]]; then exit 0; fi
elif [[ "$MODE" == "require-session-id" ]]; then
  if [[ -z "${AUTO_EVENTS_LOG:-}" || -z "${AUTO_SESSION_ID:-}" ]]; then exit 0; fi
fi
# unconditional: no guard check (preserves recoveries_threshold_fire's existing behavior — see Notes in docs/spec/issue-1458-verify-emit-single-command.md)

EMIT_ISSUE_NUMBER="$EMIT_ISSUE" emit_event "$EVENT" "$@"
