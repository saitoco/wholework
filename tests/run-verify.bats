#!/usr/bin/env bats

# Tests for run-verify.sh
# Mock claude command by placing it at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-verify.sh"

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
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" && "$*" == *"--search"* ]]; then
  # Default: no associated PR found (patch route)
  echo ""
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Mock timeout to pass through (avoids dependency on system timeout availability)
    cat > "$MOCK_DIR/timeout" <<'MOCK'
#!/bin/bash
shift  # Remove the timeout duration argument
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/timeout"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-verify.sh <issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "success: valid issue number calls claude with correct arguments" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    # Verify claude was called with correct arguments
    # Direct SKILL.md body mode: prompt contains ARGUMENTS: 123
    grep -q "ARGUMENTS: 123" "$CLAUDE_CALL_LOG"
    grep -q -- "--model claude-sonnet-4-6" "$CLAUDE_CALL_LOG"
    grep -q -- "--dangerously-skip-permissions" "$CLAUDE_CALL_LOG"
    # Should use direct prompt, not skill invocation (/verify 123)
    ! grep -q -- "-p /verify 123" "$CLAUDE_CALL_LOG"

    # Verify ANTHROPIC_MODEL environment variable was set
    grep -q "ANTHROPIC_MODEL=claude-sonnet-4-6" "$CLAUDE_CALL_LOG"
}

@test "success: output shows start and finish messages" {
    run bash "$SCRIPT" 456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting /verify for Issue #456"* ]]
    [[ "$output" == *"Finished /verify for Issue #456"* ]]
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

@test "error: VERIFY_FAILED marker in output causes non-zero exit" {
    # Override mock claude to output VERIFY_FAILED and exit 0
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "$@" >> "$CLAUDE_CALL_LOG"
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "VERIFY_FAILED"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
}

@test "success: no VERIFY_FAILED marker, exit 0 is preserved" {
    # Default mock outputs nothing special and exits 0
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
}

@test "success: skips CI wait when no associated PR found (patch route)" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"No PR found for issue #123 (patch route), skipping CI wait"* ]]
}

@test "success: calls wait-ci-checks.sh when associated PR is found" {
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
if [[ "$1" == "pr" && "$2" == "list" && "$*" == *"--search"* ]]; then
  echo "99"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"Waiting for CI checks on PR #99"* ]]
    [[ "$output" == *"CI check wait complete for PR #99"* ]]
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
    [[ "$output" == *"Starting /verify for Issue #789"* ]]
    [[ "$output" == *"Finished /verify for Issue #789"* ]]
    [[ "$output" == *"Exit code: 42"* ]]
}
