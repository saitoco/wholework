#!/bin/bash
# claude-watchdog.sh - Watchdog wrapper for claude -p invocations
# Detects hangs (no output for WATCHDOG_TIMEOUT seconds) and kills the process.
# Usage: claude-watchdog.sh <command> [args...]
#
# Environment variables:
#   WATCHDOG_TIMEOUT             - Seconds of no output before killing the process (default: 1800)
#   WATCHDOG_HEARTBEAT_INTERVAL  - Seconds between heartbeat messages during silence (default: 60)

set -uo pipefail

# Load emit_event when AUTO_EVENTS_LOG is set
[[ -n "${AUTO_EVENTS_LOG:-}" ]] && [[ -f "$(dirname "$0")/emit-event.sh" ]] && source "$(dirname "$0")/emit-event.sh" || true

WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-1800}"
WATCHDOG_HEARTBEAT_INTERVAL="${WATCHDOG_HEARTBEAT_INTERVAL:-60}"
# Check interval is min(WATCHDOG_TIMEOUT, 10) to keep tests fast with small timeouts
_CHECK_INTERVAL=$(( WATCHDOG_TIMEOUT < 10 ? WATCHDOG_TIMEOUT : 10 ))

# Global flag: set to true when watchdog triggers a kill
_watchdog_killed=false

_auto_emit_watchdog_kill() {
  local cmd_pid="$1" unchanged_time="$2"
  if [[ -n "${AUTO_EVENTS_LOG:-}" ]] && command -v emit_event >/dev/null 2>&1; then
    emit_event "watchdog_kill" \
      "phase=${EMIT_PHASE_NAME:-unknown}" \
      "pid=${cmd_pid}" \
      "silent_window_sec=${unchanged_time}" \
      "timeout_setting=${WATCHDOG_TIMEOUT}"
  fi
}

_auto_emit_max_silent() {
  local max_sec="$1"
  if [[ -n "${AUTO_EVENTS_LOG:-}" ]] && command -v emit_event >/dev/null 2>&1; then
    emit_event "max_silent_window" \
      "phase=${EMIT_PHASE_NAME:-unknown}" \
      "max_sec=${max_sec}"
  fi
}

_run_with_watchdog() {
  _watchdog_killed=false

  local tmpout
  tmpout=$(mktemp)

  # Run command in background, redirect stdout+stderr to temp file
  "$@" > "$tmpout" 2>&1 &
  local cmd_pid=$!

  # Stream temp file to stdout in real-time
  tail -f "$tmpout" &
  local tail_pid=$!

  # Watchdog loop: check output file size every _CHECK_INTERVAL seconds.
  # Kill the process if size is unchanged for WATCHDOG_TIMEOUT seconds.
  # In OUTPUT_FORMAT_JSON=1 mode, skip file-size check and use process liveness only.
  local last_size=0
  local unchanged_time=0
  local _max_unchanged_time=0
  local _next_heartbeat="${WATCHDOG_HEARTBEAT_INTERVAL}"

  while kill -0 "$cmd_pid" 2>/dev/null; do
    sleep "$_CHECK_INTERVAL"
    if [[ "${OUTPUT_FORMAT_JSON:-}" == "1" ]]; then
      # JSON mode: output arrives all-at-once at the end; skip file-size check
      unchanged_time=$((unchanged_time + _CHECK_INTERVAL))
      if [[ "$unchanged_time" -ge "$_next_heartbeat" ]]; then
        echo "watchdog: still waiting (json mode), silent for ${unchanged_time}s (pid=${cmd_pid})" >&2
        _next_heartbeat=$(( _next_heartbeat + WATCHDOG_HEARTBEAT_INTERVAL ))
      fi
      if (( unchanged_time > _max_unchanged_time )); then _max_unchanged_time=$unchanged_time; fi
      if [[ "$unchanged_time" -ge "$WATCHDOG_TIMEOUT" ]]; then
        echo "" >&2
        echo "watchdog: no output for ${WATCHDOG_TIMEOUT}s, killing process (pid=${cmd_pid})" >&2
        _auto_emit_watchdog_kill "$cmd_pid" "$unchanged_time"
        kill "$cmd_pid" 2>/dev/null
        _watchdog_killed=true
        break
      fi
    else
      local current_size
      current_size=$(wc -c < "$tmpout")
      if [[ "$current_size" -eq "$last_size" ]]; then
        unchanged_time=$((unchanged_time + _CHECK_INTERVAL))
        if (( unchanged_time > _max_unchanged_time )); then _max_unchanged_time=$unchanged_time; fi
        if [[ "$unchanged_time" -ge "$_next_heartbeat" ]]; then
          echo "watchdog: still waiting, silent for ${unchanged_time}s (pid=${cmd_pid})" >&2
          _next_heartbeat=$(( _next_heartbeat + WATCHDOG_HEARTBEAT_INTERVAL ))
        fi
        if [[ "$unchanged_time" -ge "$WATCHDOG_TIMEOUT" ]]; then
          echo "" >&2
          echo "watchdog: no output for ${WATCHDOG_TIMEOUT}s, killing process (pid=${cmd_pid})" >&2
          _auto_emit_watchdog_kill "$cmd_pid" "$unchanged_time"
          kill "$cmd_pid" 2>/dev/null
          _watchdog_killed=true
          break
        fi
      else
        last_size="$current_size"
        unchanged_time=0
        _next_heartbeat="${WATCHDOG_HEARTBEAT_INTERVAL}"
      fi
    fi
  done

  wait "$cmd_pid" 2>/dev/null
  local cmd_exit=$?

  _auto_emit_max_silent "$_max_unchanged_time"

  # Allow tail to flush any remaining buffered output before killing it
  sleep 1
  kill "$tail_pid" 2>/dev/null
  wait "$tail_pid" 2>/dev/null

  rm -f "$tmpout"
  return "$cmd_exit"
}

if [[ $# -eq 0 ]]; then
  echo "Usage: claude-watchdog.sh <command> [args...]" >&2
  exit 1
fi

_run_with_watchdog "$@"
_final_exit=$?

if [[ "$_watchdog_killed" == "true" ]]; then
  echo "watchdog: retrying disabled; please re-run the skill manually" >&2

  # Scan for observation ACs waiting for watchdog-kill event
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -x "${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh" ]]; then
    _watchdog_event_results=$("${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh" --event watchdog-kill 2>/dev/null || true)
    if [[ -n "$_watchdog_event_results" ]] && [[ "$_watchdog_event_results" != "[]" ]]; then
      _matched_count=$(echo "$_watchdog_event_results" | jq 'length' 2>/dev/null || echo 0)
      if [[ "$_matched_count" -gt 0 ]]; then
        _issue_numbers=$(echo "$_watchdog_event_results" | jq -r '.[].number' 2>/dev/null || true)
        if [[ -n "$_issue_numbers" ]]; then
          for _wk_issue in $_issue_numbers; do
            gh issue comment "$_wk_issue" --body "watchdog-kill event observed — condition FAIL (AI judgment not available in shell context; re-run \`/verify ${_wk_issue}\` to update checkbox)" 2>/dev/null || true
          done
        fi
      fi
    fi
  fi
fi

exit "$_final_exit"
