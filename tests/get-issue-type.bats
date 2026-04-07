#!/usr/bin/env bats

# Tests for get-issue-type.sh
# Mock external commands (gh) by placing them at the front of PATH
# gh-graphql.sh is used as-is; only the gh command is mocked

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-issue-type.sh"

setup() {
    cd "$PROJECT_ROOT"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Clear cache to prevent cross-test pollution
    rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"

    # Default gh mock (can be overridden per test)
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# Response for: gh repo view --json owner,name --jq ...
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf "testowner\ttestrepo\n"
    exit 0
fi
# Response for: gh api graphql ... (called via --cache without --jq)
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
    if [ -n "${MOCK_GRAPHQL_RESPONSE:-}" ]; then
        echo "$MOCK_GRAPHQL_RESPONSE"
    else
        echo '{"data":{"repository":{"issue":{"issueType":null}}}}'
    fi
    exit 0
fi
# Response for: gh issue view N --json labels -q ...
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    if [ -n "${MOCK_LABEL_OUTPUT:-}" ]; then
        echo "$MOCK_LABEL_OUTPUT"
    else
        echo ""
    fi
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
    rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"
}

# GraphQL response helper: with issueType
graphql_with_type() {
    local type="$1"
    echo "{\"data\":{\"repository\":{\"issue\":{\"issueType\":{\"name\":\"${type}\"}}}}}"
}

# GraphQL response helper: without issueType
graphql_without_type() {
    echo '{"data":{"repository":{"issue":{"issueType":null}}}}'
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: invalid issue number (non-numeric)" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "help: --help shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "success: graphql returns Bug" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_type "Bug")"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = "Bug" ]
}

@test "success: graphql returns Feature" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_type "Feature")"
    run bash "$SCRIPT" 101
    [ "$status" -eq 0 ]
    [ "$output" = "Feature" ]
}

@test "success: graphql returns Task" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_type "Task")"
    run bash "$SCRIPT" 102
    [ "$status" -eq 0 ]
    [ "$output" = "Task" ]
}

@test "success: graphql empty, label type/feature" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_type)"
    export MOCK_LABEL_OUTPUT="type/feature"
    run bash "$SCRIPT" 103
    [ "$status" -eq 0 ]
    [ "$output" = "Feature" ]
}

@test "success: graphql empty, label type/task" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_type)"
    export MOCK_LABEL_OUTPUT="type/task"
    run bash "$SCRIPT" 104
    [ "$status" -eq 0 ]
    [ "$output" = "Task" ]
}

@test "success: graphql empty, label type/bug" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_type)"
    export MOCK_LABEL_OUTPUT="type/bug"
    run bash "$SCRIPT" 105
    [ "$status" -eq 0 ]
    [ "$output" = "Bug" ]
}

@test "success: graphql empty, no type label returns empty string" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_type)"
    # MOCK_LABEL_OUTPUT not set
    run bash "$SCRIPT" 106
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "success: graphql Task takes priority over label type/bug" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_type "Task")"
    export MOCK_LABEL_OUTPUT="type/bug"
    run bash "$SCRIPT" 107
    [ "$status" -eq 0 ]
    [ "$output" = "Task" ]
}
