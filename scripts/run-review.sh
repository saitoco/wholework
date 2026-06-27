#!/bin/bash
# run-review.sh - Autonomous /review execution with Sonnet model
# Usage: run-review.sh <pr-number> [--review-only] [--light | --full]

set -euo pipefail
PR_NUMBER="${1:?Usage: run-review.sh <pr-number>}"
shift
EXTRA_ARGS="$*"

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
  export EMIT_PHASE_NAME="review"
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

echo "=== run-review.sh: Starting /review for PR #${PR_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "pr" "$PR_NUMBER" "review"
echo "Model: sonnet"
echo "Effort: high"
echo "Permissions: ${_PERM_LABEL}"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Wait for CI checks to complete before running claude
"$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER"

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
# /review has context: fork, so calling it via claude -p "/review N" prevents
# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)
# By passing SKILL.md body directly, we bypass frontmatter interpretation
SKILL_FILE="${SCRIPT_DIR}/../skills/review/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "Error: SKILL.md not found: $SKILL_FILE" >&2
  exit 1
fi

# Strip frontmatter (---...---) and extract body
# Detect the first --- after line 1 and take everything from the next line onward
FRONTMATTER_END=$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_FILE")
if [[ -z "$FRONTMATTER_END" ]]; then
  echo "Error: SKILL.md frontmatter not found" >&2
  exit 1
fi
SKILL_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$SKILL_FILE")
ARGUMENTS="${PR_NUMBER}"
if [[ -n "$EXTRA_ARGS" ]]; then
  ARGUMENTS="${ARGUMENTS} ${EXTRA_ARGS}"
fi
ARGUMENTS="${ARGUMENTS} --non-interactive"
source "$SCRIPT_DIR/guard-prefix.sh"

PROMPT="${GUARD_PREFIX}

${SKILL_BODY}

ARGUMENTS: ${ARGUMENTS}"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
load_watchdog_timeout "$SCRIPT_DIR" "review"

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
      --effort high \
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
      --effort high \
      $PERMISSION_FLAG
  EXIT_CODE=$?
fi
set -e
"$SCRIPT_DIR/handle-permission-mode-failure.sh" "$EXIT_CODE" "$SECONDS" "$PERMISSION_MODE"

_REVIEW_ISSUE=$("$SCRIPT_DIR/gh-extract-issue-from-pr.sh" "$PR_NUMBER" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue_number',''))" 2>/dev/null || echo "")

if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then
  if [[ -n "$_REVIEW_ISSUE" ]]; then
    _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" review "$_REVIEW_ISSUE" --pr "$PR_NUMBER" --check-completion 2>/dev/null) || true
    if [[ $EXIT_CODE -eq 143 ]]; then
      if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
        EXIT_CODE=0
      else
        echo "reconcile-phase-state result: $_reconcile_out"
      fi
    elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
      echo "Warning: claude exited 0 but review phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
      EXIT_CODE=1
    fi
  else
    echo "reconcile-phase-state: could not extract issue number from PR #${PR_NUMBER}, skipping reconcile" >&2
  fi
fi

if [[ $EXIT_CODE -eq 0 ]]; then
  "$SCRIPT_DIR/append-loop-state-heartbeat.sh" --issue "$PR_NUMBER" --from code --to review >/dev/null 2>&1 || true
fi

if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
  emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
fi

echo "---"
echo "=== run-review.sh: Finished /review for PR #${PR_NUMBER} ==="
print_end_banner "pr" "$PR_NUMBER" "review"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
