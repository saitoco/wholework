#!/usr/bin/env bats

# Tests for run-verify.sh
# Mock claude command by placing it at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-verify.sh"

setup() {
    # Isolate test from repo .wholework.yml
    echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
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
if [[ "$1" == "pr" && "$2" == "list" && "$*" == *"--head"* ]]; then
  # Default: no associated PR found (patch route)
  echo ""
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
  exit 0
fi
if [[ "$1" == "run" && "$2" == "list" ]]; then
  # Default: no CI runs found (patch route, skip CI wait)
  echo ""
  exit 0
fi
if [[ "$1" == "run" && "$2" == "watch" ]]; then
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
    grep -q -- "--model sonnet" "$CLAUDE_CALL_LOG"
    grep -q -- "--dangerously-skip-permissions" "$CLAUDE_CALL_LOG"
    # Should use direct prompt, not skill invocation (/verify 123)
    ! grep -q -- "-p /verify 123" "$CLAUDE_CALL_LOG"

    # Verify ANTHROPIC_MODEL environment variable was set
    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
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

@test "false-positive: VERIFY_FAILED in body text does not cause non-zero exit" {
    # Claude outputs VERIFY_FAILED embedded mid-line in body text (not at line start)
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "$@" >> "$CLAUDE_CALL_LOG"
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "This AC mentions the VERIFY_FAILED scenario from issue #393"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
}

@test "success: skips CI wait when no associated PR found and no CI runs (patch route)" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"No CI runs found for main branch (patch route), skipping CI wait"* ]]
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
if [[ "$1" == "pr" && "$2" == "list" && "$*" == *"--head"* ]]; then
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

@test "patch route: does not wait on prior merged PR when no branch PR exists" {
    # Simulate: --head returns empty (no branch PR), but a run exists on main.
    # Expected: wait-ci-checks.sh is NOT called; main branch CI wait is attempted.
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
if [[ "$1" == "pr" && "$2" == "list" && "$*" == *"--head"* ]]; then
  # No PR for this branch (patch route)
  echo ""
  exit 0
fi
if [[ "$1" == "run" && "$2" == "list" ]]; then
  # Return a run ID for main branch CI wait
  echo "9999"
  exit 0
fi
if [[ "$1" == "run" && "$2" == "watch" ]]; then
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    # wait-ci-checks.sh must NOT have been called (no "Waiting for CI checks on PR" message)
    [[ "$output" != *"Waiting for CI checks on PR"* ]]
    # Main branch CI wait should have been triggered
    [[ "$output" == *"Waiting for main branch CI run #9999 (patch route"* ]]
    [[ "$output" == *"CI run #9999 complete"* ]]
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
    grep -q -- "--dangerously-skip-permissions" "$CLAUDE_CALL_LOG"
}
