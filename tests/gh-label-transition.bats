#!/usr/bin/env bats

# Tests for gh-label-transition.sh
# Mock external commands (gh) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/gh-label-transition.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying gh calls
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "help: --help shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "success: transition to code phase" {
    run bash "$SCRIPT" 123 code
    [ "$status" -eq 0 ]
    grep -q "issue edit 123" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/code" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/issue" "$GH_CALL_LOG"
}

@test "success: transition to spec phase" {
    run bash "$SCRIPT" 456 spec
    [ "$status" -eq 0 ]
    grep -q "issue edit 456" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/spec" "$GH_CALL_LOG"
}

@test "success: transition to verify phase" {
    run bash "$SCRIPT" 789 verify
    [ "$status" -eq 0 ]
    grep -q "issue edit 789" "$GH_CALL_LOG"
    grep -q "\-\-add-label phase/verify" "$GH_CALL_LOG"
}

@test "success: remove all phase labels without adding (no target-phase)" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "issue edit 123" "$GH_CALL_LOG"
    grep -q "\-\-remove-label phase/issue" "$GH_CALL_LOG"
    run grep "\-\-add-label" "$GH_CALL_LOG"
    [ "$status" -ne 0 ]
}

@test "success: all valid phases are accepted" {
    for phase in issue spec ready code review verify done; do
        run bash "$SCRIPT" 1 "$phase"
        [ "$status" -eq 0 ]
    done
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number is required"* ]]
}

@test "error: invalid issue number (non-numeric)" {
    run bash "$SCRIPT" abc code
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number must be a positive integer"* ]]
}

@test "error: invalid issue number (zero)" {
    run bash "$SCRIPT" 0 code
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number must be a positive integer"* ]]
}

@test "error: invalid target-phase" {
    run bash "$SCRIPT" 123 invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid phase"* ]]
}
