#!/usr/bin/env bats

# Tests for filter-other-assignees.sh
# gh is replaced by a stub placed at the front of PATH; no network access happens.
# Fixtures use dummy logins (alice = the executing user, bob, Copilot, dependabot[bot]).

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/filter-other-assignees.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    export GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    : > "$GH_CALL_LOG"

    export MOCK_ME="alice"
    export MOCK_ME_FAIL=""

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$*" >> "$GH_CALL_LOG"
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
    [ "${MOCK_ME_FAIL:-}" = "1" ] && exit 1
    printf '%s' "$MOCK_ME"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    IN="$BATS_TEST_TMPDIR/in.json"
}

# Run the script with the given JSON on stdin (stdout and stderr separated).
run_filter() {
    printf '%s' "$1" > "$IN"
    run --separate-stderr bash "$SCRIPT" < "$IN"
}

nums() {
    printf '%s' "$output" | jq -r '[.[].number | tostring] | join(",")'
}

BOB='{"id":"U_dummy","login":"bob","name":"Bob","databaseId":1}'
ALICE='{"id":"U_dummy","login":"alice","name":"Alice","databaseId":2}'
COPILOT='{"id":"BOT_dummy","login":"Copilot","name":"","databaseId":3}'
DEPENDABOT='{"id":"BOT_dummy","login":"dependabot[bot]","name":"","databaseId":4}'

@test "filter: issue assigned only to another member is excluded" {
    run_filter "[{\"number\":1,\"assignees\":[$BOB]}]"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "filter: issue assigned only to the executing user is kept" {
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]}]"
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1" ]
}

@test "filter: unassigned issues (empty array, null, missing key) are kept" {
    run_filter '[{"number":1,"assignees":[]},{"number":2,"assignees":null},{"number":3}]'
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1,2,3" ]
}

@test "filter: issue assigned to the executing user and another member is excluded" {
    run_filter "[{\"number\":1,\"assignees\":[$ALICE,$BOB]}]"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "filter: bot and Copilot assignees count as another member" {
    run_filter "[{\"number\":1,\"assignees\":[$DEPENDABOT]},{\"number\":2,\"assignees\":[$COPILOT]}]"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "filter: login comparison is case-insensitive" {
    export MOCK_ME="Alice"
    run_filter '[{"number":1,"assignees":[{"login":"ALICE"}]}]'
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1" ]
}

@test "filter: order and every field of kept issues are preserved and stdout is a JSON array" {
    local json="[{\"number\":5,\"title\":\"keep me\",\"labels\":[{\"name\":\"triaged\"}],\"createdAt\":\"2026-01-01T00:00:00Z\",\"assignees\":[]},{\"number\":4,\"assignees\":[$BOB]},{\"number\":3,\"title\":\"mine\",\"assignees\":[$ALICE]}]"
    run_filter "$json"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e 'type == "array"' > /dev/null
    [ "$(nums)" = "5,3" ]
    [ "$(printf '%s' "$output" | jq -c '.[0]')" = '{"number":5,"title":"keep me","labels":[{"name":"triaged"}],"createdAt":"2026-01-01T00:00:00Z","assignees":[]}' ]
}

@test "filter: stderr names the excluded issue numbers and logins" {
    run_filter "[{\"number\":12,\"assignees\":[$BOB,$COPILOT]},{\"number\":15,\"assignees\":[$DEPENDABOT]}]"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Info: excluded 2 issue(s) assigned to someone other than the executing user"* ]] || false
    [[ "$stderr" == *"#12 (bob, Copilot)"* ]] || false
    [[ "$stderr" == *"#15 (dependabot[bot])"* ]] || false
}

@test "filter: no summary line when nothing is excluded" {
    run_filter '[{"number":1,"assignees":[]}]'
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "lookup: executing user unknown (gh api user fails) excludes every issue that has an assignee" {
    export MOCK_ME_FAIL=1
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]},{\"number\":2,\"assignees\":[$BOB]},{\"number\":3,\"assignees\":[]},{\"number\":4}]"
    [ "$status" -eq 0 ]
    [ "$(nums)" = "3,4" ]
    [ "$(printf '%s\n' "$stderr" | grep -c '^Warning: could not identify the executing user')" -eq 1 ]
    [[ "$stderr" == *"the executing user could not be identified"* ]] || false
}

@test "lookup: executing user unknown keeps unassigned issues and prints no warning when nobody is assigned" {
    export MOCK_ME_FAIL=1
    run_filter '[{"number":1,"assignees":[]},{"number":2,"assignees":null}]'
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1,2" ]
    [ -z "$stderr" ]
}

@test "lookup: empty gh api user output is treated as unknown" {
    export MOCK_ME=""
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]}]"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    [[ "$stderr" == *"could not identify the executing user"* ]] || false
}

@test "lookup: only the first line of a multi-line gh api user output is used" {
    export MOCK_ME=$'alice\nsecond'
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]}]"
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1" ]
}

@test "lookup: CRLF at the end of the gh api user output is removed" {
    export MOCK_ME=$'alice\r\n'
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]}]"
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1" ]
}

@test "lookup: malformed login from gh api user is treated as unknown" {
    export MOCK_ME='al ice!'
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]}]"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    [[ "$stderr" == *"could not identify the executing user"* ]] || false
}

@test "lookup: a 101 character login is treated as unknown and a 100 character login is accepted" {
    local long100 long101
    long100="$(printf 'a%.0s' $(seq 1 100))"
    long101="${long100}a"
    export MOCK_ME="$long101"
    run_filter "[{\"number\":1,\"assignees\":[{\"login\":\"$long101\"}]}]"
    [ "$output" = "[]" ]
    export MOCK_ME="$long100"
    run_filter "[{\"number\":1,\"assignees\":[{\"login\":\"$long100\"}]}]"
    [ "$(nums)" = "1" ]
}

@test "lookup: gh api user is not called when nobody is assigned" {
    run_filter '[{"number":1,"assignees":[]},{"number":2}]'
    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALL_LOG" ]
}

@test "lookup: gh api user is called exactly once for several assigned issues" {
    run_filter "[{\"number\":1,\"assignees\":[$ALICE]},{\"number\":2,\"assignees\":[$BOB]},{\"number\":3,\"assignees\":[$ALICE]}]"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$GH_CALL_LOG" | tr -d ' ')" -eq 1 ]
    [ "$(nums)" = "1,3" ]
}

@test "edge: empty stdin exits 1 with empty stdout" {
    run_filter ''
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Error:"* ]] || false
}

@test "edge: whitespace-only stdin exits 1 with empty stdout" {
    run_filter $'  \n '
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "edge: invalid JSON, a non-array and elements without a numeric number exit 1 with empty stdout" {
    run_filter '[{"number":1,'
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run_filter '{"number":1}'
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run_filter '[1,2]'
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run_filter '[{"title":"no number"}]'
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run_filter '[{"number":"7"}]'
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "edge: empty array prints an empty array, exits 0 and never calls gh" {
    run_filter '[]'
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    [ ! -s "$GH_CALL_LOG" ]
}

@test "edge: malformed assignees values are excluded" {
    run_filter '[{"number":1,"assignees":"alice"},{"number":2,"assignees":{"login":"alice"}},{"number":3,"assignees":true},{"number":4,"assignees":[{"name":"no login"}]},{"number":5,"assignees":[{"login":""}]},{"number":6,"assignees":[{"login":"alice"}]}]'
    [ "$status" -eq 0 ]
    [ "$(nums)" = "6" ]
    [[ "$stderr" == *"unreadable assignees"* ]] || false
}

@test "edge: titles with quotes, angle brackets, newlines and multibyte characters pass through intact" {
    run_filter '[{"number":1,"title":"a > b \"q\"\nline2 日本語","assignees":[]}]'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.[0].title')" = $'a > b "q"\nline2 日本語' ]
}

@test "edge: CRLF line endings in the input are accepted" {
    printf '[\r\n{"number":1,"assignees":[]}\r\n]\r\n' > "$IN"
    run --separate-stderr bash "$SCRIPT" < "$IN"
    [ "$status" -eq 0 ]
    [ "$(nums)" = "1" ]
}

@test "edge: control characters and newlines in logins are replaced so the summary stays on one line" {
    run_filter '[{"number":1,"assignees":[{"login":"bo\u001b[31mb\nx"}]}]'
    [ "$status" -eq 0 ]
    local info
    info="$(printf '%s\n' "$stderr" | grep -c '^Info:')"
    [ "$info" -eq 1 ]
    [ "$(printf '%s\n' "$stderr" | wc -l | tr -d ' ')" -eq 1 ]
    [[ "$stderr" == *"bo?[31mb?x"* ]] || false
}

@test "edge: the summary lists at most 20 issues and reports the rest as +K more" {
    local json
    json="$(jq -n --argjson bob "$BOB" '[range(1; 26) | {number: ., assignees: [$bob]}]')"
    run_filter "$json"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
    [[ "$stderr" == *"excluded 25 issue(s)"* ]] || false
    [[ "$stderr" == *"(+5 more)"* ]] || false
    [[ "$stderr" == *"#20 (bob)"* ]] || false
    [[ "$stderr" != *"#21 (bob)"* ]] || false
}

@test "edge: 400 issues with a large body are processed correctly" {
    local json
    json="$(jq -n --argjson bob "$BOB" --argjson alice "$ALICE" '[range(1; 401) | {number: ., title: ("t" * 200), assignees: (if . % 2 == 0 then [$bob] else [$alice] end)}]')"
    run_filter "$json"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq 'length')" -eq 200 ]
    [ "$(printf '%s' "$output" | jq '[.[].number % 2] | unique | join(",")' -r)" = "1" ]
}

@test "usage: an argument exits 1" {
    run --separate-stderr bash "$SCRIPT" extra
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Error:"* ]] || false
}

@test "usage: --help exits 0 and prints usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]] || false
    [[ "$output" == *"fail-closed"* ]] || false
}
