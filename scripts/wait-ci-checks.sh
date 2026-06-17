#!/bin/bash
# wait-ci-checks.sh - Wait for CI checks to complete on a PR
# Usage: ./scripts/wait-ci-checks.sh <pr-number>
#
# Environment variables:
#   WHOLEWORK_CI_TIMEOUT_SEC: Maximum wait time in seconds (default: 1200)
#   AUTO_EVENTS_LOG:          Path to auto-events.jsonl (emit ci_wait event when set)
#   EMIT_ISSUE_NUMBER:        Issue number for event emission
#   EMIT_PHASE_NAME:          Phase name for event emission
set -euo pipefail
PR_NUMBER="${1:?Usage: wait-ci-checks.sh <pr-number>}"
TIMEOUT_SEC="${WHOLEWORK_CI_TIMEOUT_SEC:-1200}"

_emit_ci_wait=false
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
if [[ -n "${AUTO_EVENTS_LOG:-}" ]] && [[ -f "$SCRIPT_DIR/emit-event.sh" ]]; then
  source "$SCRIPT_DIR/emit-event.sh"
  _emit_ci_wait=true
  _ci_wait_start=$(date +%s)
fi

echo "Waiting for CI checks on PR #${PR_NUMBER} (timeout: ${TIMEOUT_SEC}s)..." >&2

_ci_checks_output=""
_poll_start=$(date +%s)
while true; do
  _elapsed=$(( $(date +%s) - _poll_start ))
  if [[ "$_elapsed" -ge "$TIMEOUT_SEC" ]]; then
    echo "CI check wait timed out after ${TIMEOUT_SEC}s for PR #${PR_NUMBER}" >&2
    break
  fi
  _poll_result=""
  if command -v timeout >/dev/null 2>&1; then
    _poll_result=$(timeout --kill-after=10 30 gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null) || true
  elif command -v gtimeout >/dev/null 2>&1; then
    _poll_result=$(gtimeout 30 gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null) || true
  else
    _poll_result=$(gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null) || true
  fi
  if [[ -n "$_poll_result" ]]; then
    _ci_checks_output="$_poll_result"
    _in_progress=$(echo "$_poll_result" | jq '[.[] | select(.state == "IN_PROGRESS")] | length' 2>/dev/null || echo "1")
    if [[ "$_in_progress" -eq 0 ]]; then
      break
    fi
    echo "CI checks in progress: ${_in_progress} check(s) still running..." >&2
  fi
  sleep 60
done

if [[ "$_emit_ci_wait" == "true" ]]; then
  _ci_wait_end=$(date +%s)
  _wait_sec=$(( _ci_wait_end - _ci_wait_start ))
  _passed=$(echo "${_ci_checks_output:-}" | jq '[.[] | select(.state == "SUCCESS")] | length' 2>/dev/null || echo "0")
  _passed=${_passed:-0}
  _failed=$(echo "${_ci_checks_output:-}" | jq '[.[] | select(.state == "FAILURE")] | length' 2>/dev/null || echo "0")
  _failed=${_failed:-0}
  emit_event "ci_wait" \
    "phase=${EMIT_PHASE_NAME:-review}" \
    "wait_sec=${_wait_sec}" \
    "checks_passed=${_passed}" \
    "checks_failed=${_failed}"
fi

echo "CI check wait complete for PR #${PR_NUMBER}" >&2
