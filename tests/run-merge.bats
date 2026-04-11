#!/usr/bin/env bats

# Tests for run-merge.sh
# Mock claude command by placing it at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-merge.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying claude calls
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "$@" >> "$CLAUDE_CALL_LOG"
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test PR title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/pull/88"
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
    [[ "$output" == *"Usage: run-merge.sh <pr-number>"* ]]
}

@test "error: non-numeric PR number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: PR number must be numeric: abc"* ]]
}

@test "success: valid PR number calls claude with correct arguments" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    # Verify claude was called with correct arguments
    # Direct SKILL.md body mode: prompt contains ARGUMENTS: 123
    grep -q "ARGUMENTS: 123" "$CLAUDE_CALL_LOG"
    grep -q -- "--model claude-sonnet-4-6" "$CLAUDE_CALL_LOG"
    grep -q -- "--dangerously-skip-permissions" "$CLAUDE_CALL_LOG"
    # Should use direct prompt, not skill invocation (/merge 123)
    ! grep -q -- "-p /merge 123" "$CLAUDE_CALL_LOG"

    # Verify ANTHROPIC_MODEL environment variable was set
    grep -q "ANTHROPIC_MODEL=claude-sonnet-4-6" "$CLAUDE_CALL_LOG"
}

@test "success: output shows start and finish messages" {
    run bash "$SCRIPT" 456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting /merge for PR #456"* ]]
    [[ "$output" == *"Finished /merge for PR #456"* ]]
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
    [[ "$output" == *"Starting /merge for PR #789"* ]]
    [[ "$output" == *"Finished /merge for PR #789"* ]]
    [[ "$output" == *"Exit code: 42"* ]]
}
