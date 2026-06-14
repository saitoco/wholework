#!/bin/bash
# run-auto-sub.sh - Execute code→review→merge phases for each sub-issue.
# verify is deferred to the parent /auto session (issue #485)
#
# Usage: run-auto-sub.sh <sub-issue-number> [--base <branch>]

set -euo pipefail
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

emit_event() {
  local event_type="$1"; shift
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local json="{\"ts\":\"${ts}\",\"issue\":${SUB_NUMBER},\"event\":\"${event_type}\""
  while [[ $# -gt 0 ]]; do
    local kv="$1"; local k="${kv%%=*}"; local v="${kv#*=}"
    json="${json},\"${k}\":\"${v}\""
    shift
  done
  json="${json}}"
  mkdir -p "$(dirname "${AUTO_EVENTS_LOG}")"
  if command -v flock >/dev/null 2>&1; then
    (flock -x 200; echo "${json}" >> "${AUTO_EVENTS_LOG}") 200>"${AUTO_EVENTS_LOG}.lock"
  else
    local lock_dir="${AUTO_EVENTS_LOG}.lockdir"
    local tries=0
    while ! mkdir "${lock_dir}" 2>/dev/null; do
      tries=$((tries + 1))
      if (( tries > 50 )); then
        echo "${json}" >> "${AUTO_EVENTS_LOG}"
        return 0
      fi
      sleep 0.1
    done
    echo "${json}" >> "${AUTO_EVENTS_LOG}"
    rmdir "${lock_dir}" 2>/dev/null || true
  fi
}

run_phase_with_recovery() {
  local phase issue runner_script exit_code log_file
  phase="$1"; issue="$2"; runner_script="$3"; shift 3

  mkdir -p .tmp
  log_file=".tmp/wrapper-out-${issue}-${phase}.log"

  emit_event "phase_start" "phase=${phase}"

  set +e
  "$runner_script" "$issue" "$@" > "$log_file" 2>&1
  exit_code=$?
  set -e

  emit_event "wrapper_exit" "phase=${phase}" "exit_code=${exit_code}"

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
  if "$SCRIPT_DIR/apply-fallback.sh" "$phase" "$issue" --log "$log_file" 2>/dev/null; then
    echo "${LOG_PREFIX} [recovery] tier2 fallback catalog: recovered"
    emit_event "recovery" "phase=${phase}" "tier=2" "result=recovered"
    emit_event "phase_complete" "phase=${phase}"
    return 0
  fi

  # Tier 3: recovery sub-agent via claude -p (expensive, unknown anomaly only)
  if "$SCRIPT_DIR/spawn-recovery-subagent.sh" "$phase" "$issue" --log "$log_file" --exit-code "$exit_code"; then
    echo "${LOG_PREFIX} [recovery] tier3 sub-agent: recovered"
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
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}
    ;;
  S)
    echo "${LOG_PREFIX} --- code phase (patch): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}
    ;;
  M)
    echo "${LOG_PREFIX} --- code phase (pr): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}

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
    echo "${LOG_PREFIX} --- code phase (pr): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}

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
