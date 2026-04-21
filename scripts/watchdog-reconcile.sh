#!/bin/bash
# watchdog-reconcile.sh - Post-kill state reconciler for run-*.sh scripts
# Verifies expected state after a watchdog kill (exit 143).
# Exits 0 if state was reached (success), 143 if not yet reached, 2 on error.
#
# Usage:
#   watchdog-reconcile.sh <phase> <issue_number> [--pr <pr_number>]
#
# Phases:
#   issue       triaged label exists on the issue
#   spec        spec file exists under spec-path + phase/ready or later label
#   code-patch  origin/main has a commit matching "closes #<issue_number>"
#   code-pr     an open PR for issue-<issue_number>-* branch exists
#   review      PR has a comment containing "## Review Summary"
#   merge       PR state is MERGED
#   verify      issue is CLOSED or has phase/verify or phase/done label
#
# bash 3.2+ compatible (no declare -A, no mapfile)

set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

_usage() {
  echo "Usage: watchdog-reconcile.sh <phase> <issue_number> [--pr <pr_number>]" >&2
  echo "Phases: issue, spec, code-patch, code-pr, review, merge, verify" >&2
}

if [[ $# -lt 2 ]]; then
  _usage
  exit 2
fi

PHASE="$1"
ISSUE_NUMBER="$2"
PR_NUMBER=""
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      if [[ -z "${2:-}" ]]; then
        echo "watchdog-reconcile: --pr requires a PR number" >&2
        exit 2
      fi
      PR_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "watchdog-reconcile: unknown option: $1" >&2
      _usage
      exit 2
      ;;
  esac
done

if ! echo "$ISSUE_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "watchdog-reconcile: invalid issue number: $ISSUE_NUMBER" >&2
  exit 2
fi

_reconcile_issue() {
  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || {
    echo "watchdog-reconcile: gh issue view failed for #$ISSUE_NUMBER" >&2
    exit 2
  }
  echo "$labels" | grep -q "^triaged$"
}

_reconcile_spec() {
  local spec_path
  spec_path=$("$SCRIPT_DIR/get-config-value.sh" spec-path "docs/spec" 2>/dev/null) || spec_path="docs/spec"

  local spec_file
  spec_file=$(ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)
  if [[ -z "$spec_file" ]]; then
    return 1
  fi

  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || {
    echo "watchdog-reconcile: gh issue view failed for #$ISSUE_NUMBER" >&2
    exit 2
  }
  echo "$labels" | grep -qE '^phase/(ready|code|review|merge|verify|done)$'
}

_reconcile_code_patch() {
  git fetch origin main --quiet 2>/dev/null || {
    echo "watchdog-reconcile: git fetch failed" >&2
    exit 2
  }
  git log origin/main --oneline --grep="closes #${ISSUE_NUMBER}" 2>/dev/null | grep -q .
}

_find_code_worktree() {
  local repo_root
  repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
  local worktree_base="$repo_root/.claude/worktrees"

  # Primary: code+issue-N (run-code.sh managed)
  if [[ -d "$worktree_base/code+issue-${ISSUE_NUMBER}" ]]; then
    echo "$worktree_base/code+issue-${ISSUE_NUMBER}"
    return 0
  fi

  # Fallback: issue-N-* (SKILL.md pr-route naming convention)
  local dir
  for dir in "$worktree_base/issue-${ISSUE_NUMBER}-"*; do
    if [[ -d "$dir" ]]; then
      echo "$dir"
      return 0
    fi
  done

  return 1
}

_reconcile_code_pr() {
  # Stage 1: open PR exists (check both naming patterns used by SKILL.md and run-code.sh)
  local pr_count
  pr_count=$(gh pr list --head "issue-${ISSUE_NUMBER}-*" --state open --json number -q 'length' 2>/dev/null) || {
    echo "watchdog-reconcile: gh pr list failed for issue #$ISSUE_NUMBER" >&2
    exit 2
  }
  if [[ "${pr_count:-0}" -eq 0 ]]; then
    local pr_count2
    pr_count2=$(gh pr list --head "code+issue-${ISSUE_NUMBER}" --state open --json number -q 'length' 2>/dev/null) || true
    pr_count="${pr_count2:-0}"
  fi
  if [[ "${pr_count:-0}" -gt 0 ]]; then
    return 0
  fi

  # Stage 2: worktree with implementation commits exists — push + create PR
  local worktree_dir
  worktree_dir=$(_find_code_worktree) || {
    echo "watchdog-reconcile: no worktree found for issue #$ISSUE_NUMBER, cannot reconcile" >&2
    return 1
  }

  local has_commit
  has_commit=$(git -C "$worktree_dir" log --oneline 2>/dev/null | grep "closes #${ISSUE_NUMBER}") || true
  if [[ -z "$has_commit" ]]; then
    echo "watchdog-reconcile: worktree exists but no 'closes #${ISSUE_NUMBER}' commit found" >&2
    return 1
  fi

  echo "watchdog-reconcile: stage 2 recovery — pushing branch and creating PR for issue #$ISSUE_NUMBER" >&2
  local branch
  branch=$(git -C "$worktree_dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    echo "watchdog-reconcile: failed to detect branch in worktree $worktree_dir" >&2
    return 1
  }

  if ! git -C "$worktree_dir" push origin HEAD 2>/dev/null; then
    echo "watchdog-reconcile: git push failed for branch $branch" >&2
    return 1
  fi

  if ! gh pr create \
    --head "$branch" \
    --base main \
    --title "(watchdog recovery) Issue #${ISSUE_NUMBER}" \
    --body "Auto-created by watchdog-reconcile after watchdog kill.

closes #${ISSUE_NUMBER}" 2>/dev/null; then
    echo "watchdog-reconcile: gh pr create failed for branch $branch" >&2
    return 1
  fi

  return 0
}

_reconcile_review() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "watchdog-reconcile: review phase requires --pr <pr_number>" >&2
    exit 2
  fi
  local comments
  comments=$(gh pr view "$PR_NUMBER" --json comments -q '.comments[].body' 2>/dev/null) || {
    echo "watchdog-reconcile: gh pr view failed for PR #$PR_NUMBER" >&2
    exit 2
  }
  echo "$comments" | grep -q "## Review Summary"
}

_reconcile_merge() {
  if [[ -z "$PR_NUMBER" ]]; then
    echo "watchdog-reconcile: merge phase requires --pr <pr_number>" >&2
    exit 2
  fi
  local state
  state=$(gh pr view "$PR_NUMBER" --json state -q '.state' 2>/dev/null) || {
    echo "watchdog-reconcile: gh pr view failed for PR #$PR_NUMBER" >&2
    exit 2
  }
  [[ "$state" == "MERGED" ]]
}

_reconcile_verify() {
  local state
  state=$(gh issue view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null) || {
    echo "watchdog-reconcile: gh issue view failed for #$ISSUE_NUMBER" >&2
    exit 2
  }
  if [[ "$state" == "CLOSED" ]]; then
    return 0
  fi

  local labels
  labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || {
    echo "watchdog-reconcile: gh issue view failed for #$ISSUE_NUMBER" >&2
    exit 2
  }
  echo "$labels" | grep -qE '^phase/(verify|done)$'
}

_dispatch() {
  local phase="$1"
  local reconcile_fn

  case "$phase" in
    issue)      reconcile_fn="_reconcile_issue" ;;
    spec)       reconcile_fn="_reconcile_spec" ;;
    code-patch) reconcile_fn="_reconcile_code_patch" ;;
    code-pr)    reconcile_fn="_reconcile_code_pr" ;;
    review)     reconcile_fn="_reconcile_review" ;;
    merge)      reconcile_fn="_reconcile_merge" ;;
    verify)     reconcile_fn="_reconcile_verify" ;;
    *)
      echo "watchdog-reconcile: unknown phase: $phase" >&2
      _usage
      exit 2
      ;;
  esac

  if $reconcile_fn; then
    echo "watchdog: kill but state reconciled, treating as success" >&2
    exit 0
  else
    echo "watchdog: kill and state not reached, manual intervention required" >&2
    exit 143
  fi
}

_dispatch "$PHASE"
