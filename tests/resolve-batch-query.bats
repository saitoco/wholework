#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for resolve-batch-query.sh
# gh-graphql.sh is used as-is (like tests/get-issue-size.bats); only the `gh` binary
# (issue list / repo view / api graphql) is mocked via PATH.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/resolve-batch-query.sh"

setup() {
    cd "$PROJECT_ROOT"
    export GH_GRAPHQL_CACHE_DIR="$BATS_TEST_TMPDIR/gh-graphql-cache"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    GRAPHQL_CALL_LOG="$BATS_TEST_TMPDIR/graphql-calls.log"
    : > "$GRAPHQL_CALL_LOG"
    export GRAPHQL_CALL_LOG

    # Default: 3 open issues. Overridden per test via MOCK_ISSUE_LIST_JSON /
    # MOCK_ISSUE_LIST_EXIT / MOCK_STATUS_BY_NUM (newline "num:status" pairs, "num:FAIL" to
    # make that num's graphql call fail).
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    if [ "${MOCK_ISSUE_LIST_EXIT:-0}" != "0" ]; then
        echo "mock: gh issue list failed" >&2
        exit "$MOCK_ISSUE_LIST_EXIT"
    fi
    echo "${MOCK_ISSUE_LIST_JSON:-[]}"
    exit 0
fi
if [[ "$1" == "repo" && "$2" == "view" ]]; then
    printf "testowner\ttestrepo\n"
    exit 0
fi
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
    shift 2
    NUM=""
    JQ_EXPR=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -F)
                case "$2" in num=*) NUM="${2#num=}";; esac
                shift 2 ;;
            --jq) JQ_EXPR="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    echo "graphql-call num=$NUM" >> "$GRAPHQL_CALL_LOG"
    STATUS_LINE=$(printf '%s\n' "$MOCK_STATUS_BY_NUM" | grep "^${NUM}:")
    STATUS_VAL="${STATUS_LINE#*:}"
    if [ "$STATUS_VAL" = "FAIL" ]; then
        echo "mock: graphql failed" >&2
        exit 1
    fi
    if [ -z "$STATUS_VAL" ]; then
        RESPONSE='{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"fieldValues":{"nodes":[]}}]}}}}}'
    else
        RESPONSE="{\"data\":{\"repository\":{\"issue\":{\"projectItems\":{\"nodes\":[{\"fieldValues\":{\"nodes\":[{\"field\":{\"name\":\"Status\"},\"value\":\"${STATUS_VAL}\"}]}}]}}}}}"
    fi
    if [ -n "$JQ_EXPR" ]; then
        echo "$RESPONSE" | jq "$JQ_EXPR"
    else
        echo "$RESPONSE"
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

three_issues_json() {
    echo '[{"number":10,"labels":[{"name":"retro/code"}]},{"number":11,"labels":[{"name":"bug"}]},{"number":12,"labels":[{"name":"retro/spec"},{"name":"other"}]}]'
}

@test "label glob match: selects only issues with a matching label" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    run bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ "$output" = "10
12" ]
}

@test "status clause: narrows down to exact match" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    export MOCK_STATUS_BY_NUM="10:Backlog
12:Done"
    run bash "$SCRIPT" --query "label:retro/* status:Backlog"
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "no status clause: does not call graphql at all" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    run bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ ! -s "$GRAPHQL_CALL_LOG" ]
}

@test "--exclude: removes already-processed issue numbers" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    run bash "$SCRIPT" --query "label:retro/*" --exclude "10"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
}

@test "zero matches: exit 0 with empty stdout" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    run bash "$SCRIPT" --query "label:nonexistent/*"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "--query not specified: exit 1" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolve-batch-query:"* ]]
}

@test "unknown key: exit 1" {
    run bash "$SCRIPT" --query "foo:bar"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown key"* ]]
}

@test "no label clause: exit 1" {
    run bash "$SCRIPT" --query "status:Backlog"
    [ "$status" -eq 1 ]
    [[ "$output" == *"label:"* ]]
}

@test "gh issue list failure: exit 2" {
    export MOCK_ISSUE_LIST_EXIT=1
    run bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 2 ]
}

@test "status resolution failure: fail-closed exclusion, overall exit 0" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    export MOCK_STATUS_BY_NUM="10:FAIL
12:Backlog"
    run --separate-stderr bash "$SCRIPT" --query "label:retro/* status:Backlog"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
    [[ "$stderr" == *"excluding"* ]]
}

@test "query with whitespace: accepted as a single quoted argument" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    export MOCK_STATUS_BY_NUM="10:Backlog"
    run --separate-stderr bash "$SCRIPT" --query "label:retro/* status:Backlog"
    [ "$status" -eq 0 ]
    [ "$output" = "10" ]
}

@test "status value containing whitespace: unsupported, exit 1 as documented" {
    run --separate-stderr bash "$SCRIPT" --query "label:retro/* status:In progress"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"resolve-batch-query:"* ]]
    [[ "$stderr" == *"unknown key"* ]]
}
