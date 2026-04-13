#!/usr/bin/env bats

# Tests for wait-ci-checks.sh
# Mocks external commands (gh, timeout) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/wait-ci-checks.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    TIMEOUT_CALL_LOG="$BATS_TEST_TMPDIR/timeout_calls.log"
    export TIMEOUT_CALL_LOG

    # Default: timeout passes through to gh (skip duration arg, exec the rest)
    cat > "$MOCK_DIR/timeout" <<'MOCK'
#!/bin/bash
shift  # Remove the timeout duration argument
echo "timeout called: $@" >> "$TIMEOUT_CALL_LOG"
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/timeout"

    # Default: gh pr checks exits 0
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
    echo "All checks passed" >&2
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

@test "error: no PR number argument" {
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: wait-ci-checks.sh <pr-number>"* ]]
}

@test "success: outputs waiting and complete messages" {
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"Waiting for CI checks on PR #88"* ]]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "success: passes PR number to timeout and gh pr checks" {
    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    grep -q "pr checks 99" "$TIMEOUT_CALL_LOG"
}

@test "success: uses WHOLEWORK_CI_TIMEOUT_SEC when set" {
    export WHOLEWORK_CI_TIMEOUT_SEC=42
    run bash "$SCRIPT" 77
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout: 42s"* ]]
}

@test "success: defaults to 1200 when WHOLEWORK_CI_TIMEOUT_SEC is not set" {
    unset WHOLEWORK_CI_TIMEOUT_SEC
    run bash "$SCRIPT" 55
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout: 1200s"* ]]
}

@test "success: continues even when timeout exits non-zero (timeout occurred)" {
    # Override timeout to exit 124 (the exit code timeout uses on timeout)
    cat > "$MOCK_DIR/timeout" <<'MOCK'
#!/bin/bash
exit 124
MOCK
    chmod +x "$MOCK_DIR/timeout"

    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "success: continues even when gh pr checks fails" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}
