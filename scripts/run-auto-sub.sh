#!/bin/bash
# run-auto-sub.sh - Execute code→review→merge phases for each sub-issue.
# verify is deferred to the parent /auto session (issue #485)
#
# Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]

set -euo pipefail

# Returns true if spec_rel_path has any changes (modified or untracked).
# Uses git status --porcelain so untracked files are detected (unlike git diff --quiet).
_spec_has_changes() {
  local repo_root="$1"
  local spec_rel_path="$2"
  git -C "$repo_root" status --porcelain "$spec_rel_path" 2>/dev/null | grep -q .
}

# Validates recovery function arguments to prevent path traversal via glob patterns.
# Usage: _validate_recovery_args ISSUE [PHASE] [RECOVERY_TYPE]
# Returns 1 and prints to stderr if any argument fails validation.
_validate_recovery_args() {
  local _issue="${1:-}"
  local _phase="${2:-}"
  local _recovery_type="${3:-}"

  if [[ -z "$_issue" ]] || ! [[ "$_issue" =~ ^[0-9]+$ ]]; then
    echo "_validate_recovery_args: invalid issue: '${_issue}'" >&2
    return 1
  fi

  if [[ -n "$_phase" ]] && ! [[ "$_phase" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "_validate_recovery_args: invalid phase: '${_phase}'" >&2
    return 1
  fi

  if [[ -n "$_recovery_type" ]] && ! [[ "$_recovery_type" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "_validate_recovery_args: invalid recovery_type: '${_recovery_type}'" >&2
    return 1
  fi
}

# --write-manual-recovery subcommand: write manual recovery record to sub-issue Spec.
# Usage: run-auto-sub.sh --write-manual-recovery ISSUE [PHASE] [RECOVERY_TYPE]
# See modules/orchestration-fallbacks.md#manual-recovery-spec-write
_write_manual_recovery_to_spec() {
  local issue="$1"
  local phase="${2:-unknown}"
  local recovery_type="${3:-unspecified}"
  _validate_recovery_args "$issue" "$phase" "$recovery_type" || return 1
  local _script_dir="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
  local _repo_root
  _repo_root="$(dirname "$_script_dir")"
  local spec_dir="$_repo_root/docs/spec"
  local spec_file
  spec_file=$(ls "$spec_dir/issue-${issue}-"*.md 2>/dev/null | head -1 || true)

  if [[ -z "$spec_file" ]]; then
    local title
    title=$(gh issue view "$issue" --json title -q '.title' 2>/dev/null || echo "Issue #${issue}")
    mkdir -p "$spec_dir"
    spec_file="$spec_dir/issue-${issue}-recovery.md"
    printf '%s\n' "# Issue #${issue}: ${title}" > "$spec_file"
  fi

  if ! grep -q "^## Auto Retrospective" "$spec_file" 2>/dev/null; then
    printf '\n%s\n' "## Auto Retrospective" >> "$spec_file"
  fi

  local _date
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  printf '\n%s\n' "### Manual recovery (${phase})" >> "$spec_file"
  printf '%s\n' "- **Date**: ${_date}" >> "$spec_file"
  printf '%s\n' "- **Issue**: #${issue}, phase: ${phase}" >> "$spec_file"
  printf '%s\n' "- **Source**: parent session manual recovery" >> "$spec_file"
  printf '%s\n' "- **Recovery type**: ${recovery_type}" >> "$spec_file"
  printf '%s\n' "- **Outcome**: success" >> "$spec_file"

  local spec_rel_path="${spec_file#$_repo_root/}"

  if _spec_has_changes "$_repo_root" "$spec_rel_path"; then
    if git -C "$_repo_root" add "$spec_rel_path" \
       && git -C "$_repo_root" commit -s -m "Record manual recovery in auto retrospective for issue #${issue}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" \
       && git -C "$_repo_root" push origin HEAD; then
      echo "[#${issue}] [recovery] spec auto retrospective updated for issue #${issue} (manual recovery)"
    else
      echo "[#${issue}] WARNING: could not commit/push manual recovery to spec; continuing" >&2
    fi
  fi
}

if [[ "${1:-}" == "--write-manual-recovery" ]]; then
  shift
  if [[ -z "${1:-}" ]]; then
    echo "Error: --write-manual-recovery requires: ISSUE [PHASE] [RECOVERY_TYPE]" >&2
    exit 1
  fi
  _write_manual_recovery_to_spec "$@"
  exit 0
fi

SUB_NUMBER="${1:?Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]}"
shift

# Parse options
BASE_BRANCH=""
BASE_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      echo "Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]" >&2
      exit 1
      ;;
  esac
done

if ! [[ "$SUB_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $SUB_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
LOG_PREFIX="[#${SUB_NUMBER}]"
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
export AUTO_SESSION_ID
export EMIT_ISSUE_NUMBER="$SUB_NUMBER"

source "$SCRIPT_DIR/emit-event.sh"
source "$SCRIPT_DIR/retry-on-kill.sh"

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

# _emit_comments_consumed() is now defined in emit-event.sh (Issue #791).
# Sourced via: source "$SCRIPT_DIR/emit-event.sh" above.

_write_tier2_recovery_to_spec() {
  local issue="$1"
  local meta_file="$2"
  _validate_recovery_args "$issue" || return 1
  local _repo_root
  _repo_root="$(dirname "$SCRIPT_DIR")"
  local spec_dir="$_repo_root/docs/spec"
  local spec_file
  spec_file=$(ls "$spec_dir/issue-${issue}-"*.md 2>/dev/null | head -1 || true)

  if [[ -z "$spec_file" ]]; then
    local title
    title=$(gh issue view "$issue" --json title -q '.title' 2>/dev/null || echo "Issue #${issue}")
    mkdir -p "$spec_dir"
    spec_file="$spec_dir/issue-${issue}-recovery.md"
    printf '%s\n' "# Issue #${issue}: ${title}" > "$spec_file"
  fi

  if ! grep -q "^## Auto Retrospective" "$spec_file" 2>/dev/null; then
    printf '\n%s\n' "## Auto Retrospective" >> "$spec_file"
  fi

  cat "$meta_file" >> "$spec_file"

  local spec_rel_path="${spec_file#$_repo_root/}"

  if _spec_has_changes "$_repo_root" "$spec_rel_path"; then
    if git -C "$_repo_root" add "$spec_rel_path" \
       && git -C "$_repo_root" commit -s -m "Record Tier 2 recovery in auto retrospective for issue #${issue}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" \
       && git -C "$_repo_root" push origin HEAD; then
      echo "${LOG_PREFIX} [recovery] spec auto retrospective updated for issue #${issue}"
    else
      echo "${LOG_PREFIX} WARNING: could not commit/push Tier 2 recovery to spec; continuing" >&2
    fi
  fi
}

_write_tier3_recovery_to_spec() {
  local issue="$1"
  local phase="$2"
  local exit_code="$3"
  _validate_recovery_args "$issue" "$phase" || return 1
  local _repo_root
  _repo_root="$(dirname "$SCRIPT_DIR")"
  local spec_dir="$_repo_root/docs/spec"
  local spec_file
  spec_file=$(ls "$spec_dir/issue-${issue}-"*.md 2>/dev/null | head -1 || true)

  if [[ -z "$spec_file" ]]; then
    local title
    title=$(gh issue view "$issue" --json title -q '.title' 2>/dev/null || echo "Issue #${issue}")
    mkdir -p "$spec_dir"
    spec_file="$spec_dir/issue-${issue}-recovery.md"
    printf '%s\n' "# Issue #${issue}: ${title}" > "$spec_file"
  fi

  if ! grep -q "^## Auto Retrospective" "$spec_file" 2>/dev/null; then
    printf '\n%s\n' "## Auto Retrospective" >> "$spec_file"
  fi

  local _date
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  printf '\n%s\n' "### Tier 3 recovery (${phase})" >> "$spec_file"
  printf '%s\n' "- **Date**: ${_date}" >> "$spec_file"
  printf '%s\n' "- **Issue**: #${issue}, phase: ${phase}" >> "$spec_file"
  printf '%s\n' "- **Source**: spawn-recovery-subagent.sh" >> "$spec_file"
  printf '%s\n' "- **Wrapper exit code**: ${exit_code}" >> "$spec_file"
  printf '%s\n' "- **Outcome**: success" >> "$spec_file"
  printf '%s\n' "- **Recovery details**: see docs/reports/orchestration-recoveries.md" >> "$spec_file"

  local spec_rel_path="${spec_file#$_repo_root/}"

  if _spec_has_changes "$_repo_root" "$spec_rel_path"; then
    if git -C "$_repo_root" add "$spec_rel_path" \
       && git -C "$_repo_root" commit -s -m "Record Tier 3 recovery in auto retrospective for issue #${issue}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" \
       && git -C "$_repo_root" push origin HEAD; then
      echo "${LOG_PREFIX} [recovery] spec auto retrospective updated for issue #${issue} (tier3)"
    else
      echo "${LOG_PREFIX} WARNING: could not commit/push Tier 3 recovery to spec; continuing" >&2
    fi
  fi
}

# _write_wrapper_retry_recovery ISSUE PHASE EXIT_CODE
# Records a wrapper-retry-on-kill recovery event to orchestration-recoveries.md.
# Skips silently if the file does not exist (file not in repo → return 0).
# See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
_write_wrapper_retry_recovery() {
  local issue="$1"
  local phase="$2"
  local exit_code_arg="$3"
  local _repo_root
  _repo_root="$(dirname "$SCRIPT_DIR")"
  local _recoveries_file="${_repo_root}/docs/reports/orchestration-recoveries.md"
  if [[ ! -f "$_recoveries_file" ]]; then
    return 0
  fi
  local _date _outcome
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  if [[ "$exit_code_arg" -eq 0 ]]; then
    _outcome="success"
  else
    _outcome="escalated (retry also killed)"
  fi
  python3 << PYEOF 2>/dev/null || true
fpath = "${_recoveries_file}"
marker = "<!-- Log entries appear below, newest first. -->"
entry = (
    "\n### wrapper-retry-on-kill (${phase})\n"
    "- **Date**: ${_date}\n"
    "- **Issue**: #${issue}, phase: ${phase}\n"
    "- **Source**: retry-on-kill.sh\n"
    "- **Exit code**: ${exit_code_arg}\n"
    "- **Outcome**: ${_outcome}\n"
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
  if ! git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
    if git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md" \
       && git -C "$_repo_root" commit -s -m "Record wrapper-retry-on-kill recovery for issue #${issue} ${phase}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" \
       && git -C "$_repo_root" push origin HEAD; then
      echo "${LOG_PREFIX} [recovery] wrapper-retry-on-kill recovery log committed and pushed"
    else
      echo "${LOG_PREFIX} WARNING: could not commit/push wrapper-retry-on-kill recovery log" >&2
    fi
  fi
}

# _observe_code_milestone NUMBER
# Probes observable git/GitHub state to determine the current code_phase_milestone value.
# Used by the pr-route resume preamble to reconcile the checkpoint with live state.
# Priority: post-PR-create > post-push > post-commit > pre-commit > initial
# Uses 2>/dev/null guards to avoid failures in offline/test environments.
_observe_code_milestone() {
  local number="$1"
  local branch_name="worktree-code+issue-${number}"
  local repo_root
  repo_root="$(dirname "$SCRIPT_DIR")"

  # Check for open PR with this branch as head
  local pr_match
  pr_match=$(gh pr list --json headRefName,state 2>/dev/null | \
    jq -r ".[] | select(.headRefName == \"${branch_name}\") | select(.state == \"OPEN\") | .headRefName" \
    2>/dev/null || true)
  if [[ -n "$pr_match" ]]; then
    echo "post-PR-create"
    return
  fi

  # Check for remote branch
  if git -C "$repo_root" ls-remote --heads origin "$branch_name" 2>/dev/null | grep -q .; then
    echo "post-push"
    return
  fi

  # Check for local branch with commits ahead of base
  local ahead
  ahead=$(git -C "$repo_root" rev-list "$branch_name" \
    --not "${BASE_BRANCH:-main}" --count 2>/dev/null || echo "0")
  if [[ "${ahead:-0}" -gt 0 ]]; then
    echo "post-commit"
    return
  fi

  # Check for dirty worktree (uncommitted changes)
  local worktree_dir="${repo_root}/.claude/worktrees/code+issue-${number}"
  if [[ -d "$worktree_dir" ]] && \
     git -C "$worktree_dir" status --porcelain 2>/dev/null | grep -q .; then
    echo "pre-commit"
    return
  fi

  echo "initial"
}

run_phase_with_recovery() {
  local phase issue runner_script exit_code log_file
  phase="$1"; issue="$2"; runner_script="$3"; shift 3

  mkdir -p .tmp
  log_file=".tmp/wrapper-out-${issue}-${phase}.log"

  export EMIT_ISSUE_NUMBER="$issue"
  export EMIT_PHASE_NAME="$phase"

  # Bash-side comments_consumed emit for code phases (issue-level comment consumption).
  # Emitted before phase_start so _maybe_emit_phase_complete backfill detection
  # still sees phase_start as the last event when phase_complete is absent. (Issue #705)
  if [[ "$phase" == code* ]]; then
    _emit_comments_consumed "$issue" "code" || true
  fi

  local PHASE_START
  PHASE_START=$(date +%s)
  emit_event "phase_start" "phase=${phase}"

  set +e
  # See modules/orchestration-fallbacks.md#wrapper-retry-on-kill
  run_with_retry_on_kill "$runner_script" "$issue" "$@" > "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ "${_RETRY_ON_KILL_FIRED:-false}" == "true" ]]; then
    _write_wrapper_retry_recovery "$issue" "$phase" "$exit_code"
  fi

  emit_event "wrapper_exit" "phase=${phase}" "exit_code=${exit_code}"

  # token_usage: parse from TOKEN_USAGE_FILE if it exists
  local _token_usage_file=".tmp/token-usage-${issue}.json"
  if [[ -f "$_token_usage_file" ]]; then
    local _model _input _output _cache_read
    _model=$(jq -r '.model // empty' "$_token_usage_file" 2>/dev/null || true)
    _input=$(jq -r '.usage.input_tokens // empty' "$_token_usage_file" 2>/dev/null || true)
    _output=$(jq -r '.usage.output_tokens // empty' "$_token_usage_file" 2>/dev/null || true)
    _cache_read=$(jq -r '.usage.cache_read_input_tokens // empty' "$_token_usage_file" 2>/dev/null || true)
    if [[ -n "$_input" ]]; then
      emit_event "token_usage" "phase=${phase}" \
        "model=${_model:-unknown}" \
        "input_tokens=${_input}" \
        "output_tokens=${_output:-0}" \
        "cache_read_tokens=${_cache_read:-0}"
    fi
  fi

  # concurrent_commit_detected: check for commits on origin/main since phase start
  local _commits
  _commits=$(git log origin/main --since="@${PHASE_START}" --format="%H %an" 2>/dev/null || true)
  if [[ -n "$_commits" ]]; then
    local _phase_end; _phase_end=$(date +%s)
    local _since_sec=$(( _phase_end - PHASE_START ))
    while IFS= read -r _commit_line; do
      [[ -z "$_commit_line" ]] && continue
      local _sha="${_commit_line%% *}"
      local _author="${_commit_line#* }"
      emit_event "concurrent_commit_detected" "phase=${phase}" \
        "commit_sha=${_sha}" \
        "author=${_author}" \
        "since_phase_start_sec=${_since_sec}"
    done <<< "$_commits"
  fi

  # test_result: parse bats output from log_file (code-patch / code-pr / code phases)
  if [[ "$phase" == code* ]] && [[ -f "$log_file" ]]; then
    local _bats_line
    _bats_line=$(grep -E "[0-9]+ tests?, [0-9]+ failures?" "$log_file" 2>/dev/null | tail -1 || true)
    if [[ -n "$_bats_line" ]]; then
      local _passed _failed
      _passed=$(echo "$_bats_line" | grep -oE "^[0-9]+" || echo 0)
      _failed=$(echo "$_bats_line" | grep -oE "[0-9]+ failures?" | grep -oE "^[0-9]+" || echo 0)
      emit_event "test_result" "phase=${phase}" \
        "framework=bats" \
        "passed=${_passed}" \
        "failed=${_failed}" \
        "pattern=unit"
    fi
  fi

  if [[ $exit_code -eq 0 ]]; then
    local anomaly_out
    anomaly_out=$("$SCRIPT_DIR/detect-wrapper-anomaly.sh" --log "$log_file" --exit-code 0 --issue "$issue" --phase "$phase" 2>/dev/null || true)
    if [[ -n "$anomaly_out" ]]; then
      echo "${LOG_PREFIX} [anomaly] silent no-op detected in ${phase}:"
      echo "$anomaly_out"
    fi
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi

  # Tier 1: reconciler (bash, cheap) — completion check
  # See modules/orchestration-fallbacks.md (Observe-Diagnose-Act pattern)
  if "$SCRIPT_DIR/reconcile-phase-state.sh" "$phase" "$issue" --check-completion 2>/dev/null | grep -q '"matches_expected":true'; then
    echo "${LOG_PREFIX} [recovery] tier1 reconciler: phase completed despite wrapper exit $exit_code"
    emit_event "recovery" "phase=${phase}" "tier=1" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi

  # Tier 2: fallback catalog (bash, cheap) — known pattern recovery
  # See modules/orchestration-fallbacks.md#code-patch-silent-no-op
  local _fallback_meta_file=".tmp/fallback-meta-${issue}-${phase}.md"
  local _fallback_exit=0
  mkdir -p .tmp
  "$SCRIPT_DIR/apply-fallback.sh" "$phase" "$issue" --log "$log_file" > "$_fallback_meta_file" 2>/dev/null || _fallback_exit=$?
  if [[ $_fallback_exit -eq 0 ]]; then
    echo "${LOG_PREFIX} [recovery] tier2 fallback catalog: recovered"
    if [[ -s "$_fallback_meta_file" ]]; then
      _write_tier2_recovery_to_spec "$issue" "$_fallback_meta_file"
    fi
    rm -f "$_fallback_meta_file"
    emit_event "recovery" "phase=${phase}" "tier=2" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi
  rm -f "$_fallback_meta_file"

  # Tier 3: recovery sub-agent via claude -p (expensive, unknown anomaly only)
  if "$SCRIPT_DIR/spawn-recovery-subagent.sh" "$phase" "$issue" --log "$log_file" --exit-code "$exit_code"; then
    echo "${LOG_PREFIX} [recovery] tier3 sub-agent: recovered"
    local _repo_root; _repo_root="$(dirname "$SCRIPT_DIR")"
    if ! git -C "$_repo_root" diff --quiet "docs/reports/orchestration-recoveries.md" 2>/dev/null; then
      if git -C "$_repo_root" add "docs/reports/orchestration-recoveries.md" \
         && git -C "$_repo_root" commit -s -m "Record Tier 3 recovery event for issue #${issue} ${phase} phase" \
         && git -C "$_repo_root" push origin HEAD; then
        echo "${LOG_PREFIX} [recovery] recovery log committed and pushed"
      else
        echo "${LOG_PREFIX} WARNING: could not commit/push recovery log; /verify may detect dirty file" >&2
      fi
    fi
    _write_tier3_recovery_to_spec "$issue" "$phase" "$exit_code"
    emit_event "recovery" "phase=${phase}" "tier=3" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi

  return $exit_code
}

echo "${LOG_PREFIX} === run-auto-sub.sh: Starting sub-issue #${SUB_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$SUB_NUMBER" "auto"
echo "${LOG_PREFIX} Started at: $(date '+%Y-%m-%d %H:%M:%S')"
if [[ -n "$BASE_BRANCH" ]]; then
  echo "${LOG_PREFIX} Base branch: ${BASE_BRANCH}"
fi
echo "${LOG_PREFIX} ---"

# Determine route by fetching Size (before spec phase)
SIZE=$("$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER" 2>/dev/null || true)

emit_event "sub_start" "size=${SIZE}"

# spec phase: run only if phase/ready label is not present
LABELS=$(gh issue view "$SUB_NUMBER" --json labels -q '.labels[].name' 2>/dev/null || true)
if ! echo "$LABELS" | grep -q "phase/ready"; then
  echo "${LOG_PREFIX} --- spec phase: issue #${SUB_NUMBER} ---"
  # Bash-side comments_consumed emit for spec phase. (Issue #705)
  _emit_comments_consumed "$SUB_NUMBER" "spec" || true
  if [[ "$SIZE" == "L" ]]; then
    "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER" --opus
  else
    "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER"
  fi
fi

# Always re-fetch SIZE after spec phase (spec may have re-judged the Size)
# Mirror of skills/auto/SKILL.md Step 3a (Issue #616 for the parent path)
INITIAL_SIZE="$SIZE"
SIZE=$("$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER" 2>/dev/null || true)
if [[ -n "$INITIAL_SIZE" && "$INITIAL_SIZE" != "$SIZE" ]]; then
  echo "${LOG_PREFIX} Post-spec route demotion/upgrade: ${INITIAL_SIZE} → ${SIZE}, remaining phases re-planned"
  emit_event "size_refresh" "from=${INITIAL_SIZE}" "to=${SIZE}"
fi
if [[ -z "$SIZE" ]]; then
  echo "${LOG_PREFIX} Error: Size is not set for issue #${SUB_NUMBER}" >&2
  exit 1
fi

if [[ "$SIZE" == "XL" ]]; then
  echo "${LOG_PREFIX} Error: issue #${SUB_NUMBER} is XL. Further sub-issue splitting is required" >&2
  exit 1
fi

echo "${LOG_PREFIX} Size: ${SIZE}"

# Execute phases according to Size-based route.
# verify is deferred to the parent /auto session (issue #485)
case "$SIZE" in
  XS)
    echo "${LOG_PREFIX} --- code phase (patch): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code-patch" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}
    ;;
  S)
    echo "${LOG_PREFIX} --- code phase (patch): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code-patch" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}
    ;;
  M)
    # Resume preamble: if residual worktree/branch exists from a prior interrupted run,
    # observe the current milestone and dispatch to the appropriate recovery action.
    # Gate: fire only when local branch or worktree dir exists (avoids first-run path).
    _CODE_PR_DONE=false
    _REPO_ROOT="$(dirname "$SCRIPT_DIR")"
    _WORKTREE_DIR="${_REPO_ROOT}/.claude/worktrees/code+issue-${SUB_NUMBER}"
    _BRANCH_NAME="worktree-code+issue-${SUB_NUMBER}"
    if [[ -d "$_WORKTREE_DIR" ]] || \
       git -C "$_REPO_ROOT" rev-parse --verify "$_BRANCH_NAME" >/dev/null 2>&1; then
      echo "${LOG_PREFIX} [resume] residual artifact detected for issue #${SUB_NUMBER}"
      _OBSERVED_MS=$(_observe_code_milestone "$SUB_NUMBER")
      echo "${LOG_PREFIX} [resume] observed milestone: ${_OBSERVED_MS}"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "$_OBSERVED_MS" || true
      _RESUME_ACTION=$("$SCRIPT_DIR/auto-checkpoint.sh" resume_action "$_OBSERVED_MS")
      echo "${LOG_PREFIX} [resume] action: ${_RESUME_ACTION}"
      case "$_RESUME_ACTION" in
        skip-to-review)
          echo "${LOG_PREFIX} [resume] PR exists, skipping code phase"
          _CODE_PR_DONE=true
          ;;
        create-pr)
          echo "${LOG_PREFIX} [resume] push done, creating PR"
          if gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] create-pr failed, falling back to code phase" >&2
          fi
          ;;
        push-and-pr)
          echo "${LOG_PREFIX} [resume] commits done, pushing branch and creating PR"
          if git -C "$_REPO_ROOT" push -u origin "$_BRANCH_NAME" 2>/dev/null \
             && gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] push-and-pr failed, falling back to code phase" >&2
          fi
          ;;
        run-code)
          echo "${LOG_PREFIX} [resume] no milestone recovery needed, running code phase normally"
          ;;
      esac
    fi

    if [[ "$_CODE_PR_DONE" == "false" ]]; then
      echo "${LOG_PREFIX} --- code phase (pr): issue #${SUB_NUMBER} ---"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "initial" || true
      run_phase_with_recovery "code-pr" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
    fi

    PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "${LOG_PREFIX} Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"

    echo "${LOG_PREFIX} --- review phase (light): PR #${PR_NUMBER} ---"
    run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light

    echo "${LOG_PREFIX} --- merge phase: PR #${PR_NUMBER} ---"
    run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
    ;;
  L)
    # Resume preamble (same logic as M, pr route)
    _CODE_PR_DONE=false
    _REPO_ROOT="$(dirname "$SCRIPT_DIR")"
    _WORKTREE_DIR="${_REPO_ROOT}/.claude/worktrees/code+issue-${SUB_NUMBER}"
    _BRANCH_NAME="worktree-code+issue-${SUB_NUMBER}"
    if [[ -d "$_WORKTREE_DIR" ]] || \
       git -C "$_REPO_ROOT" rev-parse --verify "$_BRANCH_NAME" >/dev/null 2>&1; then
      echo "${LOG_PREFIX} [resume] residual artifact detected for issue #${SUB_NUMBER}"
      _OBSERVED_MS=$(_observe_code_milestone "$SUB_NUMBER")
      echo "${LOG_PREFIX} [resume] observed milestone: ${_OBSERVED_MS}"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "$_OBSERVED_MS" || true
      _RESUME_ACTION=$("$SCRIPT_DIR/auto-checkpoint.sh" resume_action "$_OBSERVED_MS")
      echo "${LOG_PREFIX} [resume] action: ${_RESUME_ACTION}"
      case "$_RESUME_ACTION" in
        skip-to-review)
          echo "${LOG_PREFIX} [resume] PR exists, skipping code phase"
          _CODE_PR_DONE=true
          ;;
        create-pr)
          echo "${LOG_PREFIX} [resume] push done, creating PR"
          if gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] create-pr failed, falling back to code phase" >&2
          fi
          ;;
        push-and-pr)
          echo "${LOG_PREFIX} [resume] commits done, pushing branch and creating PR"
          if git -C "$_REPO_ROOT" push -u origin "$_BRANCH_NAME" 2>/dev/null \
             && gh pr create --head "$_BRANCH_NAME" --base "${BASE_BRANCH:-main}" \
               --title "Issue #${SUB_NUMBER}: resume recovery" \
               --body "$(printf 'Closes #%s\n\nSpec: docs/spec/issue-%s-*.md' \
                          "$SUB_NUMBER" "$SUB_NUMBER")"; then
            "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
            _CODE_PR_DONE=true
          else
            echo "${LOG_PREFIX} [resume] push-and-pr failed, falling back to code phase" >&2
          fi
          ;;
        run-code)
          echo "${LOG_PREFIX} [resume] no milestone recovery needed, running code phase normally"
          ;;
      esac
    fi

    if [[ "$_CODE_PR_DONE" == "false" ]]; then
      echo "${LOG_PREFIX} --- code phase (pr): issue #${SUB_NUMBER} ---"
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "initial" || true
      run_phase_with_recovery "code-pr" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}
      "$SCRIPT_DIR/auto-checkpoint.sh" write_milestone "$SUB_NUMBER" "post-PR-create" || true
    fi

    PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "${LOG_PREFIX} Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"

    echo "${LOG_PREFIX} --- review phase (full): PR #${PR_NUMBER} ---"
    run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --full

    echo "${LOG_PREFIX} --- merge phase: PR #${PR_NUMBER} ---"
    run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
    ;;
  *)
    echo "${LOG_PREFIX} Error: Unknown Size: ${SIZE}" >&2
    exit 1
    ;;
esac

echo "${LOG_PREFIX} ---"
echo "${LOG_PREFIX} === run-auto-sub.sh: Completed sub-issue #${SUB_NUMBER} ==="
print_end_banner "issue" "$SUB_NUMBER" "auto"
echo "${LOG_PREFIX} Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
emit_event "sub_complete" "exit_code=0"
exit 0
