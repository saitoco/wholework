#!/usr/bin/env bats

# Tests for set-blocked-by.sh
# Mock gh-graphql.sh via MOCK_DIR pattern (WHOLEWORK_SCRIPT_DIR)

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/set-blocked-by.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export WHOLEWORK_CONFIG_PATH=/dev/null

    GRAPHQL_CALL_LOG="$BATS_TEST_TMPDIR/graphql_calls.log"
    export GRAPHQL_CALL_LOG

    cat > "$MOCK_DIR/gh-graphql.sh" << 'MOCK_EOF'
#!/bin/bash
echo "$@" >> "${GRAPHQL_CALL_LOG}"
if [[ "$*" == *"get-issue-id"* ]]; then
    for i in "$@"; do
        if [[ "$prev" == "-F" && "$i" == num=* ]]; then
            NUM="${i#num=}"
            echo "I_node_${NUM}"
        fi
        prev="$i"
    done
    exit 0
fi
if [[ "$*" == *"add-blocked-by"* ]]; then
    echo '{"data":{"addBlockedBy":{"issue":{"number":1}}}}'
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh-graphql.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "--help shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "error: only one argument" {
    run bash "$SCRIPT" 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "success: sets blocked-by relationship" {
    run bash "$SCRIPT" 100 200
    [ "$status" -eq 0 ]
}

@test "success: gh-graphql.sh called with add-blocked-by" {
    run bash "$SCRIPT" 100 200
    [ "$status" -eq 0 ]
    [ -f "$GRAPHQL_CALL_LOG" ]
    grep -q "add-blocked-by" "$GRAPHQL_CALL_LOG"
}

@test "success: get-issue-id called for both issue numbers" {
    run bash "$SCRIPT" 111 222
    [ "$status" -eq 0 ]
    grep -q "num=111" "$GRAPHQL_CALL_LOG"
    grep -q "num=222" "$GRAPHQL_CALL_LOG"
}
