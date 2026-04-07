#!/usr/bin/env bats

# Tests for gh-check-blocking.sh
# Mock gh and gh-graphql.sh via MOCK_DIR pattern

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/gh-check-blocking.sh"

setup() {
    cd "$PROJECT_ROOT"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Default gh mock
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# gh issue view N --json body -q '.body' -> plain body text
if [[ "$1" == "issue" && "$2" == "view" && "$4" == "--json" && "$5" == "body" ]]; then
    printf '%s\n' "${MOCK_BODY:-}"
    exit 0
fi
# gh issue view N --json state -q '.state' -> plain state value
if [[ "$1" == "issue" && "$2" == "view" && "$4" == "--json" && "$5" == "state" ]]; then
    NUM="$3"
    VAR="MOCK_STATE_${NUM}"
    STATE="${!VAR:-OPEN}"
    echo "${STATE}"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    # Default gh-graphql.sh mock (records add-blocked-by calls)
    cat > "$MOCK_DIR/gh-graphql.sh" << 'MOCK_EOF'
#!/bin/bash
# --cache --query get-issue-id -F num=N --jq ...
if [[ "$*" == *"get-issue-id"* ]]; then
    for i in "$@"; do
        if [[ "$prev" == "-F" && "$i" == num=* ]]; then
            NUM="${i#num=}"
            echo "I_issue_${NUM}"
        fi
        prev="$i"
    done
    exit 0
fi
# --query add-blocked-by
if [[ "$*" == *"add-blocked-by"* ]]; then
    echo "$@" >> "${BATS_TEST_TMPDIR}/graphql_calls.log"
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

@test "exit 0: no Blocked by in body" {
    export MOCK_BODY="This issue has no blocking."
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "exit 0: blocker is CLOSED" {
    export MOCK_BODY="Blocked by #200"
    export MOCK_STATE_200="CLOSED"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLOSED - skipped"* ]]
}

@test "exit 2: blocker is OPEN" {
    export MOCK_BODY="Blocked by #300"
    export MOCK_STATE_300="OPEN"
    run bash "$SCRIPT" 100
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKING: #300 (OPEN)"* ]]
}

@test "exit 2 with --dry-run: mutation not called" {
    export MOCK_BODY="Blocked by #400"
    export MOCK_STATE_400="OPEN"
    run bash "$SCRIPT" 100 --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKING: #400 (OPEN)"* ]]
    # mutation log should not exist
    [ ! -f "${BATS_TEST_TMPDIR}/graphql_calls.log" ]
}

@test "exit 2: mutation called for OPEN blocker" {
    export MOCK_BODY="Blocked by #500"
    export MOCK_STATE_500="OPEN"
    run bash "$SCRIPT" 100
    [ "$status" -eq 2 ]
    [ -f "${BATS_TEST_TMPDIR}/graphql_calls.log" ]
    [[ "$(cat "${BATS_TEST_TMPDIR}/graphql_calls.log")" == *"add-blocked-by"* ]]
}

@test "exit 0: multiple blockers all CLOSED" {
    export MOCK_BODY="Blocked by #601
Blocked by #602"
    export MOCK_STATE_601="CLOSED"
    export MOCK_STATE_602="CLOSED"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [[ "$output" == *"601"* ]]
    [[ "$output" == *"602"* ]]
}

@test "case insensitive: blocked by lowercase detected" {
    export MOCK_BODY="blocked by #700"
    export MOCK_STATE_700="OPEN"
    run bash "$SCRIPT" 100
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKING: #700 (OPEN)"* ]]
}
