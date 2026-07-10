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

git fetch origin "$BASE_BRANCH" 2>&1 || echo "Warning: git fetch origin ${BASE_BRANCH} failed; continuing with local refs" >&2

if [[ -n "$FROM_BRANCH" ]]; then
  # See modules/orchestration-fallbacks.md#ff-only-merge-fallback
  # Primary path: a checkout-less ref-to-ref fetch. git itself refuses this when
  # BASE_BRANCH is checked out in any worktree (exit 128) or when it would not be a
  # fast-forward (exit 1) -- giving --ff-only-equivalent safety without touching the
  # shared directory's working tree or HEAD.
  if ! git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"; then
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
      echo "ref-fetch rejected because ${BASE_BRANCH} is checked out here; merging in place instead..." >&2
      if ! git merge "$FROM_BRANCH" --ff-only; then
        echo "Error: FF merge failed even though ${BASE_BRANCH} is checked out locally. Resolve manually." >&2
        exit 1
      fi
    else
      echo "ref-fetch rejected; base may have diverged. Checking ancestry..." >&2
      if git merge-base --is-ancestor "origin/${BASE_BRANCH}" "$FROM_BRANCH" 2>/dev/null; then
        echo "Branch ${FROM_BRANCH} is already on origin/${BASE_BRANCH} (is-ancestor=true); skipping rebase" >&2
      else
        worktree_path=$(git worktree list --porcelain | awk -v b="refs/heads/${FROM_BRANCH}" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}')
        if [[ -n "$worktree_path" ]]; then
          if ! git -C "$worktree_path" rebase "origin/${BASE_BRANCH}"; then
            git -C "$worktree_path" rebase --abort 2>/dev/null || true
            echo "Error: Rebase of ${FROM_BRANCH} onto origin/${BASE_BRANCH} failed with conflicts. Resolve manually." >&2
            exit 1
          fi
        else
          echo "Error: Cannot locate a worktree for ${FROM_BRANCH} to rebase without touching the shared directory's checkout. Resolve manually." >&2
          exit 1
        fi
      fi
      if ! git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"; then
        echo "Error: ref-fetch of ${FROM_BRANCH} into ${BASE_BRANCH} still failed after rebase. Resolve manually." >&2
        exit 1
      fi
    fi
  fi

  # See modules/orchestration-fallbacks.md#conflict-marker-residual
  # Use git grep to limit scope to tracked files only (avoids scanning outside repo root)
  conflict_files=$(git grep -l '^<<<<<<' 2>/dev/null || true)
  if [[ -n "$conflict_files" ]]; then
    echo "Error: Conflict markers remain. Please resolve conflicts manually then push." >&2
    exit 1
  fi
fi

MAX_PUSH_RETRY=3
push_count=0
while true; do
  if git push origin "$BASE_BRANCH"; then
    break
  fi
  push_count=$((push_count + 1))
  if [[ $push_count -ge $MAX_PUSH_RETRY ]]; then
    echo "Error: git push origin ${BASE_BRANCH} failed after ${MAX_PUSH_RETRY} retries. Manual push required." >&2
    exit 1
  fi
  echo "Push rejected (non-fast-forward); retry ${push_count}/${MAX_PUSH_RETRY}: fetching and retrying onto origin/${BASE_BRANCH}..." >&2
  git fetch origin "$BASE_BRANCH"
  if [[ -n "$FROM_BRANCH" ]]; then
    # See modules/orchestration-fallbacks.md#ff-only-merge-fallback
    worktree_path=$(git worktree list --porcelain | awk -v b="refs/heads/${FROM_BRANCH}" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}')
    if [[ -z "$worktree_path" ]]; then
      echo "Error: Cannot locate a worktree for ${FROM_BRANCH} to rebase without touching the shared directory's checkout. Resolve manually." >&2
      exit 1
    fi
    if ! git -C "$worktree_path" rebase "origin/${BASE_BRANCH}"; then
      git -C "$worktree_path" rebase --abort 2>/dev/null || true
      echo "Error: Rebase during push retry failed with conflicts. Resolve manually." >&2
      exit 1
    fi
    if ! git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"; then
      echo "Error: ref-fetch retry after push-rebase failed. Resolve manually." >&2
      exit 1
    fi
  else
    if ! git rebase "origin/${BASE_BRANCH}"; then
      git rebase --abort 2>/dev/null || true
      echo "Error: Rebase during push retry failed with conflicts. Resolve manually." >&2
      exit 1
    fi
  fi
  sleep 1
done
