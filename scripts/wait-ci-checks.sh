#!/bin/bash
# wait-ci-checks.sh - Wait for CI checks to complete on a PR
# Usage: ./scripts/wait-ci-checks.sh <pr-number>
#
# Environment variables:
#   WHOLEWORK_CI_TIMEOUT_SEC:         Maximum wait time in seconds (default: 1200)
#   WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC: Grace period in seconds during which the script keeps
#                                      polling when gh pr checks reports zero registered checks
#                                      (default: 120)
#   AUTO_EVENTS_LOG:          Path to auto-events.jsonl (emit ci_wait event when set)
#   EMIT_ISSUE_NUMBER:        Issue number for event emission
#   EMIT_PHASE_NAME:          Phase name for event emission
set -euo pipefail
PR_NUMBER="${1:?Usage: wait-ci-checks.sh <pr-number>}"
TIMEOUT_SEC="${WHOLEWORK_CI_TIMEOUT_SEC:-1200}"
MIN_CHECKS_WAIT_SEC="${WHOLEWORK_CI_MIN_CHECKS_WAIT_SEC:-120}"

_emit_ci_wait=false
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
if [[ -n "${AUTO_EVENTS_LOG:-}" ]] && [[ -f "$SCRIPT_DIR/emit-event.sh" ]]; then
  source "$SCRIPT_DIR/emit-event.sh"
  _emit_ci_wait=true
  _ci_wait_start=$(date +%s)
fi

echo "Waiting for CI checks on PR #${PR_NUMBER} (timeout: ${TIMEOUT_SEC}s)..." >&2

_ci_checks_output=""
_zero_checks_seen=false
_poll_err_file=$(mktemp)
# Keep the cleanup non-fatal: under `set -e` a failing EXIT trap overwrites the
# script's exit status, and `rm` is not guaranteed to resolve when the caller has
# restricted PATH. A leftover temp file is preferable to a bogus exit code.
trap 'rm -f "$_poll_err_file" 2>/dev/null || true' EXIT
_poll_start=$(date +%s)
while true; do
  _elapsed=$(( $(date +%s) - _poll_start ))
  if [[ "$_elapsed" -ge "$TIMEOUT_SEC" ]]; then
    echo "CI check wait timed out after ${TIMEOUT_SEC}s for PR #${PR_NUMBER}" >&2
    break
  fi
  _poll_result=""
  : > "$_poll_err_file"
  if command -v timeout >/dev/null 2>&1; then
    _poll_result=$(timeout --kill-after=10 30 gh pr checks "$PR_NUMBER" --json name,state,bucket 2>"$_poll_err_file") || true
  elif command -v gtimeout >/dev/null 2>&1; then
    _poll_result=$(gtimeout 30 gh pr checks "$PR_NUMBER" --json name,state,bucket 2>"$_poll_err_file") || true
  else
    _poll_result=$(gh pr checks "$PR_NUMBER" --json name,state,bucket 2>"$_poll_err_file") || true
  fi
  # Real `gh` prints nothing to stdout for a PR with zero registered checks (it
  # exits non-zero with "no checks reported on the '<branch>' branch" on stderr
  # instead of `[]`), so treat that message as the zero-checks case explicitly.
  if [[ -z "$_poll_result" ]] && grep -q "no checks reported" "$_poll_err_file" 2>/dev/null; then
    _poll_result="[]"
  fi
  if [[ -n "$_poll_result" ]]; then
    _ci_checks_output="$_poll_result"
    _total=$(echo "$_poll_result" | jq 'length' 2>/dev/null || echo "-1")
    if [[ "$_total" -eq 0 ]]; then
      if [[ "$_elapsed" -lt "$MIN_CHECKS_WAIT_SEC" ]]; then
        echo "No CI checks registered yet on PR #${PR_NUMBER}; waiting (grace period ${MIN_CHECKS_WAIT_SEC}s)..." >&2
        sleep 60
        continue
      fi
      _zero_checks_seen=true
      echo "Warning: no CI checks registered on PR #${PR_NUMBER} after ${MIN_CHECKS_WAIT_SEC}s grace period; proceeding without CI confirmation" >&2
      break
    elif [[ "$_total" -gt 0 ]]; then
      _pending=$(echo "$_poll_result" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || echo "1")
      if [[ "$_pending" -eq 0 ]]; then
        break
      fi
      echo "CI checks pending: ${_pending} of ${_total} check(s) not yet complete..." >&2
    else
      echo "CI checks status unknown (failed to parse check count); continuing to wait..." >&2
    fi
  fi
  sleep 60
done

_total_final=$(echo "${_ci_checks_output:-[]}" | jq 'length' 2>/dev/null || echo "0")
_total_final=${_total_final:-0}
_passed=$(echo "${_ci_checks_output:-[]}" | jq '[.[] | select(.bucket == "pass")] | length' 2>/dev/null || echo "0")
_passed=${_passed:-0}
_failed=$(echo "${_ci_checks_output:-[]}" | jq '[.[] | select(.bucket == "fail")] | length' 2>/dev/null || echo "0")
_failed=${_failed:-0}
_pending_final=$(echo "${_ci_checks_output:-[]}" | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || echo "0")
_pending_final=${_pending_final:-0}
_cancelled=$(echo "${_ci_checks_output:-[]}" | jq '[.[] | select(.bucket == "cancel")] | length' 2>/dev/null || echo "0")
_cancelled=${_cancelled:-0}

if [[ "$_emit_ci_wait" == "true" ]]; then
  _ci_wait_end=$(date +%s)
  _wait_sec=$(( _ci_wait_end - _ci_wait_start ))
  emit_event "ci_wait" \
    "phase=${EMIT_PHASE_NAME:-review}" \
    "wait_sec=${_wait_sec}" \
    "checks_passed=${_passed}" \
    "checks_failed=${_failed}"
fi

echo "CI check wait complete for PR #${PR_NUMBER}" >&2
echo "ci_result: total=${_total_final} passed=${_passed} failed=${_failed} pending=${_pending_final} cancelled=${_cancelled} zero_checks=${_zero_checks_seen}"
