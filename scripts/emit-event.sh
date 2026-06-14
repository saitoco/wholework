#!/bin/bash
# emit-event.sh - Shared event emission helper for auto-events.jsonl
# Source this file to use emit_event() in run-*.sh and watchdog scripts.
#
# Usage: source emit-event.sh
#
# Required env vars:
#   AUTO_EVENTS_LOG    - Path to the JSONL log file (default: .tmp/auto-events.jsonl)
#   EMIT_ISSUE_NUMBER  - Issue number for the current phase (set by caller)
#
# Optional env vars:
#   EMIT_PHASE_NAME    - Phase name for the current execution context

emit_event() {
  local event_type="$1"; shift
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local _log="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
  local _issue="${EMIT_ISSUE_NUMBER:-0}"
  local _sid="${AUTO_SESSION_ID:-}"
  local json="{\"ts\":\"${ts}\",\"issue\":${_issue},\"event\":\"${event_type}\",\"session_id\":\"${_sid}\""
  while [[ $# -gt 0 ]]; do
    local kv="$1"; local k="${kv%%=*}"; local v="${kv#*=}"
    json="${json},\"${k}\":\"${v}\""
    shift
  done
  json="${json}}"
  mkdir -p "$(dirname "${_log}")"
  if command -v flock >/dev/null 2>&1; then
    (flock -x 200; echo "${json}" >> "${_log}") 200>"${_log}.lock"
  else
    local lock_dir="${_log}.lockdir"
    local tries=0
    while ! mkdir "${lock_dir}" 2>/dev/null; do
      tries=$((tries + 1))
      if (( tries > 50 )); then
        echo "${json}" >> "${_log}"
        return 0
      fi
      sleep 0.1
    done
    echo "${json}" >> "${_log}"
    rmdir "${lock_dir}" 2>/dev/null || true
  fi
}
