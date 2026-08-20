#!/bin/bash
# run-spec.sh - Autonomous /spec execution with Sonnet model
# Usage: run-spec.sh <issue-number> [--opus] [--fable] [--max]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-spec.sh <issue-number> [--opus] [--fable] [--max]}"
shift
# Save trailing args before parsing loop so exec re-invocation can pass them unchanged
_TRAILING_ARGS=("$@")

# Parse options
# Default: --model sonnet, --effort max (Opus path: xhigh by default, max with --max)
MODEL="sonnet"
EFFORT="max"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --opus)
      MODEL="opus"
      EFFORT="xhigh"
      shift
      ;;
    --fable)
      MODEL="claude-fable-5"
      EFFORT="high"
      shift
      ;;
    --max)
      EFFORT="max"
      shift
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-spec.sh <issue-number> [--opus] [--fable] [--max]" >&2
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
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Phase guard: block spec execution if the issue already advanced past phase/code
# (prevents a duplicate/late-firing run-spec.sh from rewinding phase/code+ back to phase/spec)
_PHASE_GUARD_LABELS=$(gh issue view "$ISSUE_NUMBER" --json labels --jq '.labels[].name' 2>/dev/null || true)
for _phase in phase/code phase/review phase/merge phase/verify phase/done; do
  if echo "$_PHASE_GUARD_LABELS" | grep -qx "$_phase"; then
    echo "[run-spec] classify=phase-guard-blocked issue=${ISSUE_NUMBER} label=${_phase}" >&2
    echo "Error: issue #${ISSUE_NUMBER} already has label '${_phase}' (phase/code or later) — aborting spec to prevent duplicate execution." >&2
    exit 1
  fi
done

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
# Primary: PGID-based file (Issue #770). No fallback to auto-session-current: that file is
# written only by /auto Step 1, so a wrapper invoked outside /auto has no claim to it and
# reading it risks misattributing a concurrent /auto session's session_id (Issue #1317).
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
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
  export EMIT_PHASE_NAME="spec"
  emit_event "phase_start" "phase=${EMIT_PHASE_NAME}" "spawn_detach=$([[ -n "${_WHOLEWORK_DETACHED:-}" ]] && echo 1 || echo 0)"
fi

# Fixed, not config-derived: this repo has no permission-mode opt-out (#1418).
PERMISSION_FLAG="--permission-mode auto"

AUTONOMY_TIER=$("$SCRIPT_DIR/get-config-value.sh" autonomy L1 2>/dev/null || echo L1)
_WW_YML="${REPO_ROOT}/.wholework.yml"
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
SPEC_RETRY_COUNT=${SPEC_RETRY_COUNT:-0}
export SPEC_RETRY_COUNT

# Pushes HEAD to origin, retrying with fetch+rebase on non-fast-forward rejection.
# Same pattern as scripts/run-auto-sub.sh's _push_with_retry().
# Usage: _push_with_retry REPO_ROOT
# Returns 0 on success, 1 if all retries are exhausted or a step fails.
_push_with_retry() {
  local repo_root="$1"
  local attempt=0
  local branch

  while true; do
    if git -C "$repo_root" push origin HEAD; then
      return 0
    fi
    attempt=$((attempt + 1))
    if [[ $attempt -ge 3 ]]; then
      return 1
    fi
    branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD) || return 1
    git -C "$repo_root" fetch origin "$branch" || return 1
    if ! git -C "$repo_root" rebase "origin/${branch}"; then
      git -C "$repo_root" rebase --abort 2>/dev/null || true
      return 1
    fi
  done
}

# _write_spec_retry_recovery ISSUE ITERATION
# Records a spec_retry_fire recovery event to orchestration-recoveries.md immediately
# before the exec self-restart -- exec replaces the running process, so recording
# after exec (or in the retried process) can never observe the failure that triggered
# it; recording must happen here, before exec.
# Skips silently if the file does not exist (file not in repo -> return 0).
# See modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire
_write_spec_retry_recovery() {
  local issue="$1"
  local iteration="$2"
  local repo_root="${REPO_ROOT:-.}"
  local recoveries_file="${repo_root}/docs/reports/orchestration-recoveries.md"
  if [[ ! -f "$recoveries_file" ]]; then
    return 0
  fi
  local _date
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  python3 << PYEOF 2>/dev/null || true
fpath = "${recoveries_file}"
marker = "<!-- Log entries appear below, newest first. -->"
entry = (
    "\n## ${_date}: spec-retry-fire\n"
    "\n### Context\n"
    "- Issue #${issue}, phase: spec\n"
    "- Source: run-spec.sh auto-retry-on-fail\n"
    "- Wrapper: run-spec.sh, iteration: ${iteration}/${AUTO_RETRY_MAX_ITERATIONS}\n"
    "\n### Diagnosis\n"
    "- cause: silent-no-op\n"
    "- reconcile-phase-state.sh --check-completion reported matches_expected:false (silent no-op) prior to this retry\n"
    "\n### Recovery Applied\n"
    "- modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire\n"
    "\n### Outcome\n"
    "- retry fired (iteration ${iteration}/${AUTO_RETRY_MAX_ITERATIONS})\n"
    "\n### Improvement Candidate\n"
    "- 未起票\n"
)
try:
    content = open(fpath).read()
    idx = content.find(marker)
    if idx != -1:
        pos = idx + len(marker)
        content = content[:pos] + entry + content[pos:]
        open(fpath, "w").write(content)
except Exception:
    pass
PYEOF
  if ! git -C "$repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
    if git -C "$repo_root" add "docs/reports/orchestration-recoveries.md" \
       && git -C "$repo_root" commit -s -m "Record spec_retry_fire recovery for issue #${issue}

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>" \
       && _push_with_retry "$repo_root"; then
      echo "[recovery] spec-retry-fire recovery log committed and pushed" >&2
    else
      echo "WARNING: could not commit/push spec-retry-fire recovery log" >&2
    fi
  fi
}

echo "=== run-spec.sh: Starting /spec for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Model: ${MODEL}"
echo "Effort: ${EFFORT}"
echo "Permissions: permission-mode auto (with allow rules template)"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"
if [[ "$MODEL" == "claude-fable-5" ]]; then
  echo "WARNING: Fable 5 opt-in — cost \$10/\$50 per MTok (2x Opus 4.8, ~3.3x Sonnet)"
  echo "WARNING: Usage credits required (subscription plans)"
  echo "WARNING: 30-day retention required — ZDR organizations not supported"
fi

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
SKILL_FILE="${SCRIPT_DIR}/../skills/spec/SKILL.md"

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
source "$SCRIPT_DIR/retry-on-kill.sh"

PROMPT="${GUARD_PREFIX}

${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"

# Pre-count: capture ## Consumed Comments section count before claude runs.
# Used by post-processor fallback to detect when LLM silently skipped writeback.
_SPEC_DIR=$(WHOLEWORK_CONFIG_PATH="${REPO_ROOT}/.wholework.yml" \
  "$SCRIPT_DIR/get-config-value.sh" spec-path docs/spec 2>/dev/null || echo "docs/spec")
_SPEC_FILE_PRE=$(ls "${REPO_ROOT}/$_SPEC_DIR/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1 || true)
_PRE_COUNT=$(grep -c "^## Consumed Comments" "${_SPEC_FILE_PRE:-/dev/null}" 2>/dev/null || true)
_PRE_COUNT="${_PRE_COUNT:-0}"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
load_watchdog_timeout "$SCRIPT_DIR" "spec"

SECONDS=0
set +e
if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
  TOKEN_USAGE_FILE=".tmp/token-usage-${ISSUE_NUMBER}.json"
  mkdir -p .tmp
  # See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
  run_with_retry_on_kill env -u CLAUDECODE ANTHROPIC_MODEL="${MODEL}" \
    WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
    OUTPUT_FORMAT_JSON=1 \
    "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
      --model "${MODEL}" \
      --effort "${EFFORT}" \
      --output-format json \
      --plugin-dir "$(dirname "$SCRIPT_DIR")" \
      $PERMISSION_FLAG \
      > "$TOKEN_USAGE_FILE"
  EXIT_CODE=$?
  jq -r '.result // empty' "$TOKEN_USAGE_FILE" 2>/dev/null || true
else
  # See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
  run_with_retry_on_kill env -u CLAUDECODE ANTHROPIC_MODEL="${MODEL}" \
    WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
    "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
      --model "${MODEL}" \
      --effort "${EFFORT}" \
      --plugin-dir "$(dirname "$SCRIPT_DIR")" \
      $PERMISSION_FLAG
  EXIT_CODE=$?
fi
set -e
"$SCRIPT_DIR/handle-permission-mode-failure.sh" "$EXIT_CODE" "$SECONDS"

if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then
  _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" spec "$ISSUE_NUMBER" --check-completion 2>/dev/null) || true
  if [[ $EXIT_CODE -eq 143 ]]; then
    if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
      EXIT_CODE=0
    fi
  elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
    echo "Warning: claude exited 0 but spec phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
    if [[ ( "$AUTONOMY_TIER" == "L2" || "$AUTONOMY_TIER" == "L3" ) ]] && \
       [[ "$AUTO_RETRY_ENABLED" == "true" ]] && \
       [[ "$SPEC_RETRY_COUNT" -lt "$AUTO_RETRY_MAX_ITERATIONS" ]]; then
      SPEC_RETRY_COUNT=$(( SPEC_RETRY_COUNT + 1 ))
      export SPEC_RETRY_COUNT
      echo "auto-retry: spec phase silent no-op, retry ${SPEC_RETRY_COUNT}/${AUTO_RETRY_MAX_ITERATIONS}" >&2
      if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
        EMIT_ISSUE_NUMBER="$ISSUE_NUMBER" emit_event "spec_retry_fire" \
          "iteration=${SPEC_RETRY_COUNT}" \
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
      # See modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire
      _write_spec_retry_recovery "$ISSUE_NUMBER" "$SPEC_RETRY_COUNT"
      exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]+"${_TRAILING_ARGS[@]}"}"
    else
      if [[ ( "$AUTONOMY_TIER" == "L2" || "$AUTONOMY_TIER" == "L3" ) ]] && \
         [[ "$AUTO_RETRY_ENABLED" == "true" ]]; then
        echo "auto-retry: max iterations reached (${SPEC_RETRY_COUNT}/${AUTO_RETRY_MAX_ITERATIONS}). Manual intervention required." >&2
      fi
      EXIT_CODE=1
    fi
  fi
fi

if [[ -n "${_EMIT_PHASE_OWNED:-}" ]]; then
  emit_event "wrapper_exit" "phase=${EMIT_PHASE_NAME}" "exit_code=${EXIT_CODE}"

  _TOKEN_USAGE_FILE=".tmp/token-usage-${ISSUE_NUMBER}.json"
  if [[ -f "$_TOKEN_USAGE_FILE" ]]; then
    _model=$(jq -r '.modelUsage // {} | to_entries | if length == 0 then empty else (max_by(.value.inputTokens + .value.outputTokens) | .key) end' "$_TOKEN_USAGE_FILE" 2>/dev/null || true)
    _input=$(jq -r '.usage.input_tokens // empty' "$_TOKEN_USAGE_FILE" 2>/dev/null || true)
    _output=$(jq -r '.usage.output_tokens // empty' "$_TOKEN_USAGE_FILE" 2>/dev/null || true)
    _cache_read=$(jq -r '.usage.cache_read_input_tokens // empty' "$_TOKEN_USAGE_FILE" 2>/dev/null || true)
    if [[ -n "$_input" ]]; then
      emit_event "token_usage" "phase=${EMIT_PHASE_NAME}" \
        "model=${_model:-unknown}" \
        "input_tokens=${_input}" \
        "output_tokens=${_output:-0}" \
        "cache_read_tokens=${_cache_read:-0}"
    fi
    rm -f "$_TOKEN_USAGE_FILE"
  fi
fi

if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
  emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
fi

# Post-processor fallback: if LLM did not append ## Consumed Comments, do it now.
# Compare post-count with pre-count; trigger fallback when count did not increase.
if [[ $EXIT_CODE -eq 0 ]]; then
  _SPEC_FILE_POST=$(ls "${REPO_ROOT}/$_SPEC_DIR/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1 || true)
  _POST_COUNT=$(grep -c "^## Consumed Comments" "${_SPEC_FILE_POST:-/dev/null}" 2>/dev/null || true)
  _POST_COUNT="${_POST_COUNT:-0}"
  if [[ "$_POST_COUNT" -le "$_PRE_COUNT" ]]; then
    _append_consumed_comments_section "$ISSUE_NUMBER" "spec" || true
  fi
fi

echo "---"
echo "=== run-spec.sh: Finished /spec for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
