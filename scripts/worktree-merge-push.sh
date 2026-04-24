#!/bin/bash
# worktree-merge-push.sh - Acquire short-lived patch lock and merge worktree branch + push
#
# Usage: worktree-merge-push.sh [--from <worktree-branch>] [--base <branch>]
#   --from  Branch to merge into base (omit to skip merge; lock+push only)
#   --base  Target branch for push (default: main)

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

FROM_BRANCH=""
BASE_BRANCH="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --from requires a branch name" >&2
        exit 1
      fi
      FROM_BRANCH="$2"
      shift 2
      ;;
    --base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --base requires a branch name" >&2
        exit 1
      fi
      BASE_BRANCH="$2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: worktree-merge-push.sh [--from <worktree-branch>] [--base <branch>]" >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PATCH_LOCK_DIR="${REPO_ROOT}/.tmp/claude-auto-patch-lock"

acquire_lock() {
  local yml_timeout
  yml_timeout=$("$SCRIPT_DIR/get-config-value.sh" patch-lock-timeout "" 2>/dev/null || true)
  { echo "$yml_timeout" | grep -qE '^[0-9]+$' && [[ "$yml_timeout" -gt 0 ]]; } || yml_timeout=""
  local timeout="${WHOLEWORK_PATCH_LOCK_TIMEOUT:-${yml_timeout:-300}}"
  local log_interval="${WHOLEWORK_PATCH_LOCK_LOG_INTERVAL:-30}"
  local elapsed=0
  local last_log=0
  local existing_pid=""

  mkdir -p "$(dirname "$PATCH_LOCK_DIR")"
  while ! mkdir "$PATCH_LOCK_DIR" 2>/dev/null; do
    existing_pid=$(cat "$PATCH_LOCK_DIR/pid" 2>/dev/null || true)
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
      echo "waiting for lock held by pid=${existing_pid:-unknown} (age=${elapsed}s)" >&2
      last_log=$elapsed
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "$$" > "${PATCH_LOCK_DIR}/pid"
  trap 'rm -rf "$PATCH_LOCK_DIR" 2>/dev/null || true' EXIT
  echo "Patch lock acquired: ${PATCH_LOCK_DIR}"
}

acquire_lock

if [[ -n "$FROM_BRANCH" ]]; then
  # See modules/orchestration-fallbacks.md#ff-only-merge-fallback
  if ! git merge "$FROM_BRANCH" --ff-only; then
    echo "FF merge failed, attempting git pull --rebase origin ${BASE_BRANCH}..." >&2
    git pull --rebase origin "$BASE_BRANCH"
    git merge "$FROM_BRANCH" --ff-only
  fi

  # See modules/orchestration-fallbacks.md#conflict-marker-residual
  # Use git grep to limit scope to tracked files only (avoids scanning outside repo root)
  conflict_output=$(git grep -l '^<<<<<<' 2>/dev/null || true)
  if [[ -n "$conflict_output" ]]; then
    echo "Error: Conflict markers remain. Please resolve conflicts manually then push." >&2
    exit 1
  fi
fi

git push origin "$BASE_BRANCH"
