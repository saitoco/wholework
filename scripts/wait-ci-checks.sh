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
if [[ "$_emit_ci_wait" == "true" ]]; then
  _ci_checks_output=""
  if command -v timeout >/dev/null 2>&1; then
      _ci_checks_output=$(timeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 2>&1 || true)
  elif command -v gtimeout >/dev/null 2>&1; then
      _ci_checks_output=$(gtimeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 2>&1 || true)
  else
      _ci_checks_output=$(gh pr checks "$PR_NUMBER" --watch --interval 60 2>&1 || true)
  fi
  _ci_wait_end=$(date +%s)
  _wait_sec=$(( _ci_wait_end - _ci_wait_start ))
  _passed=$(echo "${_ci_checks_output:-}" | grep -c -i "pass\|success" 2>/dev/null || echo 0)
  _failed=$(echo "${_ci_checks_output:-}" | grep -c -i "fail\|error" 2>/dev/null || echo 0)
  emit_event "ci_wait" \
    "phase=${EMIT_PHASE_NAME:-review}" \
    "wait_sec=${_wait_sec}" \
    "checks_passed=${_passed}" \
    "checks_failed=${_failed}"
else
  if command -v timeout >/dev/null 2>&1; then
      timeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 || true
  elif command -v gtimeout >/dev/null 2>&1; then
      gtimeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 || true
  else
      gh pr checks "$PR_NUMBER" --watch --interval 60 || true
  fi
fi

echo "CI check wait complete for PR #${PR_NUMBER}" >&2
