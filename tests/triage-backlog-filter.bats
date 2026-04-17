#!/usr/bin/env bats

# triage-backlog-filter.sh tests

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/triage-backlog-filter.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Default gh issue list response (5 issues)
    GH_ISSUE_LIST_RESPONSE='[
        {"number":1,"title":"Issue 1","labels":[]},
        {"number":2,"title":"Issue 2","labels":[]},
        {"number":3,"title":"Issue 3","labels":[{"name":"triaged"}]},
        {"number":4,"title":"Issue 4","labels":[]},
        {"number":5,"title":"Issue 5","labels":[]}
    ]'
    export GH_ISSUE_LIST_RESPONSE

    # gh mock
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    echo "$GH_ISSUE_LIST_RESPONSE"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "includes all untriaged issues" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Issues 1, 2, 4, 5: no triaged label -> included
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
    [[ "$output" == *"4"* ]]
    [[ "$output" == *"5"* ]]
}

@test "excludes issues with triaged label" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    # Issue 3: has triaged label -> excluded
    ! echo "$output" | grep -q "^3$"
}

@test "respects --limit option" {
    run bash "$SCRIPT" --limit 1
    [ "$status" -eq 0 ]
    # Only 1 line of output
    line_count=$(echo "$output" | grep -c '[0-9]')
    [ "$line_count" -eq 1 ]
}

@test "outputs nothing when all issues are triaged" {
    GH_ISSUE_LIST_RESPONSE='[
        {"number":1,"title":"Issue 1","labels":[{"name":"triaged"}]},
        {"number":2,"title":"Issue 2","labels":[{"name":"triaged"}]}
    ]'
    export GH_ISSUE_LIST_RESPONSE

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "passes --assignee flag to gh issue list" {
    RECEIVED_ARGS=""
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    echo "$*" >> "$BATS_TEST_TMPDIR/gh_args.txt"
    echo "$GH_ISSUE_LIST_RESPONSE"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --assignee testuser
    [ "$status" -eq 0 ]
    grep -q "\-\-assignee testuser" "$BATS_TEST_TMPDIR/gh_args.txt"
}

@test "passes --no-assignee flag to gh issue list" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    echo "$*" >> "$BATS_TEST_TMPDIR/gh_args.txt"
    echo "$GH_ISSUE_LIST_RESPONSE"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --no-assignee
    [ "$status" -eq 0 ]
    grep -q "\-\-no-assignee" "$BATS_TEST_TMPDIR/gh_args.txt"
}

@test "returns error when --assignee has no value" {
    run bash "$SCRIPT" --assignee
    [ "$status" -ne 0 ]
    [[ "$output" == *"--assignee"* ]] || [[ "$stderr" == *"--assignee"* ]]
}

@test "includes issues with phase/* labels when not triaged" {
    GH_ISSUE_LIST_RESPONSE='[
        {"number":1,"title":"Issue 1","labels":[]},
        {"number":2,"title":"Issue 2","labels":[{"name":"phase/verify"}]},
        {"number":3,"title":"Issue 3","labels":[{"name":"phase/code"}]},
        {"number":4,"title":"Issue 4","labels":[{"name":"triaged"}]}
    ]'
    export GH_ISSUE_LIST_RESPONSE

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "^1$"
    echo "$output" | grep -q "^2$"
    echo "$output" | grep -q "^3$"
    ! echo "$output" | grep -q "^4$"
}
