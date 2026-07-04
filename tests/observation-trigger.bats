#!/usr/bin/env bats

# Tests for observation-trigger.sh
# Mock opportunistic-search.sh via WHOLEWORK_SCRIPT_DIR; mock gh via PATH

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/observation-trigger.sh"

setup() {
    cd "$PROJECT_ROOT"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "gh called: $*" >> "$BATS_TEST_TMPDIR/gh-calls.log"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    cat > "$MOCK_DIR/opportunistic-search.sh" << 'MOCK_EOF'
#!/bin/bash
echo "${MOCK_SEARCH_OUTPUT:-[]}"
exit "${MOCK_SEARCH_EXIT:-0}"
MOCK_EOF
    chmod +x "$MOCK_DIR/opportunistic-search.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: missing --event argument" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--event"* ]]
}

@test "error: --event without value" {
    run bash "$SCRIPT" --event
    [ "$status" -eq 1 ]
    [[ "$output" == *"--event requires an argument"* ]]
}

@test "error: unknown argument" {
    run bash "$SCRIPT" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown argument"* ]]
}

@test "dry-run: exits 0 without calling opportunistic-search.sh" {
    run bash "$SCRIPT" --event pr-review-full --dry-run
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-calls.log" ]
}

@test "success: no matches exits silently without posting comments" {
    export MOCK_SEARCH_OUTPUT="[]"
    run bash "$SCRIPT" --event auto-run
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-calls.log" ]
}

@test "success: single match posts one comment" {
    export MOCK_SEARCH_OUTPUT='[{"number": 42, "condition": "watchdog-kill event is observed"}]'
    run bash "$SCRIPT" --event watchdog-kill
    [ "$status" -eq 0 ]
    grep -q "issue comment 42" "$BATS_TEST_TMPDIR/gh-calls.log"
    grep -q "watchdog-kill" "$BATS_TEST_TMPDIR/gh-calls.log"
    [ "$output" = "42" ]
}

@test "success: multiple matches post one comment each" {
    export MOCK_SEARCH_OUTPUT='[{"number": 10, "condition": "first"},{"number": 20, "condition": "second"}]'
    run bash "$SCRIPT" --event fix-cycle
    [ "$status" -eq 0 ]
    grep -q "issue comment 10" "$BATS_TEST_TMPDIR/gh-calls.log"
    grep -q "issue comment 20" "$BATS_TEST_TMPDIR/gh-calls.log"
    [[ "$output" == *"10"* ]]
    [[ "$output" == *"20"* ]]
}

@test "dedup: same issue with multiple matching conditions posts one comment" {
    export MOCK_SEARCH_OUTPUT='[{"number": 875, "condition": "first"},{"number": 875, "condition": "second"}]'
    run bash "$SCRIPT" --event auto-run
    [ "$status" -eq 0 ]
    [ "$(grep -c "issue comment 875" "$BATS_TEST_TMPDIR/gh-calls.log")" -eq 1 ]
    [ "$output" = "875" ]
}

@test "resilience: opportunistic-search.sh error does not abort trigger" {
    export MOCK_SEARCH_EXIT=1
    export MOCK_SEARCH_OUTPUT=""
    run bash "$SCRIPT" --event pr-review-light
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-calls.log" ]
}
