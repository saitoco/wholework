#!/bin/bash
# run-auto-sub.sh - Execute all phases (spec->code->review->merge->verify) for each sub-issue
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

# See modules/orchestration-fallbacks.md#verify-sync-retry
run_verify_with_retry() {
  local issue_num="$1"
  local base_branch="${2:-}"

  if [[ -n "$base_branch" ]]; then
    "$SCRIPT_DIR/run-verify.sh" "$issue_num" --base "$base_branch" && return 0
  else
    "$SCRIPT_DIR/run-verify.sh" "$issue_num" && return 0
  fi

  echo "verify FAILED: syncing with git pull --ff-only and retrying (1/1)"
  if ! git pull --ff-only; then
    echo "git pull --ff-only failed: reporting as FAIL without retry" >&2
    return 1
  fi

  if [[ -n "$base_branch" ]]; then
    "$SCRIPT_DIR/run-verify.sh" "$issue_num" --base "$base_branch"
  else
    "$SCRIPT_DIR/run-verify.sh" "$issue_num"
  fi
}

run_phase_with_recovery() {
  local phase issue runner_script exit_code log_file
  phase="$1"; issue="$2"; runner_script="$3"; shift 3

  mkdir -p .tmp
  log_file=".tmp/wrapper-out-${issue}-${phase}.log"

  set +e
  "$runner_script" "$issue" "$@" > "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]]; then
    local anomaly_out
    anomaly_out=$("$SCRIPT_DIR/detect-wrapper-anomaly.sh" --log "$log_file" --exit-code 0 --issue "$issue" --phase "$phase" 2>/dev/null || true)
    if [[ -n "$anomaly_out" ]]; then
      echo "[anomaly] silent no-op detected in ${phase}:"
      echo "$anomaly_out"
    fi
    return 0
  fi

  # Tier 1: reconciler (bash, cheap) — completion check
  # See modules/orchestration-fallbacks.md (Observe-Diagnose-Act pattern)
  if "$SCRIPT_DIR/reconcile-phase-state.sh" "$phase" "$issue" --check-completion 2>/dev/null | grep -q '"matches_expected":true'; then
    echo "[recovery] tier1 reconciler: phase completed despite wrapper exit $exit_code"
    return 0
  fi

  # Tier 2: fallback catalog (bash, cheap) — known pattern recovery
  if "$SCRIPT_DIR/apply-fallback.sh" "$phase" "$issue" --log "$log_file" 2>/dev/null; then
    echo "[recovery] tier2 fallback catalog: recovered"
    return 0
  fi

  # Tier 3: recovery sub-agent via claude -p (expensive, unknown anomaly only)
  if "$SCRIPT_DIR/spawn-recovery-subagent.sh" "$phase" "$issue" --log "$log_file" --exit-code "$exit_code"; then
    echo "[recovery] tier3 sub-agent: recovered"
    return 0
  fi

  return $exit_code
}

echo "=== run-auto-sub.sh: Starting sub-issue #${SUB_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$SUB_NUMBER" "auto"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
if [[ -n "$BASE_BRANCH" ]]; then
  echo "Base branch: ${BASE_BRANCH}"
fi
echo "---"

# Determine route by fetching Size (before spec phase)
SIZE=$("$SCRIPT_DIR/get-issue-size.sh" "$SUB_NUMBER" 2>/dev/null || true)

# spec phase: run only if phase/ready label is not present
LABELS=$(gh issue view "$SUB_NUMBER" --json labels -q '.labels[].name' 2>/dev/null || true)
if ! echo "$LABELS" | grep -q "phase/ready"; then
  echo "--- spec phase: issue #${SUB_NUMBER} ---"
  if [[ "$SIZE" == "L" ]]; then
    "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER" --opus
  else
    "$SCRIPT_DIR/run-spec.sh" "$SUB_NUMBER"
  fi
fi

# Re-fetch SIZE after spec phase in case spec set the Size label
if [[ -z "$SIZE" ]]; then
  SIZE=$("$SCRIPT_DIR/get-issue-size.sh" "$SUB_NUMBER" 2>/dev/null || true)
fi
if [[ -z "$SIZE" ]]; then
  echo "Error: Size is not set for issue #${SUB_NUMBER}" >&2
  exit 1
fi

if [[ "$SIZE" == "XL" ]]; then
  echo "Error: issue #${SUB_NUMBER} is XL. Further sub-issue splitting is required" >&2
  exit 1
fi

echo "Size: ${SIZE}"

# Execute phases according to Size-based route
case "$SIZE" in
  XS)
    echo "--- code phase (patch): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  S)
    echo "--- code phase (patch): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  M)
    echo "--- code phase (pr): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}

    PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "PR number: ${PR_NUMBER}"

    echo "--- review phase (light): PR #${PR_NUMBER} ---"
    run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light

    echo "--- merge phase: PR #${PR_NUMBER} ---"
    run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  L)
    echo "--- code phase (pr): issue #${SUB_NUMBER} ---"
    run_phase_with_recovery "code" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --pr ${BASE_FLAG:-}

    PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "PR number: ${PR_NUMBER}"

    echo "--- review phase (full): PR #${PR_NUMBER} ---"
    run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --full

    echo "--- merge phase: PR #${PR_NUMBER} ---"
    run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  *)
    echo "Error: Unknown Size: ${SIZE}" >&2
    exit 1
    ;;
esac

echo "---"
echo "=== run-auto-sub.sh: Completed sub-issue #${SUB_NUMBER} ==="
print_end_banner "issue" "$SUB_NUMBER" "auto"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit 0
