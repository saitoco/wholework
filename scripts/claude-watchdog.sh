#!/bin/bash
# claude-watchdog.sh - Watchdog wrapper for claude -p invocations
# Detects hangs (no output for WATCHDOG_TIMEOUT seconds) and kills + retries once.
# Usage: claude-watchdog.sh <command> [args...]
#
# Environment variables:
#   WATCHDOG_TIMEOUT             - Seconds of no output before killing the process (default: 1800)
#   WATCHDOG_HEARTBEAT_INTERVAL  - Seconds between heartbeat messages during silence (default: 60)

set -uo pipefail

WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-1800}"
WATCHDOG_HEARTBEAT_INTERVAL="${WATCHDOG_HEARTBEAT_INTERVAL:-60}"
# Check interval is min(WATCHDOG_TIMEOUT, 10) to keep tests fast with small timeouts
_CHECK_INTERVAL=$(( WATCHDOG_TIMEOUT < 10 ? WATCHDOG_TIMEOUT : 10 ))

# Global flag: set to true when watchdog triggers a kill (used to decide retry)
_watchdog_killed=false

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
  local last_size=0
  local unchanged_time=0
  local _next_heartbeat="${WATCHDOG_HEARTBEAT_INTERVAL}"

  while kill -0 "$cmd_pid" 2>/dev/null; do
    sleep "$_CHECK_INTERVAL"
    local current_size
    current_size=$(wc -c < "$tmpout")
    if [[ "$current_size" -eq "$last_size" ]]; then
      unchanged_time=$((unchanged_time + _CHECK_INTERVAL))
      if [[ "$unchanged_time" -ge "$_next_heartbeat" ]]; then
        echo "watchdog: still waiting, silent for ${unchanged_time}s (pid=${cmd_pid})" >&2
        _next_heartbeat=$(( _next_heartbeat + WATCHDOG_HEARTBEAT_INTERVAL ))
      fi
      if [[ "$unchanged_time" -ge "$WATCHDOG_TIMEOUT" ]]; then
        echo "" >&2
        echo "watchdog: no output for ${WATCHDOG_TIMEOUT}s, killing process (pid=${cmd_pid})" >&2
        kill "$cmd_pid" 2>/dev/null
        _watchdog_killed=true
        break
      fi
    else
      last_size="$current_size"
      unchanged_time=0
      _next_heartbeat="${WATCHDOG_HEARTBEAT_INTERVAL}"
    fi
  done

  wait "$cmd_pid" 2>/dev/null
  local cmd_exit=$?

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

# Run with 1 retry on watchdog-triggered kill
_run_with_watchdog "$@"
_final_exit=$?

if [[ "$_watchdog_killed" == "true" ]]; then
  echo "watchdog: retrying once..." >&2
  # retry
  _run_with_watchdog "$@"
  _final_exit=$?
fi

exit "$_final_exit"
