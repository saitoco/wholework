#!/bin/bash
# detect-foreign-worktree.sh - Determine whether CWD is outside any worktree,
# inside the caller's own worktree, or inside a foreign (different-owner) worktree.
#
# Usage: detect-foreign-worktree.sh <worktree-name>
#   <worktree-name>  Same value the caller passes to EnterWorktree's `name` parameter
#                     (e.g. "verify/issue-794")
#
# Output (stdout):
#   none              - not inside any worktree
#   own               - inside the worktree matching <worktree-name>
#   foreign <path>    - inside a different worktree; <path> is the main repo root

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <worktree-name>" >&2
    exit 1
fi

WORKTREE_NAME="$1"

if [ ! -f .git ]; then
    echo "none"
    exit 0
fi

EXPECTED_BRANCH="worktree-${WORKTREE_NAME//\//+}"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [ "$CURRENT_BRANCH" = "$EXPECTED_BRANCH" ]; then
    echo "own"
    exit 0
fi

MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
echo "foreign $MAIN_ROOT"
exit 0
