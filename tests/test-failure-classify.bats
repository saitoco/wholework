#!/usr/bin/env bats

# Tests for test-failure-classify.sh
# No WHOLEWORK_SCRIPT_DIR mock needed (script does not call sibling scripts).

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/test-failure-classify.sh"

@test "classify: snapshot failure pattern outputs 'snapshot' with status 0" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    cat > "$LOG_FILE" <<'EOF'
FAIL  tests/snapshots.test.js
  - renders component correctly
    snapshot doesn't match stored snapshot
    expected snapshot to be equal to stored value
    Run with --update-snapshot to update
EOF
    run bash "$SCRIPT" --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "snapshot" ]
}

@test "classify: mock failure pattern outputs 'mock' with status 0" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    cat > "$LOG_FILE" <<'EOF'
FAIL  tests/api.test.js
  - calls fetchData with correct args
    expected calls: 1
    actual calls: 0
    not called with expected arguments
EOF
    run bash "$SCRIPT" --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "mock" ]
}

@test "classify: fixture failure pattern outputs 'fixture' with status 0" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    cat > "$LOG_FILE" <<'EOF'
FAIL  tests/parser.test.js
  - parses status field
    AssertionError: expected "active", got "inactive"
EOF
    run bash "$SCRIPT" --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "fixture" ]
}

@test "classify: logic failure outputs 'logic' with status 1" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    cat > "$LOG_FILE" <<'EOF'
FAIL  tests/calculator.test.js
  - adds two numbers correctly
    TypeError: Cannot read properties of null (reading 'value')
    at Calculator.add (src/calculator.js:12:22)
EOF
    run bash "$SCRIPT" --log "$LOG_FILE"
    [ "$status" -eq 1 ]
    [ "$output" = "logic" ]
}

@test "classify: infra failure (command not found) outputs 'infra' with status 1" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    cat > "$LOG_FILE" <<'EOF'
bats: /usr/local/bin/node: command not found
Error: Cannot find module 'jest'
EOF
    run bash "$SCRIPT" --log "$LOG_FILE"
    [ "$status" -eq 1 ]
    [ "$output" = "infra" ]
}

@test "classify: infra takes priority over other patterns" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    cat > "$LOG_FILE" <<'EOF'
command not found: bats
snapshot doesn't match stored snapshot
EOF
    run bash "$SCRIPT" --log "$LOG_FILE"
    [ "$status" -eq 1 ]
    [ "$output" = "infra" ]
}

@test "classify: missing --log argument exits non-zero" {
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--log"* ]]
}

@test "classify: --log with nonexistent file exits non-zero" {
    run bash "$SCRIPT" --log /nonexistent/path/test.log
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}
