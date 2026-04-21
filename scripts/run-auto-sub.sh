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

# Process lock (prevents main branch conflicts on patch route)
REPO_ROOT="$(git -C "${SCRIPT_DIR}/.." rev-parse --show-toplevel 2>/dev/null || (cd "${SCRIPT_DIR}/.." && pwd))"
PATCH_LOCK_DIR="${REPO_ROOT}/.tmp/claude-auto-patch-lock"

acquire_patch_lock() {
  local yml_timeout
  yml_timeout=$("$SCRIPT_DIR/get-config-value.sh" patch-lock-timeout "" 2>/dev/null || true)
  { echo "$yml_timeout" | grep -qE '^[0-9]+$' && [[ "$yml_timeout" -gt 0 ]]; } || yml_timeout=""
  local timeout="${WHOLEWORK_PATCH_LOCK_TIMEOUT:-${yml_timeout:-3600}}"
  local log_interval="${WHOLEWORK_PATCH_LOCK_LOG_INTERVAL:-30}"
  local elapsed=0
  local last_log=0
  local existing_pid=""
  local existing_sub=""
  echo "Patch route commits directly to main, running sequentially (waiting for lock...)"
  mkdir -p "$(dirname "$PATCH_LOCK_DIR")"
  while ! mkdir "$PATCH_LOCK_DIR" 2>/dev/null; do
    existing_pid=$(cat "$PATCH_LOCK_DIR/pid" 2>/dev/null || true)
    existing_sub=$(cat "$PATCH_LOCK_DIR/sub-issue" 2>/dev/null || true)
    if [[ -n "$existing_pid" ]] && ! kill -0 "$existing_pid" 2>/dev/null; then
      echo "Stale lock detected (pid=$existing_pid is not running), reclaiming..." >&2
      rm -rf "$PATCH_LOCK_DIR"
      continue
    fi
    if [[ $elapsed -ge $timeout ]]; then
      echo "Error: Patch lock acquisition timeout (${timeout}s)" >&2
      exit 1
    fi
    if [[ $((elapsed - last_log)) -ge $log_interval ]]; then
      echo "waiting for lock held by pid=${existing_pid:-unknown} sub-issue=#${existing_sub:-unknown} (age=${elapsed}s, my sub-issue=#${SUB_NUMBER})" >&2
      last_log=$elapsed
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "$$" > "${PATCH_LOCK_DIR}/pid"
  echo "${SUB_NUMBER}" > "${PATCH_LOCK_DIR}/sub-issue"
  # Set EXIT trap after acquiring lock (prevents releasing another process's lock on early exit)
  trap 'release_patch_lock' EXIT
  echo "Patch lock acquired: ${PATCH_LOCK_DIR}"
}

release_patch_lock() {
  rm -rf "$PATCH_LOCK_DIR" 2>/dev/null || true
}

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
    # Patch route commits directly to main, run sequentially (trap set inside acquire_patch_lock)
    acquire_patch_lock
    "$SCRIPT_DIR/run-code.sh" "$SUB_NUMBER" --patch ${BASE_FLAG:-}
    release_patch_lock

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  S)
    echo "--- code phase (patch): issue #${SUB_NUMBER} ---"
    # Patch route commits directly to main, run sequentially (trap set inside acquire_patch_lock)
    acquire_patch_lock
    "$SCRIPT_DIR/run-code.sh" "$SUB_NUMBER" --patch ${BASE_FLAG:-}
    release_patch_lock

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  M)
    echo "--- code phase (pr): issue #${SUB_NUMBER} ---"
    "$SCRIPT_DIR/run-code.sh" "$SUB_NUMBER" --pr ${BASE_FLAG:-}

    PR_NUMBER=$(gh pr list --head "*issue-${SUB_NUMBER}-*" --json number -q '.[0].number' 2>/dev/null || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "PR number: ${PR_NUMBER}"

    echo "--- review phase (light): PR #${PR_NUMBER} ---"
    "$SCRIPT_DIR/run-review.sh" "$PR_NUMBER" --light

    echo "--- merge phase: PR #${PR_NUMBER} ---"
    "$SCRIPT_DIR/run-merge.sh" "$PR_NUMBER"

    echo "--- verify phase: issue #${SUB_NUMBER} ---"
    run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"
    ;;
  L)
    echo "--- code phase (pr): issue #${SUB_NUMBER} ---"
    "$SCRIPT_DIR/run-code.sh" "$SUB_NUMBER" --pr ${BASE_FLAG:-}

    PR_NUMBER=$(gh pr list --head "*issue-${SUB_NUMBER}-*" --json number -q '.[0].number' 2>/dev/null || true)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: Could not retrieve PR number for issue #${SUB_NUMBER}" >&2
      exit 1
    fi
    echo "PR number: ${PR_NUMBER}"

    echo "--- review phase (full): PR #${PR_NUMBER} ---"
    "$SCRIPT_DIR/run-review.sh" "$PR_NUMBER" --full

    echo "--- merge phase: PR #${PR_NUMBER} ---"
    "$SCRIPT_DIR/run-merge.sh" "$PR_NUMBER"

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
