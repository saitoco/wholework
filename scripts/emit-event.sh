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

# Documented event schemas:
#
# manual_intervention: parent session manually recovered a child wrapper failure
#   recovery_target=<phase>       e.g. code-patch, verify
#   wrapper_exit_code=<code>      original wrapper exit code
#   intervention_type=<type>      silent_no_op_manual_fix | tier3_abort_manual_fix | direct_commit
#
# verify_reopen_cycle: /verify FAIL -> issue reopen fix cycle entered
#   iteration=<n>                 verify iteration counter (from get-verify-iteration.sh)
#   reopen_reason=<reason>        pre_merge_ac_fail | post_merge_observation_fail | manual_judgment
#
# comments_consumed: skill consumed comments added since the previous phase
#   phase=<phase-name>            e.g. spec, code, verify
#   count=<n>                     total number of comments consumed
#   authors=<comma-separated>     comma-separated list of author logins
#   trust_breakdown=<flat>        KEY:n format — OWNER:n,MEMBER:n,COLLABORATOR:n,CONTRIBUTOR:n,NONE:n
#                                 (flat format avoids JSON quoting issues with emit_event() sanitization)
#
# verify_retry_fire: tail extension fired /code to retry after FAIL
#   iteration=<n>                 verify retry iteration counter (1-based within auto-retry)
#   trigger_reason=<reason>       ac_fail | verify_timeout | verify_uncertain
#   budget_remaining_tokens=<n>   estimated remaining token budget (approximated)

emit_event() {
  local event_type="$1"; shift
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local _log="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
  local _issue="${EMIT_ISSUE_NUMBER:-0}"
  local _sid="${AUTO_SESSION_ID:-}"
  local json="{\"ts\":\"${ts}\",\"issue\":${_issue},\"event\":\"${event_type}\",\"session_id\":\"${_sid}\""
  while [[ $# -gt 0 ]]; do
    local kv="$1"; local k="${kv%%=*}"; local v="${kv#*=}"
    # sanitize value: strip newlines, replace tabs, escape backslash and double-quote
    local v_sanitized="${v//$'\n'/}"
    v_sanitized="${v_sanitized//$'\t'/ }"
    v_sanitized="${v_sanitized//\\/\\\\}"
    v_sanitized="${v_sanitized//\"/\\\"}"
    json="${json},\"${k}\":\"${v_sanitized}\""
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
