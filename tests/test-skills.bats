#!/usr/bin/env bats

# Tests for test-skills.sh
# Mocks python3 to control the exit code of validate-skill-syntax.py

REAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/test-skills.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # File to log python3 call arguments
    PYTHON3_CALL_LOG="$BATS_TEST_TMPDIR/python3_calls.log"
    export PYTHON3_CALL_LOG
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "success: validate-skill-syntax.py passes" {
    cat > "$MOCK_DIR/python3" <<MOCK
#!/bin/bash
echo "\$@" > "$PYTHON3_CALL_LOG"
echo "All skills valid"
exit 0
MOCK
    chmod +x "$MOCK_DIR/python3"

    run bash "$REAL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All tests complete"* ]]

    # validate-skill-syntax.py and skills/ directory must be passed as arguments
    grep -q "validate-skill-syntax.py" "$PYTHON3_CALL_LOG"
    grep -q "skills/" "$PYTHON3_CALL_LOG"
}

@test "error: validate-skill-syntax.py fails" {
    cat > "$MOCK_DIR/python3" <<MOCK
#!/bin/bash
echo "\$@" > "$PYTHON3_CALL_LOG"
echo "Syntax error found" >&2
exit 1
MOCK
    chmod +x "$MOCK_DIR/python3"

    run bash "$REAL_SCRIPT"
    [ "$status" -ne 0 ]
}
