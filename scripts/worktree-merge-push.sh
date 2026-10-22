#!/bin/bash
# worktree-merge-push.sh - Acquire short-lived patch lock and merge worktree branch + push
#
# Usage: worktree-merge-push.sh [--from <worktree-branch>] [--base <branch>]
#   --from  Branch to merge into base (omit to skip merge; lock+push only)
#   --base  Target branch for push (default: main)
#
# The push is delegated to scripts/push-to-base.sh. A non-fast-forward rejection is retried
# (fetch + rebase) as before. When the remote rejects the push by policy ("[remote rejected]":
# branch protection, ruleset, hook), push-to-base.sh lands the commits through a phase-record
# PR instead; this script then realigns the local <base> (and the --from branch) to
# origin/<base>, so the caller's cleanup (git branch -d) keeps working even after a squash or
# rebase merge. When the commits cannot be landed, the local <base> is reset to origin/<base>
# and the script exits non-zero with where the record is kept (branch / PR).
# Invariant: a push rejected by the remote never leaves local <base> ahead of origin/<base>
# (the only exception is lock+push only with no record branch holding the commits, where
# resetting would drop them; the script says so and exits non-zero).
# See modules/worktree-lifecycle.md "Direct push rejected by the remote: phase-record PR".

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

# See modules/orchestration-fallbacks.md#ff-only-merge-fallback
# Shared by both the true-side (BASE_BRANCH checked out here) and false-side
# (ref-to-ref fetch rejected due to divergence) recovery paths: ensure FROM_BRANCH
# contains target_ref, rebasing FROM_BRANCH's worktree onto it when it does not.
# target_ref differs by caller: true side passes the local $BASE_BRANCH (its ff
# judgment is against the local checkout's HEAD); false side passes
# "origin/${BASE_BRANCH}" (its ff judgment is against the ref-to-ref fetch target).
# Exits the script directly on unrecoverable failure (no worktree found, or rebase
# conflict) so callers do not need their own error handling.
rebase_from_branch_onto() {
  local target_ref="$1"
  if git merge-base --is-ancestor "$target_ref" "$FROM_BRANCH" 2>/dev/null; then
    echo "Branch ${FROM_BRANCH} is already on ${target_ref} (is-ancestor=true); skipping rebase" >&2
    return 0
  fi
  local worktree_path
  worktree_path=$(git worktree list --porcelain | awk -v b="refs/heads/${FROM_BRANCH}" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}')
  if [[ -z "$worktree_path" ]]; then
    echo "Error: Cannot locate a worktree for ${FROM_BRANCH} to rebase without touching the shared directory's checkout. Resolve manually." >&2
    exit 1
  fi
  if ! git -C "$worktree_path" rebase "$target_ref"; then
    git -C "$worktree_path" rebase --abort 2>/dev/null || true
    echo "Error: Rebase of ${FROM_BRANCH} onto ${target_ref} failed with conflicts. Resolve manually." >&2
    exit 1
  fi
}

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
        echo "FF merge failed while ${BASE_BRANCH} is checked out; base may have diverged. Checking ancestry..." >&2
        rebase_from_branch_onto "$BASE_BRANCH"
        if ! git merge "$FROM_BRANCH" --ff-only; then
          echo "Error: FF merge failed even though ${BASE_BRANCH} is checked out locally. Resolve manually." >&2
          exit 1
        fi
      fi
    else
      echo "ref-fetch rejected; base may have diverged. Checking ancestry..." >&2
      rebase_from_branch_onto "origin/${BASE_BRANCH}"
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

# Bring local <base> back onto origin/<base> after the push was delegated to a record PR (or
# could not land). Returns non-zero when local <base> could not be aligned.
#   $1 = "fetch": refresh origin/<base> first (needed after a record PR merged);
#        anything else: use the origin/<base> already fetched at the top of this script
realign_base_to_origin() {
  if [[ "${1:-}" == "fetch" ]]; then
    git fetch origin "$BASE_BRANCH" || return 1
  fi
  if git fetch . "+refs/remotes/origin/${BASE_BRANCH}:refs/heads/${BASE_BRANCH}" 2>/dev/null; then
    return 0
  fi
  # git refuses a ref-fetch into a checked-out branch. When <base> is checked out here, move it
  # in place; `git reset --keep` keeps uncommitted changes and changes nothing when they conflict.
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
    git reset --keep "origin/${BASE_BRANCH}" -- || return 1
    return 0
  fi
  return 1
}

# After a record PR landed the commits, move the --from branch onto origin/<base> as well so
# the caller's `git branch -d` succeeds (squash / rebase merges break ancestry).
realign_from_branch_to_origin() {
  [[ -n "$FROM_BRANCH" ]] || return 0
  local wt warn
  warn="Warning: could not move ${FROM_BRANCH} onto origin/${BASE_BRANCH}; remove it with 'git branch -D ${FROM_BRANCH}' after confirming the record PR merged"
  wt=$(git worktree list --porcelain | awk -v b="refs/heads/${FROM_BRANCH}" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}')
  if [[ -n "$wt" ]]; then
    git -C "$wt" reset --keep "origin/${BASE_BRANCH}" -- || echo "$warn" >&2
  else
    git fetch . "+refs/remotes/origin/${BASE_BRANCH}:refs/heads/${FROM_BRANCH}" 2>/dev/null || echo "$warn" >&2
  fi
  return 0
}

MAX_PUSH_RETRY=3
push_count=0
while true; do
  push_rc=0
  push_out=$("$SCRIPT_DIR/push-to-base.sh" --base "$BASE_BRANCH") || push_rc=$?
  if [[ $push_rc -eq 0 ]]; then
    case "$push_out" in
      *"result=record-pr"*)
        record_pr_url=$(printf '%s\n' "$push_out" | sed -n 's/.*result=record-pr url=//p' | tail -n 1)
        echo "Direct push to ${BASE_BRANCH} was rejected by the remote; landed via phase-record PR: ${record_pr_url}" >&2
        if ! realign_base_to_origin fetch; then
          echo "Error: PR ${record_pr_url} landed the commits, but local ${BASE_BRANCH} could not be aligned with origin/${BASE_BRANCH}. Run 'git reset --keep origin/${BASE_BRANCH}' on ${BASE_BRANCH}." >&2
          exit 1
        fi
        realign_from_branch_to_origin
        ;;
    esac
    break
  fi
  if [[ $push_rc -ne 1 ]]; then
    # push-to-base.sh exit 2 (or an unexpected value): the commits could not be landed.
    # push-to-base.sh keeps them on a record branch / PR (its stderr above says where); the
    # --from branch also keeps them. Do not leave local <base> ahead of origin/<base>, unless
    # nothing else holds the commits (lock+push only, no record branch): then leave it as is.
    if [[ -z "$FROM_BRANCH" ]] && [[ -z "$(git branch --contains "$BASE_BRANCH" --list 'wholework-record/*' 2>/dev/null)" ]]; then
      echo "Error: could not land ${BASE_BRANCH} on origin (push-to-base.sh exit ${push_rc}) and no record branch holds the commits; local ${BASE_BRANCH} is left as is. Resolve manually." >&2
      exit 1
    fi
    kept_on="${FROM_BRANCH:-the wholework-record/* branch or PR reported above}"
    if realign_base_to_origin; then
      echo "Error: could not land the commits on origin/${BASE_BRANCH} (push-to-base.sh exit ${push_rc}). Local ${BASE_BRANCH} was reset to origin/${BASE_BRANCH}; the commits are kept on ${kept_on}." >&2
    else
      echo "Error: could not land the commits on origin/${BASE_BRANCH} (push-to-base.sh exit ${push_rc}), and local ${BASE_BRANCH} could not be reset: it is still ahead of origin/${BASE_BRANCH}. Run 'git reset --keep origin/${BASE_BRANCH}' on ${BASE_BRANCH} after confirming the commits are kept on ${kept_on}." >&2
    fi
    exit 1
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
    # Force refspec: local $BASE_BRANCH still holds the pre-race value set by the
    # primary merge path, so a plain (non-force) fetch would reject this update as
    # non-fast-forward -- the rebase above already re-based FROM_BRANCH onto the
    # freshly-fetched origin/$BASE_BRANCH, so overwriting the stale local ref here is
    # the correct outcome, not an unsafe force-push.
    if ! git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"; then
      # git refuses a ref-fetch into a checked-out branch even with the force refspec.
      # When BASE_BRANCH is checked out here, move it onto the rebased FROM_BRANCH in
      # place. `git merge --ff-only` (used by the primary path) cannot work: after the
      # rebase above, local BASE_BRANCH (the pre-rebase tip of FROM_BRANCH) is no longer
      # an ancestor of FROM_BRANCH. `git reset --keep` keeps uncommitted changes and
      # aborts without touching anything when they conflict with the update.
      current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
      if [[ "$current_branch" == "$BASE_BRANCH" ]]; then
        echo "ref-fetch retry rejected because ${BASE_BRANCH} is checked out here; resetting it onto ${FROM_BRANCH} in place (git reset --keep)..." >&2
        if ! git reset --keep "$FROM_BRANCH" --; then
          echo "Error: git reset --keep of ${BASE_BRANCH} onto ${FROM_BRANCH} failed (uncommitted changes in this checkout may conflict). Resolve manually." >&2
          exit 1
        fi
      else
        echo "Error: ref-fetch retry after push-rebase failed. Resolve manually." >&2
        exit 1
      fi
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
