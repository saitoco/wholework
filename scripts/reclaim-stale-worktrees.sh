#!/bin/bash
# reclaim-stale-worktrees.sh - Inventory and reclaim stale worktrees and orphan
# branches for Issues/PRs that have already completed (CLOSED/MERGED).
#
# Usage: reclaim-stale-worktrees.sh [--apply]
#   (no args)  Dry-run: report only, no deletions performed (default)
#   --apply    Actually perform worktree/branch removal
#
# Safety guards applied before any deletion (see docs/spec/issue-1119-reclaim-stale-worktrees.md):
#   - concurrent-session guard: a locked worktree whose HEAD matches the current
#     main HEAD is excluded (may be in use by a live parallel session)
#   - uncommitted-changes guard: a worktree with non-empty `git status --porcelain`
#     is left in place with a warning instead of being deleted
#   - safe branch deletion: `git branch -d` first; if rejected (squash-merged
#     branch, "not fully merged"), fall back to `-D` only when the branch tip
#     matches the MERGED PR's headRefOid
#
# bash 3.2 compatible (no associative arrays, no mapfile/readarray) so it runs
# under macOS system bash.

set -euo pipefail

APPLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: $0 [--apply]" >&2
      exit 1
      ;;
  esac
done

MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
MAIN_HEAD="$(git -C "$MAIN_ROOT" rev-parse HEAD)"

count_pruned=0
count_reclaimed_wt=0
count_reclaimed_wt_only=0
count_reclaimed_orphan=0
count_excluded=0
count_warned_uncommitted=0
count_warned_diverge=0
count_warned_gh=0
count_skipped=0

PRUNED_LIST=""
RECLAIMED_WT_LIST=""
RECLAIMED_WT_ONLY_LIST=""
RECLAIMED_ORPHAN_LIST=""
EXCLUDED_LIST=""
WARNED_UNCOMMITTED_LIST=""
WARNED_DIVERGE_LIST=""
WARNED_GH_LIST=""
SKIPPED_LIST=""

SEEN_BRANCHES=""

# classify_name: match "<anything>+(issue|pr)-<N>" (covers both the
# "worktree-{phase}+{issue|pr}-{N}" branch form and the "{phase}+{issue|pr}-{N}"
# detached-worktree directory basename form). On match, sets CLASSIFY_KIND
# (issue|pr) and CLASSIFY_NUM; returns 1 on no match.
classify_name() {
  local name="$1"
  if [[ "$name" =~ ^.+\+(issue|pr)-([0-9]+)$ ]]; then
    CLASSIFY_KIND="${BASH_REMATCH[1]}"
    CLASSIFY_NUM="${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# check_completion: sets COMPLETION_STATE (done|not-done|unknown) and, for a
# MERGED PR, COMPLETION_HEAD_REF_OID (used later for safe -D branch deletion).
check_completion() {
  local kind="$1"
  local num="$2"
  COMPLETION_STATE="not-done"
  COMPLETION_HEAD_REF_OID=""
  if [ "$kind" = "issue" ]; then
    local state
    state="$(gh issue view "$num" --json state -q .state 2>/dev/null)" || {
      COMPLETION_STATE="unknown"
      return
    }
    if [ "$state" = "CLOSED" ]; then
      COMPLETION_STATE="done"
    fi
  else
    local json
    json="$(gh pr view "$num" --json state,headRefOid 2>/dev/null)" || {
      COMPLETION_STATE="unknown"
      return
    }
    local state
    state="$(echo "$json" | jq -r '.state')"
    if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
      COMPLETION_STATE="done"
    fi
    if [ "$state" = "MERGED" ]; then
      COMPLETION_HEAD_REF_OID="$(echo "$json" | jq -r '.headRefOid')"
    fi
  fi
}

# delete_branch_safe: `git branch -d`; on rejection, fall back to `-D` only when
# kind=pr and the branch tip matches the MERGED PR's headRefOid. Returns 1 (and
# records a "warned (branch tip diverges)" entry) when neither path applies.
delete_branch_safe() {
  local branch="$1"
  local kind="$2"
  local head_ref_oid="$3"
  if git branch -d "$branch" 2>/dev/null; then
    return 0
  fi
  if [ "$kind" = "pr" ] && [ -n "$head_ref_oid" ]; then
    local branch_tip
    branch_tip="$(git rev-parse "refs/heads/$branch" 2>/dev/null || true)"
    if [ -n "$branch_tip" ] && [ "$branch_tip" = "$head_ref_oid" ] && git branch -D "$branch" 2>/dev/null; then
      return 0
    fi
  fi
  count_warned_diverge=$((count_warned_diverge + 1))
  WARNED_DIVERGE_LIST="${WARNED_DIVERGE_LIST}${branch} (branch tip diverges from merged PR head, or no merged PR found — left in place)
"
  return 1
}

# handle_worktree_entry: apply Steps C-G to one non-main, non-prunable worktree
# record parsed from `git worktree list --porcelain`.
handle_worktree_entry() {
  local path="$1"
  local head="$2"
  local branch="$3"
  local detached="$4"
  local locked="$5"

  local basis
  if [ "$detached" = "true" ]; then
    basis="$(basename "$path")"
  else
    basis="$branch"
    SEEN_BRANCHES="${SEEN_BRANCHES}${branch}
"
  fi

  if ! classify_name "$basis"; then
    count_skipped=$((count_skipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST}${path} (${basis}, unrecognized)
"
    return
  fi

  local kind="$CLASSIFY_KIND"
  local num="$CLASSIFY_NUM"

  check_completion "$kind" "$num"

  if [ "$COMPLETION_STATE" = "unknown" ]; then
    count_warned_gh=$((count_warned_gh + 1))
    WARNED_GH_LIST="${WARNED_GH_LIST}${path} (${kind} #${num}, gh lookup failed)
"
    return
  fi

  if [ "$COMPLETION_STATE" != "done" ]; then
    return
  fi

  # Step E: concurrent-session guard
  if [ "$locked" = "true" ] && [ "$head" = "$MAIN_HEAD" ]; then
    count_excluded=$((count_excluded + 1))
    EXCLUDED_LIST="${EXCLUDED_LIST}${path} (${kind} #${num}, locked + HEAD matches main)
"
    return
  fi

  # Step F: uncommitted-changes guard
  local status_out
  status_out="$(git -C "$path" status --porcelain 2>/dev/null || true)"
  if [ -n "$status_out" ]; then
    local nfiles
    nfiles="$(printf '%s\n' "$status_out" | wc -l | tr -d ' ')"
    count_warned_uncommitted=$((count_warned_uncommitted + 1))
    WARNED_UNCOMMITTED_LIST="${WARNED_UNCOMMITTED_LIST}${path} (uncommitted changes: ${nfiles} files)
"
    return
  fi

  # Step G: reclaim
  if [ "$APPLY" != "true" ]; then
    count_reclaimed_wt=$((count_reclaimed_wt + 1))
    RECLAIMED_WT_LIST="${RECLAIMED_WT_LIST}would reclaim: ${path} (${branch:-detached}, ${kind} #${num}, completed)
"
    return
  fi

  if [ "$locked" = "true" ]; then
    git worktree unlock "$path" 2>/dev/null || true
  fi

  if git worktree remove --force "$path" 2>/dev/null; then
    if [ -n "$branch" ] && ! delete_branch_safe "$branch" "$kind" "$COMPLETION_HEAD_REF_OID"; then
      count_reclaimed_wt_only=$((count_reclaimed_wt_only + 1))
      RECLAIMED_WT_ONLY_LIST="${RECLAIMED_WT_ONLY_LIST}${path} (${branch}, ${kind} #${num}, branch retained)
"
    else
      count_reclaimed_wt=$((count_reclaimed_wt + 1))
      RECLAIMED_WT_LIST="${RECLAIMED_WT_LIST}${path} (${branch:-detached}, ${kind} #${num})
"
    fi
  else
    count_skipped=$((count_skipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST}${path} (worktree remove failed)
"
  fi
}

# --- Step A: mechanically prune registry entries whose directory is already gone ---
prune_output="$(git worktree prune -v 2>&1 || true)"
if [ -n "$prune_output" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    count_pruned=$((count_pruned + 1))
    PRUNED_LIST="${PRUNED_LIST}${line}
"
  done <<< "$prune_output"
fi

# --- Step B/C/D/E/F/G: enumerate and classify remaining worktrees ---
wt_path=""
wt_head=""
wt_branch=""
wt_detached=false
wt_locked=false
wt_prunable=false
first_record=true

flush_record() {
  if [ -z "$wt_path" ]; then
    return
  fi
  if [ "$first_record" = true ]; then
    first_record=false
    return
  fi
  if [ "$wt_prunable" = true ]; then
    # Already handled (or should have been) by `git worktree prune -v` above.
    return
  fi
  handle_worktree_entry "$wt_path" "$wt_head" "$wt_branch" "$wt_detached" "$wt_locked"
}

reset_record() {
  wt_path=""
  wt_head=""
  wt_branch=""
  wt_detached=false
  wt_locked=false
  wt_prunable=false
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      flush_record
      reset_record
      wt_path="${line#worktree }"
      ;;
    "HEAD "*)
      wt_head="${line#HEAD }"
      ;;
    "branch "*)
      wt_branch="${line#branch refs/heads/}"
      ;;
    "detached")
      wt_detached=true
      ;;
    "locked"*)
      wt_locked=true
      ;;
    "prunable"*)
      wt_prunable=true
      ;;
    *)
      : # blank line separator / unrecognized field; ignore
      ;;
  esac
done < <(git worktree list --porcelain)
flush_record

# --- Step H: orphan branches (worktree directory already gone) ---
orphan_branches="$(git branch --list 'worktree-*' --format='%(refname:short)' 2>/dev/null || true)"
if [ -n "$orphan_branches" ]; then
  while IFS= read -r branch; do
    [ -z "$branch" ] && continue
    if printf '%s\n' "$SEEN_BRANCHES" | grep -qxF "$branch"; then
      continue
    fi

    if ! classify_name "$branch"; then
      count_skipped=$((count_skipped + 1))
      SKIPPED_LIST="${SKIPPED_LIST}${branch} (orphan branch, unrecognized)
"
      continue
    fi

    kind="$CLASSIFY_KIND"
    num="$CLASSIFY_NUM"

    check_completion "$kind" "$num"

    if [ "$COMPLETION_STATE" = "unknown" ]; then
      count_warned_gh=$((count_warned_gh + 1))
      WARNED_GH_LIST="${WARNED_GH_LIST}${branch} (${kind} #${num}, gh lookup failed)
"
      continue
    fi

    if [ "$COMPLETION_STATE" != "done" ]; then
      continue
    fi

    if [ "$APPLY" != "true" ]; then
      count_reclaimed_orphan=$((count_reclaimed_orphan + 1))
      RECLAIMED_ORPHAN_LIST="${RECLAIMED_ORPHAN_LIST}would reclaim (orphan branch): ${branch} (${kind} #${num}, completed)
"
      continue
    fi

    if delete_branch_safe "$branch" "$kind" "$COMPLETION_HEAD_REF_OID"; then
      count_reclaimed_orphan=$((count_reclaimed_orphan + 1))
      RECLAIMED_ORPHAN_LIST="${RECLAIMED_ORPHAN_LIST}${branch} (${kind} #${num})
"
    fi
  done <<< "$orphan_branches"
fi

# --- Step I: summary ---
print_section() {
  local title="$1"
  local count="$2"
  local list="$3"
  echo "${title}: ${count}"
  if [ -n "$list" ]; then
    printf '%s' "$list" | sed 's/^/  - /'
  fi
}

echo "=== reclaim-stale-worktrees summary ==="
print_section "pruned" "$count_pruned" "$PRUNED_LIST"
print_section "reclaimed (worktree+branch)" "$count_reclaimed_wt" "$RECLAIMED_WT_LIST"
print_section "reclaimed (worktree only, branch retained)" "$count_reclaimed_wt_only" "$RECLAIMED_WT_ONLY_LIST"
print_section "reclaimed (orphan branch only)" "$count_reclaimed_orphan" "$RECLAIMED_ORPHAN_LIST"
print_section "excluded (concurrent-session-guard)" "$count_excluded" "$EXCLUDED_LIST"
print_section "warned (uncommitted changes)" "$count_warned_uncommitted" "$WARNED_UNCOMMITTED_LIST"
print_section "warned (branch tip diverges)" "$count_warned_diverge" "$WARNED_DIVERGE_LIST"
print_section "warned (gh lookup failed)" "$count_warned_gh" "$WARNED_GH_LIST"
print_section "skipped (unrecognized)" "$count_skipped" "$SKIPPED_LIST"

if [ "$APPLY" != "true" ]; then
  echo ""
  echo "[dry-run] No changes made. Re-run with --apply to perform reclaim."
fi
