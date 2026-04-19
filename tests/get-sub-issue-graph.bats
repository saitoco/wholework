#!/usr/bin/env bats

# Tests for scripts/get-sub-issue-graph.sh
# Mocks gh-graphql.sh via WHOLEWORK_SCRIPT_DIR; does not call the real GitHub API.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-sub-issue-graph.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    cat > "$MOCK_DIR/gh-graphql.sh" << 'MOCK_EOF'
#!/bin/bash
echo "$MOCK_GRAPHQL_RESPONSE"
MOCK_EOF
    chmod +x "$MOCK_DIR/gh-graphql.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# Helper: build sub-issues JSON for the mock
# Usage: make_response <json-nodes-array>
make_response() {
    local nodes="$1"
    printf '{"data":{"repository":{"issue":{"subIssues":{"nodes":%s}}}}}\n' "$nodes"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: non-numeric argument" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "success: empty graph outputs empty arrays" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(make_response '[]')"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    result=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['execution_order'])")
    [ "$result" = "[]" ]
}

@test "success: linear chain A to B" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(make_response '[
      {"number":101,"title":"Sub 1","state":"OPEN","blockedBy":{"nodes":[]}},
      {"number":102,"title":"Sub 2","state":"OPEN","blockedBy":{"nodes":[{"number":101}]}}
    ]')"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    level0=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(d['execution_order'][0]))")
    level1=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sorted(d['execution_order'][1]))")
    [ "$level0" = "[101]" ]
    [ "$level1" = "[102]" ]
}

@test "success: orphaned blocked_by is filtered out" {
    export MOCK_GRAPHQL_RESPONSE
    # 101 blocked by 999 which is not in the sub-issues list — should be treated as independent
    MOCK_GRAPHQL_RESPONSE="$(make_response '[
      {"number":101,"title":"Sub 1","state":"OPEN","blockedBy":{"nodes":[{"number":999}]}}
    ]')"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    independent=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['independent'])")
    [[ "$independent" == *"101"* ]]
}

@test "error: cycle detection exits non-zero" {
    export MOCK_GRAPHQL_RESPONSE
    # 101 blocked by 102, 102 blocked by 101 — circular dependency
    MOCK_GRAPHQL_RESPONSE="$(make_response '[
      {"number":101,"title":"Sub 1","state":"OPEN","blockedBy":{"nodes":[{"number":102}]}},
      {"number":102,"title":"Sub 2","state":"OPEN","blockedBy":{"nodes":[{"number":101}]}}
    ]')"
    run bash "$SCRIPT" 100
    [ "$status" -ne 0 ]
}
