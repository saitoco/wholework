#!/usr/bin/env bats

# Tests for run-code.sh
# Mock claude command by placing it at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-code.sh"
SKILLS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/code"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying claude calls
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
# Log all arguments (truncated to avoid huge SKILL.md content)
echo "ARGS_COUNT=$#" >> "$CLAUDE_CALL_LOG"
# Check for -p flag and log the prompt presence
for arg in "$@"; do
    case "$arg" in
        -p) echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG" ;;
        --model) echo "FLAG_MODEL=1" >> "$CLAUDE_CALL_LOG" ;;
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
# Log the prompt content (second argument after -p)
FOUND_P=0
for arg in "$@"; do
    if [[ $FOUND_P -eq 1 ]]; then
        echo "PROMPT_CONTAINS_ARGUMENTS=$(echo "$arg" | grep -o 'ARGUMENTS:.*' | head -1)" >> "$CLAUDE_CALL_LOG"
        break
    fi
    [[ "$arg" == "-p" ]] && FOUND_P=1
done
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-code.sh <issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "success: valid issue number calls claude with --non-interactive" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    # Verify claude was called with -p flag
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_MODEL=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"

    # Verify ARGUMENTS contains --non-interactive (not --auto)
    grep -q "ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"

    # Verify ANTHROPIC_MODEL environment variable was set
    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
}

@test "success: --patch option calls claude with --patch --non-interactive" {
    run bash "$SCRIPT" 123 --patch
    [ "$status" -eq 0 ]

    # Verify ARGUMENTS contains --patch --non-interactive
    grep -q "ARGUMENTS: 123 --patch --non-interactive" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_MODEL=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "success: --patch option shows patch route in output" {
    run bash "$SCRIPT" 456 --patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Route: patch (main direct commit)"* ]]
}

@test "error: invalid option is rejected" {
    run bash "$SCRIPT" 123 --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --unknown"* ]]
}

@test "success: --pr option calls claude with --pr --non-interactive" {
    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]

    # Verify ARGUMENTS contains --pr --non-interactive
    grep -q "ARGUMENTS: 123 --pr --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "error: --full option is not supported by run-code.sh" {
    run bash "$SCRIPT" 123 --full
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --full"* ]]
}

@test "success: output shows start and finish messages" {
    run bash "$SCRIPT" 456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting /code for issue #456"* ]]
    [[ "$output" == *"Finished /code for issue #456"* ]]
    [[ "$output" == *"Model: sonnet"* ]]
    [[ "$output" == *"Permissions: skip (autonomous mode)"* ]]
}

@test "success: CLAUDECODE env var is not inherited by claude subprocess" {
    export CLAUDECODE="parent-session-id"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    # Verify CLAUDECODE was stripped by env -u
    grep -q "CLAUDECODE=__UNSET__" "$CLAUDE_CALL_LOG"
}

@test "success: --base option passes base branch in ARGUMENTS" {
    run bash "$SCRIPT" 123 --base release/v2.0
    [ "$status" -eq 0 ]

    # Verify ARGUMENTS contains --base release/v2.0 --non-interactive
    grep -q "ARGUMENTS: 123 --base release/v2.0 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --patch and --base together pass both flags" {
    run bash "$SCRIPT" 123 --patch --base release/v2.0
    [ "$status" -eq 0 ]

    grep -q "ARGUMENTS: 123 --patch --base release/v2.0 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --base option shows base branch in output" {
    run bash "$SCRIPT" 456 --base release/v2.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Base branch: release/v2.0"* ]]
}

@test "error: --base without branch name is rejected" {
    run bash "$SCRIPT" 123 --base
    [ "$status" -eq 1 ]
    [[ "$output" == *"--base requires a branch name"* ]]
}

@test "cleanup: stale branch detected and cleaned up before execution" {
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "branch" && "$2" == "--list" ]]; then
    echo "  worktree-code+issue-123"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale branch"* ]]
}

@test "error: claude command fails with non-zero exit code" {
    # Override mock claude to exit with code 42
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "$@" >> "$CLAUDE_CALL_LOG"
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
exit 42
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 789
    [ "$status" -eq 42 ]
    [[ "$output" == *"Starting /code for issue #789"* ]]
    [[ "$output" == *"Finished /code for issue #789"* ]]
    [[ "$output" == *"Exit code: 42"* ]]
}

@test "idempotency guard: --pr with no existing PR calls claude normally" {
    # Default mock returns empty for gh pr list → guard not triggered
    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
    grep -q "ARGUMENTS: 123 --pr --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "idempotency guard: --pr with existing PR skips claude and exits 0" {
    # Override gh mock to return JSON for pr list so jq filter drives extraction
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo '[{"headRefName":"worktree-code+issue-123","number":456}]'
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  echo "https://github.com/test/repo/pull/456"
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    [[ "$output" == *"Existing PR #456 detected for issue #123, skipping /code"* ]]
    # claude should NOT have been called
    [ ! -f "$CLAUDE_CALL_LOG" ]
}

@test "idempotency guard: --patch with existing PR calls claude normally" {
    # Override gh mock to return JSON for pr list (guard is skipped for --patch)
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo '[{"headRefName":"worktree-code+issue-123","number":456}]'
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123 --patch
    [ "$status" -eq 0 ]
    # Guard should NOT trigger for --patch route; claude should be called
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
}

@test "idempotency guard: no route flag with existing PR calls claude normally" {
    # Override gh mock to return JSON for pr list (guard is skipped when no route flag)
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo '[{"headRefName":"worktree-code+issue-123","number":456}]'
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    # Guard should NOT trigger when no route flag; claude should be called
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
}

@test "permission-mode: auto in .wholework.yml passes --permission-mode auto" {
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
        --permission-mode) echo "FLAG_PERM_MODE=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"
    echo "permission-mode: auto" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_PERM_MODE=1" "$CLAUDE_CALL_LOG"
    ! grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "permission-mode: bypass in .wholework.yml uses --dangerously-skip-permissions" {
    echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}
