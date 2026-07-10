#!/usr/bin/env bats

# Tests for hook-worktree-path-guard.sh
# Validates PreToolUse block/allow decisions for Edit/Write/NotebookEdit/Read
# calls depending on cwd (inside/outside a worktree) and file_path (relative,
# worktree-local absolute, or parent-repo absolute).

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/hook-worktree-path-guard.sh"

setup() {
    FIXTURE_PARENT="$BATS_TEST_TMPDIR/parentrepo"
    FIXTURE_WORKTREE="$FIXTURE_PARENT/.claude/worktrees/test-issue"
    mkdir -p "$FIXTURE_WORKTREE/docs"
    mkdir -p "$FIXTURE_PARENT/docs"
}

teardown() {
    rm -rf "$FIXTURE_PARENT"
}

@test "inside worktree + parent-repo absolute path -> exit 2 (block)" {
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_PARENT")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 2 ]
    [[ "$output" == *"hook-worktree-path-guard"* ]]
}

@test "inside worktree + worktree absolute path -> exit 0 (allow)" {
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_WORKTREE")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
}

@test "inside worktree + relative path -> exit 0 (allow)" {
    cd "$FIXTURE_WORKTREE"
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"docs/foo.md"}}'
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
}

@test "outside worktree + any path -> exit 0 (allow)" {
    cd "$FIXTURE_PARENT"
    INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_PARENT")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
}

@test "inside worktree + NotebookEdit + parent-repo absolute notebook_path -> exit 2 (block)" {
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s/docs/foo.ipynb"}}' "$FIXTURE_PARENT")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 2 ]
    [[ "$output" == *"hook-worktree-path-guard"* ]]
}

@test "inside worktree + Read + parent-repo absolute path -> exit 2 (block)" {
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_PARENT")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 2 ]
    [[ "$output" == *"hook-worktree-path-guard"* ]]
}

@test "inside worktree + Read + worktree absolute path -> exit 0 (allow)" {
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_WORKTREE")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
}

@test "inside worktree + parent-repo absolute path -> emits worktree-path-block event" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/events.jsonl"
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_PARENT")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 2 ]
    [ -f "$AUTO_EVENTS_LOG" ]
    grep -q "worktree-path-block" "$AUTO_EVENTS_LOG"
}

@test "inside worktree + parent-repo absolute path -> event log defaults under parent repo .tmp (not worktree-local)" {
    unset AUTO_EVENTS_LOG
    cd "$FIXTURE_WORKTREE"
    INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/foo.md"}}' "$FIXTURE_PARENT")
    run bash -c "echo '$INPUT' | \"$SCRIPT\""
    [ "$status" -eq 2 ]
    [ -f "$FIXTURE_PARENT/.tmp/auto-events.jsonl" ]
    [ ! -f "$FIXTURE_WORKTREE/.tmp/auto-events.jsonl" ]
}
