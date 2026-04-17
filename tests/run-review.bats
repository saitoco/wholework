#!/usr/bin/env bats

# Tests for run-review.sh
# Mock claude command by placing it at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-review.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying claude calls
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
# Check for -p flag and log the prompt presence
for arg in "$@"; do
    case "$arg" in
        -p) echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG" ;;
        --model) echo "FLAG_MODEL=1" >> "$CLAUDE_CALL_LOG" ;;
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
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
    [[ "$output" == *"Usage: run-review.sh <pr-number>"* ]]
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
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_MODEL=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"

    # Verify ANTHROPIC_MODEL environment variable was set
    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
}

@test "success: ARGUMENTS contains --non-interactive flag" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: output shows start and finish messages" {
    run bash "$SCRIPT" 456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting /review for PR #456"* ]]
    [[ "$output" == *"Finished /review for PR #456"* ]]
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

@test "success: --review-only flag is passed through to ARGUMENTS with --non-interactive" {
    run bash "$SCRIPT" 123 --review-only
    [ "$status" -eq 0 ]

    # ARGUMENTS: 123 --review-only --non-interactive should be present
    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --review-only --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --light flag is passed through to ARGUMENTS with --non-interactive" {
    run bash "$SCRIPT" 123 --light
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --light --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --full flag is passed through to ARGUMENTS with --non-interactive" {
    run bash "$SCRIPT" 123 --full
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --full --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: no extra flags includes only --non-interactive in ARGUMENTS" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: wait-ci-checks.sh is called before claude" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"Waiting for CI checks on PR #123"* ]]
    [[ "$output" == *"CI check wait complete for PR #123"* ]]
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
    [[ "$output" == *"Starting /review for PR #789"* ]]
    [[ "$output" == *"Finished /review for PR #789"* ]]
    [[ "$output" == *"Exit code: 42"* ]]
}
