#!/usr/bin/env bats

# Tests for gh-graphql.sh
# Mock external commands (gh) by placing them at the front of PATH

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/gh-graphql.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying gh calls
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    export GH_GRAPHQL_CACHE_DIR="$BATS_TEST_TMPDIR/gh-graphql-cache"
    CACHE_DIR="$GH_GRAPHQL_CACHE_DIR"
    export CACHE_DIR

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_CALL_LOG"
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf "testowner\ttestrepo\n"
    exit 0
fi
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
    echo '{"data":{"result":"ok"}}'
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "success: query with auto-resolved owner/repo" {
    run bash "$SCRIPT" 'query($owner:String!){repository(owner:$owner){id}}'
    [ "$status" -eq 0 ]
    # gh repo view was called with correct args
    grep -q "repo view --json owner,name --jq" "$GH_CALL_LOG"
    # gh api graphql received auto-resolved owner/repo
    grep -q "api graphql.*-F owner=testowner" "$GH_CALL_LOG"
    grep -q "api graphql.*-F repo=testrepo" "$GH_CALL_LOG"
}

@test "success: query with -F options" {
    run bash "$SCRIPT" 'query($num:Int!){issue(number:$num){id}}' -F num=123
    [ "$status" -eq 0 ]
    grep -q "api graphql.*-F num=123" "$GH_CALL_LOG"
}

@test "success: query with --jq option" {
    run bash "$SCRIPT" 'query{viewer{login}}' --jq '.data.viewer.login'
    [ "$status" -eq 0 ]
    grep -q "api graphql.*--jq .data.viewer.login" "$GH_CALL_LOG"
}

@test "success: explicit owner/repo skips auto-resolve" {
    run bash "$SCRIPT" 'query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){id}}' \
        -F owner=myowner -F repo=myrepo
    [ "$status" -eq 0 ]
    # gh repo view should NOT have been called
    ! grep -q "repo view" "$GH_CALL_LOG"
    # explicit owner/repo should be used
    grep -q "api graphql.*-F owner=myowner" "$GH_CALL_LOG"
    grep -q "api graphql.*-F repo=myrepo" "$GH_CALL_LOG"
}

@test "success: --query get-issue-id resolves named query" {
    run bash "$SCRIPT" --query get-issue-id -F num=123 --jq '.data.repository.issue.id'
    [ "$status" -eq 0 ]
    # gh api graphql was called
    grep -q "api graphql" "$GH_CALL_LOG"
    # query should not contain $( (shell variable detection avoidance)
    local api_call
    api_call=$(grep "api graphql" "$GH_CALL_LOG")
    [[ "$api_call" != *'$('* ]]
}

@test "success: --query get-projects-with-fields resolves named query" {
    run bash "$SCRIPT" --cache --query get-projects-with-fields
    [ "$status" -eq 0 ]
    grep -q "api graphql" "$GH_CALL_LOG"
}

@test "success: --query get-sub-issues resolves named query" {
    run bash "$SCRIPT" --query get-sub-issues -F num=780
    [ "$status" -eq 0 ]
    grep -q "api graphql" "$GH_CALL_LOG"
    local api_call
    api_call=$(grep "api graphql" "$GH_CALL_LOG")
    [[ "$api_call" == *"subIssues"* ]]
}

@test "success: --query get-blocked-by resolves named query" {
    run bash "$SCRIPT" --query get-blocked-by -F num=815
    [ "$status" -eq 0 ]
    grep -q "api graphql" "$GH_CALL_LOG"
    local api_call
    api_call=$(grep "api graphql" "$GH_CALL_LOG")
    [[ "$api_call" == *"blockedBy"* ]]
}

@test "error: --query with unknown name" {
    run bash "$SCRIPT" --query unknown-query-name
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown query name"* ]]
}

@test "error: --query without name argument" {
    run bash "$SCRIPT" --query
    [ "$status" -eq 1 ]
    [[ "$output" == *"--query"* ]]
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: empty query" {
    run bash "$SCRIPT" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty query"* ]]
}

@test "success: backslash-exclamation in query is sanitized" {
    run bash "$SCRIPT" 'query($owner:String\!,$repo:String\!){repository(owner:$owner,name:$repo){id}}'
    [ "$status" -eq 0 ]
    # query passed to gh api graphql should not contain \!
    local api_call
    api_call=$(grep "api graphql" "$GH_CALL_LOG")
    [[ "$api_call" == *'String!'* ]]
    [[ "$api_call" != *'String\!'* ]]
}

# --- Cache tests ---

cache_setup() {
    rm -rf "$CACHE_DIR"
}

cache_teardown() {
    rm -rf "$CACHE_DIR"
}

@test "cache: miss creates cache file and repo-info.tsv" {
    cache_setup
    run bash "$SCRIPT" --cache 'query{viewer{login}}'
    [ "$status" -eq 0 ]
    # cache directory should be created
    [ -d "$CACHE_DIR" ]
    # repo-info.tsv should exist
    [ -f "$CACHE_DIR/repo-info.tsv" ]
    # at least one .json cache file should exist
    local json_count
    json_count=$(find "$CACHE_DIR" -name '*.json' | wc -l | tr -d ' ')
    [ "$json_count" -ge 1 ]
    # gh api graphql should have been called
    grep -q "api graphql" "$GH_CALL_LOG"
    cache_teardown
}

@test "cache: hit skips API call on second run" {
    cache_setup
    # First run: cache miss
    bash "$SCRIPT" --cache 'query{viewer{login}}'
    : > "$GH_CALL_LOG"  # clear call log

    # Second run: cache hit
    run bash "$SCRIPT" --cache 'query{viewer{login}}'
    [ "$status" -eq 0 ]
    # gh api graphql should NOT have been called
    ! grep -q "api graphql" "$GH_CALL_LOG"
    # gh repo view should NOT have been called (repo-info cached)
    ! grep -q "repo view" "$GH_CALL_LOG"
    cache_teardown
}

@test "cache: expired TTL triggers API re-execution" {
    cache_setup
    # First run to populate cache with TTL=1
    bash "$SCRIPT" --cache --cache-ttl 1 'query{viewer{login}}'

    # Wait for TTL to expire
    sleep 2
    : > "$GH_CALL_LOG"

    # Second run: TTL expired
    run bash "$SCRIPT" --cache --cache-ttl 1 'query{viewer{login}}'
    [ "$status" -eq 0 ]
    # gh api graphql should have been called again
    grep -q "api graphql" "$GH_CALL_LOG"
    cache_teardown
}

@test "cache: --cache-clear removes cache directory" {
    cache_setup
    mkdir -p "$CACHE_DIR"
    touch "$CACHE_DIR/test.json"

    run bash "$SCRIPT" --cache-clear
    [ "$status" -eq 0 ]
    [ ! -d "$CACHE_DIR" ]
}

@test "cache: repo-info.tsv hit skips gh repo view" {
    cache_setup
    # First run: populates repo-info cache
    bash "$SCRIPT" --cache 'query{viewer{login}}'
    : > "$GH_CALL_LOG"

    # Invalidate only .json cache files (not repo-info.tsv)
    find "$CACHE_DIR" -name '*.json' -delete

    # Second run: repo-info cached but query not cached
    run bash "$SCRIPT" --cache 'query{viewer{login}}'
    [ "$status" -eq 0 ]
    # gh repo view should NOT have been called (repo-info still cached)
    ! grep -q "repo view" "$GH_CALL_LOG"
    # gh api graphql SHOULD have been called (query cache was deleted)
    grep -q "api graphql" "$GH_CALL_LOG"
    cache_teardown
}

@test "cache: no --cache flag does not create cache files" {
    cache_setup
    run bash "$SCRIPT" 'query{viewer{login}}'
    [ "$status" -eq 0 ]
    [ ! -d "$CACHE_DIR" ]
    cache_teardown
}

@test "cache: --jq filter applied on cache hit" {
    cache_setup
    # First run without --jq to populate cache
    bash "$SCRIPT" --cache 'query{viewer{login}}'
    : > "$GH_CALL_LOG"

    # Second run with --jq on cached data
    run bash "$SCRIPT" --cache 'query{viewer{login}}' --jq '.data.result'
    [ "$status" -eq 0 ]
    # Should return filtered result
    [[ "$output" == *"ok"* ]]
    # API should not have been called
    ! grep -q "api graphql" "$GH_CALL_LOG"
    cache_teardown
}
