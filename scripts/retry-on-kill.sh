#!/bin/bash
# sourceable helper — do not execute directly
# bash 3.2+ compatible: no associative arrays, no mapfile

# Default early-kill window in seconds.
# All production phase WATCHDOG_TIMEOUT defaults (see watchdog-defaults.sh) are >= 600s,
# so only external/OOM kills (typically < 300s) trigger retry; watchdog hang-kills do not.
RETRY_ON_KILL_MAX_SEC_DEFAULT=300

# run_with_retry_on_kill <command> [args...]
# Execute command; if killed early (SIGTERM=143 or SIGKILL=137) within the early-kill window,
# retry once. Sets _RETRY_ON_KILL_FIRED=true when retry is attempted.
# See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
#
# Branch A — non-kill exit:  exit code not 137 or 143 → return as-is, no retry
# Branch B — early kill:     exit code 137/143 AND elapsed < max_sec → retry once
# Branch C — late kill:      exit code 137/143 AND elapsed >= max_sec → return as-is (watchdog hang-kill)
# Branch D — retry also kill: Branch B retry also exits 137/143 → log and escalate
run_with_retry_on_kill() {
  _RETRY_ON_KILL_FIRED=false
  local _max_sec _start _end _elapsed _exit
  _max_sec="${WHOLEWORK_RETRY_ON_KILL_MAX_SEC:-$RETRY_ON_KILL_MAX_SEC_DEFAULT}"
  _start=$(date +%s)
  _exit=0
  "$@" || _exit=$?
  # Branch A: non-kill exit (includes 0)
  if [[ $_exit -ne 137 && $_exit -ne 143 ]]; then
    return $_exit
  fi
  _end=$(date +%s)
  _elapsed=$(( _end - _start ))
  # Branch C: late kill — watchdog hang-kill (elapsed >= early-kill window), no retry
  if [[ $_elapsed -ge $_max_sec ]]; then
    return $_exit
  fi
  # Branch B: early kill — retry once
  echo "retry-on-kill: command killed (exit ${_exit}) after ${_elapsed}s (< ${_max_sec}s); auto-retrying once" >&2
  _RETRY_ON_KILL_FIRED=true
  _exit=0
  "$@" || _exit=$?
  # Branch D: retry also killed — escalate to recovery/manual
  if [[ $_exit -eq 137 || $_exit -eq 143 ]]; then
    echo "retry-on-kill: retry also killed (exit ${_exit}); escalating to recovery/manual" >&2
  fi
  return $_exit
}
