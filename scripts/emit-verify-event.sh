#!/bin/bash
# emit-verify-event.sh - Single-command wrapper for /verify event emission.
#
# Replaces the `source emit-event.sh` + restore_auto_session_pointer + guard +
# emit_event compound snippet that skills/verify/SKILL.md previously embedded
# inline (rejected by the worktree isolation guard as "too complex to verify
# that it stays inside the worktree" — Issue #1458).
#
# Usage:
#   emit-verify-event.sh <issue> <event> [--require-session-id|--unconditional] [key=value ...]
#   emit-verify-event.sh --persist-session <sid-or-empty> <issue>
set -uo pipefail
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
source "$SCRIPT_DIR/emit-event.sh"

if [[ "${1:-}" == "--persist-session" ]]; then
  SID="${2:-}"
  ISSUE="${3:?usage: emit-verify-event.sh --persist-session <sid-or-empty> <issue>}"
  persist_auto_session_pointer "$SID" "$ISSUE"
  exit 0
fi

ISSUE="${1:?usage: emit-verify-event.sh <issue> <event> [--require-session-id|--unconditional] [key=value ...]}"
EVENT="${2:?event name required}"
shift 2

MODE="standard"
if [[ "${1:-}" == "--require-session-id" ]]; then
  MODE="require-session-id"; shift
elif [[ "${1:-}" == "--unconditional" ]]; then
  MODE="unconditional"; shift
fi

restore_auto_session_pointer "$ISSUE"

if [[ "$MODE" == "standard" ]]; then
  if [[ -z "${AUTO_EVENTS_LOG:-}" ]]; then exit 0; fi
elif [[ "$MODE" == "require-session-id" ]]; then
  if [[ -z "${AUTO_EVENTS_LOG:-}" || -z "${AUTO_SESSION_ID:-}" ]]; then exit 0; fi
fi
# unconditional: no guard check (preserves recoveries_threshold_fire's existing behavior — see Notes in docs/spec/issue-1458-verify-emit-single-command.md)

EMIT_ISSUE_NUMBER="$ISSUE" emit_event "$EVENT" "$@"
