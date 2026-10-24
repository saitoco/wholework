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

    # Executing-user lookup (`gh api user`): MOCK_ME is the login it prints; MOCK_ME_FAIL=1 makes
    # it fail. Calls are logged so tests can assert when the lookup does (not) happen.
    USER_CALL_LOG="$BATS_TEST_TMPDIR/user-calls.log"
    : > "$USER_CALL_LOG"
    export USER_CALL_LOG
    export MOCK_ME="alice"
    export MOCK_ME_FAIL=0

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
if [[ "$1" == "api" && "$2" == "user" ]]; then
    echo "api-user-call" >> "$USER_CALL_LOG"
    if [ "${MOCK_ME_FAIL:-0}" = "1" ]; then
        exit 1
    fi
    printf '%s' "${MOCK_ME:-}"
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

# --- Assignee exclusion (Issue #1545) ---
# Fixtures carry `assignees`; alice is the executing user (MOCK_ME), bob is another member.

assignee_issues_json() {
    echo '[{"number":10,"labels":[{"name":"retro/code"}],"assignees":[{"id":"U_dummy","login":"bob","name":"Bob","databaseId":1}]},{"number":11,"labels":[{"name":"retro/code"}],"assignees":[{"id":"U_dummy","login":"alice","name":"Alice","databaseId":2}]},{"number":12,"labels":[{"name":"retro/code"}],"assignees":[]},{"number":13,"labels":[{"name":"retro/code"}],"assignees":null},{"number":14,"labels":[{"name":"retro/code"}]}]'
}

@test "assignee: issue assigned to another member is removed from the result" {
    export MOCK_ISSUE_LIST_JSON="$(assignee_issues_json)"
    run --separate-stderr bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ "$output" = "11
12
13
14" ]
    [[ "$stderr" == *"excluded 1 issue(s) assigned to someone other than the executing user: #10 (bob)"* ]] || false
}

@test "assignee: issue assigned only to the executing user is kept" {
    export MOCK_ISSUE_LIST_JSON="$(assignee_issues_json)"
    run --separate-stderr bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qx "11"
}

@test "assignee: unassigned issues (empty array, null, missing key) are kept" {
    export MOCK_ISSUE_LIST_JSON='[{"number":12,"labels":[{"name":"retro/code"}],"assignees":[]},{"number":13,"labels":[{"name":"retro/code"}],"assignees":null},{"number":14,"labels":[{"name":"retro/code"}]}]'
    run --separate-stderr bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ "$output" = "12
13
14" ]
    [ ! -s "$USER_CALL_LOG" ]
}

@test "assignee: executing user unknown excludes every issue that has an assignee and still exits 0" {
    export MOCK_ISSUE_LIST_JSON="$(assignee_issues_json)"
    export MOCK_ME_FAIL=1
    run --separate-stderr bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ "$output" = "12
13
14" ]
    [[ "$stderr" == *"could not identify the executing user"* ]] || false
}

@test "assignee: an issue that does not match the label is not evaluated and does not trigger the user lookup" {
    export MOCK_ISSUE_LIST_JSON='[{"number":10,"labels":[{"name":"bug"}],"assignees":[{"login":"bob"}]},{"number":12,"labels":[{"name":"retro/code"}],"assignees":[]}]'
    run --separate-stderr bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
    [ ! -s "$USER_CALL_LOG" ]
    [[ "$stderr" != *"#10"* ]] || false
}

@test "assignee: gh api user is not called when no label-matched issue has an assignee" {
    export MOCK_ISSUE_LIST_JSON="$(three_issues_json)"
    run bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ ! -s "$USER_CALL_LOG" ]
}

@test "assignee: no label match means no assignee evaluation at all" {
    export MOCK_ISSUE_LIST_JSON='[{"number":10,"labels":[{"name":"bug"}],"assignees":[{"login":"bob"}]}]'
    run bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -s "$USER_CALL_LOG" ]
}

@test "assignee: excluded issues get no Status GraphQL lookup" {
    export MOCK_ISSUE_LIST_JSON="$(assignee_issues_json)"
    export MOCK_STATUS_BY_NUM="10:Backlog
11:Backlog
12:Backlog"
    run --separate-stderr bash "$SCRIPT" --query "label:retro/* status:Backlog"
    [ "$status" -eq 0 ]
    [ "$output" = "11
12" ]
    [ "$(grep -c 'num=10' "$GRAPHQL_CALL_LOG")" -eq 0 ]
    [ "$(grep -c 'num=11' "$GRAPHQL_CALL_LOG")" -eq 1 ]
}

@test "assignee: works together with a status clause and --exclude" {
    export MOCK_ISSUE_LIST_JSON="$(assignee_issues_json)"
    export MOCK_STATUS_BY_NUM="10:Backlog
11:Backlog
12:Backlog
13:Done"
    run --separate-stderr bash "$SCRIPT" --query "label:retro/* status:Backlog" --exclude "11"
    [ "$status" -eq 0 ]
    [ "$output" = "12" ]
}

@test "assignee: filter failure exits 2 with an evaluation error" {
    local fake_dir="$BATS_TEST_TMPDIR/fake-scripts"
    mkdir -p "$fake_dir"
    printf '#!/bin/bash\necho "boom" >&2\nexit 1\n' > "$fake_dir/filter-other-assignees.sh"
    chmod +x "$fake_dir/filter-other-assignees.sh"
    export MOCK_ISSUE_LIST_JSON="$(assignee_issues_json)"
    WHOLEWORK_SCRIPT_DIR="$fake_dir" run --separate-stderr bash "$SCRIPT" --query "label:retro/*"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    [[ "$stderr" == *"failed to evaluate the assignees of the candidate issues"* ]] || false
}

@test "assignee: header comment documents the exclusion, the unknown-user rule and the exit codes" {
    local header
    header="$(awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$SCRIPT")"
    [[ "$header" == *"executing user"* ]] || false
    [[ "$header" == *"fail-closed"* ]] || false
    [[ "$header" == *"cannot be identified"* ]] || false
    [[ "$header" == *"0  success"* ]] || false
    [[ "$header" == *"1  parse error"* ]] || false
    [[ "$header" == *"2  \`gh issue list\` failed"* ]] || false
}
