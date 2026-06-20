#!/bin/bash
# pre-merge-check.sh - Baseline diff classifier for pre-merge checks
# Usage: pre-merge-check.sh <pr-number> [check-name]
# Exit codes: 0 (CLEAN/FIXED/PRE_EXISTING), 1 (env error), 2 (NEW_FAILURE)

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

if [[ $# -lt 1 ]]; then
  echo "Usage: pre-merge-check.sh <pr-number> [check-name]" >&2
  exit 1
fi

PR="$1"
CHECK="${2:-forbidden-expressions}"

# Check dispatch table (modular — extend by adding cases here)
case "$CHECK" in
  forbidden-expressions)
    CHECK_REL="scripts/check-forbidden-expressions.sh"
    ;;
  *)
    echo "Error: unknown check: $CHECK" >&2
    exit 1
    ;;
esac

# Resolve refs from PR metadata
HEAD_REF=$(gh pr view "$PR" --json headRefName -q .headRefName)
if [[ -z "$HEAD_REF" ]]; then
  echo "Error: could not resolve headRefName for PR #$PR" >&2
  exit 1
fi
BASE_REF=$(gh pr view "$PR" --json baseRefName -q .baseRefName)
if [[ -z "$BASE_REF" ]]; then
  echo "Error: could not resolve baseRefName for PR #$PR" >&2
  exit 1
fi

# Fetch both refs so worktree add can reference origin/<ref>
if ! git fetch --quiet origin "$HEAD_REF" "$BASE_REF"; then
  echo "Error: git fetch failed for refs: $HEAD_REF, $BASE_REF" >&2
  exit 1
fi

# Run the check on a given ref in an ephemeral detached worktree.
# Sets _check_exit: 0 = PASS, non-zero = FAIL
run_check_on_ref() {
  local ref="$1"
  local parent_tmp
  parent_tmp=$(mktemp -d)
  local wt="${parent_tmp}/wt"

  if ! git worktree add --detach "$wt" "origin/${ref}" >/dev/null 2>&1; then
    rm -rf "$parent_tmp" 2>/dev/null || true
    echo "Error: git worktree add failed for origin/$ref" >&2
    exit 1
  fi

  if [[ ! -f "$wt/$CHECK_REL" ]]; then
    git worktree remove --force "$wt" >/dev/null 2>&1 || true
    rm -rf "$parent_tmp" 2>/dev/null || true
    echo "Error: check script not found in worktree at $wt/$CHECK_REL" >&2
    exit 1
  fi

  _check_exit=0
  ( cd "$wt" && bash "$CHECK_REL" ) >/dev/null 2>&1 || _check_exit=$?

  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$parent_tmp" 2>/dev/null || true
}

# Run on base branch (baseline)
run_check_on_ref "$BASE_REF"
baseline_status=$_check_exit

# Run on head branch (current)
run_check_on_ref "$HEAD_REF"
current_status=$_check_exit

# Classify result and emit outcome
if [[ "$baseline_status" -eq 0 && "$current_status" -ne 0 ]]; then
  echo "NEW_FAILURE: $CHECK check passes on $BASE_REF but fails on $HEAD_REF"
  exit 2
elif [[ "$baseline_status" -ne 0 && "$current_status" -ne 0 ]]; then
  echo "PRE_EXISTING: $CHECK check fails on both $BASE_REF and $HEAD_REF (pre-existing failure)"
  exit 0
elif [[ "$baseline_status" -ne 0 && "$current_status" -eq 0 ]]; then
  echo "FIXED: $CHECK check was failing on $BASE_REF but now passes on $HEAD_REF"
  exit 0
else
  echo "CLEAN: $CHECK check passes on both $BASE_REF and $HEAD_REF"
  exit 0
fi
