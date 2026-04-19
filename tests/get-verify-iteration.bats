#!/usr/bin/env bats

# Tests for get-verify-iteration.sh
# Uses WHOLEWORK_SCRIPT_DIR to inject a mock gh helper.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-verify-iteration.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Default mock gh: no comments
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo ""
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    export PATH="$MOCK_DIR:$PATH"
}

@test "returns 0 when no comments exist" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo ""
exit 0
MOCK_EOF

    run "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "returns N when single marker exists" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
printf "Some comment\n<!-- verify-iteration: 2 -->\nMore text\n"
exit 0
MOCK_EOF

    run "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "returns maximum value when multiple markers exist" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
printf "<!-- verify-iteration: 1 -->\n<!-- verify-iteration: 3 -->\n<!-- verify-iteration: 2 -->\n"
exit 0
MOCK_EOF

    run "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "returns error for non-numeric argument" {
    run "$SCRIPT" "abc"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "returns error when no argument provided" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}
