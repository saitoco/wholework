#!/bin/bash
# PreToolUse hook: block Edit/Write/NotebookEdit calls that pass an absolute
# parent-repo path while the session is inside a worktree.
# Exit 0 (allow) except when a worktree-session parent-repo absolute path is detected (exit 2, block).

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

case "$TOOL_NAME" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

[ -z "$FILE_PATH" ] && exit 0

CWD=$(pwd)

case "$CWD" in
  *".claude/worktrees/"*) ;;
  *) exit 0 ;;
esac

WORKTREE_ROOT=$(printf '%s' "$CWD" | sed -E 's|(\.claude/worktrees/[^/]+).*|\1|')
PARENT_REPO=$(printf '%s' "$WORKTREE_ROOT" | sed -E 's|/\.claude/worktrees/[^/]+$||')

case "$FILE_PATH" in
  /*) ;;
  *) exit 0 ;;
esac

case "$FILE_PATH" in
  "$WORKTREE_ROOT"/*|"$WORKTREE_ROOT") exit 0 ;;
esac

case "$FILE_PATH" in
  "$PARENT_REPO"/*)
    echo "hook-worktree-path-guard: blocked $TOOL_NAME on parent-repo absolute path '$FILE_PATH' while inside worktree session at '$CWD'. Use the worktree-local path instead (see modules/worktree-lifecycle.md § Edit/Write path conventions in worktree sessions)." >&2
    exit 2
    ;;
esac

exit 0
