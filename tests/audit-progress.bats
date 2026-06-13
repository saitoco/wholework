#!/usr/bin/env bats

# Tests for scripts/get-sub-issue-progress.sh
# Mocks gh-graphql.sh via WHOLEWORK_SCRIPT_DIR; does not call the real GitHub API.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-sub-issue-progress.sh"

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
# Usage: make_response <parent-title> <json-nodes-array>
make_response() {
    local title="$1"
    local nodes="$2"
    printf '{"data":{"repository":{"issue":{"title":"%s","subIssues":{"nodes":%s}}}}}\n' "$title" "$nodes"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "success: empty XL returns empty sub_issues array" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(make_response "Empty XL" '[]')"
    run bash "$SCRIPT" 1000
    [ "$status" -eq 0 ]
    result=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'])")
    [ "$result" = "[]" ]
}

@test "success: mixed states - CLOSED, OPEN+phase/code, OPEN+stale-verify, OPEN+blockedBy" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(make_response "Mixed XL" '[
      {
        "number": 1001,
        "title": "Done sub-issue",
        "state": "CLOSED",
        "createdAt": "2026-06-01T00:00:00Z",
        "closedAt": "2026-06-05T12:00:00Z",
        "updatedAt": "2026-06-05T12:00:00Z",
        "labels": {"nodes": [{"name": "phase/verify"}]},
        "blockedBy": {"nodes": []}
      },
      {
        "number": 1002,
        "title": "In progress sub-issue",
        "state": "OPEN",
        "createdAt": "2026-06-01T00:00:00Z",
        "closedAt": null,
        "updatedAt": "2026-06-10T12:00:00Z",
        "labels": {"nodes": [{"name": "phase/code"}]},
        "blockedBy": {"nodes": []}
      },
      {
        "number": 1003,
        "title": "Stale sub-issue",
        "state": "OPEN",
        "createdAt": "2026-01-01T00:00:00Z",
        "closedAt": null,
        "updatedAt": "2026-03-01T00:00:00Z",
        "labels": {"nodes": [{"name": "stale-verify"}]},
        "blockedBy": {"nodes": []}
      },
      {
        "number": 1004,
        "title": "Blocked sub-issue",
        "state": "OPEN",
        "createdAt": "2026-06-01T00:00:00Z",
        "closedAt": null,
        "updatedAt": "2026-06-08T00:00:00Z",
        "labels": {"nodes": []},
        "blockedBy": {"nodes": [{"number": 1002, "state": "OPEN"}]}
      }
    ]')"
    run bash "$SCRIPT" 1000
    [ "$status" -eq 0 ]
    count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['sub_issues']))")
    [ "$count" = "4" ]
    parent_title=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['parent']['title'])")
    [ "$parent_title" = "Mixed XL" ]
    closed_state=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][0]['state'])")
    [ "$closed_state" = "CLOSED" ]
}

@test "success: all done - all sub-issues CLOSED" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE="$(make_response "All Done XL" '[
      {
        "number": 2001,
        "title": "Completed 1",
        "state": "CLOSED",
        "createdAt": "2026-06-01T00:00:00Z",
        "closedAt": "2026-06-03T00:00:00Z",
        "updatedAt": "2026-06-03T00:00:00Z",
        "labels": {"nodes": []},
        "blockedBy": {"nodes": []}
      },
      {
        "number": 2002,
        "title": "Completed 2",
        "state": "CLOSED",
        "createdAt": "2026-06-01T00:00:00Z",
        "closedAt": "2026-06-04T00:00:00Z",
        "updatedAt": "2026-06-04T00:00:00Z",
        "labels": {"nodes": []},
        "blockedBy": {"nodes": []}
      }
    ]')"
    run bash "$SCRIPT" 2000
    [ "$status" -eq 0 ]
    count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['sub_issues']))")
    [ "$count" = "2" ]
    all_closed=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(all(s['state']=='CLOSED' for s in d['sub_issues']))")
    [ "$all_closed" = "True" ]
}
