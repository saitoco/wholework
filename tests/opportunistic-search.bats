#!/usr/bin/env bats

# Tests for opportunistic-search.sh
# Mock gh issue list / gh issue view

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/opportunistic-search.sh"

setup() {
    cd "$PROJECT_ROOT"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Default gh mock (can be overridden per test)
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# gh issue list --label "phase/verify" --state closed --json number --limit 50
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    echo "${MOCK_ISSUE_LIST:-[]}"
    exit 0
fi
# gh issue view N --json body -q .body
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    ISSUE_NUM="$3"
    VARNAME="MOCK_ISSUE_BODY_${ISSUE_NUM}"
    echo "${!VARNAME}"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: unknown option" {
    run bash "$SCRIPT" --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "error: multiple skill names" {
    run bash "$SCRIPT" /issue /spec
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "dry-run: outputs empty array and exits 0" {
    run bash "$SCRIPT" /issue --dry-run
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "dry-run: works with --dry-run before skill name" {
    run bash "$SCRIPT" --dry-run /spec
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "success: no issues found returns empty array" {
    export MOCK_ISSUE_LIST="[]"
    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "success: issue with matching condition is returned" {
    export MOCK_ISSUE_LIST='[{"number": 100}]'
    export MOCK_ISSUE_BODY_100='- [ ] /issue skill creates Issue after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    result="$output"
    echo "$result" | jq -e 'length == 1' > /dev/null
    echo "$result" | jq -e '.[0].number == 100' > /dev/null
    [[ "$(echo "$result" | jq -r '.[0].condition')" == *"/issue"* ]]
}

@test "filter: checked condition is excluded" {
    export MOCK_ISSUE_LIST='[{"number": 101}]'
    export MOCK_ISSUE_BODY_101='- [x] /issue skill creates Issue after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "filter: skill name mismatch is excluded" {
    export MOCK_ISSUE_LIST='[{"number": 102}]'
    export MOCK_ISSUE_BODY_102='- [ ] /spec skill creates Spec after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /issue
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "success: multiple conditions from multiple issues" {
    export MOCK_ISSUE_LIST='[{"number": 200},{"number": 201}]'
    export MOCK_ISSUE_BODY_200='- [ ] /spec skill creates file after execution <!-- verify-type: opportunistic -->'
    export MOCK_ISSUE_BODY_201='- [ ] /spec skill creates file after execution <!-- verify-type: opportunistic -->
- [x] /spec skill updates list after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /spec
    [ "$status" -eq 0 ]
    result="$output"
    echo "$result" | jq -e 'length == 2' > /dev/null
}

@test "output: condition text strips checkbox markup and HTML comments" {
    export MOCK_ISSUE_LIST='[{"number": 300}]'
    export MOCK_ISSUE_BODY_300='- [ ] /code skill can be verified after execution <!-- verify-type: opportunistic -->'

    run bash "$SCRIPT" /code
    [ "$status" -eq 0 ]
    condition="$(echo "$output" | jq -r '.[0].condition')"
    [[ "$condition" != *"- [ ]"* ]]
    [[ "$condition" != *"<!-- verify-type:"* ]]
    [[ "$condition" == *"/code skill can be verified after execution"* ]]
}
