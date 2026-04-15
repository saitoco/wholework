#!/usr/bin/env bats

# Tests for get-issue-priority.sh
# Mock external commands (gh) by placing them at the front of PATH
# gh-graphql.sh is used as-is; only the gh command is mocked

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-issue-priority.sh"

setup() {
    cd "$PROJECT_ROOT"
    export GH_GRAPHQL_CACHE_DIR="$BATS_TEST_TMPDIR/gh-graphql-cache"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

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
    if [ -n "$MOCK_GRAPHQL_RESPONSE" ]; then
        echo "$MOCK_GRAPHQL_RESPONSE"
    else
        echo '{"data":{"repository":{"issue":{"projectItems":{"nodes":[]}}}}}'
    fi
    exit 0
fi
# Response for: gh issue view N --json labels -q '.labels[].name'
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    if [ -n "$MOCK_LABEL_OUTPUT" ]; then
        echo "$MOCK_LABEL_OUTPUT"
    fi
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# GraphQL response helper: with Priority field
graphql_with_priority() {
    local priority="$1"
    echo "{\"data\":{\"repository\":{\"issue\":{\"projectItems\":{\"nodes\":[{\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Priority\"},\"value\":\"${priority}\"}]}}]}}}}}"
}

# GraphQL response helper: without Priority field
graphql_without_priority() {
    echo '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"fieldValues":{"nodes":[]}}]}}}}}'
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

@test "success: get priority from project field" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_priority "high")"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = "high" ]
}

@test "success: get all valid priority values from project field" {
    for priority in urgent high medium low; do
        rm -rf "$GH_GRAPHQL_CACHE_DIR"
        export MOCK_GRAPHQL_RESPONSE
        MOCK_GRAPHQL_RESPONSE="$(graphql_with_priority "$priority")"
        run bash "$SCRIPT" 101
        [ "$status" -eq 0 ]
        [ "$output" = "$priority" ]
    done
}

@test "success: fallback to label when project field has no priority" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_priority)"
    export MOCK_LABEL_OUTPUT="priority/medium"
    run bash "$SCRIPT" 102
    [ "$status" -eq 0 ]
    [ "$output" = "medium" ]
}

@test "success: label prefix stripped correctly" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_priority)"
    export MOCK_LABEL_OUTPUT="priority/urgent"
    run bash "$SCRIPT" 103
    [ "$status" -eq 0 ]
    [ "$output" = "urgent" ]
}

@test "error: no priority in project field or labels" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_priority)"
    # MOCK_LABEL_OUTPUT not set, so no labels
    run bash "$SCRIPT" 104
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "error: invalid priority label value is treated as unset" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_priority)"
    export MOCK_LABEL_OUTPUT="priority/INVALID"
    run bash "$SCRIPT" 106
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "success: project field takes priority over label" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_priority "urgent")"
    export MOCK_LABEL_OUTPUT="priority/low"
    run bash "$SCRIPT" 105
    [ "$status" -eq 0 ]
    [ "$output" = "urgent" ]
}
