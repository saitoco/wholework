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

@test "parent not found: returns empty title and empty sub_issues" {
    export MOCK_GRAPHQL_RESPONSE='{"data":{"repository":{"issue":null}}}'
    run bash "$SCRIPT" 9999
    [ "$status" -eq 0 ]
    parent_title=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['parent']['title'])")
    [ "$parent_title" = "" ]
    sub_issues=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'])")
    [ "$sub_issues" = "[]" ]
}

@test "sub-issue 0 items: returns empty sub_issues array" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE='{"data":{"repository":{"issue":{"title":"Empty XL","subIssues":{"nodes":[]}}}}}'
    run bash "$SCRIPT" 1000
    [ "$status" -eq 0 ]
    count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['sub_issues']))")
    [ "$count" = "0" ]
}

@test "blockedBy resolved: CLOSED blockedBy item is included in output" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE='{"data":{"repository":{"issue":{"title":"Blocked Parent","subIssues":{"nodes":[{"number":2001,"title":"Resolved sub","state":"OPEN","createdAt":"2026-06-01T00:00:00Z","closedAt":null,"updatedAt":"2026-06-10T00:00:00Z","labels":{"nodes":[]},"blockedBy":{"nodes":[{"number":1999,"state":"CLOSED"}]}}]}}}}}'
    run bash "$SCRIPT" 2000
    [ "$status" -eq 0 ]
    blocked_state=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][0]['blockedBy'][0]['state'])")
    [ "$blocked_state" = "CLOSED" ]
}

@test "state classification fields: returns labels and blockedBy for Done/In-progress/Blocked/Stale/Pending" {
    export MOCK_GRAPHQL_RESPONSE
    MOCK_GRAPHQL_RESPONSE='{"data":{"repository":{"issue":{"title":"State XL","subIssues":{"nodes":[
      {"number":3001,"title":"Done","state":"CLOSED","createdAt":"2026-06-01T00:00:00Z","closedAt":"2026-06-05T00:00:00Z","updatedAt":"2026-06-05T00:00:00Z","labels":{"nodes":[]},"blockedBy":{"nodes":[]}},
      {"number":3002,"title":"In progress","state":"OPEN","createdAt":"2026-06-01T00:00:00Z","closedAt":null,"updatedAt":"2026-06-10T00:00:00Z","labels":{"nodes":[{"name":"phase/code"}]},"blockedBy":{"nodes":[]}},
      {"number":3003,"title":"Blocked","state":"OPEN","createdAt":"2026-06-01T00:00:00Z","closedAt":null,"updatedAt":"2026-06-09T00:00:00Z","labels":{"nodes":[]},"blockedBy":{"nodes":[{"number":3002,"state":"OPEN"}]}},
      {"number":3004,"title":"Stale","state":"OPEN","createdAt":"2026-01-01T00:00:00Z","closedAt":null,"updatedAt":"2026-03-01T00:00:00Z","labels":{"nodes":[{"name":"stale-verify"}]},"blockedBy":{"nodes":[]}},
      {"number":3005,"title":"Pending","state":"OPEN","createdAt":"2026-06-01T00:00:00Z","closedAt":null,"updatedAt":"2026-06-08T00:00:00Z","labels":{"nodes":[]},"blockedBy":{"nodes":[]}}
    ]}}}}}'
    run bash "$SCRIPT" 3000
    [ "$status" -eq 0 ]
    count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['sub_issues']))")
    [ "$count" = "5" ]
    done_state=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][0]['state'])")
    [ "$done_state" = "CLOSED" ]
    in_progress_label=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][1]['labels'][0]['name'])")
    [ "$in_progress_label" = "phase/code" ]
    blocked_by_state=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][2]['blockedBy'][0]['state'])")
    [ "$blocked_by_state" = "OPEN" ]
    stale_label=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][3]['labels'][0]['name'])")
    [ "$stale_label" = "stale-verify" ]
    pending_labels=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sub_issues'][4]['labels'])")
    [ "$pending_labels" = "[]" ]
}
