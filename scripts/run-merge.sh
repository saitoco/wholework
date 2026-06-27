#!/bin/bash
# run-merge.sh - Autonomous /merge execution with Sonnet model
# Usage: run-merge.sh <pr-number>

set -euo pipefail
PR_NUMBER="${1:?Usage: run-merge.sh <pr-number>}"

# Validate PR number is numeric
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be numeric: $PR_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
export AUTO_SESSION_ID
source "$SCRIPT_DIR/emit-event.sh"

_maybe_emit_phase_complete() {
  local _exit_code=$?
  [[ "$_exit_code" -ne 0 ]] && return 0
  [[ -z "${AUTO_EVENTS_LOG:-}" ]] && return 0
  [[ -z "${AUTO_SESSION_ID:-}" ]] && return 0
  [[ -z "${EMIT_ISSUE_NUMBER:-}" ]] && return 0
  [[ -z "${EMIT_PHASE_NAME:-}" ]] && return 0
  local _last_event
  _last_event=$(grep "\"session_id\":\"${AUTO_SESSION_ID}\"" "${AUTO_EVENTS_LOG}" 2>/dev/null \
      | jq -rs --argjson n "${EMIT_ISSUE_NUMBER}" \
        '[.[] | select(.issue == $n)] | last // empty | .event // ""' 2>/dev/null || true)
  if [[ "${_last_event}" == "phase_start" ]]; then
    local _ts; _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\n' \
      "{\"ts\":\"${_ts}\",\"issue\":${EMIT_ISSUE_NUMBER},\"event\":\"phase_complete\",\"session_id\":\"${AUTO_SESSION_ID}\",\"phase\":\"${EMIT_PHASE_NAME}\",\"backfilled\":true}" \
      >> "${AUTO_EVENTS_LOG}" 2>/dev/null || true
  fi
}
trap '_maybe_emit_phase_complete' EXIT

_EMIT_PHASE_OWNED=""
if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
  _EMIT_PHASE_OWNED=1
  export EMIT_ISSUE_NUMBER="$PR_NUMBER"
  export EMIT_PHASE_NAME="merge"
  emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
fi

PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode auto 2>/dev/null || echo auto)
if [[ "$PERMISSION_MODE" == "auto" ]]; then
  PERMISSION_FLAG="--permission-mode auto"
  _PERM_LABEL="permission-mode auto (with allow rules template)"
else
  PERMISSION_FLAG="--dangerously-skip-permissions"
  _PERM_LABEL="skip (autonomous mode)"
fi

echo "=== run-merge.sh: Starting /merge for PR #${PR_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "pr" "$PR_NUMBER" "merge"
echo "Model: sonnet"
echo "Effort: low"
echo "Permissions: ${_PERM_LABEL}"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Wait for CI checks to complete before running claude
"$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER"

# See modules/orchestration-fallbacks.md#baseline-failure
# Baseline pre-merge gate: distinguish pre-existing vs new FAILURE before merge
set +e; "$SCRIPT_DIR/pre-merge-check.sh" "$PR_NUMBER"; PRE_MERGE_CHECK_EXIT=$?; set -e
if [[ "$PRE_MERGE_CHECK_EXIT" -eq 2 ]]; then
  echo "Error: pre-merge-check.sh detected a new FAILURE (not pre-existing on base branch). Fix the issue and retry merge." >&2
  exit 1
elif [[ "$PRE_MERGE_CHECK_EXIT" -ne 0 ]]; then
  echo "Warning: pre-merge-check.sh could not complete (exit ${PRE_MERGE_CHECK_EXIT}); proceeding (fail-open)." >&2
fi

# Pass SKILL.md body directly as prompt (same pattern as run-review.sh)
# /merge has no context: fork, but uses the same approach for consistency
# See: #284 (context: fork permission non-propagation issue)
SKILL_FILE="${SCRIPT_DIR}/../skills/merge/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "Error: SKILL.md not found: $SKILL_FILE" >&2
  exit 1
fi

# Strip frontmatter (---...---) and extract body
FRONTMATTER_END=$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_FILE")
if [[ -z "$FRONTMATTER_END" ]]; then
  echo "Error: SKILL.md frontmatter not found" >&2
  exit 1
fi
SKILL_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$SKILL_FILE")
source "$SCRIPT_DIR/guard-prefix.sh"

PROMPT="${GUARD_PREFIX}

${SKILL_BODY}

ARGUMENTS: ${PR_NUMBER} --non-interactive"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
load_watchdog_timeout "$SCRIPT_DIR" "merge"

SECONDS=0
set +e
if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
  TOKEN_USAGE_FILE=".tmp/token-usage-${PR_NUMBER}.json"
  mkdir -p .tmp
  ANTHROPIC_MODEL=sonnet \
    WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
    OUTPUT_FORMAT_JSON=1 \
    env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
      --model sonnet \
      --effort low \
      --output-format json \
      $PERMISSION_FLAG \
      > "$TOKEN_USAGE_FILE"
  EXIT_CODE=$?
  jq -r '.result // empty' "$TOKEN_USAGE_FILE" 2>/dev/null || true
else
  ANTHROPIC_MODEL=sonnet \
    WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
    env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
      --model sonnet \
      --effort low \
      $PERMISSION_FLAG
  EXIT_CODE=$?
fi
set -e
"$SCRIPT_DIR/handle-permission-mode-failure.sh" "$EXIT_CODE" "$SECONDS" "$PERMISSION_MODE"

_MERGE_ISSUE=$("$SCRIPT_DIR/gh-extract-issue-from-pr.sh" "$PR_NUMBER" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue_number',''))" 2>/dev/null || echo "")

if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then
  if [[ -n "$_MERGE_ISSUE" ]]; then
    _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" merge "$_MERGE_ISSUE" --pr "$PR_NUMBER" --check-completion 2>/dev/null) || true
    if [[ $EXIT_CODE -eq 143 ]]; then
      if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
        EXIT_CODE=0
      fi
    elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
      echo "Warning: claude exited 0 but merge phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
      EXIT_CODE=1
    fi
    if [[ $EXIT_CODE -eq 0 ]]; then
      _issue_labels=$(gh issue view "$_MERGE_ISSUE" --json labels -q '[.labels[].name]' 2>/dev/null || echo "")
      if echo "$_issue_labels" | grep -q '"phase/review"' && ! echo "$_issue_labels" | grep -q '"phase/verify"'; then
        echo "Warning: merge completed but phase label still at phase/review. Auto-transitioning to phase/verify." >&2
        "$SCRIPT_DIR/gh-label-transition.sh" "$_MERGE_ISSUE" verify || true
      fi
    fi
  else
    echo "reconcile-phase-state: could not extract issue number from PR #${PR_NUMBER}, skipping reconcile" >&2
    # Fallback: check PR state directly when issue extraction fails
    if [[ $EXIT_CODE -eq 0 ]]; then
      PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state 2>/dev/null || echo "")
      if [[ -n "$PR_STATE" && "$PR_STATE" != "MERGED" ]]; then
        echo "Warning: PR #${PR_NUMBER} state is '${PR_STATE}', not MERGED. Merge may have failed." >&2
        EXIT_CODE=1
      fi
    fi
  fi
fi

# CI test_result emit (pr route, EXIT_CODE=0 + AUTO_EVENTS_LOG set)
if [[ $EXIT_CODE -eq 0 && -n "${AUTO_EVENTS_LOG:-}" ]]; then
  _branch=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' 2>/dev/null || true)
  _run_id=""
  if [[ -n "$_branch" ]]; then
    _run_id=$(gh run list --workflow=test.yml --branch="$_branch" --status=success --limit=1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
  fi
  if [[ -n "$_run_id" ]]; then
    _log=$(gh run view "$_run_id" --log 2>/dev/null || true)
    _total=$(echo "$_log" | grep -oE "1\.\.[0-9]+" | grep -oE "[0-9]+$" | head -1 || echo 0)
    _failed=$(echo "$_log" | grep -c "not ok ") || _failed=0
    if [[ "${_total:-0}" -gt 0 ]]; then
      _passed=$((_total - _failed))
      emit_event "test_result" "phase=merge" "framework=bats" "source=ci" "passed=${_passed}" "failed=${_failed}" "run_id=${_run_id}"
    else
      echo "Warning: run-merge.sh: gh run view ${_run_id} --log: TAP plan line (1..N) not found" >&2
    fi
  fi
fi

if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
  emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
fi

echo "---"
echo "=== run-merge.sh: Finished /merge for PR #${PR_NUMBER} ==="
print_end_banner "pr" "$PR_NUMBER" "merge"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
