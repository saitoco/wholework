#!/bin/bash
# run-code.sh - Autonomous /code execution with Sonnet model
# Usage: run-code.sh <issue-number> [--patch|--pr] [--base <branch>]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-code.sh <issue-number> [--patch|--pr] [--base <branch>]}"
shift
# Save trailing args before parsing loop so exec re-invocation can pass them unchanged
_TRAILING_ARGS=("$@")

# Parse options
ROUTE_FLAG=""
BASE_FLAG=""
BASE_BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch|--pr)
      if [[ -n "$ROUTE_FLAG" ]]; then
        echo "Error: --patch and --pr cannot be specified together" >&2
        exit 1
      fi
      ROUTE_FLAG="$1"
      shift
      ;;
    --base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --base requires a branch name" >&2
        exit 1
      fi
      BASE_BRANCH="$2"
      BASE_FLAG="--base $2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-code.sh <issue-number> [--patch|--pr] [--base <branch>]" >&2
      exit 1
      ;;
  esac
done

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $ISSUE_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
# Session isolation check: detect other-session dirty files (best-effort)
if [[ -x "${SCRIPT_DIR}/check-verify-dirty.sh" ]]; then
  _dirty_exit=0
  bash "${SCRIPT_DIR}/check-verify-dirty.sh" "${ISSUE_NUMBER}" || _dirty_exit=$?
  case "${_dirty_exit}" in
    0) ;;
    1)
      echo "Error: parent main has uncommitted changes. Resolve before proceeding." >&2
      exit 1
      ;;
    2)
      echo "Warning: detected other-session dirty files. Proceeding (best-effort)." >&2
      ;;
  esac
fi
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
# Primary: PGID-based file written by SKILL.md Step 1 (Issue #770/PR #793).
# Fallback: auto-session-current for cases where PGID does not match (e.g., PGID
# mismatch between Bash tool call contexts). As of PR #793 SKILL.md writes only the
# PGID file; the auto-session-current fallback is defensive dead code unless a future
# code path restores writes to that file (Issue #791 iteration B).
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || cat ".tmp/auto-session-current" 2>/dev/null || echo '')}"
export AUTO_SESSION_ID
source "$SCRIPT_DIR/emit-event.sh"

_maybe_emit_phase_complete() {
  local _exit_code=$?
  [[ "$_exit_code" -ne 0 && "$_exit_code" -ne 143 ]] && return 0
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
  export EMIT_ISSUE_NUMBER="$ISSUE_NUMBER"
  if [[ "$ROUTE_FLAG" == "--pr" ]]; then
    export EMIT_PHASE_NAME="code-pr"
  elif [[ "$ROUTE_FLAG" == "--patch" ]]; then
    export EMIT_PHASE_NAME="code-patch"
  else
    export EMIT_PHASE_NAME="code"
  fi
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

AUTONOMY_TIER=$("$SCRIPT_DIR/get-config-value.sh" autonomy L1 2>/dev/null || echo L1)
_REPO_ROOT="$(dirname "$SCRIPT_DIR")"
_WW_YML="${_REPO_ROOT}/.wholework.yml"
AUTO_RETRY_ENABLED="false"
AUTO_RETRY_MAX_ITERATIONS=3
if [[ -f "$_WW_YML" ]]; then
  _raw_enabled=$(awk '/^auto-retry-on-fail:/{f=1; next} f && /^[[:space:]]+enabled:/{gsub(/.*enabled:[[:space:]]*/,""); gsub(/[[:space:]].*/,""); print; exit} /^[^[:space:]]/{f=0}' "$_WW_YML" | tr -d ' ')
  [[ "$_raw_enabled" == "true" ]] && AUTO_RETRY_ENABLED="true"
  _raw_max=$(awk '/^auto-retry-on-fail:/{f=1; next} f && /^[[:space:]]+(max_iterations|threshold):/{gsub(/.*:[[:space:]]*/,""); gsub(/[[:space:]].*/,""); print; exit} /^[^[:space:]]/{f=0}' "$_WW_YML" | tr -d ' ')
  if [[ -n "$_raw_max" && "$_raw_max" =~ ^[0-9]+$ && "$_raw_max" -gt 0 ]]; then
    AUTO_RETRY_MAX_ITERATIONS="$_raw_max"
  fi
fi
CODE_RETRY_COUNT=${CODE_RETRY_COUNT:-0}
export CODE_RETRY_COUNT

echo "=== run-code.sh: Starting /code for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "code"
echo "Model: sonnet"
echo "Effort: high"
echo "Permissions: ${_PERM_LABEL}"
if [[ "$ROUTE_FLAG" == "--patch" ]]; then
  echo "Route: patch (${BASE_BRANCH:-main} direct commit)"
elif [[ "$ROUTE_FLAG" == "--pr" ]]; then
  echo "Route: pr (branch + PR)"
fi
if [[ -n "$BASE_BRANCH" ]]; then
  echo "Base branch: ${BASE_BRANCH}"
fi
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Idempotency guard: skip if open PR already exists for this issue
if [[ "$ROUTE_FLAG" == "--pr" ]]; then
  EXISTING_PR=$(gh pr list --state open --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${ISSUE_NUMBER}\") | .number" | head -1 || true)
  if [[ -n "$EXISTING_PR" ]]; then
    echo "=== run-code.sh: Existing PR #${EXISTING_PR} detected for issue #${ISSUE_NUMBER}, skipping /code ==="
    echo "PR: $(gh pr view ${EXISTING_PR} --json url -q '.url')"
    print_end_banner "issue" "$ISSUE_NUMBER" "code"
    echo "Next actions:"
    echo "  - /review ${EXISTING_PR}"
    echo "  - /auto ${ISSUE_NUMBER}"
    exit 0
  fi
fi

# Cleanup stale worktrees/branches from previous failed runs
WORKTREE_PATH="${SCRIPT_DIR}/../.claude/worktrees/code+issue-${ISSUE_NUMBER}"
WORKTREE_BRANCH="worktree-code+issue-${ISSUE_NUMBER}"
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "run-code.sh: stale worktree detected, cleaning up: $WORKTREE_PATH"
  git worktree remove --force "$WORKTREE_PATH" 2>/dev/null \
    || echo "Warning: Failed to remove stale worktree: $WORKTREE_PATH"
fi
if git branch --list "$WORKTREE_BRANCH" 2>/dev/null | grep -q .; then
  echo "run-code.sh: stale branch detected, cleaning up: $WORKTREE_BRANCH"
  git branch -D "$WORKTREE_BRANCH" 2>/dev/null \
    || echo "Warning: Failed to delete stale branch: $WORKTREE_BRANCH"
fi

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
# /code has context: fork, so calling it via claude -p "/code N" prevents
# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)
# By passing SKILL.md body directly, we bypass frontmatter interpretation
SKILL_FILE="${SCRIPT_DIR}/../skills/code/SKILL.md"

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

# Include route flag and base flag in ARGUMENTS
EXTRA_FLAGS=""
if [[ -n "$ROUTE_FLAG" ]]; then
  EXTRA_FLAGS="${EXTRA_FLAGS} ${ROUTE_FLAG}"
fi
if [[ -n "$BASE_FLAG" ]]; then
  EXTRA_FLAGS="${EXTRA_FLAGS} ${BASE_FLAG}"
fi

source "$SCRIPT_DIR/guard-prefix.sh"
source "$SCRIPT_DIR/retry-on-kill.sh"

if [[ -n "$EXTRA_FLAGS" ]]; then
  PROMPT="${GUARD_PREFIX}

${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER}${EXTRA_FLAGS} --non-interactive"
else
  PROMPT="${GUARD_PREFIX}

${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"
fi

# Pre-count: capture ## Consumed Comments section count before claude runs.
# Used by post-processor fallback to detect when LLM silently skipped writeback.
_SPEC_DIR=$(WHOLEWORK_CONFIG_PATH="$(dirname "$SCRIPT_DIR")/.wholework.yml" \
  "$SCRIPT_DIR/get-config-value.sh" spec-path docs/spec 2>/dev/null || echo "docs/spec")
_SPEC_FILE_PRE=$(ls "$(dirname "$SCRIPT_DIR")/$_SPEC_DIR/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1 || true)
_PRE_COUNT=$(grep -c "^## Consumed Comments" "${_SPEC_FILE_PRE:-/dev/null}" 2>/dev/null || true)
_PRE_COUNT="${_PRE_COUNT:-0}"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
load_watchdog_timeout "$SCRIPT_DIR" "code"

_emit_comments_consumed "$ISSUE_NUMBER" "code" || true

_PRE_HEAD=$(git rev-parse HEAD 2>/dev/null || true)
SECONDS=0
set +e
if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
  TOKEN_USAGE_FILE=".tmp/token-usage-${ISSUE_NUMBER}.json"
  mkdir -p .tmp
  # See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
  run_with_retry_on_kill env -u CLAUDECODE ANTHROPIC_MODEL=sonnet \
    WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
    OUTPUT_FORMAT_JSON=1 \
    "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
      --model sonnet \
      --effort high \
      --output-format json \
      --plugin-dir "$(dirname "$SCRIPT_DIR")" \
      $PERMISSION_FLAG \
      > "$TOKEN_USAGE_FILE"
  EXIT_CODE=$?
  jq -r '.result // empty' "$TOKEN_USAGE_FILE" 2>/dev/null || true
else
  # See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
  run_with_retry_on_kill env -u CLAUDECODE ANTHROPIC_MODEL=sonnet \
    WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
    "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
      --model sonnet \
      --effort high \
      --plugin-dir "$(dirname "$SCRIPT_DIR")" \
      $PERMISSION_FLAG
  EXIT_CODE=$?
fi
set -e
"$SCRIPT_DIR/handle-permission-mode-failure.sh" "$EXIT_CODE" "$SECONDS" "$PERMISSION_MODE"

if [[ "$ROUTE_FLAG" == "--patch" ]]; then
  _RECONCILE_PHASE="code-patch"
else
  _RECONCILE_PHASE="code-pr"
fi

if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then
  _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" "$_RECONCILE_PHASE" "$ISSUE_NUMBER" --check-completion 2>/dev/null) || true
  echo "reconcile-phase-state result: $_reconcile_out"
  if [[ $EXIT_CODE -eq 143 ]]; then
    if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
      EXIT_CODE=0
    fi
  elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
    echo "Warning: claude exited 0 but $_RECONCILE_PHASE phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
    if [[ ( "$AUTONOMY_TIER" == "L2" || "$AUTONOMY_TIER" == "L3" ) ]] && \
       [[ "$AUTO_RETRY_ENABLED" == "true" ]] && \
       [[ "$CODE_RETRY_COUNT" -lt "$AUTO_RETRY_MAX_ITERATIONS" ]]; then
      CODE_RETRY_COUNT=$(( CODE_RETRY_COUNT + 1 ))
      export CODE_RETRY_COUNT
      echo "auto-retry: code phase silent no-op, retry ${CODE_RETRY_COUNT}/${AUTO_RETRY_MAX_ITERATIONS}" >&2
      if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
        EMIT_ISSUE_NUMBER="$ISSUE_NUMBER" emit_event "code_retry_fire" \
          "iteration=${CODE_RETRY_COUNT}" \
          "trigger_reason=silent_no_op"
      fi
      # auto-retry preflight: stash parent-main untracked files (except in-progress
      # docs/sessions/** from other concurrent sessions) so a silent no-op's stray
      # file does not block check-verify-dirty.sh on the retry re-invocation.
      _STRAY_UNTRACKED=$(git ls-files --others --exclude-standard -- ':!docs/sessions/**' 2>/dev/null | head -5)
      if [[ -n "$_STRAY_UNTRACKED" ]]; then
        echo "auto-retry preflight: stashing parent-main untracked files: $_STRAY_UNTRACKED" >&2
        git stash push --include-untracked -m "auto-retry preflight for #$ISSUE_NUMBER" -- ':!docs/sessions/**' 2>/dev/null || true
      fi
      exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"
    else
      if [[ ( "$AUTONOMY_TIER" == "L2" || "$AUTONOMY_TIER" == "L3" ) ]] && \
         [[ "$AUTO_RETRY_ENABLED" == "true" ]]; then
        echo "auto-retry: max iterations reached (${CODE_RETRY_COUNT}/${AUTO_RETRY_MAX_ITERATIONS}). Manual intervention required." >&2
      fi
      EXIT_CODE=1
    fi
  fi
fi

# See modules/orchestration-fallbacks.md#code-base-conflict
if [[ "$ROUTE_FLAG" == "--pr" && $EXIT_CODE -eq 0 ]]; then
  _PR_NUM=$(echo "$_reconcile_out" | jq -r '.actual.pr_number // empty' 2>/dev/null || true)
  if [[ -n "$_PR_NUM" && "$_PR_NUM" =~ ^[0-9]+$ ]]; then
    _merge_status=$("$SCRIPT_DIR/gh-pr-merge-status.sh" "$_PR_NUM" 2>/dev/null || true)
    if echo "$_merge_status" | grep -q '"reason"[[:space:]]*:[[:space:]]*"conflicts"'; then
      echo "Warning: code phase completed but PR #${_PR_NUM} has conflicts with base." >&2
      echo "This is likely due to a concurrent merge on the base branch during code phase." >&2
      echo "PR diff (merge-base based) shows only this Issue's changes correctly -- do not mistake this for contamination." >&2
      echo "Recommended: resolve conflicts before /merge. See modules/orchestration-fallbacks.md#code-base-conflict for the recovery procedure." >&2
    fi
  fi
fi

# bash-level post-execution Signed-off-by detection (safety net for DCO compliance)
if [[ $EXIT_CODE -eq 0 && -n "${_PRE_HEAD:-}" ]]; then
  _new_commits=$(git log "${_PRE_HEAD}..HEAD" --format='%H' 2>/dev/null || true)
  if [[ -n "$_new_commits" ]]; then
    _missing_sob=""
    while IFS= read -r _h; do
      if ! git log -1 --format='%B' "$_h" 2>/dev/null | grep -q "^Signed-off-by:"; then
        _missing_sob="${_missing_sob}${_missing_sob:+ }${_h}"
      fi
    done <<< "$_new_commits"
    if [[ -n "$_missing_sob" ]]; then
      echo "Warning: Signed-off-by missing in commits — DCO check may fail: ${_missing_sob}" >&2
    fi
  fi
fi

if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
  emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
fi

# Post-processor fallback: if LLM did not append ## Consumed Comments, do it now.
# Compare post-count with pre-count; trigger fallback when count did not increase.
if [[ $EXIT_CODE -eq 0 ]]; then
  _SPEC_FILE_POST=$(ls "$(dirname "$SCRIPT_DIR")/$_SPEC_DIR/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1 || true)
  _POST_COUNT=$(grep -c "^## Consumed Comments" "${_SPEC_FILE_POST:-/dev/null}" 2>/dev/null || true)
  _POST_COUNT="${_POST_COUNT:-0}"
  if [[ "$_POST_COUNT" -le "$_PRE_COUNT" ]]; then
    _append_consumed_comments_section "$ISSUE_NUMBER" "code" || true
  fi
fi

echo "---"
echo "=== run-code.sh: Finished /code for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "code"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
