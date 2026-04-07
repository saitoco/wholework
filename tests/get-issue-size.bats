#!/usr/bin/env bats

# Tests for get-issue-size.sh
# Mock external commands (gh) by placing them at the front of PATH
# gh-graphql.sh is used as-is; only the gh command is mocked

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-issue-size.sh"

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
    rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"
}

# GraphQL response helper: with Size field
graphql_with_size() {
    local size="$1"
    echo "{\"data\":{\"repository\":{\"issue\":{\"projectItems\":{\"nodes\":[{\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Size\"},\"value\":\"${size}\"}]}}]}}}}}"
}

# GraphQL response helper: without Size field
graphql_without_size() {
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

@test "success: get size from project field" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_size "M")"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = "M" ]
}

@test "success: get all valid size values from project field" {
    for size in XS S M L XL; do
        rm -rf "$PROJECT_ROOT/.tmp/gh-graphql-cache"
        export MOCK_GRAPHQL_RESPONSE
        MOCK_GRAPHQL_RESPONSE="$(graphql_with_size "$size")"
        run bash "$SCRIPT" 101
        [ "$status" -eq 0 ]
        [ "$output" = "$size" ]
    done
}

@test "success: fallback to label when project field has no size" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_size)"
    export MOCK_LABEL_OUTPUT="size/S"
    run bash "$SCRIPT" 102
    [ "$status" -eq 0 ]
    [ "$output" = "S" ]
}

@test "success: label prefix stripped correctly" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_size)"
    export MOCK_LABEL_OUTPUT="size/XL"
    run bash "$SCRIPT" 103
    [ "$status" -eq 0 ]
    [ "$output" = "XL" ]
}

@test "error: no size in project field or labels" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_size)"
    # MOCK_LABEL_OUTPUT not set, so no labels
    run bash "$SCRIPT" 104
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "error: invalid size label value is treated as unset" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_without_size)"
    export MOCK_LABEL_OUTPUT="size/INVALID"
    run bash "$SCRIPT" 106
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
}

@test "success: project field takes priority over label" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(graphql_with_size "L")"
    export MOCK_LABEL_OUTPUT="size/S"
    run bash "$SCRIPT" 105
    [ "$status" -eq 0 ]
    [ "$output" = "L" ]
}
