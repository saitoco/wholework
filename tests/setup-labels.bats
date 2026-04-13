#!/usr/bin/env bats

# Tests for setup-labels.sh
# Mocks the gh command by placing it at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/setup-labels.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_CALL_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "success: creates 11 labels" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # gh label create must be called 11 times (6 phase/* + triaged + 3 type/* + fix-cycle)
    [ "$(grep -c 'label create' "$GH_CALL_LOG")" -eq 11 ]
}

@test "success: each label uses --force flag" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -s "$GH_CALL_LOG" ]
    # All 11 calls must include --force
    force_count=$(grep -c -- '--force' "$GH_CALL_LOG")
    [ "$force_count" -eq 11 ]
}

@test "success: correct label names" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q 'label create phase/issue' "$GH_CALL_LOG"
    grep -q 'label create phase/spec' "$GH_CALL_LOG"
    grep -q 'label create phase/ready' "$GH_CALL_LOG"
    grep -q 'label create phase/code' "$GH_CALL_LOG"
    grep -q 'label create phase/review' "$GH_CALL_LOG"
    grep -q 'label create phase/verify' "$GH_CALL_LOG"
    grep -q 'label create triaged' "$GH_CALL_LOG"
    grep -q 'label create type/bug' "$GH_CALL_LOG"
    grep -q 'label create type/feature' "$GH_CALL_LOG"
    grep -q 'label create type/task' "$GH_CALL_LOG"
    grep -q 'label create fix-cycle' "$GH_CALL_LOG"
}

@test "success: correct colors (without # prefix)" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # phase/* labels use 1B4F8A, triage-related use unique colors
    [ "$(grep -c -- '--color 1B4F8A' "$GH_CALL_LOG")" -eq 6 ]
    grep -q -- '--color 0E8A16' "$GH_CALL_LOG"
    grep -q -- '--color D73A4A' "$GH_CALL_LOG"
    grep -q -- '--color 0075CA' "$GH_CALL_LOG"
    grep -q -- '--color E4E669' "$GH_CALL_LOG"
}

@test "success: completion message includes label count" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"11"* ]]
}

@test "error: gh command failure propagates" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
}
